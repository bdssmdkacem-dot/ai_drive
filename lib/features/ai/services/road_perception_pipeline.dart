import 'package:camera/camera.dart';

import '../../lane_detection/services/lane_detection_service.dart';
import '../../object_detection/services/yolo_object_detection_service.dart';
import '../models/tracked_object.dart';
import 'collision_prediction_service.dart';

class PerceptionFrame {
  const PerceptionFrame({
    required this.trackedObjects,
    required this.risk,
    required this.lanePosition,
    required this.laneReading,
    required this.timestamp,
    required this.frameWidth,
    required this.frameHeight,
  });

  final List<TrackedObject> trackedObjects;
  final RiskAssessment? risk;
  final LanePosition lanePosition;
  final LaneReading? laneReading;
  final DateTime timestamp;
  final int frameWidth;
  final int frameHeight;
}

/// Unified road-perception pipeline using the real YOLO/LiteRT detector.
///
/// Camera -> YOLO/LiteRT -> temporal tracking -> lane geometry -> collision
/// prediction -> synchronized PerceptionFrame.
class RoadPerceptionPipeline {
  RoadPerceptionPipeline({
    YoloObjectDetectionService? objectDetection,
    CollisionPredictionService? collisionPrediction,
    LaneDetectionService? laneDetection,
  })  : _objectDetection = objectDetection ?? YoloObjectDetectionService(),
        _collisionPrediction = collisionPrediction ?? CollisionPredictionService(),
        _laneDetection = laneDetection ?? LaneDetectionService();

  final YoloObjectDetectionService _objectDetection;
  final CollisionPredictionService _collisionPrediction;
  final LaneDetectionService _laneDetection;

  LaneReading? get lastLaneReading => _laneDetection.lastReading;

  Future<void> init() => _objectDetection.init();

  Future<PerceptionFrame?> processFrame({
    required CameraImage image,
    int rotationDegrees = 0,
  }) async {
    final timestamp = DateTime.now();

    final results = await Future.wait([
      _objectDetection.processFrame(image, rotationDegrees: rotationDegrees),
      Future.value(_laneDetection.evaluate(
        yPlane: image.planes.first.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: image.planes.first.bytesPerRow,
      )),
    ]);

    final tracked = results[0] as List<TrackedObject>;
    final lanePosition = results[1] as LanePosition;
    final risk = _collisionPrediction.assess(tracked);

    return PerceptionFrame(
      trackedObjects: List.unmodifiable(tracked),
      risk: risk,
      lanePosition: lanePosition,
      laneReading: _laneDetection.lastReading,
      timestamp: timestamp,
      frameWidth: image.width,
      frameHeight: image.height,
    );
  }

  Future<void> dispose() => _objectDetection.dispose();
}
