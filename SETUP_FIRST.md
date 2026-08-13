# One manual step required before your first local build

This scaffold was generated in an offline sandbox with no internet access,
so it's missing one small **binary** file that normally ships with every
Flutter Android project: `android/gradle/wrapper/gradle-wrapper.jar`.

`android/gradlew` / `android/gradlew.bat` and
`android/gradle/wrapper/gradle-wrapper.properties` are already in place —
you just need to regenerate the jar once, which takes a few seconds:

## Option A (recommended) — let Flutter do it

From the project root, with the Flutter SDK installed:

```bash
flutter create --platforms=android .
```

This regenerates any missing standard Android wrapper files (including
`gradle-wrapper.jar`) **without touching your existing `lib/`, `pubspec.yaml`,
or the custom `AndroidManifest.xml`/`build.gradle` in this repo** — it only
fills in missing platform boilerplate.

## Option B — generate it directly with Gradle

If you have Gradle installed locally:

```bash
cd android
gradle wrapper --gradle-version 8.6
```

Either option only needs to be run **once**, right after cloning — commit
the resulting `gradle-wrapper.jar` to the repo afterward so CI and other
contributors don't need to repeat this step.
