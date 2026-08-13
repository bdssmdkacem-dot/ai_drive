import 'dart:io';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Converts a `camera` plugin [CameraImage] frame into the `InputImage`
/// type ML Kit expects. Handles the Android (NV21) case used throughout
/// this app; iOS is not a target platform for v1 (Android-only release).
class CameraImageConverter {
  CameraImageConverter._();

  static InputImage? toInputImage(
    CameraImage image,
    CameraDescription description,
    int sensorOrientation,
  ) {
    if (!Platform.isAndroid) return null;

    final bytes = _concatenatePlanes(image.planes);

    final rotation =
        InputImageRotationValue.fromRawValue(sensorOrientation) ??
            InputImageRotation.rotation0deg;

    final format =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21;

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  static List<int> _concatenatePlanes(List<Plane> planes) {
    final allBytes = <int>[];
    for (final plane in planes) {
      allBytes.addAll(plane.bytes);
    }
    return allBytes;
  }
}
