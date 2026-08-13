import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/themes/app_theme.dart';
import '../../../shared/models/incident.dart';
import '../../../shared/repositories/trip_repository.dart';
import '../../../shared/utils/camera_image_converter.dart';
import '../../camera/services/camera_manager.dart';
import '../../voice/services/voice_assistant_service.dart';
import '../services/driver_monitor_service.dart';

class DriverMonitorScreen extends StatefulWidget {
  const DriverMonitorScreen({super.key});

  @override
  State<DriverMonitorScreen> createState() => _DriverMonitorScreenState();
}

class _DriverMonitorScreenState extends State<DriverMonitorScreen> {
  final _service = DriverMonitorService();
  final _voice = VoiceAssistantService();
  final _tripRepo = TripRepository();

  CameraController? _controller;
  DriverAlertType _alert = DriverAlertType.none;
  bool _busy = false;
  DateTime? _lastSpokenAt;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _voice.init();
    final controller = await CameraManager.instance.startDriverCamera(
      onFrame: _onFrame,
    );
    if (mounted) setState(() => _controller = controller);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy) return;
    _busy = true;
    try {
      final controller = _controller;
      if (controller == null) return;
      final inputImage = CameraImageConverter.toInputImage(
        image,
        controller.description,
        controller.description.sensorOrientation,
      );
      if (inputImage == null) return;

      final result = await _service.processFrame(inputImage);
      if (mounted) setState(() => _alert = result.type);

      if (result.type == DriverAlertType.drowsy ||
          result.type == DriverAlertType.lookingAway) {
        await _handleAlert(result.type);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _handleAlert(DriverAlertType type) async {
    final now = DateTime.now();
    final last = _lastSpokenAt;
    if (last != null && now.difference(last).inSeconds < 5) return;
    _lastSpokenAt = now;

    final phrase = type == DriverAlertType.drowsy
        ? 'انتبه! تبدو متعبًا، فكر بأخذ استراحة'
        : 'ركّز على الطريق من فضلك';
    await _voice.speak(phrase);

    await _tripRepo.logIncident(
      Incident()
        ..type = type == DriverAlertType.drowsy
            ? IncidentType.drowsiness
            : IncidentType.phoneUsage
        ..occurredAt = now,
    );
  }

  @override
  void dispose() {
    _service.dispose();
    CameraManager.instance.stopDriverCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Monitor')),
      body: Column(
        children: [
          Expanded(
            child: controller != null && controller.value.isInitialized
                ? CameraPreview(controller)
                : const Center(child: CircularProgressIndicator()),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: _alertColor(_alert).withOpacity(0.15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_alertIcon(_alert), color: _alertColor(_alert)),
                const SizedBox(width: 10),
                Text(
                  _alertLabel(_alert),
                  style: TextStyle(
                    color: _alertColor(_alert),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _alertColor(DriverAlertType type) => switch (type) {
        DriverAlertType.drowsy => AppTheme.danger,
        DriverAlertType.eyesClosed => AppTheme.warning,
        DriverAlertType.lookingAway => AppTheme.warning,
        DriverAlertType.noFaceDetected => AppTheme.textSecondary,
        DriverAlertType.none => AppTheme.success,
      };

  IconData _alertIcon(DriverAlertType type) => switch (type) {
        DriverAlertType.drowsy => Icons.bedtime,
        DriverAlertType.eyesClosed => Icons.visibility_off,
        DriverAlertType.lookingAway => Icons.visibility_off,
        DriverAlertType.noFaceDetected => Icons.face_retouching_off,
        DriverAlertType.none => Icons.check_circle,
      };

  String _alertLabel(DriverAlertType type) => switch (type) {
        DriverAlertType.drowsy => 'Drowsiness detected',
        DriverAlertType.eyesClosed => 'Eyes closed',
        DriverAlertType.lookingAway => 'Looking away from road',
        DriverAlertType.noFaceDetected => 'No face detected',
        DriverAlertType.none => 'Alert',
      };
}
