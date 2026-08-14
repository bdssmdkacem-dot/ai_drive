import 'package:flutter/material.dart';

import '../../../core/themes/app_theme.dart';
import '../../ai/models/tracked_object.dart';
import '../../ai/services/collision_prediction_service.dart';
import '../../lane_detection/services/lane_detection_service.dart';

/// A stylized, synthetic top-down/perspective driving scene in the style
/// of Tesla's in-car visualization: the road, lane lines, and nearby
/// vehicles/pedestrians are drawn as abstract shapes positioned from the
/// AI pipeline's output, rather than showing the raw camera feed.
///
/// Honest scope note (see docs/AI.md): this is a 2.5D pseudo-perspective
/// illustration built with 2D canvas drawing (`CustomPainter`) — converging
/// lines, size-scaling-by-distance, and now per-object motion smoothing
/// create a more fluid 3D impression, but there's still no real 3D scene
/// graph, camera projection matrix, or depth buffer like Tesla's actual
/// (Unreal-Engine-based) visualization.
///
/// Orientation: the scene's proportions (vanishing point height, road
/// width) adapt to the widget's actual aspect ratio each frame, so it
/// reads correctly in both portrait and landscape rather than assuming a
/// tall phone screen.
class TeslaVisualizationView extends StatefulWidget {
  const TeslaVisualizationView({
    super.key,
    required this.trackedObjects,
    required this.risk,
    this.laneReading,
    this.speedKmh,
  });

  final List<TrackedObject> trackedObjects;
  final RiskAssessment? risk;
  final LaneReading? laneReading;
  final double? speedKmh;

  @override
  State<TeslaVisualizationView> createState() => _TeslaVisualizationViewState();
}

class _TeslaVisualizationViewState extends State<TeslaVisualizationView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  /// Smoothed (interpolated) render state per tracked object, keyed by
  /// tracking ID, so objects glide toward their new detected position
  /// each frame instead of jumping — detections arrive at the AI
  /// pipeline's cadence (every other camera frame), which is far choppier
  /// than a 60fps repaint would otherwise look.
  final Map<int, _SmoothedObject> _smoothed = {};

  /// Accumulated phase for the flowing lane-dash animation, advanced each
  /// tick proportionally to speed (falls back to a plausible constant if
  /// no GPS speed is available yet) so the road reads as "moving" under
  /// the vehicle rather than static.
  double _dashPhase = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..addListener(_onTick)
      ..repeat();
  }

  void _onTick() {
    const smoothingFactor = 0.25; // higher = snappier, lower = floatier

    final presentIds = <int>{};
    for (final obj in widget.trackedObjects) {
      presentIds.add(obj.trackingId);
      final target = _targetFor(obj);
      final existing = _smoothed[obj.trackingId];
      _smoothed[obj.trackingId] = existing == null
          ? target
          : existing.lerpTo(target, smoothingFactor);
    }
    // Drop objects no longer detected this frame (immediate — a brief
    // flicker on a dropped detection is preferable to stale ghosts
    // lingering on screen).
    _smoothed.removeWhere((id, _) => !presentIds.contains(id));

    final speed = widget.speedKmh ?? 40.0;
    _dashPhase = (_dashPhase + speed * 0.00025) % 1.0;

    if (mounted) setState(() {});
  }

  _SmoothedObject _targetFor(TrackedObject obj) {
    final boxCenterXNorm = (obj.boundingBox.left + obj.boundingBox.width / 2) / obj.frameWidth;
    final depthT = (1.0 - obj.closenessScore).clamp(0.05, 0.95);
    return _SmoothedObject(
      trackingId: obj.trackingId,
      lateralNorm: boxCenterXNorm,
      depthT: depthT,
      category: obj.category,
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ScenePainter(
                  smoothedObjects: _smoothed.values.toList(growable: false),
                  risk: widget.risk,
                  laneReading: widget.laneReading,
                  dashPhase: _dashPhase,
                  isLandscape: isLandscape,
                ),
              ),
            ),
            if (widget.speedKmh != null) _SpeedReadout(speedKmh: widget.speedKmh!, isLandscape: isLandscape),
          ],
        );
      },
    );
  }
}

class _SpeedReadout extends StatelessWidget {
  const _SpeedReadout({required this.speedKmh, required this.isLandscape});
  final double speedKmh;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          speedKmh.round().toString(),
          style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w200),
        ),
        const Text('km/h', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      ],
    );

    // Landscape: Tesla's real center-console display is itself
    // landscape-oriented, so tucking the speed readout to the side
    // (rather than centered at the bottom, which would sit awkwardly
    // wide) matches that layout better and leaves the road scene
    // unobstructed.
    if (isLandscape) {
      return Positioned(
        top: 0,
        bottom: 0,
        right: 24,
        child: Center(child: content),
      );
    }
    return Positioned(bottom: 24, left: 0, right: 0, child: Center(child: content));
  }
}

/// Interpolatable render state for one tracked object.
class _SmoothedObject {
  const _SmoothedObject({
    required this.trackingId,
    required this.lateralNorm,
    required this.depthT,
    required this.category,
  });

  final int trackingId;
  final double lateralNorm;
  final double depthT;
  final RoadObjectCategory category;

  _SmoothedObject lerpTo(_SmoothedObject target, double t) {
    return _SmoothedObject(
      trackingId: trackingId,
      lateralNorm: lateralNorm + (target.lateralNorm - lateralNorm) * t,
      depthT: depthT + (target.depthT - depthT) * t,
      category: target.category,
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.smoothedObjects,
    required this.risk,
    required this.laneReading,
    required this.dashPhase,
    required this.isLandscape,
  });

  final List<_SmoothedObject> smoothedObjects;
  final RiskAssessment? risk;
  final LaneReading? laneReading;
  final double dashPhase;
  final bool isLandscape;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppTheme.background, Color.lerp(AppTheme.background, Colors.black, 0.4)!],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Landscape has less vertical room to work with, so the vanishing
    // point sits higher up (smaller fraction) and the road is
    // proportionally narrower relative to the wider canvas — otherwise
    // the road reads as a short, squat wedge instead of receding
    // convincingly into the distance.
    final vpYFraction = isLandscape ? 0.18 : 0.32;
    final roadWidthFraction = isLandscape ? 0.55 : 0.9;

    final vanishingPoint = Offset(size.width / 2, size.height * vpYFraction);
    final roadBottomY = size.height * 0.98;

    _drawRoad(canvas, size, vanishingPoint, roadBottomY, roadWidthFraction);
    _drawLaneLines(canvas, size, vanishingPoint, roadBottomY);
    _drawEgoVehicle(canvas, size, isLandscape);
    for (final obj in smoothedObjects) {
      _drawTrackedObject(canvas, size, vanishingPoint, roadBottomY, obj);
    }
  }

  void _drawRoad(Canvas canvas, Size size, Offset vp, double roadBottomY, double roadWidthFraction) {
    final roadWidthAtBottom = size.width * roadWidthFraction;
    final path = Path()
      ..moveTo(vp.dx - 4, vp.dy)
      ..lineTo(vp.dx + 4, vp.dy)
      ..lineTo(size.width / 2 + roadWidthAtBottom / 2, roadBottomY)
      ..lineTo(size.width / 2 - roadWidthAtBottom / 2, roadBottomY)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF1B222B));
  }

  void _drawLaneLines(Canvas canvas, Size size, Offset vp, double roadBottomY) {
    final leftNorm = laneReading?.leftLineX ?? 0.3;
    final rightNorm = laneReading?.rightLineX ?? 0.7;

    final leftBottomX = leftNorm * size.width;
    final rightBottomX = rightNorm * size.width;

    final paint = Paint()
      ..color = laneReading != null
          ? AppTheme.primary
          : AppTheme.textSecondary.withValues(alpha: 0.4)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(vp, Offset(leftBottomX, roadBottomY), paint);
    canvas.drawLine(vp, Offset(rightBottomX, roadBottomY), paint);

    // Flowing center dashes: phase-shifted each frame by dashPhase so the
    // dashes appear to travel from the vanishing point toward the
    // vehicle, giving a sense of forward motion even though the "road"
    // itself is a static drawing.
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 2;
    const dashCount = 6;
    for (int i = 0; i < dashCount; i++) {
      final t0 = ((i / dashCount) + dashPhase) % 1.0;
      final t1 = (((i + 0.5) / dashCount) + dashPhase) % 1.0;
      if (t1 < t0) continue; // skip the wrap-around segment, avoids a stray long dash
      canvas.drawLine(
        Offset.lerp(vp, Offset(size.width / 2, roadBottomY), t0)!,
        Offset.lerp(vp, Offset(size.width / 2, roadBottomY), t1)!,
        dashPaint,
      );
    }
  }

  void _drawEgoVehicle(Canvas canvas, Size size, bool isLandscape) {
    final cx = size.width / 2;
    final bottom = size.height * (isLandscape ? 0.9 : 0.94);
    final w = isLandscape ? 36.0 : 46.0;
    final h = isLandscape ? 50.0 : 66.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, bottom - h / 2), width: w, height: h),
      const Radius.circular(10),
    );
    canvas.drawRRect(rect, Paint()..color = AppTheme.primary);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, bottom - h * 0.68), width: w * 0.6, height: h * 0.3),
        const Radius.circular(6),
      ),
      Paint()..color = AppTheme.background.withValues(alpha: 0.6),
    );
  }

  void _drawTrackedObject(
    Canvas canvas,
    Size size,
    Offset vp,
    double roadBottomY,
    _SmoothedObject obj,
  ) {
    final depthT = obj.depthT;
    final screenPos = Offset.lerp(
      Offset(size.width / 2 + (obj.lateralNorm - 0.5) * size.width * 0.9, roadBottomY),
      vp,
      depthT,
    )!;

    final scale = (1.0 - depthT).clamp(0.15, 1.0);
    final baseSize = obj.category == RoadObjectCategory.person ? 18.0 : 34.0;
    final w = baseSize * scale;
    final h = (obj.category == RoadObjectCategory.person ? 34.0 : 20.0) * scale;

    final isRiskObject = risk?.object.trackingId == obj.trackingId &&
        (risk?.level == RiskLevel.warning || risk?.level == RiskLevel.danger);
    final color = isRiskObject
        ? (risk!.level == RiskLevel.danger ? AppTheme.danger : AppTheme.warning)
        : (obj.category == RoadObjectCategory.person ? AppTheme.warning : AppTheme.textSecondary);

    // A soft ground-contact shadow beneath each object reads as a cheap
    // but effective depth cue — objects "sitting on" the road rather than
    // floating flat shapes. Drawn flat (unskewed) since it represents
    // contact with the ground plane, not the object's own geometry.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(screenPos.dx, screenPos.dy + h * 0.42), width: w * 0.9, height: h * 0.22),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    // Perspective skew: lean the box toward the vanishing point based on
    // how far off-center it is and how far away it is (depthT). This
    // mirrors how the lane lines converge and reads as much more
    // "in-scene" than an axis-aligned rectangle floating over the road —
    // a cheap trick, but an effective one for a flat 2D canvas.
    final lateralOffsetNorm = (screenPos.dx - size.width / 2) / (size.width / 2);
    final skew = -lateralOffsetNorm * 0.22 * depthT;

    canvas.save();
    canvas.translate(screenPos.dx, screenPos.dy);
    canvas.transform(Matrix4.skewX(skew).storage);
    canvas.translate(-screenPos.dx, -screenPos.dy);

    final rect = Rect.fromCenter(center: screenPos, width: w, height: h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w * 0.2)),
      Paint()..color = color,
    );

    if (isRiskObject) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(4), Radius.circular(w * 0.25)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => true; // driven by the ticker each frame
}
