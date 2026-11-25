import 'dart:io';

import 'package:face_tag/design/design.dart';
import 'package:face_tag/theme/lenzo_theme.dart';
import 'package:face_tag/widgets/face_mesh.dart';
import 'package:face_tag/widgets/page_thread.dart';
import 'package:face_tag/widgets/scan_border.dart';
import 'package:face_tag/widgets/swipe_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('Border state from recognition results', () {
    test('no face → idle', () {
      expect(scanStateFor(const []), ScanState.idle);
    });
    test('still checking or not sure → searching, never unknown', () {
      expect(scanStateFor(const [null]), ScanState.searching);
      expect(scanStateFor(const [-1]), ScanState.searching);
      expect(scanStateFor(const [0, null]), ScanState.searching);
      expect(scanStateFor(const [5, null]), ScanState.searching);
    });
    test('confirmed unknown → amber', () {
      expect(scanStateFor(const [0]), ScanState.unknown);
      expect(scanStateFor(const [5, 0]), ScanState.unknown);
    });
    test('everyone recognized → success', () {
      expect(scanStateFor(const [5]), ScanState.recognized);
      expect(scanStateFor(const [5, 9]), ScanState.recognized);
    });
  });

  group('Scan border animation', () {
    Future<void> pump(
      WidgetTester t,
      ScanState s, {
      bool active = true,
      bool reduceMotion = false,
    }) => t.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              height: 500,
              child: ScanBorder(state: s, radius: 24, active: active),
            ),
          ),
        ),
      ),
    );

    testWidgets('no face: nothing drawn, nothing animates', (t) async {
      await pump(t, ScanState.idle);
      await t.pump(const Duration(milliseconds: 500));
      expect(t.hasRunningAnimations, isFalse);
      // A face that leaves: the glow fades out and everything stops.
      await pump(t, ScanState.searching);
      await t.pump(const Duration(milliseconds: 600));
      expect(t.hasRunningAnimations, isTrue);
      await pump(t, ScanState.idle);
      await t.pump(const Duration(milliseconds: 300)); // settle delay
      await t.pump(const Duration(milliseconds: 700)); // fade out
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('unknown: amber, then completely still', (t) async {
      await pump(t, ScanState.searching);
      await t.pump(const Duration(milliseconds: 300));
      await pump(t, ScanState.unknown);
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 800));
      final st = t.state(find.byType(ScanBorder)) as dynamic;
      expect(st.toneValue as double, 1);
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('searching loops continuously', (t) async {
      await pump(t, ScanState.searching);
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(t.hasRunningAnimations, isTrue);
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('recognized: one pulse, then nothing animates', (t) async {
      await pump(t, ScanState.searching);
      await t.pump(const Duration(milliseconds: 300));
      await pump(t, ScanState.recognized);
      await t.pump(const Duration(milliseconds: 100));
      expect(t.hasRunningAnimations, isTrue, reason: 'pulse plays');
      await t.pump(const Duration(milliseconds: 1200));
      expect(t.hasRunningAnimations, isFalse, reason: 'settles to static');
      // Same face stays recognized: no repeat.
      await pump(t, ScanState.recognized);
      await t.pump(const Duration(milliseconds: 100));
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('one odd frame does not change the colour', (t) async {
      await pump(t, ScanState.searching);
      await t.pump(const Duration(milliseconds: 300));
      // Unknown for 100 ms only (less than the 250 ms settle time).
      await pump(t, ScanState.unknown);
      await t.pump(const Duration(milliseconds: 100));
      await pump(t, ScanState.searching);
      await t.pump(const Duration(milliseconds: 400));
      final st = t.state(find.byType(ScanBorder)) as dynamic;
      expect(st.toneValue as double, 0, reason: 'stayed mint');
      // A held unknown turns amber.
      await pump(t, ScanState.unknown);
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 600));
      expect(st.toneValue as double, 1);
    });

    testWidgets('stops when the camera is inactive', (t) async {
      await pump(t, ScanState.searching, active: false);
      await t.pump(const Duration(milliseconds: 600));
      expect(t.hasRunningAnimations, isFalse);
      await pump(t, ScanState.searching);
      await t.pump(const Duration(milliseconds: 50));
      expect(t.hasRunningAnimations, isTrue);
    });

    testWidgets('Remove animations: static glow, no loop', (t) async {
      await pump(t, ScanState.searching, reduceMotion: true);
      await t.pump(const Duration(milliseconds: 100));
      expect(t.hasRunningAnimations, isFalse);
      expect(t.takeException(), isNull);
    });

    test('loop is 2 s', () {
      expect(ScanBorder.loop, const Duration(seconds: 2));
    });
  });

  group('Tracking', () {
    test('mesh is subtle: mint, lines 15–25%, dots 25–40%', () {
      expect(meshColor, LenzoColors.accent);
      expect(meshLineOpacity, inInclusiveRange(0.15, 0.25));
      expect(meshDotOpacity, inInclusiveRange(0.25, 0.40));
    });

    test('small jitter is damped', () {
      final prev = [const Offset(100, 100), const Offset(150, 100)];
      final next = [const Offset(101, 100), const Offset(151, 100)];
      final out = smoothPoints(prev, next, faceWidth: 120);
      // Moves well under a pixel instead of the full pixel.
      expect(out[0].dx, inExclusiveRange(100.3, 100.5));
    });

    test('real movement is followed with no lag', () {
      final prev = [const Offset(100, 100), const Offset(150, 100)];
      final next = [const Offset(120, 100), const Offset(170, 100)];
      expect(smoothPoints(prev, next, faceWidth: 120), next);
    });

    test('new face or other mesh kind is not blended', () {
      final next = [const Offset(1, 1)];
      expect(smoothPoints(null, next, faceWidth: 100), next);
      expect(
        smoothPoints(const [Offset(0, 0), Offset(1, 1)], next, faceWidth: 100),
        next,
      );
    });

    test('settles on the true position (no drift)', () {
      var p = [const Offset(100, 100)];
      for (var i = 0; i < 20; i++) {
        p = smoothPoints(p, const [Offset(102, 100)], faceWidth: 120);
      }
      expect(p.first.dx, closeTo(102, 0.01));
    });

    test('overlay easing reaches 90% in 0.12 s', () {
      // 1 - e^(-rate * t) = 0.9
      expect(meshEaseRate * 0.12, closeTo(2.3026, 0.01));
    });

    test('points map to the preview, mirrored for the front camera', () {
      // Detection frame 720 × 1280 (portrait), preview 360 × 640.
      const image = Size(720, 1280);
      const preview = Size(360, 640);
      const face = Rect.fromLTWH(100, 300, 200, 260);
      final back = imageRectToWidget(face, image, preview, false);
      expect(back, const Rect.fromLTWH(50, 150, 100, 130));
      final front = imageRectToWidget(face, image, preview, true);
      expect(front, const Rect.fromLTWH(210, 150, 100, 130));
    });
  });

  group('One background colour', () {
    test('Android window and splash colour equals the app background', () {
      final xml = File('android/app/src/main/res/values/colors.xml')
          .readAsStringSync();
      final hex = RegExp(r'name="lenzo_background">#([0-9A-Fa-f]{6})<')
          .firstMatch(xml)!
          .group(1)!;
      expect(Color(int.parse('FF$hex', radix: 16)), LenzoColors.background);
    });

    test('theme, system navigation bar and routes use it', () {
      final theme = Lenzo.theme();
      expect(theme.scaffoldBackgroundColor, LenzoColors.background);
      expect(theme.canvasColor, LenzoColors.background);
      expect(lenzoSystemUi.systemNavigationBarColor, LenzoColors.background);
      expect(Lenzo.background, LenzoColors.background);
    });

    testWidgets('pushed pages are not dimmed and have no shadow', (t) async {
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LenzoSwipeRoute.underneath(0.8, const SizedBox()),
        ),
      );
      expect(find.byType(DecoratedBox), findsNothing);
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LenzoSwipeRoute.pageFrame(const SizedBox()),
        ),
      );
      expect(
        t.widget<ColoredBox>(find.byType(ColoredBox)).color,
        LenzoColors.background,
      );
      expect(find.byType(DecoratedBox), findsNothing);
    });
  });

  group('Page thread', () {
    PageThreadPainter painter(PageController c) => PageThreadPainter(
      pages: c,
      pageCount: 3,
      time: ValueNotifier(0),
      pulse: const AlwaysStoppedAnimation(0),
    );

    test('runs past both ends of the three pages', () {
      final c = PageController(initialPage: 1);
      final p = painter(c);
      expect(PageThreadPainter.start, lessThan(0));
      expect(p.end, greaterThan(3));
      c.dispose();
    });

    test('course: low on Settings, behind the camera, low on People', () {
      expect(PageThreadPainter.courseAt(0.5), closeTo(0.84, 1e-9));
      expect(PageThreadPainter.courseAt(1.5), closeTo(0.46, 1e-9));
      expect(PageThreadPainter.courseAt(2.5), closeTo(0.88, 1e-9));
      // Smooth S-curves: no jumps anywhere, including past the edges.
      var last = PageThreadPainter.courseAt(-0.3);
      for (var x = -0.29; x <= 3.3; x += 0.01) {
        final y = PageThreadPainter.courseAt(x);
        expect((y - last).abs(), lessThan(0.02));
        last = y;
      }
    });

    test('drifts gently and smoothly, staying in its lane', () {
      const h = 700.0;
      var moved = false;
      for (var x = -0.25; x <= 3.25; x += 0.1) {
        var prev = PageThreadPainter.lineY(x, 0, h);
        for (var t = 0.0; t < 60; t += 1 / 60) {
          final y = PageThreadPainter.lineY(x, t, h);
          expect(
            (y - PageThreadPainter.courseAt(x) * h).abs(),
            lessThanOrEqualTo(PageThreadPainter.drift * h + 0.01),
          );
          expect((y - prev).abs(), lessThan(1), reason: 'no jumps');
          if ((y - PageThreadPainter.lineY(x, 0, h)).abs() > 8) moved = true;
          prev = y;
        }
      }
      expect(moved, isTrue);
    });

    test('pulse enters beyond the left end and leaves beyond the right', () {
      final c = PageController(initialPage: 1);
      final p = painter(c);
      expect(p.pulseAt(0), lessThan(PageThreadPainter.start));
      expect(
        p.pulseAt(1) - PageThreadPainter.pulseLength,
        greaterThanOrEqualTo(p.end),
      );
      c.dispose();
    });

    Widget thread(PageController c, {bool still = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            PageThread(pages: c, pageCount: 3),
            PageView(
              controller: c,
              children: const [SizedBox(), SizedBox(), SizedBox()],
            ),
          ],
        ),
      ),
    );

    testWidgets('follows the drag both ways and settles, never restarting', (
      t,
    ) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = PageController(initialPage: 1);
      addTearDown(c.dispose);
      await t.pumpWidget(thread(c));
      final g = await t.startGesture(const Offset(300, 300));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(-15, 0));
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(c.page, closeTo(1 + 150 / 360, 0.02));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(15, 0)); // back again
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(c.page, closeTo(1, 0.02));
      await g.up();
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(c.page, 1.0);
      expect(t.takeException(), isNull);
    });

    testWidgets('pulse plays once per event and then stops', (t) async {
      final c = PageController(initialPage: 1);
      addTearDown(c.dispose);
      await t.pumpWidget(thread(c, still: true));
      // With Remove animations: no drift and no pulse.
      ThreadPulse.instance.fire();
      await t.pump(const Duration(milliseconds: 100));
      expect(t.hasRunningAnimations, isFalse);

      await t.pumpWidget(thread(c));
      await t.pump();
      final st = t.state(find.byType(PageThread)) as dynamic;
      expect(st.pulsing as bool, isFalse);
      ThreadPulse.instance.fire();
      await t.pump(const Duration(milliseconds: 100));
      expect(st.pulsing as bool, isTrue);
      await t.pump(PageThread.pulseDuration + const Duration(milliseconds: 50));
      expect(st.pulsing as bool, isFalse);
      expect(t.takeException(), isNull);
    });
  });
}
