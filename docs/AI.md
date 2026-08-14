# AI Pipeline — Implementation Notes & Roadmap

This documents what's real vs. simplified in v1, so future work (yours or an
agent's) picks up from an accurate baseline instead of assuming the
architecture doc's feature list is fully implemented.

## What's fully functional in v1

- **Object detection & tracking** (`object_detection_service.dart`) — uses
  Google ML Kit's on-device Object Detection & Tracking API. Real detection,
  real tracking IDs, runs offline after the model is bundled.
- **Collision / risk assessment** (`collision_prediction_service.dart`) —
  derives a time-to-collision estimate from how fast a tracked object's
  bounding box grows frame-to-frame. This is a *monocular heuristic*, not a
  calibrated distance measurement — see "Known limitations" below.
- **Driver monitoring** (`driver_monitor_service.dart`) — uses ML Kit Face
  Detection's eye-open probabilities and head-yaw angle for drowsiness /
  looking-away detection. Real, working, on-device.
- **Dashcam** (`dashcam_recorder_service.dart`) — real loop recording,
  manual clip save, emergency clip protection.
- **Parking mode** (`parking_mode_service.dart`) — real accelerometer-based
  impact detection.
- **Voice** (`voice_assistant_service.dart`) — real speech-to-text /
  text-to-speech via platform packages, Arabic + English command parsing.
- **GPS trip tracking** (`gps_service.dart`, `trip_stats_accumulator.dart`) —
  real distance/avg-speed/max-speed tracking from `Geolocator`'s position
  stream, replacing what was previously hardcoded to zero in
  `LiveDrivingScreen`. The distance-accumulation math is isolated in a
  pure-Dart, unit-tested class with no location-plugin dependency.
- **"Tesla-style" synthetic visualization** (`tesla_visualization_view.dart`)
  — a stylized driving scene built with `CustomPainter`, toggleable
  alongside the raw camera preview in `LiveDrivingScreen`. Honest scope:
  this is 2D canvas drawing with perspective tricks (converging lines,
  size-by-distance, ground-contact shadows), not a real 3D engine/scene
  graph like Tesla's actual UI. Object positions come from the same
  detection/tracking data used for collision warnings — lateral position
  from where each detection sits in the camera frame, "distance" from the
  same bounding-box-size proxy used elsewhere (not calibrated depth). Lane
  lines are drawn from `LaneDetectionService`'s actual detected peak
  positions when available, falling back to a plausible symmetric lane
  when the current frame has no confident reading (so the scene doesn't
  flicker to "no road"). Object motion is smoothed frame-to-frame (an
  exponential blend toward each new detection, driven by a continuous
  60fps ticker) rather than snapping directly to raw detection output,
  since the AI pipeline only produces a new reading every other camera
  frame — unsmoothed, that reads as jittery rather than fluid. Object
  boxes are also perspective-skewed (via `Canvas.transform`/
  `Matrix4.skewX`) based on lateral offset and depth, so they lean toward
  the vanishing point consistent with the converging road/lane lines
  instead of floating as flat axis-aligned rectangles. The scene's
  proportions (vanishing point height, road width) and the speed
  readout's position adapt to portrait vs. landscape via the widget's own
  aspect ratio at paint time — there's no orientation lock anywhere in
  the app, so this needed to hold up in both without distortion. The
  camera-preview view mode is similarly wrapped to crop-to-fill rather
  than stretch when the aspect ratio doesn't match the screen, and
  switching between camera/synthetic modes crossfades via
  `AnimatedSwitcher` instead of a hard cut.

## Known limitations / simplified in v1

1. **Lane detection** — v1 now runs a real pixel-based edge-detection
   heuristic directly on the road camera's luma plane (see
   `lane_detection_service.dart`): it finds the two strongest brightness
   edges in a bottom-of-frame ROI (candidate lane lines), tracks their
   midpoint against true frame center, and smooths/confirms drift across
   several frames before alerting. This is wired into `LiveDrivingScreen`
   (spoken warning + `IncidentType.laneDeparture` logging + a lane-status
   badge in the UI) — it was previously built but never actually
   connected to the live pipeline; that's fixed now.

   This is still a classical heuristic, not a trained segmentation
   network — it assumes roughly straight, reasonably visible lane
   markings and will struggle with faded lines, heavy shadows, glare, or
   sharp curves. For a step up in robustness:
   - A native OpenCV pipeline (proper Canny + Hough transform), or
   - A dedicated lane-segmentation TFLite model (e.g. an exported
     Ultra-Fast-Lane-Detection or similar model), run via `tflite_flutter`.
   Either is a real chunk of work — plan a v1.1 milestone for this if the
   current heuristic's false-positive/negative rate isn't good enough in
   real-world testing.

2. **Vehicle sub-classification** (car vs. truck vs. motorcycle vs. bus) —
   ML Kit's stock object detector gives coarse categories only. For
   class-level accuracy, export a mobile-optimized YOLO (e.g. YOLOv8n) to
   TFLite and swap it into `ObjectDetectionService`.

3. **Traffic sign / traffic light recognition** — not implemented in v1.
   This needs its own detection model (traffic signs are a distinct,
   well-studied CV task) — a good v1.2 candidate.

4. **Distance estimation** — the "closeness" score is a bounding-box-area
   proxy, not metric distance. Real metric distance needs either a
   calibrated single-camera depth model, stereo camera input, or fusing in
   a rangefinder/ultrasonic accessory. Treat current warnings as relative
   ("something is closing in fast"), not "that car is 12 meters away."

5. **Wake word ("Hey Drive")** — v1 uses tap-to-talk instead of an always-on
   hotword. Always-on wake-word detection needs a dedicated engine (e.g.
   Picovoice Porcupine) with its own native integration and model license.

6. **Android Auto** — a working v1 foundation now exists (list-based
   actions that hand off to Google Maps for actual navigation — see
   `docs/ANDROID_AUTO.md` for exactly what's implemented, what's
   deliberately excluded, and a known fragility in how it reads the
   phone app's saved home/work addresses). Full turn-by-turn rendered on
   the car's own screen (`NavigationTemplate`) is still not implemented.

7. **Concurrent camera streaming + recording — FIXED, was a real bug.**
   `LiveDrivingScreen` originally called `controller.startImageStream()`
   for AI frames *and* a separate plain `controller.startVideoRecording()`
   for the dashcam, on the same `CameraController`. That combination isn't
   supported by the `camera` plugin — it doesn't throw, but frame delivery
   to `startImageStream`'s callback silently stops once recording starts.
   Symptom in the field: the app runs fine, dashcam records fine, but no
   collision/lane-drift/risk badges ever trigger, because the AI pipeline
   never receives another frame after recording begins.

   Fixed by using `CameraController.startVideoRecording(onAvailable:
   callback)` instead — the plugin's own supported path for simultaneous
   recording + frame streaming (it routes to `startVideoCapturing`
   internally). `DashcamRecorderService.startLoopRecording` now takes an
   optional `onFrame` parameter and threads it through every
   start/stop/restart of recording (initial start, segment rotation,
   resuming after a saved clip) so frame delivery survives all of those.
   `CameraManager.startRoadCamera` no longer starts an image stream itself
   — screens that need AI frames from the road camera must go through the
   recorder's `onFrame`, not a separate `startImageStream` call.

## Suggested next milestones

- v1.0: ship current feature set (this scaffold), test thoroughly on 3-4
  real Android devices, closed testing track on Play Console.
- v1.1: real lane detection (native CV or TFLite segmentation model).
- v1.2: traffic sign/light recognition; custom YOLO for vehicle sub-classes.
- v1.3: always-on wake word.
- v1.4: Android Auto — replace the SharedPreferences read with a proper
  platform-channel bridge; add parking-mode toggle and read-only trip
  safety stats to the car screen (see docs/ANDROID_AUTO.md).
- v2.0: full turn-by-turn rendered on the car's own screen
  (`NavigationTemplate`), if Google Maps hand-off proves insufficient.
