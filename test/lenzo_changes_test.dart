import 'dart:typed_data';

import 'package:face_tag/data/models.dart';
import 'package:face_tag/design/design.dart';
import 'package:face_tag/screens/camera_screen.dart' show noteForOverlay;
import 'package:face_tag/services/face_crop.dart';
import 'package:face_tag/theme/lenzo_theme.dart';
import 'package:face_tag/widgets/face_mesh.dart';
import 'package:face_tag/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

Person _p({
  int lent = 0,
  int repaid = 0,
  int borrowed = 0,
  int paidBack = 0,
  String? notes,
  String name = 'Asha',
}) => Person(
  id: 1,
  name: name,
  createdAt: DateTime(2026),
  lentPaise: lent,
  repaidPaise: repaid,
  borrowedPaise: borrowed,
  paidBackPaise: paidBack,
  notes: notes,
);

Set<PeopleTab> _tabs(Person p) => {
  for (final t in PeopleTab.values)
    if (p.isIn(t)) t,
};

void main() {
  group('Saved People tabs', () {
    test('owed to me only → To Receive', () {
      expect(_tabs(_p(lent: 50000)), {PeopleTab.receive});
    });
    test('I owe only → To Pay', () {
      expect(_tabs(_p(borrowed: 20000)), {PeopleTab.pay});
    });
    test('both open balances → both money tabs, not Others', () {
      expect(_tabs(_p(lent: 50000, borrowed: 20000)), {
        PeopleTab.receive,
        PeopleTab.pay,
      });
    });
    test('settled both ways → Others', () {
      expect(
        _tabs(_p(lent: 50000, repaid: 50000, borrowed: 100, paidBack: 100)),
        {PeopleTab.others},
      );
    });
    test('saved only for recognition or a note → Others', () {
      expect(_tabs(_p()), {PeopleTab.others});
      expect(_tabs(_p(notes: 'Classmate')), {PeopleTab.others});
    });
    test('partly repaid stays in To Receive', () {
      expect(_tabs(_p(lent: 50000, repaid: 49999)), {PeopleTab.receive});
    });
    test('over-repaid (needs review, nothing open) → Others', () {
      final p = _p(lent: 100, repaid: 300);
      expect(p.needsReview, isTrue);
      expect(_tabs(p), {PeopleTab.others});
    });
    test('every person is in at least one tab', () {
      for (final p in [
        _p(),
        _p(lent: 1),
        _p(borrowed: 1),
        _p(lent: 1, repaid: 1),
        _p(lent: 5, borrowed: 5),
        _p(lent: 1, repaid: 9),
        _p(borrowed: 1, paidBack: 9),
      ]) {
        expect(_tabs(p), isNotEmpty);
      }
    });
    test('very large amounts are classified and formatted', () {
      final p = _p(lent: 99999999999); // ₹99.99 crore
      expect(_tabs(p), {PeopleTab.receive});
      expect(formatRupeesCompact(p.toReceivePaise), isNotEmpty);
    });
  });

  group('Overlay note text', () {
    test('no note → nothing', () {
      expect(noteForOverlay(null), isNull);
      expect(noteForOverlay(''), isNull);
      expect(noteForOverlay('   \n\t '), isNull);
    });
    test('whitespace collapsed', () {
      expect(noteForOverlay('  Class\n\nmate  '), 'Class mate');
    });
    test('long notes are cut to 140 characters with an ellipsis', () {
      final long = 'word ' * 100;
      final t = noteForOverlay(long)!;
      expect(t.length, lessThanOrEqualTo(140));
      expect(t.endsWith('…'), isTrue);
    });
    test('note panels compare by text', () {
      expect(const FaceInfo.note('a'), const FaceInfo.note('a'));
      expect(const FaceInfo.note('a') == const FaceInfo.note('b'), isFalse);
      expect(const FaceInfo.note('a') == const FaceInfo([]), isFalse);
    });
  });

  group('Recognition overlay', () {
    // A face 120 × 150 in the middle of a 360 × 640 portrait frame.
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
      await tester.pumpWidget(
        MaterialApp(
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
                  label: 'boy',
                  verified: true,
                  info: info,
                ),
              ],
              imageSize: const Size(360, 640),
              mirror: false,
              hits: hits,
            ),
          ),
        ),
      );
      // Let the face and its panel fade in.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      return hits;
    }

    testWidgets('a note sits below the face without covering it', (
      tester,
    ) async {
      final hits = await pump(tester, const FaceInfo.note('Classmate'));
      expect(tester.takeException(), isNull);
      expect(hits.panelAt(face.center), isNull, reason: 'covers the face');
      // Found under the face, centred.
      Object? below;
      for (var y = face.bottom; y < face.bottom + 60 && below == null; y++) {
        below = hits.panelAt(Offset(face.center.dx, y));
      }
      expect(below, 1);
    });

    testWidgets('a long note is drawn without errors and stays clear', (
      tester,
    ) async {
      final note = noteForOverlay(
        'Met at the college fest. Owes nothing now but asked about the '
                'laptop loan again; remind him about the deposit next month. ' *
            3,
      )!;
      final hits = await pump(tester, FaceInfo.note(note));
      expect(tester.takeException(), isNull);
      expect(hits.panelAt(face.center), isNull);
    });

    testWidgets('no note and no money → no panel at all', (tester) async {
      final hits = await pump(tester, null);
      expect(tester.takeException(), isNull);
      for (var y = 0.0; y < 640; y += 8) {
        for (var x = 0.0; x < 360; x += 8) {
          expect(hits.panelAt(Offset(x, y)), isNull);
        }
      }
    });

    testWidgets('money panels still draw (unchanged behaviour)', (
      tester,
    ) async {
      final hits = await pump(
        tester,
        const FaceInfo([InfoRow('To Receive', '₹5,000')]),
      );
      expect(tester.takeException(), isNull);
      var found = false;
      for (var y = 0.0; y < 640 && !found; y += 4) {
        for (var x = 0.0; x < 360 && !found; x += 4) {
          found = hits.panelAt(Offset(x, y)) != null;
        }
      }
      expect(found, isTrue);
    });
  });

  group('Saved photo orientation', () {
    /// A grey NV21 frame, [w] × [h] raw (landscape, as the sensor gives
    /// it), with white where [bright] says so, given in *upright*
    /// coordinates for [rotation].
    Uint8List frame(
      int w,
      int h,
      int rotation,
      bool Function(int ux, int uy) bright,
    ) {
      final out = Uint8List(w * h * 3 ~/ 2)..fillRange(0, w * h, 60);
      out.fillRange(w * h, out.length, 128); // neutral colour
      for (var ry = 0; ry < h; ry++) {
        for (var rx = 0; rx < w; rx++) {
          // Raw → upright, the inverse of the mapping in face_crop.dart.
          final (ux, uy) = switch (rotation) {
            90 => (h - 1 - ry, rx),
            270 => (ry, w - 1 - rx),
            180 => (w - 1 - rx, h - 1 - ry),
            _ => (rx, ry),
          };
          if (bright(ux, uy)) out[ry * w + rx] = 250;
        }
      }
      return out;
    }

    /// Mean brightness of the top-left and top-right quarters.
    (double, double) topQuarters(Uint8List jpeg) {
      final im = img.decodeJpg(jpeg)!;
      double mean(int x0, int x1) {
        var sum = 0.0, n = 0;
        for (var y = 0; y < im.height ~/ 2; y++) {
          for (var x = x0; x < x1; x++) {
            sum += im.getPixel(x, y).luminance;
            n++;
          }
        }
        return sum / n;
      }

      return (mean(0, im.width ~/ 2), mean(im.width ~/ 2, im.width));
    }

    for (final rotation in [90, 270]) {
      test('upright and correctly mirrored (rotation $rotation)', () {
        const w = 160, h = 120; // raw
        // Upright frame is 120 wide × 160 tall. Mark the subject's
        // upper-left area (as an onlooker sees it).
        final nv21 = frame(w, h, rotation, (x, y) => x < 50 && y < 70);
        Uint8List shot({bool mirror = false}) => portraitJpegFromNv21(
          nv21: nv21,
          width: w,
          height: h,
          rotation: rotation,
          box: const Rect.fromLTWH(20, 30, 80, 80),
          leftEye: const Offset(40, 60),
          rightEye: const Offset(80, 60),
          mirror: mirror,
        );
        final (l, r) = topQuarters(shot());
        expect(l, greaterThan(r + 40), reason: 'not upright as seen');
        final (ml, mr) = topQuarters(shot(mirror: true));
        expect(mr, greaterThan(ml + 40), reason: 'mirror did not flip');
        // Never upside down: the bottom half stays dark.
        final im = img.decodeJpg(shot())!;
        var bottom = 0.0;
        for (var y = im.height * 3 ~/ 4; y < im.height; y++) {
          for (var x = 0; x < im.width ~/ 2; x++) {
            bottom += im.getPixel(x, y).luminance;
          }
        }
        bottom /= (im.height ~/ 4) * (im.width ~/ 2);
        expect(bottom, lessThan(l - 40));
      });
    }

    test('recognition crops are not mirrored (embeddings unchanged)', () {
      const w = 160, h = 120;
      final nv21 = frame(w, h, 270, (x, y) => x < 50 && y < 70);
      final crop = cropAlignedFaceFromNv21(
        nv21: nv21,
        width: w,
        height: h,
        rotation: 270,
        box: const Rect.fromLTWH(20, 30, 80, 80),
        leftEye: const Offset(40, 60),
        rightEye: const Offset(80, 60),
      );
      final (l, r) = topQuarters(img.encodeJpg(crop));
      expect(l, greaterThan(r + 40));
    });
  });

  group('Inputs', () {
    testWidgets('no outline in any state; focus lightens the fill', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: Lenzo.theme(),
          home: Scaffold(
            body: Column(
              children: [
                TextField(
                  focusNode: focus,
                  decoration: lenzoFieldDecoration(hint: 'Name'),
                ),
              ],
            ),
          ),
        ),
      );
      final d = lenzoFieldDecoration(hint: 'x', error: 'bad');
      for (final b in [
        d.border,
        d.enabledBorder,
        d.focusedBorder,
        d.errorBorder,
        d.focusedErrorBorder,
        d.disabledBorder,
      ]) {
        expect(b!.borderSide, BorderSide.none);
      }
      final fill = lenzoFieldFill();
      expect(fill.resolve({}), LenzoColors.field);
      expect(fill.resolve({WidgetState.focused}), LenzoColors.fieldFocused);
      expect(LenzoColors.field, isNot(LenzoColors.background));
      expect(
        lenzoFieldFill(raised: true).resolve({}),
        isNot(LenzoColors.surface),
        reason: 'inputs on cards must differ from the card',
      );
      expect(LenzoRadius.input, LenzoRadius.card);
    });
  });
}
