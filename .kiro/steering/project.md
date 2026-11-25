# Project: Lenzo

- The app is called **Lenzo**. Use this name in all user-facing text (app label, titles, messages).
- Flutter app, Android only. Code is in `lib/`, Android config in `android/`.
- Visual style: premium and minimal, Lenzo dark-green theme. Colors live in `lib/theme/lenzo_theme.dart`.
- The Android package id is still `com.nitesh.face_tag`. Changing it would install a separate app and lose saved faces, so only change it if the user asks.
- Face detection: Google ML Kit (bundled). Face recognition: FaceNet-512 TFLite (`assets/facenet_512.tflite`). Everything runs on the phone.
- Build/test: `flutter analyze`, `flutter build apk --release`, install with `adb install -r build/app/outputs/flutter-apk/app-release.apk`. Flutter is at `~/development/flutter/bin`, Android SDK at `~/Android/Sdk`.

## After every code change: update the phone app

The user wants the app on their phone (POCO 2201117PI, wireless adb) updated after every change, without asking.

1. Run `flutter analyze` and `flutter test test/`; only continue if both pass.
2. `flutter build apk --release`.
3. Check the APK's package is `com.nitesh.face_tag` with `~/Android/Sdk/build-tools/36.1.0/aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk`.
4. Find the phone with `adb devices -l` (model `2201117PI`); if missing, `adb connect` to its `adb-YDS4XKH6MJKJPNMV` address from `adb mdns services`.
5. Install only with `adb install -r` (an in-place update that keeps data). Compare `firstInstallTime` before and after to confirm it was an update.
6. Never uninstall, clear data, or run `flutter run` / `flutter install` / `flutter drive` against the production app. If the phone isn't reachable, say so and stop.
