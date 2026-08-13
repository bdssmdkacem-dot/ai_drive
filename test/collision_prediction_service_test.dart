import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_drive/features/ai/models/tracked_object.dart';
import 'package:ai_drive/features/ai/services/collision_prediction_service.dart';

TrackedObject _object({
  required double area,
  double? previousArea,
  DateTime? timestamp,
  DateTime? previousTimestamp,
}) {
  // normalizedArea = (box.width * box.height) / (frameWidth * frameHeight).
  // For a square box of side `s` on a 1000x1000 frame, normalizedArea =
  // s^2 / 1e6, so s = sqrt(area) * 1000 to hit the target `area` exactly.
  const frameW = 1000;
  const frameH = 1000;
  final s = _sqrt(area) * frameW;
  return TrackedObject(
    trackingId: 1,
    category: RoadObjectCategory.vehicle,
    boundingBox: Rect.fromLTWH(0, 0, s, s),
    frameWidth: frameW,
    frameHeight: frameH,
    timestamp: timestamp ?? DateTime(2026, 1, 1, 12, 0, 1),
    previousBoxArea: previousArea,
    previousTimestamp: previousTimestamp,
  );
}

double _sqrt(double x) {
  if (x <= 0) return 0;
  double guess = x;
  for (var i = 0; i < 20; i++) {
    guess = 0.5 * (guess + x / guess);
  }
  return guess;
}

void main() {
  group('CollisionPredictionService', () {
    final service = CollisionPredictionService();

    test('no risk when nothing detected', () {
      expect(service.assess([]), isNull);
    });

    test('far, non-approaching object is not flagged', () {
      final obj = _object(area: 0.05);
      final result = service.assess([obj]);
      expect(result, isNull);
    });

    test('rapidly growing close object is flagged as danger', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final t1 = t0.add(const Duration(milliseconds: 200));
      // area grows from 0.5 to 0.9 in 0.2s -> fast growth, close to filling frame
      final obj = _object(
        area: 0.9,
        previousArea: 0.5,
        timestamp: t1,
        previousTimestamp: t0,
      );
      final result = service.assess([obj]);
      expect(result, isNotNull);
      expect(result!.level, anyOf(RiskLevel.warning, RiskLevel.danger));
    });

    test('shrinking (receding) object is not flagged', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final t1 = t0.add(const Duration(milliseconds: 200));
      final obj = _object(
        area: 0.3,
        previousArea: 0.6,
        timestamp: t1,
        previousTimestamp: t0,
      );
      final result = service.assess([obj]);
      expect(result, isNull);
    });
  });
}
