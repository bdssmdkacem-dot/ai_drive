import 'dart:typed_data';

enum LanePosition { centered, driftingLeft, driftingRight, unknown }

/// A snapshot of the most recent confident lane-line detection, in
/// frame-normalized coordinates (0.0 = left edge of frame, 1.0 = right
/// edge), for callers that want the actual geometry — e.g. a visualization
/// — rather than just the coarse [LanePosition] classification.
class LaneReading {
  const LaneReading({
    required this.leftLineX,
    required this.rightLineX,
    required this.offset,
  });

  /// Normalized (0..1) x-position of the detected left lane line.
  final double leftLineX;

  /// Normalized (0..1) x-position of the detected right lane line.
  final double rightLineX;

  /// Smoothed lateral offset, same convention as [evaluate]'s internal
  /// calculation: positive means the vehicle has drifted left.
  final double offset;
}

/// A lightweight, pure-Dart lane-position estimator that runs directly on
/// the road camera's luma (brightness) plane — no native CV library, no
/// trained model.
///
/// Algorithm (classical edge-detection, not machine learning):
/// 1. Look only at a region of interest (ROI) near the bottom of the frame
///    — the road surface directly ahead, where lane markings are most
///    reliably visible and closest to the vehicle.
/// 2. For each sampled row in the ROI, compute a simple horizontal
///    gradient (|pixel(x+1) - pixel(x-1)|) — lane markings show up as
///    sharp brightness edges against asphalt.
/// 3. Sum gradient strength per column across all sampled ROI rows,
///    producing a 1D "edge histogram" across the frame's width.
/// 4. Find the two strongest, sufficiently-separated peaks in that
///    histogram (non-max suppression around the first peak before
///    picking the second) — these are the candidate left/right lane
///    lines. Peaks are found across the *whole* frame width rather than
///    assuming one lives in the left half and one in the right half,
///    because a real drift event can shift both lines toward the same
///    side of the frame — a fixed half-split would miss exactly the
///    case this feature exists to catch.
/// 5. Compare the midpoint between those two edges to the frame's true
///    center — an offset means the vehicle isn't centered in its lane.
/// 6. Smooth the offset across frames (EMA) and require several
///    consecutive readings before reporting drift, to avoid single-frame
///    false positives from shadows, other vehicles, or road debris.
///
/// Known limitations (see docs/AI.md): this is a heuristic, not a trained
/// lane-segmentation network. It can be fooled by faded/missing lane
/// markings, heavy shadows, wet roads with glare, or curves (it assumes
/// roughly straight, symmetric lane lines near the vehicle). It does not
/// attempt to detect lane lines far ahead or through curves. Treat it as
/// a "did something change under the car" signal, not a certified
/// lane-departure warning system.
class LaneDetectionService {
  static const double _minEdgeStrength = 12.0; // ignore near-flat ROIs (poor lighting/no markings)
  static const double _driftThresholdNormalized = 0.12; // fraction of half-frame-width
  static const int _sampleStep = 4; // pixel stride for both axes — perf vs. accuracy tradeoff
  static const int _confirmFramesNeeded = 3;
  static const double _minPeakSeparationFraction = 0.15; // min distance between the two lane-line peaks

  double? _smoothedOffset;
  int _consecutiveDriftDirection = 0; // positive = right-drift streak, negative = left-drift streak
  LanePosition _lastConfirmed = LanePosition.unknown;
  LaneReading? _lastReading;

  /// The geometry behind the most recent confident [evaluate] call, or
  /// null if no confident reading has ever been produced (or the last
  /// frame decayed due to no visible markings). Useful for visualizations
  /// that want to draw the actual detected lane lines.
  LaneReading? get lastReading => _lastReading;

  /// [yPlane] is the luma (brightness) plane of an NV21/YUV420 camera
  /// frame — plane index 0, which is safe to read as plain grayscale
  /// regardless of the chroma subsampling format. [bytesPerRow] accounts
  /// for any row padding some devices add (row stride can exceed width).
  LanePosition evaluate({
    required Uint8List yPlane,
    required int width,
    required int height,
    required int bytesPerRow,
  }) {
    final roiTop = (height * 0.60).toInt();
    final roiBottom = (height * 0.92).toInt();
    if (roiBottom <= roiTop || width < 20) return LanePosition.unknown;

    final edgeHistogram = Float64List(width);

    for (int y = roiTop; y < roiBottom; y += _sampleStep) {
      final rowStart = y * bytesPerRow;
      if (rowStart + width >= yPlane.length) continue;
      for (int x = 1; x < width - 1; x += _sampleStep) {
        final left = yPlane[rowStart + x - 1];
        final right = yPlane[rowStart + x + 1];
        edgeHistogram[x] += (right - left).abs();
      }
    }

    final peaks = _twoStrongestPeaks(edgeHistogram, width);
    if (peaks == null) {
      return _decay();
    }

    final laneCenterX = (peaks.left + peaks.right) / 2.0;
    final frameCenterX = width / 2.0;
    // Positive offset: detected lane midpoint sits right of true frame
    // center, i.e. the vehicle (camera) has drifted left within the lane.
    final offset = (laneCenterX - frameCenterX) / frameCenterX;

    final prev = _smoothedOffset;
    _smoothedOffset = prev == null ? offset : (prev * 0.7 + offset * 0.3);

    _lastReading = LaneReading(
      leftLineX: peaks.left / width,
      rightLineX: peaks.right / width,
      offset: _smoothedOffset!,
    );

    return _classify(_smoothedOffset!);
  }

  /// Finds the two strongest, well-separated peaks in [histogram] — the
  /// candidate left and right lane-line edges — using simple non-max
  /// suppression: take the global max, zero out a window around it, then
  /// take the next max from what remains. Returns null if either peak is
  /// too weak (no confident markings) or the two peaks are too close
  /// together to plausibly be two different lane lines.
  ({double left, double right})? _twoStrongestPeaks(
    Float64List histogram,
    int width,
  ) {
    final first = _peak(histogram, 0, width);
    if (first == null || histogram[first] < _minEdgeStrength) return null;

    final suppressed = Float64List.fromList(histogram);
    final suppressionRadius = (width * 0.06).toInt().clamp(1, width);
    final sStart = (first - suppressionRadius).clamp(0, width);
    final sEnd = (first + suppressionRadius).clamp(0, width);
    for (int i = sStart; i < sEnd; i++) {
      suppressed[i] = 0;
    }

    final second = _peak(suppressed, 0, width);
    if (second == null || suppressed[second] < _minEdgeStrength) return null;

    final minSeparation = width * _minPeakSeparationFraction;
    if ((first - second).abs() < minSeparation) return null;

    final left = first < second ? first : second;
    final right = first < second ? second : first;
    return (left: left.toDouble(), right: right.toDouble());
  }

  int? _peak(Float64List histogram, int start, int end) {
    double best = 0;
    int? bestIdx;
    for (int i = start; i < end; i++) {
      if (histogram[i] > best) {
        best = histogram[i];
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  LanePosition _classify(double offset) {
    if (offset > _driftThresholdNormalized) {
      _consecutiveDriftDirection =
          _consecutiveDriftDirection > 0 ? _consecutiveDriftDirection + 1 : 1;
    } else if (offset < -_driftThresholdNormalized) {
      _consecutiveDriftDirection =
          _consecutiveDriftDirection < 0 ? _consecutiveDriftDirection - 1 : -1;
    } else {
      _consecutiveDriftDirection = 0;
      _lastConfirmed = LanePosition.centered;
      return LanePosition.centered;
    }

    if (_consecutiveDriftDirection.abs() >= _confirmFramesNeeded) {
      _lastConfirmed = _consecutiveDriftDirection > 0
          ? LanePosition.driftingLeft
          : LanePosition.driftingRight;
    }
    return _lastConfirmed;
  }

  /// Called when a frame's ROI didn't yield a confident reading (e.g. no
  /// visible lane markings). Doesn't immediately reset to "unknown" so a
  /// single bad frame doesn't erase an in-progress drift confirmation.
  LanePosition _decay() {
    _consecutiveDriftDirection = 0;
    return _lastConfirmed == LanePosition.unknown
        ? LanePosition.unknown
        : _lastConfirmed;
  }

  /// Call when the driver intentionally changes lanes, so drift detection
  /// doesn't immediately re-fire against the new lane's markings.
  void reset() {
    _smoothedOffset = null;
    _consecutiveDriftDirection = 0;
    _lastConfirmed = LanePosition.unknown;
    _lastReading = null;
  }
}
