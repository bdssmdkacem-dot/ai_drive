import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import '../../lane_detection/services/lane_detection_service.dart';
import '../../object_detection/services/object_detection_service.dart';
import '../models/tracked_object.dart';
import 'collision_prediction_service.dart';

/// A single synchronized perception snapshot consumed by driving UI and
/// safety logic. Keeping detection, lane geometry and collision assessment
/// together prevents the UI from accidentally mixing results from different
/// camera frames.
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

/// Coordinates the complete road-perception pass for one camera frame.
///
/// The screen no longer knows which detector/tracker is being used. A future
/// YOLO/TFLite backend can replace [ObjectDetectionService] without changing
/// collision prediction, lane processing, recording, voice alerts or the 3D
/// renderer.
class RoadPerceptionPipeline {
  RoadPerceptionPipeline({
    ObjectDetectionService? objectDetection,
    CollisionPredictionService? collisionPrediction,
    LaneDetectionService? laneDetection,
  })  : _objectDetection = objectDetection ?? ObjectDetectionService(),
        _collisionPrediction =
            collisionPrediction ?? CollisionPredictionService(),
        _laneDetection = laneDetection ?? LaneDetectionService();

  final ObjectDetectionService _objectDetection;
  final CollisionPredictionService _collisionPrediction;
  final LaneDetectionService _laneDetection;

  LaneReading? get lastLaneReading => _laneDetection.lastReading;

  Future<PerceptionFrame?> processFrame({
    required CameraImage image,
    required InputImage inputImage,
    required int frameWidth,
    required int frameHeight,
  }) async {
    final timestamp = DateTime.now();

    final results = await Future.wait([
      _objectDetection.processFrame(inputImage, frameWidth, frameHeight),
      Future.value(
        _laneDetection.evaluate(
          yPlane: image.planes.first.bytes,
          width: image.width,
          height: image.height,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      ),
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
      frameWidth: frameWidth,
      frameHeight: frameHeight,
    );
  }

  Future<void> dispose() => _objectDetection.dispose();
}
