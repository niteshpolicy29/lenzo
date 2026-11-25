import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The first-run screens, in order.
enum OnboardingStep { welcome, faceSetup, tutorial, done }

/// How far a new user got through onboarding. Saved as a small JSON file
/// next to the app's data, never in the face database.
///
/// Whether the owner's face is enrolled is not stored here: the database is
/// the source of truth for that (see [resolveOnboardingStep]).
@immutable
class OnboardingProgress {
  const OnboardingProgress({
    this.welcomeDone = false,
    this.tutorialDone = false,
  });

  /// "Get Started" was tapped.
  final bool welcomeDone;

  /// "Start Lenzo" or "Skip" was tapped on the tutorial.
  final bool tutorialDone;

  OnboardingProgress copyWith({bool? welcomeDone, bool? tutorialDone}) =>
      OnboardingProgress(
        welcomeDone: welcomeDone ?? this.welcomeDone,
        tutorialDone: tutorialDone ?? this.tutorialDone,
      );

  static const _version = 1;

  Map<String, Object> toJson() => {
    'version': _version,
    'welcomeDone': welcomeDone,
    'tutorialDone': tutorialDone,
  };

  /// Null if [json] isn't a progress record this version understands.
  static OnboardingProgress? fromJson(Object? json) {
    if (json is! Map || json['version'] != _version) return null;
    final welcome = json['welcomeDone'], tutorial = json['tutorialDone'];
    if (welcome is! bool || tutorial is! bool) return null;
    return OnboardingProgress(welcomeDone: welcome, tutorialDone: tutorial);
  }

  @override
  bool operator ==(Object other) =>
      other is OnboardingProgress &&
      other.welcomeDone == welcomeDone &&
      other.tutorialDone == tutorialDone;

  @override
  int get hashCode => Object.hash(welcomeDone, tutorialDone);

  @override
  String toString() =>
      'OnboardingProgress(welcome: $welcomeDone, tutorial: $tutorialDone)';
}

/// Which screen to open at launch.
///
/// - An owner is saved and there is no progress record: someone who set up
///   Lenzo before onboarding existed. They go straight to Home.
/// - An owner is saved and the record says the tutorial isn't done: a new
///   user who enrolled their face and closed the app. They see the tutorial.
/// - No owner: Welcome, or the face scan if "Get Started" was already
///   tapped. A record never counts as an enrolled face; only the database
///   does, so a lost or edited file can't skip enrollment.
OnboardingStep resolveOnboardingStep({
  required bool hasOwner,
  required OnboardingProgress? progress,
}) {
  if (hasOwner) {
    if (progress == null || progress.tutorialDone) return OnboardingStep.done;
    return OnboardingStep.tutorial;
  }
  if (progress != null && progress.welcomeDone) {
    return OnboardingStep.faceSetup;
  }
  return OnboardingStep.welcome;
}

/// Reads and writes [OnboardingProgress] in `onboarding.json`.
class OnboardingStore {
  OnboardingStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const fileName = 'onboarding.json';

  Future<File> _file() async =>
      File(p.join((await _directory()).path, fileName));

  /// The saved progress, or null if there is none or it can't be read.
  Future<OnboardingProgress?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      return OnboardingProgress.fromJson(jsonDecode(await f.readAsString()));
    } catch (e) {
      debugPrint('Onboarding progress unreadable: $e');
      return null;
    }
  }

  /// Saves [progress]. The file is written to a temporary name and then
  /// renamed, so a crash mid-write leaves the previous record intact.
  Future<void> save(OnboardingProgress progress) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(progress.toJson()), flush: true);
    await tmp.rename(f.path);
  }
}
