# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Fixed
- **Trip stats were hardcoded to zero** — `LiveDrivingScreen.dispose()`
  always called `endTrip(distanceKm: 0, avgSpeedKmh: 0, maxSpeedKmh: 0)`
  regardless of the actual drive. Now backed by real GPS tracking.
- **Lane detection was built but never wired into `LiveDrivingScreen`** —
  the service existed standalone with no caller. Now integrated into the
  live driving frame pipeline alongside object/collision detection.
- Replaced the lane-detection algorithm's fixed left-half/right-half peak
  search with a whole-frame two-peak search (non-max suppression). The
  half-split version could never detect a real drift event, because
  drifting shifts *both* lane lines toward the same side of the frame —
  exactly the case a fixed half-split misses.

### Added
- Lane detection upgraded from a device-rotation-sensor heuristic to real
  pixel-based edge detection on the road camera's luma plane (still a
  classical heuristic, not a trained model — see `docs/AI.md`).
- Live Driving screen now shows a lane-status badge, speaks a drift
  warning, and logs `IncidentType.laneDeparture` on confirmed drift.
- Android Auto v1 foundation: `CarAppService`/`Session`/`MainCarScreen`
  offering Navigate Home/Work and nearby parking/gas search, handing off
  to Google Maps. See `docs/ANDROID_AUTO.md` for exact scope and a known
  fragility (reads the phone app's SharedPreferences directly using the
  legacy storage format — re-verify after any `shared_preferences`
  plugin upgrade).
- Home/Work address fields in Settings, feeding both the voice assistant's
  "navigate home/work" commands and the new Android Auto screen.
- **GPS trip tracking** — real distance/avg/max speed via `GpsService`,
  backed by a unit-tested `TripStatsAccumulator` (no more hardcoded zeros).
- **"Tesla-style" synthetic visualization** — a stylized `CustomPainter`
  driving scene (converging road, lane lines from real detection,
  vehicles/pedestrians positioned from the AI pipeline) toggleable in
  `LiveDrivingScreen` alongside the raw camera preview. See `docs/AI.md`
  for exactly what "3D" means here (2D canvas perspective tricks, not a
  real 3D engine).

## [1.0.0] — Initial scaffold

### Added
- Full Flutter project structure across all planned features (camera, AI
  detection/tracking, collision prediction, driver monitoring, lane
  heuristic, dashcam, parking mode, voice assistant, navigation, trips,
  vehicles, settings).
- Local-only Isar database — no backend, no account system.
- Android platform config: manifest permissions, signing scaffold,
  adaptive + legacy launcher icons, Play Store feature graphic.
- GitHub Actions CI (analyze/test/debug build) and Release (signed AAB,
  Play Store publish step ready to enable) workflows.
- Play Store metadata (English + Arabic) via `fastlane/metadata/android/`.
- Documentation: `README.md`, `docs/AI.md` (implementation notes & known
  limitations), `docs/PRIVACY.md`, `docs/PLAY_STORE_DEPLOYMENT.md`.
- Unit tests for voice command parsing, collision risk assessment, and
  lane-drift heuristic.

### Known limitations (see `docs/AI.md` for full detail)
- Lane detection is a device-rotation heuristic, not real computer-vision
  lane-line detection.
- Object detection uses Google ML Kit's stock model (coarse categories),
  not a custom-trained vehicle-subclass model.
- No traffic sign/light recognition.
- Distance/collision estimates are a monocular bounding-box-growth proxy,
  not calibrated metric distance.
- Voice wake word ("Hey Drive") is tap-to-talk in this version; true
  always-on hotword detection needs a licensed wake-word engine.
- Android Auto is not implemented — planned as a v2.0 module.

### Not yet verified
- This scaffold was built without a local Flutter SDK/emulator available
  in the build environment. `flutter analyze`, `flutter test`, and a real
  device run have not been executed against this exact code — do this
  before your first release build. See `SETUP_FIRST.md`.
