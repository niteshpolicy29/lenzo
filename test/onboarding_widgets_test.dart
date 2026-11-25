import 'dart:math' as math;
import 'dart:typed_data';

import 'package:face_tag/design/design.dart';
import 'package:face_tag/screens/onboarding_screens.dart';
import 'package:face_tag/services/face_repository.dart';
import 'package:face_tag/theme/lenzo_theme.dart';
import 'package:face_tag/widgets/cover_box.dart';
import 'package:face_tag/widgets/fade_swap.dart';
import 'package:face_tag/widgets/lenzo_calendar.dart';
import 'package:face_tag/widgets/owner_face_scan.dart';
import 'package:face_tag/widgets/single_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child, {double textScale = 1, bool reduceMotion = false}) {
  // The screen size itself comes from tester.view (see _setSize).
  return MaterialApp(
    theme: Lenzo.theme(),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduceMotion,
      ),
      child: app!,
    ),
    home: child,
  );
}

void main() {
  group('SingleMessage', () {
    const a = GuideMessage('Position your face in the circle');
    const b = GuideMessage('Keep your eyes open', color: LenzoColors.warning);
    const c = GuideMessage('Hold still…');

    Widget host(GuideMessage m, {bool reduceMotion = false}) => _app(
      Center(child: SingleMessage(message: m)),
      reduceMotion: reduceMotion,
    );

    double opacity(WidgetTester t) => t
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('single-message')),
                matching: find.byType(FadeTransition),
              )
              .first, // the nearest: SingleMessage's own fade
        )
        .opacity
        .value;

    testWidgets('never shows two messages, and fades out fully first', (
      tester,
    ) async {
      await tester.pumpWidget(host(a));
      await tester.pump(const Duration(milliseconds: 500)); // past the hold
      await tester.pumpWidget(host(b));
      var last = a.text;
      var swaps = 0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        final shownA = find.text(a.text).evaluate().length;
        final shownB = find.text(b.text).evaluate().length;
        expect(shownA + shownB, 1, reason: 'exactly one message on screen');
        final now = shownA == 1 ? a.text : b.text;
        if (now != last) {
          swaps++;
          // The new message starts invisible: the old one had faded out.
          expect(opacity(tester), lessThan(0.2));
          last = now;
        }
      }
      expect(swaps, 1);
      expect(find.text(b.text), findsOneWidget);
      expect(opacity(tester), 1);
    });

    testWidgets('rapid changes skip to the latest message', (tester) async {
      await tester.pumpWidget(host(a));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(host(b));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(host(a));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle(const Duration(milliseconds: 10));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(c.text), findsOneWidget);
      expect(find.text(a.text), findsNothing);
      expect(find.text(b.text), findsNothing);
    });

    testWidgets('each message is held before the next one', (tester) async {
      await tester.pumpWidget(host(a));
      await tester.pumpWidget(host(b));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(a.text), findsOneWidget, reason: 'held for 450 ms');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text(b.text), findsOneWidget);
    });

    testWidgets('swaps instantly with Remove animations on', (tester) async {
      await tester.pumpWidget(host(a, reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(host(b, reduceMotion: true));
      await tester.pump();
      await tester.pump();
      expect(find.text(b.text), findsOneWidget);
      expect(find.text(a.text), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Circular camera preview', () {
    const box = Key('content');

    testWidgets('portrait picture covers the circle, centred, not stretched', (
      tester,
    ) async {
      const s = 240.0;
      await tester.pumpWidget(
        _app(
          const Center(
            child: ScanCircle(
              size: s,
              child: CoverBox(
                aspectRatio: 9 / 16,
                child: ColoredBox(key: box, color: Color(0xFF00FF00)),
              ),
            ),
          ),
        ),
      );
      final circle = tester.getRect(find.byType(ScanCircle));
      final content = tester.getRect(find.byKey(box));
      expect(circle.size, const Size(s, s));
      // Keeps the 9:16 shape: full width, taller than the circle.
      expect(content.width, closeTo(s, 0.01));
      expect(content.height, closeTo(s * 16 / 9, 0.01));
      expect(content.width / content.height, closeTo(9 / 16, 0.001));
      // Covers the whole circle and is centred on it.
      expect(content.left, lessThanOrEqualTo(circle.left + 0.01));
      expect(content.right, greaterThanOrEqualTo(circle.right - 0.01));
      expect(content.top, lessThan(circle.top));
      expect(content.bottom, greaterThan(circle.bottom));
      expect(content.center.dx, closeTo(circle.center.dx, 0.01));
      expect(content.center.dy, closeTo(circle.center.dy, 0.01));
    });

    testWidgets('fills the circle under loose constraints (no narrow strip)', (
      tester,
    ) async {
      // The old preview used FittedBox inside AnimatedSwitcher's Stack,
      // which shrank it to a 9:16 strip. Same parents here.
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox.square(
              dimension: 200,
              child: AnimatedSwitcher(
                duration: Duration.zero,
                child: const CoverBox(
                  aspectRatio: 9 / 16,
                  child: ColoredBox(key: box, color: Color(0xFF00FF00)),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(CoverBox)), const Size(200, 200));
      expect(tester.getSize(find.byKey(box)).width, closeTo(200, 0.01));
    });

    test('cover size for landscape and square content', () {
      expect(
        CoverBox.coverSize(const Size(200, 200), 16 / 9),
        Size(200 * 16 / 9, 200),
      );
      expect(CoverBox.coverSize(const Size(200, 100), 1), const Size(200, 200));
    });
  });

  // -------------------------------------------------------------------------
  // Fitting on the target phone
  // -------------------------------------------------------------------------

  /// The POCO 2201117PI as configured: 1080×2400 px at density 500
  /// (345.6 × 768 dp), status bar 32 dp, 3-button navigation bar 48 dp,
  /// system text size 1.17×.
  const phone = Size(345.6, 768);
  const statusBar = 32.0, navBar = 48.0, phoneText = 1.17;

  Future<void> onPhone(
    WidgetTester tester, {
    Size size = phone,
    double keyboard = 0,
  }) async {
    const dpr = 3.125;
    tester.view.physicalSize = size * dpr;
    tester.view.devicePixelRatio = dpr;
    tester.view.padding = const FakeViewPadding(
      top: statusBar * dpr,
      bottom: navBar * dpr,
    );
    tester.view.viewPadding = tester.view.padding;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
    addTearDown(tester.view.reset);
  }

  /// No vertical scrolling: every vertical scroll view has nothing to
  /// scroll. (The page always has one, so that it can scroll when needed
  /// without rebuilding its content.)
  void expectNoScroll(WidgetTester tester) {
    for (final e in find.byType(Scrollable).evaluate()) {
      final s = (e as StatefulElement).state as ScrollableState;
      if (s.position.axis != Axis.vertical) continue;
      expect(
        s.position.maxScrollExtent,
        0,
        reason: 'the page should fit without scrolling',
      );
    }
  }

  /// Fits the screen: nothing overflows, nothing scrolls, and [action] is
  /// fully above the navigation bar (and the keyboard, if shown).
  void expectFits(
    WidgetTester tester,
    Finder action, {
    Size size = phone,
    double keyboard = 0,
  }) {
    expect(tester.takeException(), isNull);
    expectNoScroll(tester);
    final r = tester.getRect(action);
    final bottomLimit = size.height - math.max(navBar, keyboard);
    expect(r.bottom, lessThanOrEqualTo(bottomLimit + 0.5));
    expect(action.hitTestable(), findsOneWidget);
  }

  /// The heading starts below the step dots (not underneath them).
  void expectHeadingClear(WidgetTester tester, String heading) {
    final dots = tester.getRect(find.byType(OnboardingSteps));
    final title = tester.getRect(find.text(heading));
    expect(title.top, greaterThanOrEqualTo(dots.bottom));
    expect(dots.top, greaterThanOrEqualTo(statusBar));
  }

  group('Welcome', () {
    testWidgets('fits the target phone with no scrolling', (tester) async {
      await onPhone(tester);
      var started = 0;
      await tester.pumpWidget(
        _app(WelcomeScreen(onStart: () => started++), textScale: phoneText),
      );
      await tester.pumpAndSettle();
      expectFits(tester, find.text('Get Started'));
      expectHeadingClear(tester, 'Track money\nwith a face');
      expect(find.byType(WelcomeArt), findsOneWidget);
      expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);
      await tester.tap(find.text('Get Started'));
      expect(started, 1);
    });

    testWidgets('small phone (320 × 568) still fits', (tester) async {
      const small = Size(320, 568);
      await onPhone(tester, size: small);
      await tester.pumpWidget(_app(WelcomeScreen(onStart: () {})));
      await tester.pumpAndSettle();
      expectFits(tester, find.text('Get Started'), size: small);
    });

    testWidgets('very large text scrolls instead of overflowing', (
      tester,
    ) async {
      await onPhone(tester);
      await tester.pumpWidget(
        _app(WelcomeScreen(onStart: () {}), textScale: 2),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Get Started'));
      expect(find.text('Get Started').hitTestable(), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Face setup (camera and database replaced by stand-ins)
  // -------------------------------------------------------------------------

  group('Face setup', () {
    final fakeScan = OwnerScan(
      faces: const [],
      portrait: Uint8List(0),
      match: const FaceMatch(MatchKind.unknown, score: 0),
    );

    /// Same footprint as OwnerFaceScan: ring, gap, two-line message.
    Widget fakeCamera(
      BuildContext _,
      double size,
      OwnerScan? scan,
      ValueChanged<OwnerScan> onCaptured,
    ) => SizedBox(
      key: const Key('scan'),
      width: size + 22,
      height: size + 22 + 16 + 44,
      child: scan == null
          ? TextButton(
              onPressed: () => onCaptured(fakeScan),
              child: const Text('capture'),
            )
          : const Text('captured'),
    );

    Widget screen({
      required Future<void> Function(String, OwnerScan) enroll,
      VoidCallback? onEnrolled,
    }) => _app(
      FaceSetupScreen.test(
        scanBuilder: fakeCamera,
        enroll: enroll,
        onBack: () {},
        onEnrolled: onEnrolled ?? () {},
      ),
      textScale: phoneText,
    );

    testWidgets('scanning and captured states fit the target phone', (
      tester,
    ) async {
      await onPhone(tester);
      await tester.pumpWidget(screen(enroll: (_, _) async {}));
      await tester.pumpAndSettle();
      expect(find.text('Set up your face'), findsOneWidget);
      expectHeadingClear(tester, 'Set up your face');
      expect(tester.takeException(), isNull);
      expectNoScroll(tester);
      final scanning = tester.getSize(find.byKey(const Key('scan')));
      expect(scanning.width - 22, greaterThanOrEqualTo(200));

      await tester.tap(find.text('capture'));
      await tester.pumpAndSettle();
      expect(find.text('Add your name'), findsOneWidget);
      expectFits(tester, find.text('Scan again'));
      // The circle stays a good size with the form shown.
      final captured = tester.getSize(find.byKey(const Key('scan')));
      expect(captured.width - 22, greaterThanOrEqualTo(160));
    });

    testWidgets('Scan again matches Save and continue; Save stays mint', (
      tester,
    ) async {
      await onPhone(tester);
      await tester.pumpWidget(screen(enroll: (_, _) async {}));
      await tester.pumpAndSettle();
      await tester.tap(find.text('capture'));
      await tester.pumpAndSettle();
      LenzoButton button(String label) => tester.widget<LenzoButton>(
        find.ancestor(of: find.text(label), matching: find.byType(LenzoButton)),
      );
      Rect rect(String label) => tester.getRect(
        find.ancestor(of: find.text(label), matching: find.byType(LenzoButton)),
      );
      expect(button('Save and continue').kind, LenzoButtonKind.primary);
      expect(button('Scan again').kind, LenzoButtonKind.outlineAccent);
      expect(button('Save and continue').compact, isFalse);
      expect(button('Scan again').compact, isFalse);
      final save = rect('Save and continue'), again = rect('Scan again');
      expect(again.width, closeTo(save.width, 0.01));
      expect(again.height, closeTo(save.height, 0.01));
      expect(again.left, closeTo(save.left, 0.01));
      expect(again.top, greaterThan(save.bottom));
    });

    testWidgets(
      'with the keyboard open, the name field and Save stay visible',
      (tester) async {
        await onPhone(tester);
        await tester.pumpWidget(screen(enroll: (_, _) async {}));
        await tester.pumpAndSettle();
        await tester.tap(find.text('capture'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextField));
        await onPhone(tester, keyboard: 320);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final save = find.text('Save and continue');
        expect(
          tester.getRect(save).bottom,
          lessThanOrEqualTo(phone.height - 320),
        );
        expect(save.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(find.byType(TextField)).bottom,
          lessThanOrEqualTo(phone.height - 320),
        );
      },
    );

    testWidgets('the name field keeps focus while the keyboard opens', (
      tester,
    ) async {
      // A real keyboard slides up over ~250 ms, so the space shrinks step
      // by step. The field must survive every step (if it is rebuilt, it
      // loses focus and Android closes the keyboard again).
      await onPhone(tester);
      await tester.pumpWidget(screen(enroll: (_, _) async {}));
      await tester.pumpAndSettle();
      await tester.tap(find.text('capture'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final field = tester.state<EditableTextState>(find.byType(EditableText));
      expect(field.widget.focusNode.hasFocus, isTrue);
      for (var k = 0.0; k <= 420; k += 30) {
        await onPhone(tester, keyboard: k);
        await tester.pump(const Duration(milliseconds: 16));
        final now = tester.state<EditableTextState>(find.byType(EditableText));
        expect(identical(now, field), isTrue, reason: 'field rebuilt at $k');
        expect(now.widget.focusNode.hasFocus, isTrue, reason: 'lost at $k');
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Back down again (keyboard closing) without errors.
      for (var k = 420.0; k >= 0; k -= 60) {
        await onPhone(tester, keyboard: k);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('saves only with a name, then reports enrolled', (
      tester,
    ) async {
      await onPhone(tester);
      final saved = <String>[];
      var enrolled = 0;
      await tester.pumpWidget(
        screen(
          enroll: (name, _) async => saved.add(name),
          onEnrolled: () => enrolled++,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('capture'));
      await tester.pumpAndSettle();
      // Captured is not saved: nothing is written yet.
      expect(saved, isEmpty);
      await tester.tap(find.text('Save and continue'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your name to continue'), findsOneWidget);
      expect(saved, isEmpty);
      await tester.enterText(find.byType(TextField), '  Nitesh   Kumar ');
      await tester.tap(find.text('Save and continue'));
      // (The busy spinner keeps running; in the app the page moves on.)
      await tester.pump(const Duration(seconds: 1));
      expect(saved, ['Nitesh Kumar']);
      expect(enrolled, 1);
    });

    testWidgets('a failed save offers Try again and does not continue', (
      tester,
    ) async {
      await onPhone(tester);
      var attempts = 0, enrolled = 0;
      await tester.pumpWidget(
        screen(
          enroll: (_, _) async {
            attempts++;
            if (attempts == 1) throw Exception('disk full');
          },
          onEnrolled: () => enrolled++,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('capture'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Nitesh');
      await tester.tap(find.text('Save and continue'));
      await tester.pump(const Duration(seconds: 1));
      expect(enrolled, 0);
      expect(find.textContaining("Couldn't save your profile"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(seconds: 1));
      expect(attempts, 2);
      expect(enrolled, 1);
    });

    testWidgets('Scan again returns to scanning', (tester) async {
      await onPhone(tester);
      await tester.pumpWidget(screen(enroll: (_, _) async {}));
      await tester.pumpAndSettle();
      await tester.tap(find.text('capture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan again'));
      await tester.pumpAndSettle();
      expect(find.text('capture'), findsOneWidget);
      expect(find.text('Set up your face'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Tutorial carousel
  // -------------------------------------------------------------------------

  group('Tutorial', () {
    testWidgets('three slides with the exact texts, fitting the phone', (
      tester,
    ) async {
      await onPhone(tester);
      await tester.pumpWidget(
        _app(TutorialScreen(onDone: () {}), textScale: phoneText),
      );
      await tester.pumpAndSettle();
      expectFits(tester, find.text('Next'));
      expectHeadingClear(tester, 'How Lenzo works');
      expect(tutorialSlides.map((s) => s.text), [
        'Point your camera at someone to recognize them.',
        'Track money you lend and borrow.',
        'See who owes you and who you owe.',
      ]);
      expect(tutorialSlides.map((s) => s.title), [
        'Recognize People',
        'Track Money',
        'Stay Organized',
      ]);
      expect(find.text('Recognize People'), findsOneWidget);
      expect(find.bySemanticsLabel('Slide 1 of 3'), findsOneWidget);
    });

    testWidgets('swipe moves between slides and updates the dots', (
      tester,
    ) async {
      await onPhone(tester);
      await tester.pumpWidget(_app(TutorialScreen(onDone: () {})));
      await tester.pumpAndSettle();
      await tester.fling(find.byType(PageView), const Offset(-250, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text('Track Money').hitTestable(), findsOneWidget);
      expect(find.bySemanticsLabel('Slide 2 of 3'), findsOneWidget);
      await tester.fling(find.byType(PageView), const Offset(250, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Slide 1 of 3'), findsOneWidget);
    });

    testWidgets('Next walks through; Start Lenzo and Skip finish', (
      tester,
    ) async {
      await onPhone(tester);
      var done = 0;
      await tester.pumpWidget(_app(TutorialScreen(onDone: () => done++)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Slide 2 of 3'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Start Lenzo'), findsOneWidget);
      expect(done, 0);
      await tester.tap(find.text('Start Lenzo'));
      expect(done, 1);
      await tester.tap(find.text('Skip'));
      expect(done, 2);
    });

    testWidgets('slide and icon transitions take 200–350 ms', (tester) async {
      expect(
        TutorialScreen.transition.inMilliseconds,
        inInclusiveRange(200, 350),
      );
      await onPhone(tester);
      await tester.pumpWidget(_app(TutorialScreen(onDone: () {})));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      // Real frames (16 ms); everything settles within 350 ms.
      for (var t = 0; t < 350; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // (Button ripples may still be fading; check the slide itself.)
      final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
      expect(pages.page, 1.0);
      expect(find.bySemanticsLabel('Slide 2 of 3'), findsOneWidget);
      expect(TutorialScreen.iconDraw.inMilliseconds, lessThanOrEqualTo(200));
    });

    testWidgets('small phone fits; very large text scrolls safely', (
      tester,
    ) async {
      const small = Size(320, 568);
      await onPhone(tester, size: small);
      await tester.pumpWidget(_app(TutorialScreen(onDone: () {})));
      await tester.pumpAndSettle();
      expectFits(tester, find.text('Next'), size: small);

      await onPhone(tester);
      await tester.pumpWidget(
        _app(TutorialScreen(onDone: () {}), textScale: 2),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Next'));
      expect(find.text('Next').hitTestable(), findsOneWidget);
    });

    testWidgets('works with Remove animations on', (tester) async {
      await onPhone(tester);
      await tester.pumpWidget(
        _app(TutorialScreen(onDone: () {}), reduceMotion: true),
      );
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('Slide 2 of 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Payment reminder calendar
  // -------------------------------------------------------------------------

  group('Calendar', () {
    Widget calendar({
      double width = 320,
      double textScale = phoneText,
      ValueChanged<DateTime>? onSave,
    }) => _app(
      Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: LenzoCalendar(
              initialDate: DateTime(2026, 11, 25),
              firstDate: DateTime(2026, 1, 1),
              lastDate: DateTime(2030, 12, 31),
              onSave: onSave ?? (_) {},
              onCancel: () {},
            ),
          ),
        ),
      ),
      textScale: textScale,
    );

    Finder grid(int y, int m) => find.byKey(ValueKey<Object>('m$y-$m'));

    testWidgets('month title is one line, arrows left and right', (
      tester,
    ) async {
      await onPhone(tester);
      await tester.pumpWidget(calendar());
      await tester.pumpAndSettle();
      final title = find.text('November 2026');
      expect(title, findsOneWidget);
      final t = tester.getRect(title);
      // One line: about one line-height tall.
      expect(t.height, lessThan(15 * phoneText * 1.3 * 1.5));
      final prev = tester.getRect(find.byTooltip('Previous'));
      final next = tester.getRect(find.byTooltip('Next'));
      expect(prev.right, lessThanOrEqualTo(t.left));
      expect(next.left, greaterThanOrEqualTo(t.right));
      expect((prev.center.dy - next.center.dy).abs(), lessThan(0.5));
    });

    testWidgets('narrow screen uses "Nov 2026" and does not overflow', (
      tester,
    ) async {
      await onPhone(tester, size: const Size(320, 640));
      await tester.pumpWidget(calendar(width: 236, textScale: 1.3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Nov 2026'), findsOneWidget);
    });

    testWidgets('changing month: fixed size, fade only, never two months', (
      tester,
    ) async {
      await onPhone(tester);
      await tester.pumpWidget(calendar());
      await tester.pumpAndSettle();
      final area = find.byType(FadeSwap);
      final before = tester.getRect(area);
      final day1 = tester.getRect(find.text('1'));
      await tester.tap(find.byTooltip('Next'));
      var sawEmptyGap = false;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        final nov = grid(2026, 11).evaluate().isNotEmpty;
        final dec = grid(2026, 12).evaluate().isNotEmpty;
        expect(nov && dec, isFalse, reason: 'two months drawn together');
        expect(tester.getRect(area), before, reason: 'grid changed size');
        final o = tester
            .widget<FadeTransition>(
              find
                  .descendant(of: area, matching: find.byType(FadeTransition))
                  .first,
            )
            .opacity
            .value;
        if (o < 0.05) sawEmptyGap = true;
      }
      expect(sawEmptyGap, isTrue, reason: 'old month fades out fully first');
      expect(grid(2026, 12), findsOneWidget);
      expect(find.text('December 2026'), findsOneWidget);
      // Dates sit in the same cells: no sliding offset after the change.
      final dec1 = tester.getRect(find.text('1'));
      expect(dec1.top, closeTo(day1.top, 0.5));
    });

    testWidgets('the whole month change takes 150–200 ms', (tester) async {
      await onPhone(tester);
      await tester.pumpWidget(calendar());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next'));
      // Real frames (16 ms): done within 200 ms plus a frame.
      for (var t = 0; t < 216; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(grid(2026, 12), findsOneWidget);
      final fade = tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byType(FadeSwap),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1.0);
    });

    testWidgets('rapid taps land on the last month cleanly', (tester) async {
      await onPhone(tester);
      await tester.pumpWidget(calendar());
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('Next'));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(find.text('March 2027'), findsOneWidget);
      expect(grid(2027, 3), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('day numbers fit their cells; selection saves', (tester) async {
      await onPhone(tester);
      DateTime? saved;
      await tester.pumpWidget(calendar(onSave: (d) => saved = d));
      await tester.pumpAndSettle();
      for (final d in ['1', '15', '28', '30']) {
        final text = tester.getRect(find.text(d));
        final cell = tester.getRect(
          find
              .ancestor(of: find.text(d), matching: find.byType(Container))
              .first,
        );
        expect(cell.contains(text.topLeft), isTrue, reason: 'day $d clipped');
        expect(
          cell.contains(text.bottomRight - const Offset(0.1, 0.1)),
          isTrue,
        );
      }
      await tester.tap(find.text('12'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      expect(saved, DateTime(2026, 11, 12));
    });

    testWidgets('Cancel and Save are equal and aligned', (tester) async {
      await onPhone(tester);
      await tester.pumpWidget(calendar());
      await tester.pumpAndSettle();
      Rect r(String s) => tester.getRect(
        find.ancestor(of: find.text(s), matching: find.byType(LenzoButton)),
      );
      expect(r('Cancel').width, closeTo(r('Save').width, 0.01));
      expect(r('Cancel').top, closeTo(r('Save').top, 0.01));
      expect(r('Cancel').height, closeTo(r('Save').height, 0.01));
    });
  });

  testWidgets('step dots announce their position', (tester) async {
    await tester.pumpWidget(
      _app(const Center(child: OnboardingSteps(current: 2))),
    );
    expect(find.bySemanticsLabel('Step 2 of 3'), findsOneWidget);
  });
}
