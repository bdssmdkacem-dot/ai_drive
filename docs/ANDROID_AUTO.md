# Android Auto — Implementation Notes

## What this v1 foundation does

When AI Drive Assistant is opened on an Android Auto head unit, it shows a
simple list screen (`MainCarScreen.kt`) with:

- **Navigate Home / Navigate Work** — hands off to the device's default
  maps app (Google Maps) via a `geo:` intent, using the home/work
  addresses you set in the phone app's Settings screen.
- **Nearby Parking / Nearby Gas Station** — same hand-off pattern, as a
  map search query.
- A static "manage from your phone" note for dashcam/driver monitoring —
  these are intentionally **not** exposed on the car screen.

## What this deliberately does NOT do (and why)

Per the architecture doc's own guidance and Android Auto's distraction
rules, these are out of scope for the car screen specifically (they remain
fully available on the phone):

- Live camera feed / dashcam preview
- 3D visualization
- Any custom turn-by-turn rendering — we hand off to Google Maps rather
  than implementing `NavigationTemplate` ourselves, which would mean
  reimplementing routing, rerouting, and live traffic on top of what
  Google Maps already does well.

## Known fragility — read before relying on this

`MainCarScreen.readFlutterPref()` reads the phone app's SharedPreferences
directly from Kotlin, using the **legacy** Android SharedPreferences file
name (`FlutterSharedPreferences`, keys prefixed `flutter.`) that the
`shared_preferences` plugin has historically used. This works with the
plugin version pinned in `pubspec.yaml`, but:

- If you upgrade `shared_preferences` to a version that defaults to
  Jetpack DataStore, this read will silently return `null` instead of
  throwing — test this explicitly after any `shared_preferences` upgrade.
- For a version-proof, longer-term approach, replace this with an
  explicit `MethodChannel` between the Flutter app and a small persistent
  native store (or a Room/SQLite table written by both sides), rather than
  depending on a Flutter plugin's internal storage format.

## Testing without a car

Use Android Auto's **Desktop Head Unit (DHU)**, part of the Android SDK:

```bash
# From the Android SDK's extras/google/auto tools, roughly:
adb forward tcp:5277 tcp:5277
desktop-head-unit
```

Full setup: <https://developer.android.com/training/cars/testing>

## Play Store review requirements

Android Auto apps go through **additional** Google review beyond the
normal Play Store process, and the app category declared in
`automotive_app_desc.xml` (currently `poi`) must match what the app
actually does. If you build this out further (e.g. real turn-by-turn),
revisit the category — see
<https://developer.android.com/training/cars/parking> and the sibling
docs there for the current category list and requirements before
submitting.

## Suggested next steps if you extend this

1. Swap the SharedPreferences read for a proper platform-channel bridge.
2. Add a `GridTemplate` or `ActionStrip` for one-tap "Start Parking Mode"
   (state toggle only — no camera preview on the car screen).
3. Surface the current trip's safety-warning count (read-only) via a
   second `Row` once there's a robust way to read Isar data from the
   native side (e.g. a small companion SQLite mirror table, since Isar
   itself doesn't have a stable native-Android read API outside Dart).
