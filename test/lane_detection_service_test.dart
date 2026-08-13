import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_drive/features/lane_detection/services/lane_detection_service.dart';

/// Builds a synthetic grayscale frame (as a flat Uint8List, one byte per
/// pixel — equivalent to an NV21 frame's Y-plane) with two vertical
/// "lane line" edges at the given x-positions, simulating bright lane
/// markings on a dark road.
Uint8List _syntheticFrame({
  required int width,
  required int height,
  required int leftLineX,
  required int rightLineX,
}) {
  final data = Uint8List(width * height);
  data.fillRange(0, data.length, 40); // dark asphalt background

  // Paint a few-pixel-wide bright line at each lane position, across the
  // whole frame height, so it falls inside the service's ROI regardless
  // of exact ROI bounds.
  for (int y = 0; y < height; y++) {
    for (int dx = -1; dx <= 1; dx++) {
      final rowStart = y * width;
      final lx = leftLineX + dx;
      final rx = rightLineX + dx;
      if (lx >= 0 && lx < width) data[rowStart + lx] = 220;
      if (rx >= 0 && rx < width) data[rowStart + rx] = 220;
    }
  }
  return data;
}

void main() {
  group('LaneDetectionService', () {
    const width = 320;
    const height = 240;

    test('symmetric lane lines around center read as centered eventually', () {
      final service = LaneDetectionService();
      final frame = _syntheticFrame(
        width: width,
        height: height,
        leftLineX: (width * 0.25).toInt(),
        rightLineX: (width * 0.75).toInt(),
      );

      LanePosition? last;
      for (var i = 0; i < 5; i++) {
        last = service.evaluate(
          yPlane: frame,
          width: width,
          height: height,
          bytesPerRow: width,
        );
      }
      expect(last, LanePosition.centered);
    });

    test('lane lines both shifted right of center confirm as a drift after repeated frames', () {
      final service = LaneDetectionService();
      // Both lines shifted well to the right of the frame's true center
      // -> detected lane midpoint sits right of center -> driftingLeft
      // per the service's documented sign convention.
      final frame = _syntheticFrame(
        width: width,
        height: height,
        leftLineX: (width * 0.55).toInt(),
        rightLineX: (width * 0.95).toInt(),
      );

      LanePosition? last;
      for (var i = 0; i < 6; i++) {
        last = service.evaluate(
          yPlane: frame,
          width: width,
          height: height,
          bytesPerRow: width,
        );
      }
      expect(last, LanePosition.driftingLeft);
    });

    test('a blank/flat frame (no visible markings) reports unknown', () {
      final service = LaneDetectionService();
      final flat = Uint8List(width * height)..fillRange(0, width * height, 60);

      final result = service.evaluate(
        yPlane: flat,
        width: width,
        height: height,
        bytesPerRow: width,
      );
      expect(result, LanePosition.unknown);
    });

    test('reset() clears drift confirmation state', () {
      final service = LaneDetectionService();
      final driftedFrame = _syntheticFrame(
        width: width,
        height: height,
        leftLineX: (width * 0.55).toInt(),
        rightLineX: (width * 0.95).toInt(),
      );
      for (var i = 0; i < 6; i++) {
        service.evaluate(
          yPlane: driftedFrame,
          width: width,
          height: height,
          bytesPerRow: width,
        );
      }

      service.reset();

      final flat = Uint8List(width * height)..fillRange(0, width * height, 60);
      final afterReset = service.evaluate(
        yPlane: flat,
        width: width,
        height: height,
        bytesPerRow: width,
      );
      expect(afterReset, LanePosition.unknown);
    });
  });
}
