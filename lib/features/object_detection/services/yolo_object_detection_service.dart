import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../../ai/models/tracked_object.dart';

/// Real on-device road detector backed by Ultralytics YOLO/LiteRT.
class YoloObjectDetectionService {
  YoloObjectDetectionService({
    this.modelPath = 'yolo26n',
    this.confidenceThreshold = 0.30,
    this.iouThreshold = 0.45,
  }) : _yolo = YOLO(
          modelPath: modelPath,
          task: YOLOTask.detect,
          useGpu: true,
        );

  final String modelPath;
  final double confidenceThreshold;
  final double iouThreshold;
  final YOLO _yolo;

  final Map<int, _TrackState> _tracks = {};
  int _nextTrackId = 1;
  bool _loaded = false;

  Future<void> init() async {
    if (_loaded) return;
    await _yolo.loadModel();
    _loaded = true;
  }

  Future<List<TrackedObject>> processFrame(
    CameraImage image, {
    int rotationDegrees = 0,
  }) async {
    await init();

    final prepared = _prepareFrame(image, rotationDegrees);
    final rawResult = await _yolo.predict(
      prepared.jpegBytes,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
    final result = YOLODetectionResults.fromMap(rawResult);

    final now = DateTime.now();
    final detections = <_Detection>[];

    for (final detection in result.detections) {
      final category = _categoryFor(detection.className);
      if (category == RoadObjectCategory.unknown) continue;

      final normalized = detection.normalizedBox;
      final box = Rect.fromLTWH(
        (normalized.left * prepared.width).clamp(0, prepared.width.toDouble()),
        (normalized.top * prepared.height).clamp(0, prepared.height.toDouble()),
        (normalized.width * prepared.width).clamp(0, prepared.width.toDouble()),
        (normalized.height * prepared.height).clamp(0, prepared.height.toDouble()),
      );
      if (box.width < 2 || box.height < 2) continue;

      detections.add(_Detection(
        category: category,
        className: detection.className,
        confidence: detection.confidence,
        box: box,
      ));
    }

    final usedTrackIds = <int>{};
    final tracked = <TrackedObject>[];

    for (final detection in detections) {
      _TrackState? best;
      var bestIou = 0.0;

      for (final candidate in _tracks.values) {
        if (usedTrackIds.contains(candidate.id) ||
            candidate.category != detection.category) {
          continue;
        }
        final iou = _intersectionOverUnion(candidate.box, detection.box);
        if (iou > bestIou) {
          bestIou = iou;
          best = candidate;
        }
      }

      if (best != null && bestIou >= iouThreshold) {
        usedTrackIds.add(best.id);
        tracked.add(_makeTrackedObject(best, detection, now, prepared.width, prepared.height));
        best
          ..box = detection.box
          ..timestamp = now
          ..category = detection.category
          ..className = detection.className
          ..confidence = detection.confidence;
      } else {
        final track = _TrackState(
          id: _nextTrackId++,
          box: detection.box,
          category: detection.category,
          className: detection.className,
          confidence: detection.confidence,
          timestamp: now,
        );
        _tracks[track.id] = track;
        usedTrackIds.add(track.id);
        tracked.add(_makeTrackedObject(track, detection, now, prepared.width, prepared.height));
      }
    }

    _tracks.removeWhere(
      (_, track) => now.difference(track.timestamp).inMilliseconds > 1200,
    );

    return tracked;
  }

  TrackedObject _makeTrackedObject(
    _TrackState track,
    _Detection detection,
    DateTime now,
    int width,
    int height,
  ) {
    final hasHistory = track.timestamp != now;
    final previousArea = track.box.width * track.box.height / (width * height);
    return TrackedObject(
      trackingId: track.id,
      category: detection.category,
      boundingBox: detection.box,
      frameWidth: width,
      frameHeight: height,
      timestamp: now,
      className: detection.className,
      confidence: detection.confidence,
      previousBoxArea: hasHistory ? previousArea : null,
      previousTimestamp: hasHistory ? track.timestamp : null,
    );
  }

  RoadObjectCategory _categoryFor(String raw) {
    final label = raw.trim().toLowerCase();
    if ({'car', 'truck', 'bus', 'motorcycle', 'motorbike'}.contains(label)) {
      return RoadObjectCategory.vehicle;
    }
    if (label == 'person' || label == 'pedestrian') {
      return RoadObjectCategory.person;
    }
    if (label == 'bicycle' || label == 'bike') {
      return RoadObjectCategory.bicycle;
    }
    if (label == 'stop sign' || label.contains('traffic sign')) {
      return RoadObjectCategory.trafficSign;
    }
    if (label == 'traffic light') {
      return RoadObjectCategory.trafficLight;
    }
    return RoadObjectCategory.unknown;
  }

  double _intersectionOverUnion(Rect a, Rect b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    final intersection = math.max(0.0, right - left) * math.max(0.0, bottom - top);
    if (intersection <= 0) return 0;
    final union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0 : intersection / union;
  }

  _PreparedFrame _prepareFrame(CameraImage image, int rotationDegrees) {
    final targetWidth = math.min(640, image.width);
    final targetHeight = math.max(1, (image.height * targetWidth / image.width).round());
    final rgb = img.Image(width: targetWidth, height: targetHeight);
    final yPlane = image.planes[0];
    final uPlane = image.planes.length > 1 ? image.planes[1] : null;
    final vPlane = image.planes.length > 2 ? image.planes[2] : null;

    for (var y = 0; y < targetHeight; y++) {
      final sourceY = (y * image.height / targetHeight).floor();
      for (var x = 0; x < targetWidth; x++) {
        final sourceX = (x * image.width / targetWidth).floor();
        final yValue = _planeValue(yPlane, sourceX, sourceY);
        final u = uPlane == null ? 128 : _planeValue(uPlane, sourceX ~/ 2, sourceY ~/ 2);
        final v = vPlane == null ? 128 : _planeValue(vPlane, sourceX ~/ 2, sourceY ~/ 2);
        final r = (yValue + 1.402 * (v - 128)).round().clamp(0, 255);
        final g = (yValue - 0.344136 * (u - 128) - 0.714136 * (v - 128)).round().clamp(0, 255);
        final b = (yValue + 1.772 * (u - 128)).round().clamp(0, 255);
        rgb.setPixelRgb(x, y, r, g, b);
      }
    }

    var upright = rgb;
    final normalizedRotation = rotationDegrees % 360;
    if (normalizedRotation == 90 || normalizedRotation == 180 || normalizedRotation == 270) {
      upright = img.copyRotate(rgb, angle: normalizedRotation);
    }

    return _PreparedFrame(
      jpegBytes: Uint8List.fromList(img.encodeJpg(upright, quality: 78)),
      width: upright.width,
      height: upright.height,
    );
  }

  int _planeValue(Plane plane, int x, int y) {
    final pixelStride = plane.bytesPerPixel ?? 1;
    final maxRow = math.max(0, plane.bytes.length ~/ plane.bytesPerRow - 1);
    final row = y.clamp(0, maxRow);
    final maxColumn = math.max(0, plane.bytesPerRow ~/ pixelStride - 1);
    final column = x.clamp(0, maxColumn);
    final index = row * plane.bytesPerRow + column * pixelStride;
    if (index < 0 || index >= plane.bytes.length) return 128;
    return plane.bytes[index];
  }

  Future<void> dispose() async {
    _tracks.clear();
    _loaded = false;
    _yolo.dispose();
  }
}

class _Detection {
  const _Detection({
    required this.category,
    required this.className,
    required this.confidence,
    required this.box,
  });

  final RoadObjectCategory category;
  final String className;
  final double confidence;
  final Rect box;
}

class _TrackState {
  _TrackState({
    required this.id,
    required this.box,
    required this.category,
    required this.className,
    required this.confidence,
    required this.timestamp,
  });

  final int id;
  Rect box;
  RoadObjectCategory category;
  String className;
  double confidence;
  DateTime timestamp;
}

class _PreparedFrame {
  const _PreparedFrame({
    required this.jpegBytes,
    required this.width,
    required this.height,
  });

  final Uint8List jpegBytes;
  final int width;
  final int height;
}
