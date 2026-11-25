import 'dart:io';

import 'package:face_tag/data/models.dart';
import 'package:face_tag/design/design.dart';
import 'package:face_tag/screens/camera_screen.dart';
import 'package:face_tag/screens/people_screen.dart';
import 'package:face_tag/services/face_repository.dart';
import 'package:face_tag/theme/lenzo_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Saved People as it sits in the app: the middle-right page of a pager
/// (Settings | Home | Saved People), on the home route, kept alive.
class _Pager extends StatefulWidget {
  const _Pager({required this.repo});
  final FaceRepository repo;
  @override
  State<_Pager> createState() => _PagerState();
}

class _PagerState extends State<_Pager> {
  final pages = PageController(initialPage: 2);
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageView(
    key: const PageStorageKey('home-pages'),
    controller: pages,
    children: [
      const SizedBox(),
      const SizedBox(),
      PeopleScreen(repo: widget.repo, onBack: () {}),
    ],
  );
}

late Directory _dir;

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    PeopleMemory.reset();
    _dir = await Directory.systemTemp.createTemp('lenzo_tabs');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => _dir.path,
        );
    await databaseFactory.setDatabasesPath(_dir.path);
  });

  setUp(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'plugins.flutter.io/camera',
      'plugins.flutter.io/camera_android_camerax',
      'google_mlkit_face_detector',
      'dev.fluttercommunity.plus/sensors/method',
      'dev.fluttercommunity.plus/sensors/accelerometer',
    ]) {
      m.setMockMethodCallHandler(MethodChannel(name), (call) async {
        if (call.method == 'availableCameras') return <Object>[];
        return null;
      });
    }
  });

  tearDown(() async {
    await databaseFactory.deleteDatabase('${_dir.path}/face_tag.db');
    await _dir.delete(recursive: true);
  });

  Future<FaceRepository> seed(WidgetTester t) async {
    return (await t.runAsync(() async {
      final repo = await FaceRepository.openForTest();
      final face = img.Image(width: 160, height: 160);
      final emb = List.filled(512, 0.0);
      Future<void> add(String n, {int lent = 0, int borrowed = 0}) =>
          repo.registerPerson(
            name: n,
            embedding: emb,
            faceCrop: face,
            lentPaise: lent,
            borrowedPaise: borrowed,
          );
      await add('Asha', lent: 50000);
      await add('Raj', borrowed: 69900);
      await add('Boy');
      for (var i = 1; i <= 12; i++) {
        await add('Zpay $i', borrowed: 1000 * i);
      }
      return repo;
    }))!;
  }

  Future<void> settle(WidgetTester t) async {
    // Database work runs on real time; give it a few slices.
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 50));
    }
    await _pumpFor(t, const Duration(milliseconds: 700));
  }

  PageController tabs(WidgetTester t) => t
      .widget<LenzoSegmentedControl>(
        find.byType(LenzoSegmentedControl, skipOffstage: false),
      )
      .controller;

  Future<void> openAndBack(
    WidgetTester t,
    String name, {
    required bool system,
    bool swipe = false,
    List<int>? seen,
  }) async {
    if (find.text(name).hitTestable().evaluate().isEmpty) {
      debugPrint(
        'DBGTEXTS ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()}',
      );
    }
    await t.tap(find.text(name).hitTestable().first);
    await settle(t);
    expect(find.text('Money Borrowed'), findsOneWidget);
    if (swipe) {
      // Swipe right on the contact page, the app's own back gesture.
      final g = await t.startGesture(const Offset(40, 420));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(25, 0));
        await t.pump(const Duration(milliseconds: 16));
        seen?.add(tabs(t).page!.round());
      }
      await g.up();
    } else if (system) {
      await t.binding.handlePopRoute();
    } else {
      await t.tap(find.byTooltip('Back to camera').hitTestable().last);
    }
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 16));
      seen?.add(tabs(t).page!.round());
      if (i % 5 == 0) {
        await t.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
      }
    }
    await settle(t);
  }

  Future<FaceRepository> start(WidgetTester t) async {
    t.view.physicalSize = const Size(360, 780);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = await seed(t);
    await t.pumpWidget(
      MaterialApp(
        theme: Lenzo.theme(),
        home: Scaffold(body: _Pager(repo: repo)),
      ),
    );
    await settle(t);
    return repo;
  }

  for (final (label, index, name) in [
    ('To Pay (', 1, 'Raj'),
    ('To Receive (', 0, 'Asha'),
    ('Others (', 2, 'Boy'),
  ]) {
    for (final system in [false, true]) {
      testWidgets(
        '$label$name → back (${system ? 'system Back' : 'arrow'}) keeps tab',
        (t) async {
          await start(t);
          await t.tap(find.textContaining(label));
          await _pumpFor(t, const Duration(milliseconds: 700));
          expect(tabs(t).page, index.toDouble());
          final seen = <int>[];
          await openAndBack(t, name, system: system, seen: seen);
          expect(seen.toSet(), {index}, reason: 'no flash of another tab');
          expect(tabs(t).page, index.toDouble());
        },
      );
    }
  }

  testWidgets('search and scroll survive; ten round trips', (t) async {
    await start(t);
    await t.tap(find.textContaining('To Pay ('));
    await _pumpFor(t, const Duration(milliseconds: 700));
    await t.drag(find.text('Zpay 2').hitTestable(), const Offset(0, -300));
    await _pumpFor(t, const Duration(milliseconds: 700));
    double offset() => (t.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const PageStorageKey('people-pay')),
            matching: find.byType(Scrollable),
          )
          .first,
    )).position.pixels;
    final before = offset();
    expect(before, greaterThan(0));
    await openAndBack(t, 'Zpay 4', system: true);
    expect(offset(), closeTo(before, 1));
    await t.enterText(find.byType(TextField).first, 'raj');
    await _pumpFor(t, const Duration(milliseconds: 700));
    await openAndBack(t, 'Raj', system: false);
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      'raj',
    );
    for (var i = 0; i < 10; i++) {
      await openAndBack(t, 'Raj', system: i.isEven);
      expect(tabs(t).page, 1.0, reason: 'round trip $i');
    }
  });

  testWidgets('a balance change that empties the tab keeps the tab', (t) async {
    final repo = await start(t);
    await t.tap(find.textContaining('Others ('));
    await _pumpFor(t, const Duration(milliseconds: 700));
    // Boy gets money lent while his page is open → leaves Others.
    await t.tap(find.text('Boy').hitTestable().first);
    await settle(t);
    final boy = (await t.runAsync(() => repo.getPersons()))!
        .firstWhere((p) => p.name == 'Boy');
    await t.runAsync(() => repo.addEntry(boy.id, MoneyKind.lent, 10000));
    await t.binding.handlePopRoute();
    await settle(t);
    expect(tabs(t).page, 2.0);
    expect(find.text('Boy'), findsNothing);
  });

  for (final (label, index, name) in [
    ('To Pay (', 1, 'Raj'),
    ('Others (', 2, 'Boy'),
  ]) {
    testWidgets('$label$name → swipe back keeps tab', (t) async {
      await start(t);
      await t.tap(find.textContaining(label));
      await _pumpFor(t, const Duration(milliseconds: 700));
      final seen = <int>[];
      await openAndBack(t, name, system: false, swipe: true, seen: seen);
      expect(find.text('Money Borrowed'), findsNothing, reason: 'popped');
      expect(seen.toSet(), {index});
      expect(tabs(t).page, index.toDouble());
    });
  }

  group('inside the real home pager (CameraScreen)', () {
    Future<void> startReal(WidgetTester t) async {
      t.view.physicalSize = const Size(360, 780);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final repo = await seed(t);
      await t.pumpWidget(
        MaterialApp(
          theme: Lenzo.theme(),
          home: CameraScreen(repo: repo),
        ),
      );
      await settle(t);
      await t.tap(find.byTooltip('Saved people'));
      await settle(t);
      expect(find.byType(LenzoSegmentedControl).hitTestable(), findsOneWidget);
    }

    for (final (label, index, name) in [
      ('To Pay (', 1, 'Raj'),
      ('Others (', 2, 'Boy'),
    ]) {
      for (final system in [false, true]) {
        testWidgets(
          '$label$name → back (${system ? 'system Back' : 'arrow'})',
          (t) async {
            await startReal(t);
            await t.tap(find.textContaining(label).hitTestable());
            await _pumpFor(t, const Duration(milliseconds: 700));
            expect(tabs(t).page, index.toDouble());
            final seen = <int>[];
            await openAndBack(t, name, system: system, seen: seen);
            expect(seen.toSet(), {index}, reason: 'flash of another tab');
            expect(tabs(t).page, index.toDouble());
          },
        );
      }
    }
  });
}

/// Pumps frames for [d] (the camera page has animations that never settle).
Future<void> _pumpFor(WidgetTester t, Duration d) async {
  for (var e = Duration.zero; e < d; e += const Duration(milliseconds: 16)) {
    await t.pump(const Duration(milliseconds: 16));
  }
}
