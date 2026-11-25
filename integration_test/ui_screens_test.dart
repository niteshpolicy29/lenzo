// On-device check of the redesigned screens, in Lenzo Test only.
//
// Seeds a few contacts in the test app's own database, opens Saved People
// (all three tabs, search), the New Contact form (fields, focus, calendar),
// and saves screenshots through the driver. Refuses to run outside
// com.nitesh.face_tag.devtest.
import 'package:face_tag/screens/new_contact_screen.dart';
import 'package:face_tag/screens/owner_screens.dart';
import 'package:face_tag/screens/people_screen.dart';
import 'package:face_tag/services/face_repository.dart';
import 'package:face_tag/theme/lenzo_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('redesigned screens on device', (tester) async {
    final dbDir = await getDatabasesPath();
    if (!dbDir.contains('com.nitesh.face_tag.devtest')) {
      fail('Refusing to run outside Lenzo Test (data folder: $dbDir)');
    }
    final report = <String, Object>{'test_app_data': dbDir};

    final repo = await FaceRepository.create();
    final face = img.Image(width: 160, height: 160);
    final emb = List.filled(512, 0.0);
    if (repo.ownerId == null) {
      await repo.registerOwner(name: 'Test Owner', faces: [(face, emb)]);
    }
    if ((await repo.getPersons()).isEmpty) {
      Future<void> add(
        String name, {
        int lent = 0,
        int repaid = 0,
        int borrowed = 0,
        String? notes,
      }) => repo.registerPerson(
        name: name,
        embedding: emb,
        faceCrop: face,
        lentPaise: lent,
        repaidPaise: repaid,
        borrowedPaise: borrowed,
        notes: notes,
      );
      await add('Asha', lent: 500000);
      await add('Ravi', borrowed: 120000);
      await add('Both Ways', lent: 30000, borrowed: 10000);
      await add('Settled Sam', lent: 20000, repaid: 20000);
      await add('boy', notes: 'Classmate');
      await add(
        'Bartholomew Alexander Fitzgerald-Montgomery the Third',
        notes:
            'Met at the college fest; asked about the laptop loan, remind '
            'him about the deposit next month and the hostel fees.',
      );
      await add('Big Lender', lent: 99999999999);
    }

    await binding.convertFlutterSurfaceToImage();
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    }

    // ---- Saved People: three tabs and search ---------------------------
    await tester.pumpWidget(
      MaterialApp(
        theme: Lenzo.theme(),
        home: PeopleScreen(repo: repo, animateEntrance: false),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('Others ('), findsOneWidget);
    report['tab_labels'] = [
      for (final t in ['To Receive (', 'To Pay (', 'Others ('])
        (find.textContaining(t).evaluate().single.widget as Text).data!,
    ];
    await shot('01_people_receive');
    await tester.tap(find.textContaining('To Pay ('));
    await shot('02_people_pay');
    await tester.tap(find.textContaining('Others ('));
    await shot('03_people_others');
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'bo');
    await shot('04_people_search_focused');
    expect(tester.takeException(), isNull);

    // ---- Settings ----------------------------------------------------------
    await tester.pumpWidget(
      MaterialApp(
        theme: Lenzo.theme(),
        home: OwnerProfileScreen(repo: repo, onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profile Settings'), findsOneWidget);
    expect(find.textContaining('photos saved'), findsNothing);
    await shot('08_settings');
    expect(tester.takeException(), isNull);

    // ---- New Contact form ------------------------------------------------
    await tester.pumpWidget(
      MaterialApp(
        theme: Lenzo.theme(),
        home: NewContactScreen(repo: repo, faceCrop: face, embedding: emb),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You gave them'), findsNothing);
    expect(find.text('You took from them'), findsNothing);
    await shot('05_register');
    await tester.tap(find.byType(TextField).first);
    await shot('06_register_name_focused');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(
      find.text('Select a date'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Select a date'));
    await shot('07_register_calendar');
    expect(tester.takeException(), isNull);

    // Merge: takeScreenshot stores the images in reportData too.
    binding.reportData = {...?binding.reportData, ...report};
  });
}
