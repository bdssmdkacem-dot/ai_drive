import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/constants/app_constants.dart';

/// Watches the accelerometer while the vehicle is parked and flags a
/// probable impact (someone hitting/scratching the car, a break-in
/// attempt jostling it, etc.) so the caller can start emergency
/// recording + push a notification.
class ParkingModeService {
  StreamSubscription<AccelerometerEvent>? _sub;
  double? _restingMagnitude;
  final _impactController = StreamController<double>.broadcast();

  /// Emits the impact magnitude (m/s^2 delta) whenever a likely impact is
  /// detected.
  Stream<double> get onImpact => _impactController.stream;

  void start() {
    _restingMagnitude = null;
    _sub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onEvent);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _restingMagnitude = null;
  }

  void _onEvent(AccelerometerEvent e) {
    final magnitude = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

    if (_restingMagnitude == null) {
      _restingMagnitude = magnitude;
      return;
    }

    final delta = (magnitude - _restingMagnitude!).abs();

    if (delta > AppConstants.impactAccelerationThreshold) {
      _impactController.add(delta);
      // Don't let a real hit permanently shift the resting baseline.
    } else {
      // Slowly adapt to gravity-orientation drift (phone resettling).
      _restingMagnitude = _restingMagnitude! * 0.98 + magnitude * 0.02;
    }
  }

  void dispose() {
    stop();
    _impactController.close();
  }
}
