import 'package:face_tag/screens/photo_picker.dart';
import 'package:face_tag/theme/lenzo_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

final _jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));

class _Photo implements PhotoItem {
  _Photo(this.id, [this._path]);
  @override
  final String id;
  final String? _path;
  @override
  Future<Uint8List?> thumbnail(int size) async => _jpeg;
  @override
  Future<String?> path() async => _path;
}

class _Source implements PhotoSource {
  _Source({this.access = PhotoAccess.granted, Map<String, int>? albums})
    : counts = albums ?? {'All': 130, 'Recent': 12, 'Gallery': 5};
  PhotoAccess access;
  final Map<String, int> counts;
  int requests = 0, settings = 0, more = 0;
  final pagesAsked = <String>[];

  @override
  Future<PhotoAccess> requestAccess() async {
    requests++;
    return access;
  }

  @override
  Future<List<PhotoAlbum>> albums() async => [
    for (final e in counts.entries) PhotoAlbum(id: e.key, name: e.key),
  ];

  @override
  Future<List<PhotoItem>> photos(PhotoAlbum album, {required int page}) async {
    pagesAsked.add('${album.id}:$page');
    final total = counts[album.id]!;
    final start = page * PhotoSource.pageSize;
    final end = (start + PhotoSource.pageSize).clamp(0, total);
    return [
      for (var i = start; i < end; i++)
        _Photo('${album.id}-$i', i == 1 ? null : '/p/${album.id}/$i.jpg'),
    ];
  }

  @override
  Future<void> chooseMore() async => more++;
  @override
  Future<void> openSettings() async => settings++;
}

void main() {
  Future<String?> open(WidgetTester t, _Source s) async {
    t.view.physicalSize = const Size(360, 760);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    String? result = 'not closed';
    await t.pumpWidget(
      MaterialApp(
        theme: Lenzo.theme(),
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    result = await pickLenzoPhoto(c, source: s),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return result;
  }

  testWidgets('shows albums and a photo grid in Lenzo style', (t) async {
    final s = _Source();
    await open(t, s);
    expect(t.takeException(), isNull);
    expect(find.text('Choose a photo'), findsOneWidget);
    for (final tag in ['All', 'Recent', 'Gallery']) {
      expect(find.text(tag), findsOneWidget);
    }
    // Three equal tags across the screen, no scrolling row.
    final w = [
      for (final tag in ['All', 'Recent', 'Gallery'])
        t
            .getSize(
              find.ancestor(
                of: find.text(tag),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .width,
    ];
    expect(w.toSet().length, 1);
    expect(find.byType(ListView), findsNothing);
    expect(find.bySemanticsLabel('Photo 1'), findsOneWidget);
    expect(s.pagesAsked, ['All:0']);
    final scaffold = t.widget<Scaffold>(find.byType(Scaffold).last);
    expect(scaffold.backgroundColor, Lenzo.background);
  });

  testWidgets('loads more photos while scrolling', (t) async {
    final s = _Source();
    await open(t, s);
    await t.drag(find.byType(GridView), const Offset(0, -3000));
    await t.pumpAndSettle();
    expect(s.pagesAsked, containsAll(['All:0', 'All:1']));
    expect(t.takeException(), isNull);
  });

  testWidgets('switching album shows its photos', (t) async {
    final s = _Source();
    await open(t, s);
    await t.tap(find.text('Gallery'));
    await t.pumpAndSettle();
    expect(s.pagesAsked.last, 'Gallery:0');
    expect(find.bySemanticsLabel('Photo 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Photo 6'), findsNothing);
  });

  testWidgets('tapping a photo returns its path', (t) async {
    String? picked;
    final s = _Source();
    t.view.physicalSize = const Size(360, 760);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: Lenzo.theme(),
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => picked = await pickLenzoPhoto(c, source: s),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Photo 3'));
    await t.pumpAndSettle();
    expect(picked, '/p/All/2.jpg');
    expect(find.text('Choose a photo'), findsNothing);
  });

  testWidgets('a photo that cannot be read keeps the picker open', (t) async {
    await open(t, _Source());
    await t.tap(find.bySemanticsLabel('Photo 2')); // path() returns null
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text("Couldn't open this photo. Try another."), findsOneWidget);
    expect(find.text('Choose a photo'), findsOneWidget);
  });

  testWidgets('no access: explains, retries, opens settings', (t) async {
    final s = _Source(access: PhotoAccess.denied);
    await open(t, s);
    expect(find.text('Allow access to your photos'), findsOneWidget);
    await t.tap(find.text('Open settings'));
    expect(s.settings, 1);
    s.access = PhotoAccess.granted;
    await t.tap(find.text('Allow access'));
    await t.pumpAndSettle();
    expect(s.requests, 2);
    expect(find.bySemanticsLabel('Photo 1'), findsOneWidget);
  });

  testWidgets('limited access: banner to choose more', (t) async {
    final s = _Source(access: PhotoAccess.limited);
    await open(t, s);
    expect(
      find.text('Lenzo can see only some of your photos.'),
      findsOneWidget,
    );
    await t.tap(find.text('Choose more'));
    await t.pumpAndSettle();
    expect(s.more, 1);
  });

  testWidgets('no photos at all', (t) async {
    await open(t, _Source(albums: {}));
    expect(find.text('No photos here'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('back closes with nothing chosen', (t) async {
    await open(t, _Source());
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
    expect(find.text('Choose a photo'), findsNothing);
  });
}
