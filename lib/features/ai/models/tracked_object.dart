import 'dart:ui';

enum RoadObjectCategory { vehicle, person, unknown }

/// A detected object on the road, tracked frame-to-frame so we can estimate
/// how quickly it is growing in the frame (a proxy for closing distance).
class TrackedObject {
  TrackedObject({
    required this.trackingId,
    required this.category,
    required this.boundingBox,
    required this.frameWidth,
    required this.frameHeight,
    required this.timestamp,
    this.previousBoxArea,
    this.previousTimestamp,
  });

  final int trackingId;
  final RoadObjectCategory category;
  final Rect boundingBox;
  final int frameWidth;
  final int frameHeight;
  final DateTime timestamp;

  /// Normalized bounding-box area (0..1) from the previous frame, used to
  /// estimate closing speed. Null on the first sighting.
  final double? previousBoxArea;
  final DateTime? previousTimestamp;

  double get normalizedArea =>
      (boundingBox.width * boundingBox.height) / (frameWidth * frameHeight);

  /// Rough distance proxy: bigger box = closer. Not a calibrated metric
  /// distance — a real implementation needs stereo/depth or a calibrated
  /// monocular model. Returned as "closeness" 0 (far) .. 1 (very close).
  double get closenessScore => normalizedArea.clamp(0, 1);

  /// Estimated time-to-collision in seconds based on how fast the bounding
  /// box area is growing between frames. Returns null if we don't have a
  /// previous sample yet, or if the object isn't approaching.
  double? get estimatedTimeToCollisionSeconds {
    final prevArea = previousBoxArea;
    final prevTime = previousTimestamp;
    if (prevArea == null || prevTime == null) return null;

    final dt = timestamp.difference(prevTime).inMilliseconds / 1000.0;
    if (dt <= 0) return null;

    final growthRate = (normalizedArea - prevArea) / dt;
    if (growthRate <= 0.0001) return null; // not approaching

    final remainingArea = 1.0 - normalizedArea;
    if (remainingArea <= 0) return 0;

    return (remainingArea / growthRate).clamp(0, 60);
  }
}
