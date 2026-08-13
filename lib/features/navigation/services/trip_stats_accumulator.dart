/// Accumulates distance/speed stats from a stream of (speed, timestamp)
/// samples. Kept as plain Dart with no `Geolocator` dependency so it's
/// unit-testable without a real device/emulator location provider.
class TripStatsAccumulator {
  double _distanceKm = 0;
  double _maxSpeedKmh = 0;
  double _speedSumKmh = 0;
  int _sampleCount = 0;
  DateTime? _lastSampleAt;

  double get distanceKm => _distanceKm;
  double get maxSpeedKmh => _maxSpeedKmh;
  double get avgSpeedKmh => _sampleCount == 0 ? 0 : _speedSumKmh / _sampleCount;

  /// Feed a new GPS fix. [speedMps] is speed in meters/second (as reported
  /// by `Position.speed`), [timestamp] is when the fix was taken.
  void addSample({required double speedMps, required DateTime timestamp}) {
    final speedKmh = (speedMps < 0 ? 0 : speedMps) * 3.6;

    final last = _lastSampleAt;
    if (last != null) {
      final dtHours = timestamp.difference(last).inMilliseconds / 3600000.0;
      if (dtHours > 0 && dtHours < 0.05) {
        // Ignore gaps > ~3 minutes (app backgrounded, GPS lost) so a long
        // gap doesn't get counted as distance traveled at the last known
        // speed.
        _distanceKm += speedKmh * dtHours;
      }
    }

    _maxSpeedKmh = speedKmh > _maxSpeedKmh ? speedKmh : _maxSpeedKmh;
    _speedSumKmh += speedKmh;
    _sampleCount++;
    _lastSampleAt = timestamp;
  }

  void reset() {
    _distanceKm = 0;
    _maxSpeedKmh = 0;
    _speedSumKmh = 0;
    _sampleCount = 0;
    _lastSampleAt = null;
  }
}
