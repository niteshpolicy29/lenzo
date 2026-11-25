import 'package:face_tag/design/design.dart';
import 'package:face_tag/theme/lenzo_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('pill shows the selected tab when the pages give no position', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // A controller with no pages attached (as for a moment after
    // returning from a contact): it would report its initial page, 0.
    final c = PageController();
    addTearDown(c.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: Lenzo.theme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: LenzoSegmentedControl(
              controller: c,
              selected: 1,
              labels: const ['To Receive (1)', 'To Pay (2)', 'Others (0)'],
            ),
          ),
        ),
      ),
    );
    final pill = t.getRect(
      find
          .descendant(
            of: find.byType(LenzoSegmentedControl),
            matching: find.byType(FractionallySizedBox),
          )
          .first,
    );
    expect(pill.contains(t.getCenter(find.text('To Pay (2)'))), isTrue);
    expect(pill.contains(t.getCenter(find.text('To Receive (1)'))), isFalse);
  });
}
