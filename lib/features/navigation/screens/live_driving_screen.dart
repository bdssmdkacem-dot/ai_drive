import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/themes/app_theme.dart';
import '../../../shared/models/incident.dart';
import '../../../shared/repositories/trip_repository.dart';
import '../../../shared/utils/camera_image_converter.dart';
import '../../ai/models/tracked_object.dart';
import '../../ai/services/collision_prediction_service.dart';
import '../../camera/services/camera_manager.dart';
import '../../dashcam/services/dashcam_recorder_service.dart';
import '../../lane_detection/services/lane_detection_service.dart';
import '../../object_detection/services/object_detection_service.dart';
import '../../voice/services/voice_assistant_service.dart';
import '../services/gps_service.dart';
import '../widgets/tesla_visualization_view.dart';

enum _ViewMode { camera, synthetic }

/// This screen implements the full AI pipeline described in the
/// architecture doc:
/// Camera -> Frame Capture -> Preprocessing -> Object Detection ->
/// Object Tracking -> Distance/Closeness -> Collision Prediction ->
/// Risk Assessment -> Voice Warning -> UI Update.
///
/// It also tracks real trip stats via GPS and offers a synthetic Tesla-style
/// visualization as an alternative to the raw camera preview.
class LiveDrivingScreen extends StatefulWidget {
  const LiveDrivingScreen({super.key});

  @override
  State<LiveDrivingScreen> createState() => _LiveDrivingScreenState();
}

class _LiveDrivingScreenState extends State<LiveDrivingScreen> {
  final _objectDetection = ObjectDetectionService();
  final _collisionPrediction = CollisionPredictionService();
  final _laneDetection = LaneDetectionService();
  final _voice = VoiceAssistantService();
  final _tripRepo = TripRepository();
  final _gps = GpsService();

  CameraController? _controller;
  DashcamRecorderService? _recorder;
  RiskAssessment? _lastRisk;
  LanePosition _lastLanePosition = LanePosition.unknown;
  List<TrackedObject> _lastTracked = const [];
  double? _speedKmh;
  int? _tripId;
  bool _busy = false;
  int _frameCounter = 0;
  DateTime? _lastWarningSpokenAt;
  DateTime? _lastLaneWarningSpokenAt;
  _ViewMode _viewMode = _ViewMode.camera;

  StreamSubscription<double>? _speedSub;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _start();
  }

  Future<void> _start() async {
    await _voice.init();
    _tripId = await _tripRepo.startTrip();

    final gpsStarted = await _gps.start();
    if (gpsStarted) {
      _speedSub = _gps.speedKmhStream.listen((kmh) {
        if (mounted) setState(() => _speedKmh = kmh);
      });
    }

    final controller = await CameraManager.instance.startRoadCamera(
      onFrame: _onFrame,
    );
    _recorder = DashcamRecorderService(controller);
    await _recorder!.startLoopRecording();

    if (mounted) setState(() => _controller = controller);
  }

  Future<void> _onFrame(CameraImage image) async {
    _frameCounter++;
    if (_frameCounter % 2 != 0) return;
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

      final tracked = await _objectDetection.processFrame(
        inputImage,
        image.width,
        image.height,
      );
      final risk = _collisionPrediction.assess(tracked);

      final lanePosition = _laneDetection.evaluate(
        yPlane: image.planes.first.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      if (mounted) {
        setState(() {
          _lastRisk = risk;
          _lastLanePosition = lanePosition;
          _lastTracked = tracked;
        });
      }

      if (risk != null &&
          (risk.level == RiskLevel.warning || risk.level == RiskLevel.danger)) {
        await _handleRisk(risk);
      }

      if (lanePosition == LanePosition.driftingLeft ||
          lanePosition == LanePosition.driftingRight) {
        await _handleLaneDrift(lanePosition);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _handleLaneDrift(LanePosition position) async {
    final now = DateTime.now();
    final last = _lastLaneWarningSpokenAt;
    if (last != null && now.difference(last).inSeconds < 4) return;
    _lastLaneWarningSpokenAt = now;

    unawaited(_voice.speak('انتبه، انحراف عن المسار'));
    await _tripRepo.logIncident(
      Incident()
        ..type = IncidentType.laneDeparture
        ..occurredAt = now,
    );
  }

  Future<void> _handleRisk(RiskAssessment risk) async {
    final now = DateTime.now();
    final last = _lastWarningSpokenAt;
    if (last == null || now.difference(last).inSeconds >= 3) {
      _lastWarningSpokenAt = now;
      final phrase = risk.level == RiskLevel.danger
          ? 'تحذير! خطر اصطدام'
          : 'انتبه، مركبة قريبة';
      unawaited(_voice.speak(phrase));
    }

    if (risk.level == RiskLevel.danger) {
      final clip = await _recorder?.captureEmergencyClip();
      await _tripRepo.logIncident(
        Incident()
          ..type = IncidentType.collisionWarning
          ..occurredAt = now
          ..videoPath = clip?.path,
      );
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _speedSub?.cancel();
    _gps.stop();
    _gps.dispose();
    _recorder?.stop();
    _objectDetection.dispose();
    CameraManager.instance.stopRoadCamera();
    if (_tripId != null) {
      _tripRepo.endTrip(
        _tripId!,
        distanceKm: _gps.distanceKm,
        avgSpeedKmh: _gps.avgSpeedKmh,
        maxSpeedKmh: _gps.maxSpeedKmh,
      );
    }
    super.dispose();
  }

  Widget _buildMainView(CameraController? controller) {
    if (_viewMode == _ViewMode.synthetic) {
      return TeslaVisualizationView(
        trackedObjects: _lastTracked,
        risk: _lastRisk,
        laneReading: _laneDetection.lastReading,
        speedKmh: _speedKmh,
      );
    }
    if (controller != null && controller.value.isInitialized) {
      return CameraPreview(controller);
    }
    return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildMainView(controller),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  if (_speedKmh != null) ...[
                    const SizedBox(width: 4),
                    _SpeedBadge(speedKmh: _speedKmh!),
                  ],
                  const Spacer(),
                  _LaneBadge(position: _lastLanePosition),
                  const SizedBox(width: 8),
                  _RiskBadge(risk: _lastRisk),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            right: 20,
            child: FloatingActionButton.small(
              heroTag: 'view-mode-fab',
              backgroundColor: AppTheme.surface,
              onPressed: () {
                setState(() {
                  _viewMode = _viewMode == _ViewMode.camera
                      ? _ViewMode.synthetic
                      : _ViewMode.camera;
                });
              },
              child: Icon(
                _viewMode == _ViewMode.camera ? Icons.threed_rotation : Icons.videocam,
                color: AppTheme.primary,
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton(
                backgroundColor: AppTheme.primary,
                onPressed: () async {
                  final clip = await _recorder?.saveCurrentClip();
                  if (clip != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Clip saved')),
                    );
                  }
                },
                child: const Icon(Icons.videocam, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge({required this.speedKmh});
  final double speedKmh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${speedKmh.round()} km/h',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _LaneBadge extends StatelessWidget {
  const _LaneBadge({required this.position});
  final LanePosition position;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (position) {
      LanePosition.driftingLeft => (Icons.arrow_back, 'DRIFT L', AppTheme.warning),
      LanePosition.driftingRight => (Icons.arrow_forward, 'DRIFT R', AppTheme.warning),
      LanePosition.centered => (Icons.vertical_align_center, 'LANE OK', AppTheme.success),
      LanePosition.unknown => (Icons.help_outline, 'LANE --', AppTheme.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.risk});
  final RiskAssessment? risk;

  @override
  Widget build(BuildContext context) {
    final level = risk?.level ?? RiskLevel.none;
    final (color, label) = switch (level) {
      RiskLevel.danger => (AppTheme.danger, 'DANGER'),
      RiskLevel.warning => (AppTheme.warning, 'WARNING'),
      RiskLevel.caution => (AppTheme.warning.withValues(alpha: 0.7), 'CAUTION'),
      RiskLevel.none => (AppTheme.success, 'CLEAR'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
