import 'dart:io';

import 'package:face_tag/services/onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveOnboardingStep', () {
    const fresh = OnboardingProgress();
    const welcomed = OnboardingProgress(welcomeDone: true);
    const finished = OnboardingProgress(welcomeDone: true, tutorialDone: true);

    test('existing user (owner saved, no record) goes straight Home', () {
      expect(
        resolveOnboardingStep(hasOwner: true, progress: null),
        OnboardingStep.done,
      );
    });

    test('new user with no record starts at Welcome', () {
      expect(
        resolveOnboardingStep(hasOwner: false, progress: null),
        OnboardingStep.welcome,
      );
      expect(
        resolveOnboardingStep(hasOwner: false, progress: fresh),
        OnboardingStep.welcome,
      );
    });

    test('restart after Get Started resumes at the face scan', () {
      expect(
        resolveOnboardingStep(hasOwner: false, progress: welcomed),
        OnboardingStep.faceSetup,
      );
    });

    test('restart after enrolment resumes at the tutorial', () {
      expect(
        resolveOnboardingStep(hasOwner: true, progress: welcomed),
        OnboardingStep.tutorial,
      );
    });

    test('finished onboarding goes Home', () {
      expect(
        resolveOnboardingStep(hasOwner: true, progress: finished),
        OnboardingStep.done,
      );
    });

    test('a record can never skip enrolment: no owner means face scan', () {
      expect(
        resolveOnboardingStep(hasOwner: false, progress: finished),
        OnboardingStep.faceSetup,
      );
    });
  });

  group('OnboardingStore', () {
    late Directory dir;
    late OnboardingStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('lenzo_onboarding_test');
      store = OnboardingStore(directory: () async => dir);
    });

    tearDown(() => dir.delete(recursive: true));

    File file() => File('${dir.path}/${OnboardingStore.fileName}');

    test('no file means no progress', () async {
      expect(await store.load(), isNull);
    });

    test('saves and loads progress, leaving no temporary file', () async {
      const p = OnboardingProgress(welcomeDone: true);
      await store.save(p);
      expect(await store.load(), p);
      await store.save(p.copyWith(tutorialDone: true));
      expect(
        await store.load(),
        const OnboardingProgress(welcomeDone: true, tutorialDone: true),
      );
      expect(File('${file().path}.tmp').existsSync(), isFalse);
    });

    test('a corrupt file reads as no progress', () async {
      await file().writeAsString('{"version": 1, "welcomeDone": tr');
      expect(await store.load(), isNull);
    });

    test('an unknown version or wrong types read as no progress', () async {
      await file().writeAsString(
        '{"version": 2, "welcomeDone": true, "tutorialDone": true}',
      );
      expect(await store.load(), isNull);
      await file().writeAsString(
        '{"version": 1, "welcomeDone": "yes", "tutorialDone": true}',
      );
      expect(await store.load(), isNull);
    });
  });
}
