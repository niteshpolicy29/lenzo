import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_tag/data/models.dart';
import 'package:face_tag/design/design.dart';
import 'package:face_tag/screens/camera_screen.dart' show personOverlay;
import 'package:face_tag/screens/gallery_add.dart';
import 'package:face_tag/screens/owner_screens.dart';
import 'package:face_tag/services/camera_choice.dart';
import 'package:face_tag/services/face_crop.dart';
import 'package:face_tag/services/gallery_face.dart';
import 'package:face_tag/theme/lenzo_theme.dart';
import 'package:face_tag/utils/format.dart';
import 'package:face_tag/widgets/face_mesh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

CameraDescription _cam(
  String id,
  CameraLensDirection d, [
  CameraLensType t = CameraLensType.unknown,
]) => CameraDescription(
  name: id,
  lensDirection: d,
  sensorOrientation: 90,
  lensType: t,
);

const _back = CameraLensDirection.back, _front = CameraLensDirection.front;

Person _p({
  String name = 'Rahul',
  int lent = 0,
  int repaid = 0,
  int borrowed = 0,
  int paidBack = 0,
  String? notes,
  DateTime? reminder,
}) => Person(
  id: 7,
  name: name,
  createdAt: DateTime(2026),
  lentPaise: lent,
  repaidPaise: repaid,
  borrowedPaise: borrowed,
  paidBackPaise: paidBack,
  notes: notes,
  reminder: reminder,
);

List<String> _lines(FaceInfo? f) => f == null
    ? const []
    : [
        for (final r in f.rows) '${r.label}: ${r.value}',
        if (f.note != null) f.note!,
        for (final r in f.after) '${r.label}: ${r.value}',
      ];

void main() {
  // -------------------------------------------------------------------------
  group('Camera choice: one rear, one front', () {
    test('a typical 4-lens phone uses only the main rear and front', () {
      final all = [
        _cam('0', _back),
        _cam('1', _front),
        _cam('2', _back), // ultra-wide
        _cam('3', _back), // macro
        _cam('4', _back), // depth
      ];
      expect(primaryCameras(all).map((c) => c.name), ['0', '1']);
    });

    test('the main rear camera is not assumed to be listed first', () {
      final all = [_cam('1', _front), _cam('5', _back), _cam('2', _back)];
      expect(primaryCameras(all).map((c) => c.name), ['2', '1']);
    });

    test('a camera reported as wide beats a lower id', () {
      final all = [
        _cam('0', _back, CameraLensType.ultraWide),
        _cam('3', _back, CameraLensType.wide),
        _cam('1', _front),
      ];
      expect(primaryCameras(all).first.name, '3');
    });

    test('fallbacks: one side only, non-numeric ids, nothing', () {
      expect(primaryCameras([_cam('1', _front)]).map((c) => c.name), ['1']);
      expect(
        primaryCameras([_cam('b', _back), _cam('a', _back), _cam('f', _front)])
            .map((c) => c.name),
        ['b', 'f'],
      );
      expect(primaryCameras(const []), isEmpty);
      expect(
        primaryCameras([_cam('9', CameraLensDirection.external)]).length,
        1,
      );
    });

    test('switching cycles rear → front → rear', () {
      final cams = primaryCameras([
        _cam('0', _back),
        _cam('2', _back),
        _cam('1', _front),
        _cam('3', _back),
      ]);
      var i = 0;
      final seen = <String>[];
      for (var k = 0; k < 6; k++) {
        i = (i + 1) % cams.length;
        seen.add(cams[i].lensDirection.name);
      }
      expect(seen, ['front', 'back', 'front', 'back', 'front', 'back']);
    });
  });

  // -------------------------------------------------------------------------
  group('Recognition overlay shows only what exists', () {
    final now = DateTime(2026, 11, 20);
    final nov25 = DateTime(2026, 11, 25);

    test('A: only a note', () {
      final f = personOverlay(_p(notes: 'Classmate'), now: now);
      expect(_lines(f), ['Classmate']);
      expect(f!.noteOnly, isTrue);
    });
    test('B: only money lent', () {
      expect(_lines(personOverlay(_p(lent: 50000), now: now)), [
        'To Receive: ₹500',
      ]);
    });
    test('C: only money borrowed', () {
      expect(_lines(personOverlay(_p(borrowed: 100000), now: now)), [
        'To Pay: ₹1,000',
      ]);
    });
    test('D: only a reminder', () {
      expect(_lines(personOverlay(_p(reminder: nov25), now: now)), [
        'Reminder: 25 Nov',
      ]);
    });
    test('E: everything, in order', () {
      expect(
        _lines(
          personOverlay(
            _p(
              lent: 50000,
              borrowed: 100000,
              notes: 'Classmate',
              reminder: nov25,
            ),
            now: now,
          ),
        ),
        ['To Receive: ₹500', 'To Pay: ₹1,000', 'Classmate', 'Reminder: 25 Nov'],
      );
    });
    test('only a name: no panel', () {
      expect(personOverlay(_p(), now: now), isNull);
      expect(personOverlay(_p(notes: '   '), now: now), isNull);
    });
    test('settled balances never show ₹0', () {
      final f = personOverlay(
        _p(lent: 50000, repaid: 50000, notes: 'Paid back'),
        now: now,
      );
      expect(_lines(f), ['Paid back']);
      expect(_lines(f).join(), isNot(contains('₹0')));
    });
    test('outstanding, not totals: partial repayment', () {
      expect(_lines(personOverlay(_p(lent: 50000, repaid: 20000), now: now)), [
        'To Receive: ₹300',
      ]);
    });
    test('large amounts are compact', () {
      expect(_lines(personOverlay(_p(lent: 10000000), now: now)), [
        'To Receive: ₹1L',
      ]);
      expect(_lines(personOverlay(_p(borrowed: 100000000), now: now)), [
        'To Pay: ₹10L',
      ]);
    });
    test('a reminder in another year shows the year', () {
      expect(
        _lines(personOverlay(_p(reminder: DateTime(2027, 1, 3)), now: now)),
        ['Reminder: 3 Jan 2027'],
      );
    });
  });

  // -------------------------------------------------------------------------
  group('Overlay drawing', () {
    const face = Rect.fromLTWH(120, 245, 120, 150);
    final mesh = FaceMesh(
      kind: 'landmark',
      points: [
        face.topLeft,
        face.topRight,
        face.bottomLeft,
        face.bottomRight,
        face.center,
      ],
      edges: const [(0, 1), (1, 3), (3, 2), (2, 0)],
      major: const [4],
    );

    Future<MeshHits> pump(WidgetTester tester, FaceInfo? info) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final hits = MeshHits();
      Widget overlay(FaceInfo? i) => MaterialApp(
        theme: Lenzo.theme(),
        home: SizedBox(
          width: 360,
          height: 640,
          child: FaceMeshOverlay(
            faces: [
              MeshFace(
                key: 1,
                mesh: mesh,
                color: LenzoColors.accent,
                label: 'Rahul',
                verified: true,
                info: i,
              ),
            ],
            imageSize: const Size(360, 640),
            mirror: false,
            hits: hits,
          ),
        ),
      );
      await tester.pumpWidget(overlay(info));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      return hits;
    }

    Rect panel(MeshHits hits) {
      var r = Rect.zero;
      for (var y = 0.0; y < 640; y += 2) {
        for (var x = 0.0; x < 360; x += 2) {
          if (hits.panelAt(Offset(x, y)) != null) {
            r = r == Rect.zero
                ? Rect.fromLTWH(x, y, 1, 1)
                : r.expandToInclude(Rect.fromLTWH(x, y, 1, 1));
          }
        }
      }
      return r;
    }

    testWidgets('all details in one panel that grows and clears the face', (
      tester,
    ) async {
      final small = panel(
        await pump(tester, const FaceInfo([InfoRow('To Receive', '₹500')])),
      );
      final full = panel(
        await pump(
          tester,
          FaceInfo(
            const [InfoRow('To Receive', '₹500'), InfoRow('To Pay', '₹1,000')],
            note: 'Classmate',
            after: const [InfoRow('Reminder', '25 Nov')],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(full.height, greaterThan(small.height * 2));
      expect(full.overlaps(face.deflate(8)), isFalse);
    });

    testWidgets('a long note wraps inside the panel without errors', (
      tester,
    ) async {
      final r = panel(
        await pump(
          tester,
          FaceInfo(
            const [InfoRow('To Receive', '₹5L')],
            note:
                'Met at the college fest, asked about the laptop loan again '
                'and the hostel deposit next month.',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(r.width, lessThan(260));
      expect(r.overlaps(face.deflate(8)), isFalse);
    });

    testWidgets('changing details keeps one stable panel', (tester) async {
      await pump(tester, const FaceInfo.note('Classmate'));
      final hits = await pump(
        tester,
        const FaceInfo([InfoRow('To Pay', '₹1,000')], note: 'Classmate'),
      );
      expect(tester.takeException(), isNull);
      expect(panel(hits), isNot(Rect.zero));
    });
  });

  // -------------------------------------------------------------------------
  group('Saved People tabs typography', () {
    testWidgets('one font size and weight for all three labels', (
      tester,
    ) async {
      for (final (width, scale) in [
        (320.0, 1.0),
        (360.0, 1.17),
        (300.0, 1.3),
      ]) {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final pages = PageController();
        addTearDown(pages.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: Lenzo.theme(),
            builder: (c, a) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: a!,
            ),
            home: Scaffold(
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: LenzoSegmentedControl(
                      controller: pages,
                      labels: const [
                        'To Receive (12)',
                        'To Pay (3)',
                        'Others (104)',
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: pages,
                      children: const [SizedBox(), SizedBox(), SizedBox()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final texts = [
          for (final l in ['To Receive (12)', 'To Pay (3)', 'Others (104)'])
            tester.widget<Text>(find.text(l)),
        ];
        final sizes = texts.map((t) => t.style!.fontSize).toSet();
        final weights = texts.map((t) => t.style!.fontWeight).toSet();
        expect(sizes.length, 1, reason: 'sizes differ at $width/$scale');
        expect(weights, {FontWeight.w600});
        // Each label fits its segment (not clipped).
        final seg = (width - 40) / 3;
        for (final l in ['To Receive (12)', 'To Pay (3)', 'Others (104)']) {
          final r = tester.getRect(find.text(l));
          expect(r.width, lessThanOrEqualTo(seg));
        }
        // Selecting another tab keeps the size.
        await tester.tap(find.text('Others (104)'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.text('Others (104)')).style!.fontSize,
          sizes.single,
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  group('Gallery photos', () {
    img.Image scene(int w, int h) {
      // Grey photo with a bright patch at the subject's upper left.
      final im = img.Image(width: w, height: h);
      img.fill(im, color: img.ColorRgb8(60, 60, 60));
      img.fillRect(
        im,
        x1: 20,
        y1: 30,
        x2: 60,
        y2: 70,
        color: img.ColorRgb8(250, 250, 250),
      );
      return im;
    }

    test(
      'EXIF rotation is applied (photo saved sideways comes upright)',
      () async {
        final upright = scene(120, 160);
        // What a phone stores for a portrait photo: pixels turned 90° left,
        // with EXIF orientation 6 ("rotate 90° clockwise to view").
        final stored = img.copyRotate(upright, angle: -90)
          ..exif.imageIfd.orientation = 6;
        final dir = await Directory.systemTemp.createTemp('lenzo_gallery');
        addTearDown(() => dir.delete(recursive: true));
        final f = File('${dir.path}/p.jpg')
          ..writeAsBytesSync(img.encodeJpg(stored));
        final loaded = (await loadUprightImage(f.path))!;
        expect((loaded.width, loaded.height), (120, 160));
        expect(loaded.getPixel(40, 50).luminance, greaterThan(200));
        expect(loaded.getPixel(80, 50).luminance, lessThan(100));
      },
    );

    test('unreadable files are reported, not thrown', () async {
      final dir = await Directory.systemTemp.createTemp('lenzo_gallery');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/x.jpg')..writeAsStringSync('not an image');
      expect(await loadUprightImage(f.path), isNull);
    });

    test('crops are not mirrored and match the camera framing', () {
      final photo = scene(120, 160);
      const box = Rect.fromLTWH(10, 20, 80, 80);
      final crop = cropAlignedFaceFromImage(
        photo,
        box: box,
        leftEye: const Offset(30, 50),
        rightEye: const Offset(70, 50),
      );
      expect(crop.width, kFaceCropSize);
      // Same scene as an NV21 camera frame (no rotation).
      final nv = Uint8List(120 * 160 * 3 ~/ 2)..fillRange(0, 120 * 160, 60);
      nv.fillRange(120 * 160, nv.length, 128);
      for (var y = 30; y <= 70; y++) {
        for (var x = 20; x <= 60; x++) {
          nv[y * 120 + x] = 250;
        }
      }
      final cam = cropAlignedFaceFromNv21(
        nv21: nv,
        width: 120,
        height: 160,
        rotation: 0,
        box: box,
        leftEye: const Offset(30, 50),
        rightEye: const Offset(70, 50),
      );
      var diff = 0.0;
      for (var y = 0; y < crop.height; y++) {
        for (var x = 0; x < crop.width; x++) {
          diff += (crop.getPixel(x, y).luminance - cam.getPixel(x, y).luminance)
              .abs();
        }
      }
      // Same picture apart from smoothing at the edges of the patch.
      expect(diff / (crop.width * crop.height), lessThan(12));
      // Upper-left stays upper-left (not mirrored).
      expect(
        crop.getPixel(40, 40).luminance,
        greaterThan(crop.getPixel(120, 40).luminance + 100),
      );
    });

    test('a face makes a crop, a sharp 512 px portrait and a preview', () {
      final f = faceFromImage(
        scene(400, 500),
        const Rect.fromLTWH(100, 120, 160, 180),
        (const Offset(150, 190), const Offset(210, 190)),
      );
      expect(img.decodeJpg(f.portrait)!.width, 512);
      expect(img.decodeJpg(f.thumbnail)!.width, 160);
    });
  });

  // -------------------------------------------------------------------------
  group('Face choice sheet', () {
    final thumb = img.encodeJpg(img.Image(width: 16, height: 16));
    GalleryFace face() => GalleryFace(
      box: Rect.zero,
      crop: img.Image(width: 4, height: 4),
      portrait: thumb,
      thumbnail: thumb,
    );

    Future<void> show(WidgetTester t, GalleryFaces found) async {
      t.view.physicalSize = const Size(360, 760);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: Lenzo.theme(),
          home: Scaffold(body: FaceChoiceSheet(found: found)),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }

    testWidgets('no face: clear message, choose another photo', (t) async {
      await show(t, const GalleryFaces([], GalleryFaceError.noFace));
      expect(find.text('No face found'), findsOneWidget);
      expect(find.text('Choose another photo'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('unreadable photo', (t) async {
      await show(t, const GalleryFaces([], GalleryFaceError.unreadable));
      expect(find.text("Couldn't open this photo"), findsOneWidget);
    });

    testWidgets('one face: preview and Continue', (t) async {
      await show(t, GalleryFaces([face()]));
      expect(find.text('Face found'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.bySemanticsLabel('Face 1 of 1'), findsOneWidget);
    });

    testWidgets('several faces: choose one', (t) async {
      await show(t, GalleryFaces([face(), face(), face()]));
      expect(find.text('Choose a face'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Face \d of 3$')),
        findsNWidgets(3),
      );
      await t.tap(find.bySemanticsLabel('Face 3 of 3'));
      await t.pump();
      expect(
        t.getSemantics(find.bySemanticsLabel('Face 3 of 3')),
        isSemantics(isSelected: true),
      );
      expect(
        t.getSemantics(find.bySemanticsLabel('Face 1 of 3')),
        isSemantics(isSelected: false),
      );
    });
  });

  test('Update Face Scan does not ask for a name again', () {
    expect(
      OwnerFaceUpdateScreen.capturedMessage,
      'Face captured successfully. Save to update your face scan.',
    );
    expect(OwnerFaceUpdateScreen.capturedMessage, isNot(contains('name')));
  });

  test('short date format', () {
    expect(
      formatShortDate(DateTime(2026, 11, 25), now: DateTime(2026)),
      '25 Nov',
    );
  });

  test('outline accent button is mint', () {
    expect(LenzoButtonKind.values, contains(LenzoButtonKind.outlineAccent));
  });
}
