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

/// Live driving camera with a real-time camera preview, bounded AI frame
/// processing, camera controls, risk HUD and the optional 3D visualization.
///
/// Camera preview and AI inference are intentionally decoupled: the preview
/// remains smooth while inference drops frames when the previous inference is
/// still running.
class LiveDrivingScreen extends StatefulWidget {
  const LiveDrivingScreen({super.key});

  @override
  State<LiveDrivingScreen> createState() => _LiveDrivingScreenState();
}

class _LiveDrivingScreenState extends State<LiveDrivingScreen>
    with WidgetsBindingObserver {
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
  bool _startingCamera = false;
  String? _cameraError;
  int _frameCounter = 0;
  int _processedFrames = 0;
  int _droppedFrames = 0;
  DateTime? _lastInferenceAt;
  Duration _lastInferenceLatency = Duration.zero;

  double _zoom = 1.0;
  double _maxZoom = 1.0;
  bool _focusLocked = false;
  _ViewMode _viewMode = _ViewMode.camera;

  DateTime? _lastWarningSpokenAt;
  DateTime? _lastLaneWarningSpokenAt;
  StreamSubscription<double>? _speedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _start();
  }

  Future<void> _start() async {
    try {
      await _voice.init();
      _tripId = await _tripRepo.startTrip();

      final gpsStarted = await _gps.start();
      if (gpsStarted) {
        _speedSub = _gps.speedKmhStream.listen((kmh) {
          if (mounted) setState(() => _speedKmh = kmh);
        });
      }

      await _startRoadCamera();
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError = 'Camera could not start: $e');
      }
    }
  }

  Future<void> _startRoadCamera() async {
    if (_startingCamera) return;
    _startingCamera = true;

    try {
      final controller = await CameraManager.instance.startRoadCamera(
        resolution: ResolutionPreset.high,
      );

      final maxZoom = await controller.getMaxZoomLevel();
      _recorder = DashcamRecorderService(controller);

      // The recorder owns the camera stream so recording and AI frame
      // delivery share one controller. _onFrame applies back-pressure.
      await _recorder!.startLoopRecording(onFrame: _onFrame);

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _maxZoom = maxZoom.clamp(1.0, 8.0);
        _zoom = 1.0;
        _cameraError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError = 'Camera initialization failed: $e');
      }
    } finally {
      _startingCamera = false;
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    _frameCounter++;

    // Keep the preview/recording path responsive. Inference is intentionally
    // sampled rather than processing every camera frame.
    if (_frameCounter % 2 != 0) return;
    if (_busy) {
      _droppedFrames++;
      return;
    }

    _busy = true;
    final startedAt = DateTime.now();

    try {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return;

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

      final latency = DateTime.now().difference(startedAt);
      _processedFrames++;
      _lastInferenceAt = DateTime.now();
      _lastInferenceLatency = latency;

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
    } catch (e) {
      debugPrint('AI frame processing failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _focusAt(Offset localPosition, Size size) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final point = Offset(
      (localPosition.dx / size.width).clamp(0.0, 1.0),
      (localPosition.dy / size.height).clamp(0.0, 1.0),
    );

    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
      if (mounted) setState(() => _focusLocked = true);
    } catch (e) {
      debugPrint('Camera focus control unavailable: $e');
    }
  }

  Future<void> _resetFocus() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFocusPoint(null);
      await controller.setExposurePoint(null);
    } catch (_) {
      // Some camera devices do not support clearing focus/exposure points.
    }
    if (mounted) setState(() => _focusLocked = false);
  }

  Future<void> _setZoom(double value) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = value.clamp(1.0, _maxZoom);
    try {
      await controller.setZoomLevel(next);
      if (mounted) setState(() => _zoom = next);
    } catch (e) {
      debugPrint('Camera zoom unavailable: $e');
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // CameraController is owned by CameraManager/recorder. Do not dispose it
    // from the lifecycle callback while recording; the recorder can recover
    // the stream when the app returns to the foreground.
    if (state == AppLifecycleState.resumed && mounted && _cameraError != null) {
      unawaited(_startRoadCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _resetFocus,
            onTapUp: (details) => _focusAt(details.localPosition, size),
            onScaleUpdate: (details) {
              if (details.scale != 1.0) {
                unawaited(_setZoom(_zoom * details.scale));
              }
            },
            child: ClipRect(
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxWidth / controller.value.aspectRatio,
                    child: CameraPreview(controller),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    if (_cameraError != null) {
      return _CameraErrorView(
        message: _cameraError!,
        onRetry: _startRoadCamera,
      );
    }

    return const Center(
      child: CircularProgressIndicator(color: AppTheme.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final inferenceFps = _processedFrames == 0 || _lastInferenceAt == null
        ? 0
        : (_lastInferenceLatency.inMilliseconds > 0
              ? (1000 / _lastInferenceLatency.inMilliseconds).clamp(0, 60)
              : 0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_viewMode),
              child: _buildMainView(controller),
            ),
          ),
          if (_viewMode == _ViewMode.camera && controller?.value.isInitialized == true)
            Positioned(
              left: 16,
              right: 16,
              bottom: 100,
              child: IgnorePointer(
                child: Row(
                  children: [
                    _CameraStatusChip(
                      icon: Icons.memory,
                      text: '${_lastTracked.length} objects',
                    ),
                    const SizedBox(width: 6),
                    _CameraStatusChip(
                      icon: Icons.speed,
                      text: '${_lastInferenceLatency.inMilliseconds} ms',
                    ),
                    const Spacer(),
                    _CameraStatusChip(
                      icon: _focusLocked ? Icons.lock : Icons.center_focus_strong,
                      text: _focusLocked ? 'FOCUS' : 'AUTO',
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SafeArea(
              child: Row(
                children: [
                  _GlassButton(
                    icon: Icons.arrow_back,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  if (_speedKmh != null) _SpeedBadge(speedKmh: _speedKmh!),
                  const Spacer(),
                  _LaneBadge(position: _lastLanePosition),
                  const SizedBox(width: 8),
                  _RiskBadge(risk: _lastRisk),
                ],
              ),
            ),
          ),
          if (_viewMode == _ViewMode.camera)
            Positioned(
              right: 14,
              top: 110,
              child: SafeArea(
                child: Column(
                  children: [
                    _GlassButton(
                      icon: Icons.add,
                      onPressed: () => _setZoom(_zoom + 0.25),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_zoom.toStringAsFixed(1)}x',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _GlassButton(
                      icon: Icons.remove,
                      onPressed: () => _setZoom(_zoom - 0.25),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            bottom: 20,
            right: 16,
            child: _GlassButton(
              icon: _viewMode == _ViewMode.camera
                  ? Icons.threed_rotation
                  : Icons.videocam,
              onPressed: () {
                setState(() {
                  _viewMode = _viewMode == _ViewMode.camera
                      ? _ViewMode.synthetic
                      : _ViewMode.camera;
                });
              },
            ),
          ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton(
                heroTag: 'save-clip',
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

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 21),
        ),
      ),
    );
  }
}

class _CameraStatusChip extends StatelessWidget {
  const _CameraStatusChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Live camera unavailable',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry camera'),
            ),
          ],
        ),
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
