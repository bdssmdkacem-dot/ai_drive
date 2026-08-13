import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'trip_stats_accumulator.dart';

/// Wraps `Geolocator`'s position stream and feeds every fix into a
/// [TripStatsAccumulator], so callers get both live speed/heading and
/// running trip totals (distance, avg/max speed) without duplicating the
/// accumulation logic per screen.
class GpsService {
  final _accumulator = TripStatsAccumulator();
  StreamSubscription<Position>? _sub;
  final _speedController = StreamController<double>.broadcast(); // km/h
  final _headingController = StreamController<double>.broadcast(); // degrees

  Stream<double> get speedKmhStream => _speedController.stream;
  Stream<double> get headingStream => _headingController.stream;

  double get distanceKm => _accumulator.distanceKm;
  double get maxSpeedKmh => _accumulator.maxSpeedKmh;
  double get avgSpeedKmh => _accumulator.avgSpeedKmh;

  Future<bool> start() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    _accumulator.reset();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // meters — avoid flooding updates while stationary
      ),
    ).listen(_onPosition);

    return true;
  }

  void _onPosition(Position position) {
    _accumulator.addSample(
      speedMps: position.speed,
      timestamp: position.timestamp,
    );
    final speedKmh = (position.speed < 0 ? 0 : position.speed) * 3.6;
    _speedController.add(speedKmh);
    if (position.heading >= 0) {
      _headingController.add(position.heading);
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    _sub?.cancel();
    _speedController.close();
    _headingController.close();
  }
}
