# Play Store Deployment Guide

## 1. One-time local setup

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates Isar *.g.dart files
cp android/local.properties.example android/local.properties
# edit android/local.properties: set sdk.dir, flutter.sdk, and maps.apiKey
```

Get a Google Maps API key (Maps SDK for Android) from the
[Google Cloud Console](https://console.cloud.google.com/google/maps-apis) —
restrict it to your app's package name (`com.comptaflow.aidrive`) and SHA-1
fingerprint.

## 2. Generate your upload keystore (once)

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

```bash
cp android/key.properties.example android/key.properties
# fill in storePassword, keyPassword, keyAlias=upload, storeFile=<absolute path to upload-keystore.jks>
```

**Never commit `upload-keystore.jks` or `key.properties`** — both are
already in `.gitignore`.

## 3. Local release build (sanity check before CI)

```bash
flutter build appbundle --release
# output: build/app/outputs/bundle/release/app-release.aab
```

Install and test the release build on a real device before submitting:

```bash
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

## 4. Play Console setup (first-time, manual)

1. Create the app in [Play Console](https://play.google.com/console) —
   package name `com.comptaflow.aidrive`.
2. Store listing: use `fastlane/metadata/android/en-US/` and `ar/` for the
   title/short/full descriptions (Play Console lets you add both English
   and Arabic as supported languages).
3. **Privacy policy**: host `docs/PRIVACY.md` publicly (GitHub Pages is the
   easiest option — enable Pages on this repo, point it at `/docs`) and
   paste that URL into Play Console's Privacy Policy field.
4. **App content** questionnaire: this app uses Camera, Microphone, and
   Location — declare these accurately, and note that AI processing is
   on-device only (relevant for the Data Safety section: mark camera/mic/
   location as "not collected" / "not shared" since nothing leaves the
   device, but "processed on device").
5. Upload your **first release manually** (App Bundle from step 3) to the
   Internal testing track. Google Play requires at least one manual upload
   before the Play Developer API can publish automatically.
6. Required graphic assets — **icon and feature graphic are already generated**
   for you in `fastlane/metadata/android/en-US/images/` (`icon.png` 512×512,
   `featureGraphic.png` 1024×500) and mirrored under `ar/images/`. Only
   screenshots are still needed:
   - At least 2 phone screenshots (min 320px, max 3840px on the long side) —
     capture these from a real run of the app (Dashboard, Live Driving with
     a risk badge visible, Dashcam, Parking Mode are good candidates) and
     drop them into `fastlane/metadata/android/en-US/images/phoneScreenshots/`
     (folder already created).

## 5. Automating future releases via GitHub Actions

Once step 4.5 (first manual upload) is done:

1. Create a Google Play **service account** (Play Console → Setup → API
   access → link a Google Cloud project → create service account with
   "Release manager" permission).
2. Download its JSON key.
3. Add these repository secrets (Settings → Secrets and variables → Actions):
   - `UPLOAD_KEYSTORE_BASE64` — output of `base64 -i upload-keystore.jks`
   - `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`
   - `MAPS_API_KEY_RELEASE`, `MAPS_API_KEY_DEBUG`
   - `PLAY_SERVICE_ACCOUNT_JSON` — paste the full JSON key
4. Uncomment the "Publish to Play Store" step in
   `.github/workflows/release.yml`.
5. From then on, pushing a tag like `v1.0.1` builds a signed AAB and
   publishes it to the `internal` track (or whichever track you choose via
   the manual `workflow_dispatch` trigger).

## 6. Repo → GitHub, first push

```bash
cd ai_drive
git init
git add .
git commit -m "Initial scaffold: AI Drive Assistant v1"
git branch -M main
git remote add origin git@github.com:<your-username>/ai-drive-assistant.git
git push -u origin main
```
