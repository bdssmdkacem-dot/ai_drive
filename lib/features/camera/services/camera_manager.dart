import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Wraps the `camera` plugin and exposes the rear (road-facing) and front
/// (driver-facing) cameras used throughout the app.
///
/// Only one CameraController can stream at a time per physical camera, so
/// screens must call [stopRoadCamera]/[stopDriverCamera] when leaving.
class CameraManager {
  CameraManager._();
  static final CameraManager instance = CameraManager._();

  List<CameraDescription> _cameras = [];
  CameraController? roadController;
  CameraController? driverController;

  Future<void> discoverCameras() async {
    _cameras = await availableCameras();
  }

  CameraDescription? get _rearCamera => _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

  CameraDescription? get _frontCamera {
    try {
      return _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
    } catch (_) {
      return null;
    }
  }

  Future<CameraController> startRoadCamera({
    ResolutionPreset resolution = ResolutionPreset.high,
    void Function(CameraImage image)? onFrame,
  }) async {
    final desc = _rearCamera;
    if (desc == null) {
      throw StateError('No rear camera available on this device.');
    }
    await stopRoadCamera();
    final controller = CameraController(
      desc,
      resolution,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await controller.initialize();
    if (onFrame != null) {
      await controller.startImageStream(onFrame);
    }
    roadController = controller;
    return controller;
  }

  Future<CameraController?> startDriverCamera({
    ResolutionPreset resolution = ResolutionPreset.medium,
    void Function(CameraImage image)? onFrame,
  }) async {
    final desc = _frontCamera;
    if (desc == null) {
      debugPrint('No front camera available — driver monitoring disabled.');
      return null;
    }
    await stopDriverCamera();
    final controller = CameraController(
      desc,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await controller.initialize();
    if (onFrame != null) {
      await controller.startImageStream(onFrame);
    }
    driverController = controller;
    return controller;
  }

  Future<void> stopRoadCamera() async {
    final c = roadController;
    roadController = null;
    if (c != null) {
      if (c.value.isStreamingImages) await c.stopImageStream();
      await c.dispose();
    }
  }

  Future<void> stopDriverCamera() async {
    final c = driverController;
    driverController = null;
    if (c != null) {
      if (c.value.isStreamingImages) await c.stopImageStream();
      await c.dispose();
    }
  }

  Future<void> disposeAll() async {
    await stopRoadCamera();
    await stopDriverCamera();
  }
}
