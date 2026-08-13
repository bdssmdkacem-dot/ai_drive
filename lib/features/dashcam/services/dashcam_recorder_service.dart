import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_constants.dart';

enum RecordingMode { off, loop, manual, emergency }

/// Continuous loop-recording dashcam, with manual clip saving and
/// emergency (impact/collision-triggered) clip protection.
///
/// Loop recording works by re-starting a fixed-length video segment on the
/// [CameraController] every [AppConstants.dashcamLoopSegmentMinutes]
/// minutes, then deleting the oldest segment once
/// [AppConstants.dashcamMaxStoredSegments] is exceeded — this is the
/// standard approach used by dedicated dashcam hardware.
///
/// Important: the `camera` plugin (not this class) decides the actual file
/// path for each recording, returned from `stopVideoRecording()`. We only
/// ever track a segment in [_segments] *after* it's been written — never a
/// path we guessed in advance — otherwise pruning/deletion targets files
/// that don't exist while real segments leak and are never cleaned up.
class DashcamRecorderService {
  DashcamRecorderService(this._controller);

  final CameraController _controller;
  Timer? _segmentTimer;
  RecordingMode _mode = RecordingMode.off;
  final List<File> _segments = [];

  RecordingMode get mode => _mode;
  List<File> get segments => List.unmodifiable(_segments);

  Future<Directory> _dashcamDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'dashcam'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> startLoopRecording() async {
    if (_mode == RecordingMode.loop) return;
    _mode = RecordingMode.loop;
    await _dashcamDir(); // ensure storage dir exists
    await _controller.startVideoRecording();
    _segmentTimer = Timer.periodic(
      Duration(minutes: AppConstants.dashcamLoopSegmentMinutes),
      (_) => _rotateSegment(),
    );
  }

  Future<void> stop() async {
    _segmentTimer?.cancel();
    _segmentTimer = null;
    if (_controller.value.isRecordingVideo) {
      final file = await _controller.stopVideoRecording();
      _segments.add(File(file.path));
      await _pruneOldSegments();
    }
    _mode = RecordingMode.off;
  }

  /// Stops the current segment and keeps it permanently (excluded from
  /// loop pruning), then immediately resumes loop recording. Used for
  /// manual "Save Clip" and voice-triggered saves.
  Future<File?> saveCurrentClip() async {
    if (!_controller.value.isRecordingVideo) return null;
    final xfile = await _controller.stopVideoRecording();
    final saved = File(xfile.path);
    await _controller.startVideoRecording(); // resume loop immediately
    return saved;
  }

  /// Called by the collision-prediction / impact-detection pipeline to
  /// protect the current buffer as an emergency clip.
  Future<File?> captureEmergencyClip() => saveCurrentClip();

  Future<void> _rotateSegment() async {
    if (!_controller.value.isRecordingVideo) return;
    final xfile = await _controller.stopVideoRecording();
    _segments.add(File(xfile.path));
    await _pruneOldSegments();
    await _controller.startVideoRecording();
  }

  Future<void> _pruneOldSegments() async {
    while (_segments.length > AppConstants.dashcamMaxStoredSegments) {
      final oldest = _segments.removeAt(0);
      if (await oldest.exists()) {
        await oldest.delete();
      }
    }
  }
}
