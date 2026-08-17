import 'dart:ui';

enum RoadObjectCategory {
  vehicle,
  person,
  bicycle,
  trafficSign,
  trafficLight,
  unknown,
}

/// A YOLO detection promoted to a frame-to-frame tracked road object.
class TrackedObject {
  TrackedObject({
    required this.trackingId,
    required this.category,
    required this.boundingBox,
    required this.frameWidth,
    required this.frameHeight,
    required this.timestamp,
    this.className = 'unknown',
    this.confidence = 0,
    this.previousBoxArea,
    this.previousTimestamp,
  });

  final int trackingId;
  final RoadObjectCategory category;
  final Rect boundingBox;
  final int frameWidth;
  final int frameHeight;
  final DateTime timestamp;
  final String className;
  final double confidence;

  final double? previousBoxArea;
  final DateTime? previousTimestamp;

  double get normalizedArea =>
      (boundingBox.width * boundingBox.height) / (frameWidth * frameHeight);

  double get closenessScore => normalizedArea.clamp(0, 1);

  double? get estimatedTimeToCollisionSeconds {
    final prevArea = previousBoxArea;
    final prevTime = previousTimestamp;
    if (prevArea == null || prevTime == null) return null;

    final dt = timestamp.difference(prevTime).inMilliseconds / 1000.0;
    if (dt <= 0) return null;

    final growthRate = (normalizedArea - prevArea) / dt;
    if (growthRate <= 0.0001) return null;

    final remainingArea = 1.0 - normalizedArea;
    if (remainingArea <= 0) return 0;

    return (remainingArea / growthRate).clamp(0, 60);
  }
}
