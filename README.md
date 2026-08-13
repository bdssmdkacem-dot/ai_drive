# AI Drive Assistant

An on-device, offline-first ADAS + dashcam companion app for Android, built
with Flutter. No account, no cloud upload — all AI processing (collision
detection, driver monitoring) runs locally on the phone.

## Feature set (v1)

- **Live driving mode** — road-facing camera + ML Kit object detection/
  tracking, monocular time-to-collision heuristic, spoken (Arabic/English)
  warnings, automatic emergency clip capture, real-time lane-drift
  detection, and a toggleable Tesla-style synthetic visualization view
- **GPS trip tracking** — real distance/avg/max speed, replacing what was
  previously a hardcoded placeholder
- **Driver monitoring** — front camera watches for drowsiness / eyes-closed /
  looking-away using ML Kit Face Detection
- **Dashcam** — loop recording, manual clip save, emergency clip protection
- **Parking mode** — accelerometer-based impact detection while parked,
  auto-records a clip + push notification
- **Voice assistant** — tap-to-talk commands in Arabic/English (navigate
  home/work, record, save clip, find parking/gas station, etc.)
- **Navigation** — Google Maps turn-by-turn
- **Trips & vehicles** — local trip history and multi-vehicle profiles
- **Android Auto** — a v1 foundation (Navigate Home/Work, nearby parking/gas
  search) that hands off to Google Maps; see `docs/ANDROID_AUTO.md` for scope

See `docs/AI.md` for exactly what's fully implemented vs. simplified in v1
(lane detection, wake-word, Android Auto, etc. are documented there with
a clear path to "real" implementations).

## Tech stack

Flutter · Google ML Kit (on-device object + face detection) · Isar (local DB)
· Google Maps SDK · `camera` · `speech_to_text` / `flutter_tts` ·
`sensors_plus` · GitHub Actions CI/CD

## Getting started

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
cp android/local.properties.example android/local.properties
# fill in sdk.dir, flutter.sdk, maps.apiKey
flutter run
```

Full deployment walkthrough (signing, Play Console setup, CI/CD publishing):
see `docs/PLAY_STORE_DEPLOYMENT.md`.

Privacy policy (required for Play Store submission — camera/mic/location
permissions): `docs/PRIVACY.md`.

## Project structure

```
lib/
  core/          theme, routes, constants
  features/      one folder per feature (camera, ai, object_detection,
                 driver_monitor, dashcam, parking, navigation, voice, ...)
  shared/        models (Isar collections), repositories, database, utils
android/         Android platform project (Play Store release config, CI signing)
fastlane/        Play Store listing metadata (English + Arabic)
docs/            AI implementation notes, privacy policy, deployment guide
.github/workflows/  CI (analyze/test/debug build) + Release (signed AAB)
```

## Disclaimer

This app is a driving aid, not a certified safety system. AI detection can
miss objects or produce false warnings — it does not replace attentive
driving. Make this disclaimer visible in the app's onboarding/settings and
in the Play Store listing (already included in the fastlane description).
