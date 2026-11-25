// On-device test of the camera screen: start-up, camera switching (repeated
// and rapid), Home ↔ Saved People, a contact page, and background/resume.
// It measures real frame timings and switch latency and reports them to the
// driver (build/lenzo_device_report.json).
//
// SAFETY: runs only inside the separate test app "Lenzo Test"
// (com.nitesh.face_tag.devtest, see android/app/build.gradle.kts), never the
// real Lenzo: it stops at once if its data folder isn't the test app's.
// flutter drive uninstalls the app it ran; that is only ever Lenzo Test.
//
// Run (profile mode, on the phone), always naming the test APK so the tool
// can't fall back to another package:
//   flutter build apk --profile
//   flutter drive --profile \
//     --use-application-binary build/app/outputs/flutter-apk/app-profile.apk \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/camera_test.dart -d <device>

import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:face_tag/main.dart' as app;
import 'package:face_tag/services/face_repository.dart';
import 'package:face_tag/widgets/scan_border.dart';
import 'package:face_tag/screens/camera_screen.dart' show cameraStillKey;
import 'package:flutter/scheduler.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

final _timings = <FrameTiming>[];

Map<String, Object> _frameStats(List<FrameTiming> t) {
  if (t.isEmpty) return {'frames': 0};
  double ms(Duration d) => d.inMicroseconds / 1000;
  List<double> sorted(Iterable<double> v) => v.toList()..sort();
  double pct(List<double> v, double p) =>
      v[math.min(v.length - 1, (v.length * p).floor())];
  final build = sorted(t.map((f) => ms(f.buildDuration)));
  final raster = sorted(t.map((f) => ms(f.rasterDuration)));
  final total = t.map((f) => ms(f.totalSpan)).toList();
  String r(double v) => v.toStringAsFixed(1);
  return {
    'frames': t.length,
    'build_ms_p50': r(pct(build, 0.5)),
    'build_ms_p90': r(pct(build, 0.9)),
    'build_ms_max': r(build.last),
    'raster_ms_p50': r(pct(raster, 0.5)),
    'raster_ms_p90': r(pct(raster, 0.9)),
    'raster_ms_max': r(raster.last),
    // Frames whose build or raster missed the 16.7 ms (60 Hz) budget.
    'janky_build_or_raster': t
        .where((f) => ms(f.buildDuration) > 16.7 || ms(f.rasterDuration) > 16.7)
        .length,
    'total_span_ms_max': r(total.reduce(math.max)),
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real frames at the display rate, not test-paced ones.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('camera switching and navigation on device', (tester) async {
    final report = <String, Object>{};
    final errors = <String>[];
    SchedulerBinding.instance.addTimingsCallback(_timings.addAll);

    Future<void> run(Duration d) async {
      final end = DateTime.now().add(d);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<Duration> waitFor(
      bool Function() ok, {
      Duration timeout = const Duration(seconds: 10),
      void Function()? eachFrame,
    }) async {
      final sw = Stopwatch()..start();
      while (!ok()) {
        if (sw.elapsed > timeout) throw TestFailure('timed out after $timeout');
        await tester.pump(const Duration(milliseconds: 8));
        eachFrame?.call();
      }
      return sw.elapsed;
    }

    CameraController? controller() {
      final f = find.byType(CameraPreview);
      if (f.evaluate().isEmpty) return null;
      final c = tester.widget<CameraPreview>(f.first).controller;
      return c.value.isInitialized ? c : null;
    }

    CameraLensDirection? lens() => controller()?.description.lensDirection;
    bool stillShown() => find.byKey(cameraStillKey).evaluate().isNotEmpty;
    // The preview is fully faded in (so the camera has delivered frames).
    bool live() {
      final prev = find.byType(CameraPreview);
      if (controller() == null || stillShown()) return false;
      final op = find.ancestor(of: prev.first, matching: find.byType(Opacity));
      return op.evaluate().isNotEmpty &&
          tester.widget<Opacity>(op.first).opacity == 1;
    }

    bool switchingCard() =>
        find.textContaining('Switching camera').evaluate().isNotEmpty;

    // ---- Safety: only in the isolated test app ---------------------------
    final dbDir = await getDatabasesPath();
    if (!dbDir.contains('com.nitesh.face_tag.devtest')) {
      fail('Refusing to run outside Lenzo Test (data folder: $dbDir)');
    }
    // The test app starts empty: give it a placeholder owner so it opens
    // on the camera screen. This only writes to the test app's own data.
    final seed = await FaceRepository.create();
    if (seed.ownerId == null) {
      await seed.registerOwner(
        name: 'Test Owner',
        faces: [(img.Image(width: 160, height: 160), List.filled(512, 0.0))],
      );
    }
    report['test_app_data'] = dbDir;

    // ---- Start-up -------------------------------------------------------
    final startSw = Stopwatch()..start();
    app.main();
    await waitFor(live, timeout: const Duration(seconds: 30));
    report['startup_to_preview_ms'] = startSw.elapsedMilliseconds;
    await run(const Duration(seconds: 2));
    // ---- Idle: scanning border animating, camera live ------------------
    _timings.clear();
    final borderStates = <String>[];
    final idleSw = Stopwatch()..start();
    while (idleSw.elapsed < const Duration(seconds: 4)) {
      await tester.pump(const Duration(milliseconds: 16));
      final b = find.byType(ScanBorder);
      final st = b.evaluate().isEmpty
          ? 'none'
          : tester.widget<ScanBorder>(b.first).state.name;
      if (borderStates.isEmpty || borderStates.last != st) borderStates.add(st);
    }
    report['idle_scanning'] = {
      'border_states': borderStates,
      ..._frameStats(List.of(_timings)),
    };
    final switchButton = find.byTooltip('Switch camera');
    expect(switchButton, findsOneWidget);

    // Diagnostic mode (--dart-define=LENZO_DIAG=true): log where the preview
    // texture actually is on screen, every 200 ms, then stop.
    if (const bool.fromEnvironment('LENZO_DIAG')) {
      final t0 = DateTime.now();
      Future<void> sample(String tag) async {
        for (var i = 0; i < 15; i++) {
          final tex = find.byType(Texture);
          String geo = 'none';
          if (tex.evaluate().isNotEmpty) {
            final box = tester.renderObject<RenderBox>(tex.first);
            final o = box.localToGlobal(Offset.zero);
            geo =
                '${box.size.width.round()}x${box.size.height.round()} '
                '@${o.dx.round()},${o.dy.round()} attached=${box.attached}';
          }
          final c = controller();
          debugPrint(
            'DIAG $tag +${DateTime.now().difference(t0).inMilliseconds}ms '
            'tex=${tex.evaluate().length} $geo '
            'ctl=${c?.cameraId} stream=${c?.value.isStreamingImages} '
            'still=${stillShown()}',
          );
          await run(const Duration(milliseconds: 200));
        }
      }

      await sample('idle');
      for (var k = 0; k < 6; k++) {
        await tester.tap(switchButton, warnIfMissed: false);
        await sample('after-switch-$k');
      }
      binding.reportData = report;
      return;
    }

    // ---- One switch, measured ----------------------------------------------
    Future<Map<String, Object>> switchOnce() async {
      final before = controller()!;
      final fromLens = before.description.lensDirection;
      var blankFrames = 0, card = false;
      _timings.clear();
      await tester.tap(switchButton, warnIfMissed: false);
      // Time until the new camera is ready (a different controller, other
      // lens), then until its fade-in has finished (the still is removed).
      final ready = await waitFor(
        () {
          final c = controller();
          return c != null &&
              !identical(c, before) &&
              c.description.lensDirection != fromLens;
        },
        eachFrame: () {
          card |= switchingCard();
          // Nothing in the camera area: neither preview nor last frame.
          if (controller() == null && !stillShown()) blankFrames++;
        },
      );
      // A camera that sends no frames is reopened after 1.5 s; count those.
      final opened = <CameraController>{controller()!};
      final shown = await waitFor(
        live,
        timeout: const Duration(seconds: 6),
        eachFrame: () {
          final c = controller();
          if (c != null) opened.add(c);
        },
      );
      await run(const Duration(milliseconds: 300));
      // Is the new preview actually painted? (Opacity above it at 1, and a
      // Texture inside it.)
      final prev = find.byType(CameraPreview);
      final op = find.ancestor(of: prev.first, matching: find.byType(Opacity));
      final opacity = op.evaluate().isEmpty
          ? -1.0
          : tester.widget<Opacity>(op.first).opacity;
      final textures = find
          .descendant(of: prev.first, matching: find.byType(Texture))
          .evaluate()
          .length;
      final result = {
        'from': fromLens.name,
        'preview_opacity': opacity,
        'textures': textures,
        'camera_id': controller()?.cameraId ?? -1,
        'tap_to_ready_ms': ready.inMilliseconds,
        'reopened_for_no_frames': opened.length - 1,
        'tap_to_fade_done_ms': (ready + shown).inMilliseconds,
        'frames_without_preview_or_still': blankFrames,
        'switching_card_seen': card,
        ...{
          for (final e in _frameStats(List.of(_timings)).entries)
            'ui_${e.key}': e.value,
        },
      };
      debugPrint('LENZO_SWITCH $result');
      return result;
    }

    final switches = <Map<String, Object>>[];
    // Camera devices used, in order (Camera2 ids): must alternate between
    // exactly one rear and one front camera.
    final used = <String>['${lens()!.name}:${controller()!.description.name}'];
    for (var i = 0; i < 10; i++) {
      switches.add(await switchOnce());
      used.add('${lens()!.name}:${controller()!.description.name}');
      await run(const Duration(milliseconds: 700));
    }
    report['switches'] = switches;
    report['cameras_used'] = used;
    report['all_cameras'] = [
      for (final c in await availableCameras())
        '${c.lensDirection.name}:${c.name}',
    ];
    if (used.toSet().length != 2) {
      errors.add(
        'switching used ${used.toSet()} (expected one rear, one front)',
      );
    }
    for (var i = 1; i < used.length; i++) {
      if (used[i].split(':').first == used[i - 1].split(':').first) {
        errors.add('switch $i did not alternate: ${used[i - 1]} → ${used[i]}');
      }
    }
    final readies = [for (final s in switches) s['tap_to_ready_ms'] as int]
      ..sort();
    report['switch_ready_ms_median'] = readies[readies.length ~/ 2];
    report['switch_ready_ms_max'] = readies.last;
    if (switches.any((s) => s['switching_card_seen'] == true)) {
      errors.add('"Switching camera" card appeared');
    }

    // ---- Rapid taps: only one switch may run --------------------------
    final rapidFrom = lens()!;
    final rapidStart = controller();
    final seen = <CameraController>{};
    // Lens of every camera opened, in order; more than one change means a
    // second switch ran.
    final lensChanges = <String>[rapidFrom.name];
    void note() {
      final c = controller();
      if (c != null && !identical(c, rapidStart)) seen.add(c);
      final l = c?.description.lensDirection.name;
      if (l != null && l != lensChanges.last) lensChanges.add(l);
    }

    for (var i = 0; i < 5; i++) {
      await tester.tap(switchButton, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 40));
      note();
    }
    await waitFor(() {
      note();
      final c = controller();
      return c != null && c.description.lensDirection != rapidFrom;
    });
    final rapidSw = Stopwatch()..start();
    while (rapidSw.elapsed < const Duration(seconds: 4)) {
      await tester.pump(const Duration(milliseconds: 16));
      note();
    }
    report['rapid_taps'] = {
      'taps': 5,
      'from': rapidFrom.name,
      'ended_on': lens()?.name ?? 'none',
      'controllers_created': seen.length,
      'lens_sequence': lensChanges,
    };
    if (lensChanges.length != 2) {
      errors.add('rapid taps switched ${lensChanges.length - 1} times');
    }

    // ---- Home → Settings (swipe right) → Home ---------------------------
    final beforeSettings = controller()!;
    _timings.clear();
    await tester.fling(
      find.byType(PageView).first,
      const Offset(320, 0),
      1600,
      warnIfMissed: false,
    );
    await run(const Duration(milliseconds: 700));
    final onSettings = find
        .text('Profile Settings')
        .hitTestable()
        .evaluate()
        .isNotEmpty;
    report['swipe_to_settings'] = {
      'reached_settings': onSettings,
      ..._frameStats(List.of(_timings)),
    };
    if (!onSettings) errors.add('swipe right did not open Settings');
    await tester.fling(
      find.byType(PageView).first,
      const Offset(-320, 0),
      1600,
      warnIfMissed: false,
    );
    await run(const Duration(milliseconds: 700));
    if (!identical(controller(), beforeSettings)) {
      errors.add('camera restarted after Home ↔ Settings');
    }

    // ---- Home → Saved People → Home: camera kept --------------------------
    final homeController = controller()!;
    _timings.clear();
    await tester.fling(
      find.byType(PageView).first,
      const Offset(-320, 0),
      1600,
      warnIfMissed: false,
    );
    await run(const Duration(milliseconds: 700));
    final onPeople = find
        .text('Saved People')
        .hitTestable()
        .evaluate()
        .isNotEmpty;
    report['swipe_to_people'] = {
      'reached_people': onPeople,
      ..._frameStats(List.of(_timings)),
    };
    if (!onPeople) errors.add('swipe did not reach Saved People');

    // Open the first contact, if there is one, then come back.
    final tile = find.byTooltip(RegExp('^Edit ')).hitTestable();
    if (tile.evaluate().isNotEmpty) {
      _timings.clear();
      // Tap the card body, left of its edit button.
      await tester.tapAt(tester.getCenter(tile.first) - const Offset(160, 0));
      await run(const Duration(milliseconds: 600));
      final opened = find.text('Verified Contact').evaluate().isNotEmpty;
      final back = find.byTooltip('Back to camera').hitTestable();
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back.last);
      }
      await run(const Duration(milliseconds: 600));
      report['contact_page'] = {
        'opened': opened,
        ..._frameStats(List.of(_timings)),
      };
    } else {
      report['contact_page'] = 'no contact card visible to open';
    }

    _timings.clear();
    await tester.fling(
      find.byType(PageView).first,
      const Offset(320, 0),
      1600,
      warnIfMissed: false,
    );
    await run(const Duration(milliseconds: 700));
    final sameCamera = identical(controller(), homeController);
    report['swipe_back_home'] = {
      'camera_kept_without_restart': sameCamera,
      ..._frameStats(List.of(_timings)),
    };
    if (!sameCamera) errors.add('camera restarted after Home ↔ People');

    report['switch_after_navigation'] = await switchOnce();

    // ---- Background and resume ------------------------------------------
    final beforePause = controller();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await run(const Duration(milliseconds: 800));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final resumeMs = await waitFor(
      () => live() && !identical(controller(), beforePause),
    );
    report['resume_to_preview_ms'] = resumeMs.inMilliseconds;
    report['switch_after_resume'] = await switchOnce();

    debugPrint('LENZO_REPORT $report');
    report['errors'] = errors;
    binding.reportData = {...?binding.reportData, ...report};
    expect(errors, isEmpty);
  });
}
