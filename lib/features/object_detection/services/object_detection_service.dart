import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

import '../../ai/models/tracked_object.dart';

/// Detects and tracks vehicles/people in the road-facing camera stream
/// using ML Kit's on-device Object Detection & Tracking API.
///
/// ML Kit's stock model gives coarse labels (e.g. "Vehicle", "Fashion
/// good", "Home good"). We map its coarse categories to the app's
/// [RoadObjectCategory]; for production-grade class-level accuracy
/// (car vs. truck vs. motorcycle) this should be swapped for a custom
/// TFLite model (e.g. a mobile-optimized YOLO export) — see docs/AI.md.
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

      final t = TrackedObject(
        trackingId: id,
        category: category,
        boundingBox: obj.boundingBox,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        timestamp: now,
        previousBoxArea: _lastAreaById[id],
        previousTimestamp: _lastSeenById[id],
      );

      _lastAreaById[id] = t.normalizedArea;
      _lastSeenById[id] = now;
      tracked.add(t);
    }

    return tracked;
  }

  RoadObjectCategory _mapCategory(List<DetectedObjectLabel> labels) {
    for (final label in labels) {
      final text = label.text.toLowerCase();
      if (text.contains('vehicle') || text.contains('car')) {
        return RoadObjectCategory.vehicle;
      }
      if (text.contains('person')) {
        return RoadObjectCategory.person;
      }
    }
    return RoadObjectCategory.unknown;
  }

  Future<void> dispose() async {
    await _detector.close();
  }
}
