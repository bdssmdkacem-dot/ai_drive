/// Global, non-secret constants for the AI Drive Assistant app.
class AppConstants {
  AppConstants._();

  static const String appName = 'AI Drive Assistant';
  static const String packageId = 'com.comptaflow.aidrive';

  // Wake word (button-activated in v1 — always-on hotword needs a native
  // engine such as Porcupine and is out of scope for the offline MVP).
  static const String wakeWordLabel = 'Hey Drive';

  // Collision / warning thresholds
  static const double timeToCollisionWarningSeconds = 2.5;
  static const double timeToCollisionDangerSeconds = 1.2;
  static const double minFollowingDistanceMeters = 15;

  // Driver monitoring thresholds
  static const double eyesClosedProbabilityThreshold = 0.35;
  static const int drowsyEyeClosedFramesThreshold = 15; // ~ consecutive frames
  static const double lookingAwayYawThresholdDegrees = 35;

  // Dashcam
  static const int dashcamLoopSegmentMinutes = 3;
  static const int dashcamMaxStoredSegments = 20;
  static const int emergencyClipPreSeconds = 10;
  static const int emergencyClipPostSeconds = 10;

  // Parking mode
  static const double impactAccelerationThreshold = 18.0; // m/s^2 delta

  // AI processing
  static const int detectionFrameSkip = 2; // process every Nth frame
}
