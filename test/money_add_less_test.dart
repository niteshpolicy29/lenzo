import 'package:face_tag/data/models.dart';
import 'package:face_tag/design/design.dart';
import 'package:face_tag/screens/people_screen.dart' show PeopleMemory;
import 'package:face_tag/screens/person_detail_screen.dart' show AddLessToggle;
import 'package:face_tag/theme/lenzo_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

var _id = 0;
MoneyEntry _e(MoneyKind k, int rupees, DateTime at, {bool legacy = false}) =>
    MoneyEntry(
      id: ++_id,
      personId: 1,
      kind: k,
      amountPaise: rupees * 100,
      at: at,
      legacy: legacy,
    );

/// A person as the database builds them: totals summed from the entries.
Person _person(List<MoneyEntry> entries) {
  final t = MoneyEntry.totals(entries);
  return Person(
    id: 1,
    name: 'Raj',
    createdAt: DateTime(2026),
    lentPaise: t[MoneyKind.lent]!,
    repaidPaise: t[MoneyKind.repaid]!,
    borrowedPaise: t[MoneyKind.borrowed]!,
    paidBackPaise: t[MoneyKind.paidBack]!,
  );
}

Set<PeopleTab> _tabs(Person p) => {
  for (final t in PeopleTab.values)
    if (p.isIn(t)) t,
};

void main() {
  final d1 = DateTime(2026, 11, 20), d2 = DateTime(2026, 11, 23);

  group('Add and Less', () {
    test('Money Lent: Add increases, Less (saved as repaid) decreases', () {
      final entries = [_e(MoneyKind.lent, 738, d1)];
      expect(_person(entries).toReceivePaise, 73800);
      entries.add(_e(MoneyKind.lent, 200, d2)); // Add ₹200
      expect(_person(entries).toReceivePaise, 93800); // ₹938
      entries.add(_e(MoneyKind.repaid, 300, d2)); // Less ₹300
      expect(_person(entries).toReceivePaise, 63800);
    });

    test('Money Borrowed: ₹699 Less ₹200 → ₹499', () {
      final entries = [
        _e(MoneyKind.borrowed, 699, d1),
        _e(MoneyKind.paidBack, 200, d2),
      ];
      expect(_person(entries).toPayPaise, 49900);
    });

    test('reaching ₹0 moves the person to Others', () {
      final entries = [_e(MoneyKind.borrowed, 699, d1)];
      expect(_tabs(_person(entries)), {PeopleTab.pay});
      entries.add(_e(MoneyKind.paidBack, 699, d2));
      expect(_tabs(_person(entries)), {PeopleTab.others});
    });

    test('both balances open → both money tabs', () {
      final p = _person([
        _e(MoneyKind.lent, 500, d1),
        _e(MoneyKind.borrowed, 100, d1),
      ]);
      expect(_tabs(p), {PeopleTab.receive, PeopleTab.pay});
    });

    test('summary totals follow', () {
      final a = _person([
        _e(MoneyKind.lent, 500, d1),
        _e(MoneyKind.repaid, 200, d2),
      ]);
      final m = MoneySummary.of([a]);
      expect(m.toReceivePaise, 30000);
      expect(m.toPayPaise, 0);
    });
  });

  group('History', () {
    test('each operation is a line with date, sign, type and balance', () {
      final entries = [
        _e(MoneyKind.borrowed, 699, d1),
        _e(MoneyKind.paidBack, 200, d2),
        _e(MoneyKind.lent, 50, d2), // other account: not in this history
      ];
      final lines = ledgerOf(entries, MoneyKind.borrowed);
      expect(lines.length, 2);
      // Newest first.
      expect(lines[0].added, isFalse);
      expect(lines[0].entry.amountPaise, 20000);
      expect(lines[0].balancePaise, 49900);
      expect(lines[0].entry.at, d2);
      expect(lines[1].added, isTrue);
      expect(lines[1].balancePaise, 69900);
    });

    test('old records (earlier totals, old repayments) are kept in order', () {
      final entries = [
        _e(MoneyKind.lent, 1000, DateTime(2025), legacy: true),
        _e(MoneyKind.repaid, 400, DateTime(2025), legacy: true),
        _e(MoneyKind.lent, 100, d2),
      ];
      final lines = ledgerOf(entries, MoneyKind.lent);
      expect(lines.map((l) => l.balancePaise), [70000, 60000, 100000]);
      expect(lines.every((l) => entries.contains(l.entry)), isTrue);
    });

    test('balance never shown below ₹0 for over-repaid old data', () {
      final lines = ledgerOf([
        _e(MoneyKind.lent, 100, d1),
        _e(MoneyKind.repaid, 300, d2),
      ], MoneyKind.lent);
      expect(lines.first.balancePaise, 0);
    });
  });

  group('Add | Less toggle', () {
    Widget host(bool less, ValueChanged<bool> on, {bool still = false}) =>
        MaterialApp(
          theme: Lenzo.theme(),
          builder: (c, a) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: still),
            child: a!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: AddLessToggle(less: less, onChanged: on),
              ),
            ),
          ),
        );

    testWidgets('both options, equal width, tapping switches', (t) async {
      var less = false;
      await t.pumpWidget(host(less, (v) => less = v));
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Less'), findsOneWidget);
      expect(t.getSemantics(find.text('Add')), isSemantics(isSelected: true));
      await t.tap(find.text('Less'));
      expect(less, isTrue);
      await t.pumpWidget(host(less, (v) => less = v));
      // The mint pill slides over within 200 ms.
      await t.pump(const Duration(milliseconds: 200));
      expect(t.hasRunningAnimations, isFalse);
      final pill = t.getRect(
        find.descendant(
          of: find.byType(AnimatedAlign),
          matching: find.byType(DecoratedBox),
        ),
      );
      final lessText = t.getRect(find.text('Less'));
      expect(pill.contains(lessText.center), isTrue);
      expect(AddLessToggle.duration.inMilliseconds, inInclusiveRange(150, 200));
    });

    testWidgets('selected is mint with dark text', (t) async {
      await t.pumpWidget(host(true, (_) {}));
      await t.pumpAndSettle();
      final style = t
          .widget<AnimatedDefaultTextStyle>(
            find
                .ancestor(
                  of: find.text('Less'),
                  matching: find.byType(AnimatedDefaultTextStyle),
                )
                .first,
          )
          .style;
      expect(style.color, LenzoColors.onAccent);
    });
  });

  group('Saved People memory', () {
    setUp(PeopleMemory.reset);
    test('defaults to To Receive and no search', () {
      expect(PeopleMemory.tab, 0);
      expect(PeopleMemory.query, '');
    });
    testWidgets('a page rebuilt from scratch starts on the remembered tab', (
      t,
    ) async {
      PeopleMemory.tab = 1; // To Pay
      final c = PageController(initialPage: PeopleMemory.tab);
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: PageView(
            key: const PageStorageKey('people-tabs'),
            controller: c,
            children: const [Text('r'), Text('p'), Text('o')],
          ),
        ),
      );
      expect(c.page, 1.0);
      expect(find.text('p'), findsOneWidget);
    });
  });
}
