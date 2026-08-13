import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

import '../../ai/models/tracked_object.dart';

/// Detects and tracks vehicles/people in the road-facing camera stream
/// using ML Kit's on-device Object Detection & Tracking API.
///
/// ML Kit's stock model gives coarse labels (e.g. "Vehicle", "Fashion good",
/// "Home good"). We map its coarse categories to the app's
/// [RoadObjectCategory].
///
/// For production-grade class-level accuracy (car vs. truck vs. motorcycle),
/// this should be replaced with a custom TFLite model such as a
/// mobile-optimized YOLO model.
class ObjectDetectionService {
  ObjectDetectionService() {
    _detector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.stream,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
  }

  late final ObjectDetector _detector;

  final Map<int, double> _lastAreaById = {};
  final Map<int, DateTime> _lastSeenById = {};

  Future<List<TrackedObject>> processFrame(
    InputImage inputImage,
    int frameWidth,
    int frameHeight,
  ) async {
    final results = await _detector.processImage(inputImage);
    final now = DateTime.now();
    final tracked = <TrackedObject>[];

    for (final obj in results) {
      final id = obj.trackingId ?? obj.boundingBox.hashCode;
      final category = _mapCategory(obj.labels);

      final trackedObject = TrackedObject(
        trackingId: id,
        category: category,
        boundingBox: obj.boundingBox,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        timestamp: now,
        previousBoxArea: _lastAreaById[id],
        previousTimestamp: _lastSeenById[id],
      );

      _lastAreaById[id] = trackedObject.normalizedArea;
      _lastSeenById[id] = now;
      tracked.add(trackedObject);
    }

    return tracked;
  }

  RoadObjectCategory _mapCategory(List<Label> labels) {
    for (final label in labels) {
      final text = label.text.toLowerCase();

      if (text.contains('vehicle') ||
          text.contains('car') ||
          text.contains('truck') ||
          text.contains('bus') ||
          text.contains('motorcycle') ||
          text.contains('motorbike')) {
        return RoadObjectCategory.vehicle;
      }

      if (text.contains('person') ||
          text.contains('pedestrian') ||
          text.contains('human')) {
        return RoadObjectCategory.person;
      }
    }

    return RoadObjectCategory.unknown;
  }

  Future<void> dispose() async {
    await _detector.close();
  }
}
