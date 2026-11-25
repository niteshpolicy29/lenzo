# Lenzo

Lenzo is an Android app (Flutter) that remembers who you lent money to and who you borrowed from, using face recognition. Point the camera at someone and Lenzo shows their name, what they owe you, what you owe them, their personal note and any payment reminder. Everything runs and stays on the phone.

## Features

- **Face recognition on the phone:** Google ML Kit finds faces, and a FaceNet-512 TFLite model recognises them. Nothing is sent to a server.
- **Camera Home screen:**
  - **Overlay:** a faint face-tracking mesh, plus a panel that shows only the details that exist for that person (To Receive, To Pay, note, reminder).
  - **Scanning glow:** mint while checking a face, one pulse when the face is recognised, amber for someone not saved.
  - **Cameras:** switching uses only the main rear and main front camera.
- **Saved People:** To Receive, To Pay and Others tabs, search, and a To Receive / To Pay summary card. Contacts can be added from the camera or from a gallery photo, through Lenzo's own photo picker.
- **Money tracking:** Money Lent and Money Borrowed, each with **Add** and **Less**, an outstanding balance, and a dated history. Personal notes and payment reminders with an in-app calendar.
- **Onboarding:** Welcome, owner face scan and a three-slide tutorial. Progress is saved, so a restart continues where you left off.
- **Navigation:** Settings, Home and Saved People sit side by side and follow your finger when you swipe. One glowing "connection" thread runs behind all three pages.

## Tech stack

| Area | Packages |
|---|---|
| Camera and faces | `camera`, `google_mlkit_face_detection`, `tflite_flutter` (FaceNet-512), `image` |
| Storage | `sqflite` (database v6, with a `money_entries` table), `path_provider` |
| Photos | `photo_manager` (Lenzo's own picker) |
| Motion and sensors | `flutter_animate`, `animations`, `lottie`, `flutter_staggered_animations`, `sensors_plus` |

The app has about 15,000 lines of Dart in `lib/`. The design system (colour, spacing, type and motion tokens, plus shared components) is in `lib/design/`.

## Build and run

```bash
flutter analyze
flutter test test/
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk   # updates in place, keeps data
```

- **Production app:** the package id is `com.nitesh.face_tag`. Don't change it: a new id installs a separate app without your saved faces.
- **Test app:** device tests run in a separate debug/profile app, `com.nitesh.face_tag.devtest` ("Lenzo Test"). That way an automated run can never uninstall or wipe the real app.

```bash
flutter build apk --profile --target=integration_test/camera_test.dart
flutter drive --profile --use-application-binary build/app/outputs/flutter-apk/app-profile.apk \
  --driver=test_driver/integration_test.dart --target=integration_test/camera_test.dart
```

---

# Building Lenzo with Kiro

These answers describe what was actually used on this project. Where a Kiro feature wasn't used, the answer says so.

## Kiro IDE, CLI, Web, Crew: how did they differ?

The whole project was built in the **Kiro IDE**, so there is no comparison with the CLI, Web or Crew to report.

- **Mode:** most work ran in **Autopilot** Vibe sessions. Kiro read the code, made changes across many files, and ran `flutter analyze`, the tests and the Android build in the terminal.
- **Phone access:** Kiro installed builds over wireless `adb` and pulled screen recordings and screenshots from the phone.
- **Images:** screenshots dropped into the chat (bugs, design references) were read directly, and many of the requests started from one.

## Custom agents

**No custom agents were created.** The work used Kiro's default agent. For the larger changes, investigating code before editing it was part of that agent's normal flow.

The practice with the most impact was a strict testing rule rather than an agent: every device test runs only in the separate Lenzo Test app, never in the real one. An early automated run uninstalled the real app and erased its data, which couldn't be recovered. The separate test app, a database check that refuses to run anywhere else, and a package-id check before every install were all added after that, so it couldn't happen again.

## Agent hooks

**No agent hooks were set up** (the project has no `.kiro/hooks/` folder).

The repeated workflow, "after every change: analyze, test, build, check the package id, update the phone app in place", was saved as a **steering rule** instead (see below). A `PostTaskExec` or `Stop` hook running `flutter analyze && flutter test` would be a natural next step.

## Spec-driven development vs vibe coding

**No Kiro specs were used.** The project was built through Vibe sessions.

The requests themselves often worked like small specs. Many were long, structured messages with numbered requirements, exact behaviour (for example the A–E recognition-overlay cases and the Add / Less examples), design limits and a test list. Kiro treated each one as a checklist and reported which items were verified and which weren't.

| Approach used here | Effect |
|---|---|
| Detailed, numbered requests | Clear acceptance criteria, so each change came with matching tests |
| Short follow-ups ("update my app", "add space under the tags") | Fast changes to small details |
| Screenshots of bugs | The exact screen and state to fix |

The weak point of vibe coding showed up with the Saved People tab bug. Two fixes were made before the real cause was found: the tab was never lost; the highlight fell back to the first tab for a moment. A spec with a written requirement and a test for that exact state would likely have caught it sooner.

## Steering docs

The project has one steering file, `.kiro/steering/project.md`, which is always included. It records:

- the app name (Lenzo) to use in all text, and the visual style (premium, minimal, dark green);
- that the Android package id must stay `com.nitesh.face_tag`, and why (changing it loses saved faces);
- the face-detection and recognition stack, and that everything runs on the phone;
- the build, test and install commands and the Flutter and Android SDK paths;
- **after every code change, update the phone app**: analyze, test, build, check the package id, install only with `adb install -r`, and never uninstall or clear data.

The rules that made the biggest difference were the **data-safety ones**: the package id and the "update in place only" install rule. They turned a one-time lesson (the data loss) into behaviour that holds in every session, and they removed the need to repeat "update my app" after each change.

## MCP

**No MCP servers were configured.** Kiro's built-in tools covered what was needed:

- **Web search and fetch:** used to read the Impeccable design guidelines (its audit, native-app audit and onboarding checklists) directly from GitHub. Those checklists scored the screens on accessibility, performance, theming, platform fit and screen sizes.
- **Terminal:** `adb` for installing on the phone, `screenrecord` for recordings, and a small Python/OpenCV script to check recordings frame by frame. That script found blank camera frames during camera switching and confirmed the background colour stays the same during swipes.

An MCP server for Android device control or Flutter DevTools could replace parts of that scripting.

## Property-based testing (PBT)

**No property-based testing library was used.** The tests are example-based Flutter unit and widget tests: about 150 tests in 9 files under `test/`, plus 3 on-device tests.

Some tests check a rule across many inputs, which is close to PBT in spirit:

- every saved person falls into at least one Saved People tab, across all combinations of lent, borrowed and repaid;
- the background thread is continuous across all three pages, and its drift never jumps between frames or leaves its lane;
- face-point smoothing never drifts from the true position;
- only one guidance message is ever on screen, checked every 10 ms during a change;
- the onboarding screens fit without scrolling at several screen sizes and text sizes.

**Issues these tests caught:**

- the name field on the face-setup screen losing focus while the keyboard opened (only visible when the keyboard opens gradually);
- the "Verified Contact" label overflowing with large text;
- the Saved People highlight falling back to the first tab when the pages had no position yet;
- a crash in the face-mesh painter when the mesh changed shape.

Good candidates for real PBT would be the money ledger (any sequence of Adds and Lesses gives a balance that is never negative and matches the summary) and the tab classification.

## Kiro powers

**No Kiro powers were installed** (`~/.kiro/powers/installed.json` is empty).

The bundled expertise came from **Impeccable**, used as a fetched reference rather than a power: its audit and onboarding guidelines shaped the scoring, the spacing and type scale, and the motion rules (short, decelerating, and following "Remove animations"). The app's own design tokens in `lib/design/tokens.dart` hold those decisions, so every screen uses the same values.

Third-party tools added through this work include `photo_manager` (for the custom photo picker) and `sqflite_common_ffi` (to run database-backed widget tests on the computer).
