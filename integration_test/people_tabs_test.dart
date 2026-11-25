// Reproduces the Saved People tab reset through the real app, in Lenzo Test
// only: open Saved People, pick a tab (and search / scroll), open a contact,
// come back with the app arrow or system Back, and check what is selected.
import 'package:face_tag/design/design.dart';
import 'package:face_tag/main.dart' as app;
import 'package:face_tag/services/face_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Saved People keeps its tab across a contact', (tester) async {
    final dbDir = await getDatabasesPath();
    if (!dbDir.contains('com.nitesh.face_tag.devtest')) {
      fail('Refusing to run outside Lenzo Test (data folder: $dbDir)');
    }
    final repo = await FaceRepository.create();
    final face = img.Image(width: 160, height: 160);
    final emb = List.filled(512, 0.0);
    if (repo.ownerId == null) {
      await repo.registerOwner(name: 'Test Owner', faces: [(face, emb)]);
    }
    if ((await repo.getPersons()).isEmpty) {
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
      for (var i = 1; i <= 14; i++) {
        await add('Zpay $i', borrowed: 1000 * i);
      }
    }

    Future<void> run(Duration d) async {
      final end = DateTime.now().add(d);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> until(bool Function() ok, {int seconds = 20}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ok()) {
        if (DateTime.now().isAfter(end)) throw TestFailure('timed out');
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    PageController tabs() => tester
        .widget<LenzoSegmentedControl>(find.byType(LenzoSegmentedControl))
        .controller;
    int selected() => tabs().page!.round();

    final report = <String, Object>{};
    final errors = <String>[];

    app.main();
    await until(() => find.byTooltip('Saved people').evaluate().isNotEmpty);
    await run(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Saved people'));
    await run(const Duration(seconds: 1));

    Future<void> openContactAndBack(String name, {required bool system}) async {
      if (find.text(name).evaluate().isEmpty) {
        debugPrint(
          'PEOPLEDBG texts ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()} '
          'fields ${find.byType(TextField).evaluate().map((e) => (e.widget as TextField).controller?.text).toList()}',
        );
      }
      if (find.text(name).hitTestable().evaluate().isEmpty) {
        await tester.ensureVisible(find.text(name).first);
        await run(const Duration(milliseconds: 400));
      }
      await tester.tap(find.text(name).hitTestable().first);
      await until(() => find.text('Money Borrowed').evaluate().isNotEmpty);
      await run(const Duration(milliseconds: 800));
      debugPrint('PEOPLEDBG ---- going back (${system ? 'system' : 'arrow'})');
      if (system) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byTooltip('Back to camera').hitTestable().last);
      }
      // Watch every frame on the way back for a flash of another tab.
      final seen = <int>{};
      final end = DateTime.now().add(const Duration(milliseconds: 1200));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byType(LenzoSegmentedControl).evaluate().isNotEmpty &&
            tabs().hasClients) {
          seen.add(selected());
        }
      }
      debugPrint('PEOPLEDBG ---- back done, tabs seen $seen');
      report['seen_${name}_${system ? 'system' : 'arrow'}'] = seen.toList();
    }

    Future<void> check(String label, int tab, String name) async {
      await tester.tap(find.textContaining(label).first);
      await run(const Duration(milliseconds: 700));
      for (final system in [false, true]) {
        await openContactAndBack(name, system: system);
        final now = selected();
        report['${label}_${system ? 'system' : 'arrow'}'] = now;
        if (now != tab) {
          errors.add(
            '$label via ${system ? 'system Back' : 'arrow'}: tab $now',
          );
        }
      }
    }

    await check('To Pay (', 1, 'Raj');
    await check('To Receive (', 0, 'Asha');
    await check('Others (', 2, 'Boy');

    // Search + scroll on To Pay.
    await tester.tap(find.textContaining('To Pay (').first);
    await run(const Duration(milliseconds: 600));
    await tester.drag(find.text('Zpay 1').hitTestable(), const Offset(0, -250));
    await run(const Duration(milliseconds: 800));
    final scrollBefore = _listOffset(tester);
    final visible = find
        .textContaining('Zpay')
        .hitTestable()
        .evaluate()
        .map((e) => (e.widget as Text).data!)
        .toList();
    await openContactAndBack(visible[visible.length ~/ 2], system: true);
    final scrollAfter = _listOffset(tester);
    report['scroll_before'] = scrollBefore;
    report['scroll_after'] = scrollAfter;
    if ((scrollAfter - scrollBefore).abs() > 1) errors.add('scroll reset');
    if (selected() != 1) errors.add('scroll test: tab ${selected()}');

    await tester.enterText(_search(tester), 'raj');
    FocusManager.instance.primaryFocus?.unfocus();
    await run(const Duration(milliseconds: 800));
    await openContactAndBack('Raj', system: false);
    report['search_after'] = tester
        .widget<EditableText>(_search(tester))
        .controller
        .text;
    if (report['search_after'] != 'raj') errors.add('search cleared');
    if (selected() != 1) errors.add('search test: tab ${selected()}');

    // Ten round trips.
    await tester.enterText(_search(tester), '');
    FocusManager.instance.primaryFocus?.unfocus();
    await run(const Duration(milliseconds: 800));
    var resets = 0;
    for (var i = 0; i < 10; i++) {
      await openContactAndBack('Raj', system: i.isEven);
      if (selected() != 1) resets++;
    }
    report['ten_round_trips_resets'] = resets;
    if (resets > 0) errors.add('$resets resets in 10 round trips');

    debugPrint('PEOPLE_REPORT $report errors=$errors');
    binding.reportData = {...report, 'errors': errors};
    expect(errors, isEmpty);
  });
}

double _listOffset(WidgetTester tester) {
  final s = find
      .byType(Scrollable)
      .evaluate()
      .map((e) {
        return (e as StatefulElement).state as ScrollableState;
      })
      .where((s) => s.position.axis == Axis.vertical && s.mounted);
  for (final st in s) {
    if (st.position.maxScrollExtent > 0) return st.position.pixels;
  }
  return 0;
}

/// The Saved People search field.
Finder _search(WidgetTester tester) => find
    .descendant(
      of:
          find
              .byType(LenzoSegmentedControl, skipOffstage: false)
              .evaluate()
              .isEmpty
          ? find.byType(Scaffold)
          : find
                .ancestor(
                  of: find.byType(LenzoSegmentedControl, skipOffstage: false),
                  matching: find.byType(Column, skipOffstage: false),
                )
                .first,
      matching: find.byType(EditableText, skipOffstage: false),
      skipOffstage: false,
    )
    .first;
