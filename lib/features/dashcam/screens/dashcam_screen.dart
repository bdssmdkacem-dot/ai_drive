import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/themes/app_theme.dart';
import '../../camera/services/camera_manager.dart';
import '../services/dashcam_recorder_service.dart';

class DashcamScreen extends StatefulWidget {
  const DashcamScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<DashcamScreen> createState() => _DashcamScreenState();
}

class _DashcamScreenState extends State<DashcamScreen> {
  CameraController? _controller;
  DashcamRecorderService? _recorder;
  bool _recording = false;

  Future<void> _startCamera() async {
    final controller = await CameraManager.instance.startRoadCamera();
    _recorder = DashcamRecorderService(controller);
    if (mounted) setState(() => _controller = controller);
  }

  Future<void> _toggleRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;
    if (_recording) {
      await recorder.stop();
    } else {
      await recorder.startLoopRecording();
    }
    setState(() => _recording = !_recording);
  }

  Future<void> _saveClip() async {
    final file = await _recorder?.saveCurrentClip();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(file != null ? 'Clip saved' : 'Not recording')),
    );
  }

  @override
  void dispose() {
    _recorder?.stop();
    CameraManager.instance.stopRoadCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    final body = Column(
      children: [
        Expanded(
          child: controller != null && controller.value.isInitialized
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CameraPreview(controller),
                )
              : Center(
                  child: ElevatedButton.icon(
                    onPressed: _startCamera,
                    icon: const Icon(Icons.videocam),
                    label: const Text('Start Dashcam'),
                  ),
                ),
        ),
        if (controller != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _toggleRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _recording ? AppTheme.danger : AppTheme.primary,
                  ),
                  icon: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
                  label: Text(_recording ? 'Stop' : 'Record (Loop)'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _recording ? _saveClip : null,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Clip'),
                ),
              ],
            ),
          ),
      ],
    );

    if (widget.embedded) {
      return Padding(padding: const EdgeInsets.all(16), child: body);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Dashcam')),
      body: Padding(padding: const EdgeInsets.all(16), child: body),
    );
  }
}
