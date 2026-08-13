import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../core/constants/app_constants.dart';

enum DriverAlertType { none, eyesClosed, drowsy, lookingAway, noFaceDetected }

/// Uses the front (driver-facing) camera + ML Kit's Face Detection API to
/// flag eyes-closed / drowsiness / looking-away / phone-usage-adjacent
/// distraction. This is a heuristic, camera-only implementation — it is a
/// safety *aid*, not a certified driver-monitoring system.
class DriverMonitorService {
  DriverMonitorService() {
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // gives eye-open probabilities
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  late final FaceDetector _detector;
  int _consecutiveClosedFrames = 0;

  Future<DriverAlertResult> processFrame(InputImage inputImage) async {
    final faces = await _detector.processImage(inputImage);

    if (faces.isEmpty) {
      _consecutiveClosedFrames = 0;
      return const DriverAlertResult(DriverAlertType.noFaceDetected, null, null);
    }

    final face = faces.first;
    final leftOpen = face.leftEyeOpenProbability;
    final rightOpen = face.rightEyeOpenProbability;

    final bothEyesLikelyClosed = leftOpen != null &&
        rightOpen != null &&
        leftOpen < AppConstants.eyesClosedProbabilityThreshold &&
        rightOpen < AppConstants.eyesClosedProbabilityThreshold;

    if (bothEyesLikelyClosed) {
      _consecutiveClosedFrames++;
    } else {
      _consecutiveClosedFrames = 0;
    }

    if (_consecutiveClosedFrames >= AppConstants.drowsyEyeClosedFramesThreshold) {
      return DriverAlertResult(DriverAlertType.drowsy, leftOpen, rightOpen);
    }
    if (bothEyesLikelyClosed) {
      return DriverAlertResult(DriverAlertType.eyesClosed, leftOpen, rightOpen);
    }

    final yaw = face.headEulerAngleY; // left/right head turn
    if (yaw != null && yaw.abs() > AppConstants.lookingAwayYawThresholdDegrees) {
      return DriverAlertResult(DriverAlertType.lookingAway, leftOpen, rightOpen);
    }

    return DriverAlertResult(DriverAlertType.none, leftOpen, rightOpen);
  }

  Future<void> dispose() async {
    await _detector.close();
  }
}

class DriverAlertResult {
  const DriverAlertResult(this.type, this.leftEyeOpenProb, this.rightEyeOpenProb);
  final DriverAlertType type;
  final double? leftEyeOpenProb;
  final double? rightEyeOpenProb;
}
