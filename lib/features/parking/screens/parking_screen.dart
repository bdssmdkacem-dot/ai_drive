import 'package:flutter/material.dart';

import '../../../core/themes/app_theme.dart';
import '../../../shared/models/incident.dart';
import '../../../shared/repositories/trip_repository.dart';
import '../../camera/services/camera_manager.dart';
import '../../dashcam/services/dashcam_recorder_service.dart';
import '../../notifications/services/notification_service.dart';
import '../services/parking_mode_service.dart';

class ParkingScreen extends StatefulWidget {
  const ParkingScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<ParkingScreen> createState() => _ParkingScreenState();
}

class _ParkingScreenState extends State<ParkingScreen> {
  final _parkingMode = ParkingModeService();
  final _tripRepo = TripRepository();
  DashcamRecorderService? _recorder;
  bool _active = false;
  int _impactCount = 0;

  Future<void> _toggle() async {
    if (_active) {
      _parkingMode.stop();
      await _recorder?.stop();
      await CameraManager.instance.stopRoadCamera();
      setState(() => _active = false);
      return;
    }

    final controller = await CameraManager.instance.startRoadCamera();
    _recorder = DashcamRecorderService(controller);

    _parkingMode.onImpact.listen((magnitude) async {
      _impactCount++;
      final clip = await _recorder?.captureEmergencyClip();
      await _tripRepo.logIncident(
        Incident()
          ..type = IncidentType.parkingImpact
          ..occurredAt = DateTime.now()
          ..videoPath = clip?.path
          ..note = 'Impact magnitude: ${magnitude.toStringAsFixed(1)}',
      );
      await NotificationService.instance.showParkingAlert(
        title: 'Possible impact detected',
        body: 'Your vehicle may have been hit. A clip was saved.',
      );
      if (mounted) setState(() {});
    });

    _parkingMode.start();
    setState(() => _active = true);
  }

  @override
  void dispose() {
    _parkingMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_parking,
            size: 72,
            color: _active ? AppTheme.primary : AppTheme.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            _active ? 'Parking Mode Active' : 'Parking Mode Off',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _active
                ? 'Watching for impacts • $_impactCount detected this session'
                : 'Detects impacts while your car is parked and records a clip',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _toggle,
            style: ElevatedButton.styleFrom(
              backgroundColor: _active ? AppTheme.danger : AppTheme.primary,
            ),
            child: Text(_active ? 'Stop Parking Mode' : 'Start Parking Mode'),
          ),
        ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Parking Mode')),
      body: body,
    );
  }
}
