import 'package:flutter_test/flutter_test.dart';
import 'package:ai_drive/features/navigation/services/trip_stats_accumulator.dart';

void main() {
  group('TripStatsAccumulator', () {
    test('first sample only sets speed stats, no distance yet', () {
      final acc = TripStatsAccumulator();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      acc.addSample(speedMps: 20, timestamp: t0); // 72 km/h

      expect(acc.distanceKm, 0);
      expect(acc.maxSpeedKmh, closeTo(72, 0.01));
      expect(acc.avgSpeedKmh, closeTo(72, 0.01));
    });

    test('constant speed sampled every second accumulates expected distance', () {
      final acc = TripStatsAccumulator();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      // 20 m/s = 72 km/h, sampled every second for 5 minutes (300 samples) —
      // realistic GPS fix frequency, unlike a single hour-long gap.
      const speedMps = 20.0;
      const totalSeconds = 300;
      for (var i = 0; i <= totalSeconds; i++) {
        acc.addSample(
          speedMps: speedMps,
          timestamp: t0.add(Duration(seconds: i)),
        );
      }

      // Expected distance: 72 km/h * (300/3600) h = 6.0 km
      expect(acc.distanceKm, closeTo(6.0, 0.05));
      expect(acc.maxSpeedKmh, closeTo(72, 0.01));
    });

    test('negative/invalid speed is treated as zero, never goes negative', () {
      final acc = TripStatsAccumulator();
      acc.addSample(speedMps: -5, timestamp: DateTime(2026, 1, 1));
      expect(acc.maxSpeedKmh, 0);
      expect(acc.avgSpeedKmh, 0);
    });

    test('a large time gap between samples is not counted as distance', () {
      final acc = TripStatsAccumulator();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      acc.addSample(speedMps: 30, timestamp: t0);
      // 20-minute gap — e.g. app was backgrounded / GPS lost
      acc.addSample(speedMps: 30, timestamp: t0.add(const Duration(minutes: 20)));

      // Should not have accumulated 30m/s * 20min worth of distance.
      expect(acc.distanceKm, lessThan(5));
    });

    test('reset clears all accumulated stats', () {
      final acc = TripStatsAccumulator();
      acc.addSample(speedMps: 25, timestamp: DateTime(2026, 1, 1));
      acc.addSample(speedMps: 25, timestamp: DateTime(2026, 1, 1, 0, 1));
      acc.reset();

      expect(acc.distanceKm, 0);
      expect(acc.maxSpeedKmh, 0);
      expect(acc.avgSpeedKmh, 0);
    });

    test('avgSpeedKmh reflects the mean of sampled speeds', () {
      final acc = TripStatsAccumulator();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      acc.addSample(speedMps: 10, timestamp: t0); // 36 km/h
      acc.addSample(speedMps: 20, timestamp: t0.add(const Duration(seconds: 30))); // 72 km/h
      acc.addSample(speedMps: 30, timestamp: t0.add(const Duration(seconds: 60))); // 108 km/h

      expect(acc.avgSpeedKmh, closeTo(72, 0.01)); // mean of 36/72/108
      expect(acc.maxSpeedKmh, closeTo(108, 0.01));
    });
  });
}
