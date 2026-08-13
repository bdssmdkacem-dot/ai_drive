import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Converts a [CameraImage] frame into the [InputImage] format expected
/// by Google ML Kit.
///
/// Android-only for the v1 release. The camera image planes are
/// concatenated into a single [Uint8List] before being passed to ML Kit.
class CameraImageConverter {
  CameraImageConverter._();

  static InputImage? toInputImage(
    CameraImage image,
    CameraDescription description,
    int sensorOrientation,
  ) {
    if (!Platform.isAndroid) {
      return null;
    }

    final bytes = _concatenatePlanes(image.planes);

    final rotation =
        InputImageRotationValue.fromRawValue(sensorOrientation) ??
            InputImageRotation.rotation0deg;

    final format =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21;

    final metadata = InputImageMetadata(
      size: Size(
        image.width.toDouble(),
        image.height.toDouble(),
      ),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: metadata,
    );
  }

  static Uint8List _concatenatePlanes(List<Plane> planes) {
    final allBytes = <int>[];

    for (final plane in planes) {
      allBytes.addAll(plane.bytes);
    }

    return Uint8List.fromList(allBytes);
  }
}
