import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photo_manager/photo_manager.dart';

import '../design/design.dart';
import '../theme/lenzo_theme.dart';
import '../widgets/lenzo_ui.dart';
import '../widgets/swipe_route.dart';

// ---------------------------------------------------------------------------
// Where photos come from
// ---------------------------------------------------------------------------

/// Access to the phone's photos.
enum PhotoAccess { granted, limited, denied }

/// An album (Recent, Camera, Screenshots…).
class PhotoAlbum {
  const PhotoAlbum({required this.id, required this.name, this.count});
  final String id;
  final String name;
  final int? count;
}

/// One photo in an album.
abstract class PhotoItem {
  String get id;

  /// A small square preview.
  Future<Uint8List?> thumbnail(int size);

  /// The full photo's path on the phone, or null if it can't be read.
  Future<String?> path();
}

/// The phone's photo library, behind an interface so the picker can be
/// tested without a phone.
abstract class PhotoSource {
  Future<PhotoAccess> requestAccess();
  Future<List<PhotoAlbum>> albums();
  Future<List<PhotoItem>> photos(PhotoAlbum album, {required int page});

  /// With limited access: lets the user choose more photos to share.
  Future<void> chooseMore();
  Future<void> openSettings();
  static const pageSize = 60;
}

/// [PhotoSource] reading the phone's MediaStore (images only).
class DevicePhotoSource implements PhotoSource {
  const DevicePhotoSource();

  static const _type = RequestType.image;
  static final _cache = <String, AssetPathEntity>{};

  @override
  Future<PhotoAccess> requestAccess() async {
    final s = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(type: _type, mediaLocation: false),
      ),
    );
    return switch (s) {
      PermissionState.authorized => PhotoAccess.granted,
      PermissionState.limited => PhotoAccess.limited,
      _ => PhotoAccess.denied,
    };
  }

  /// How far back "Recent" goes.
  static const recentDays = 30;

  /// Always the same three tags: All (every photo), Recent (the last 30
  /// days) and Gallery (the Camera album: photos taken with this phone;
  /// all photos if there is no Camera album).
  @override
  Future<List<PhotoAlbum>> albums() async {
    final all = await PhotoManager.getAssetPathList(type: _type, onlyAll: true);
    if (all.isEmpty || await all.first.assetCountAsync == 0) return const [];
    _cache['all'] = all.first;

    final now = DateTime.now();
    final recent = await PhotoManager.getAssetPathList(
      type: _type,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        createTimeCond: DateTimeCond(
          min: now.subtract(const Duration(days: recentDays)),
          max: now.add(const Duration(days: 1)),
        ),
      ),
    );
    _cache['recent'] = recent.isEmpty ? all.first : recent.first;

    final paths = await PhotoManager.getAssetPathList(type: _type);
    AssetPathEntity? camera;
    for (final p in paths) {
      if (!p.isAll && p.name.toLowerCase() == 'camera') camera = p;
    }
    _cache['gallery'] = camera ?? all.first;

    return const [
      PhotoAlbum(id: 'all', name: 'All'),
      PhotoAlbum(id: 'recent', name: 'Recent'),
      PhotoAlbum(id: 'gallery', name: 'Gallery'),
    ];
  }

  @override
  Future<List<PhotoItem>> photos(PhotoAlbum album, {required int page}) async {
    final p = _cache[album.id];
    if (p == null) return const [];
    final list = await p.getAssetListPaged(
      page: page,
      size: PhotoSource.pageSize,
    );
    return [for (final a in list) _DevicePhoto(a)];
  }

  @override
  Future<void> chooseMore() => PhotoManager.presentLimited(type: _type);

  @override
  Future<void> openSettings() => PhotoManager.openSetting();
}

class _DevicePhoto implements PhotoItem {
  _DevicePhoto(this.asset);
  final AssetEntity asset;

  @override
  String get id => asset.id;

  @override
  Future<Uint8List?> thumbnail(int size) =>
      asset.thumbnailDataWithSize(ThumbnailSize.square(size), quality: 80);

  @override
  Future<String?> path() async => (await asset.originFile)?.path;
}

// ---------------------------------------------------------------------------
// The picker
// ---------------------------------------------------------------------------

/// Opens Lenzo's photo picker and returns the chosen photo's path, or null
/// if the user backs out.
Future<String?> pickLenzoPhoto(
  BuildContext context, {
  PhotoSource source = const DevicePhotoSource(),
}) => Navigator.of(context).push<String>(
  LenzoSwipeRoute<String>(builder: (_) => PhotoPickerScreen(source: source)),
);

/// Full-screen photo picker in Lenzo's style: album chips across the top
/// and a grid of the album's photos, newest first. Asks for access to the
/// photos itself and explains what to do when it isn't given. Tapping a
/// photo returns its path.
class PhotoPickerScreen extends StatefulWidget {
  const PhotoPickerScreen({super.key, required this.source});
  final PhotoSource source;

  @override
  State<PhotoPickerScreen> createState() => _PhotoPickerScreenState();
}

class _PhotoPickerScreenState extends State<PhotoPickerScreen>
    with WidgetsBindingObserver {
  PhotoAccess? _access;
  List<PhotoAlbum> _albums = const [];
  PhotoAlbum? _album;
  final List<PhotoItem> _photos = [];
  int _page = 0;
  bool _loading = false;
  bool _done = false;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Settings: check access again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _access == PhotoAccess.denied) {
      _start();
    }
  }

  Future<void> _start() async {
    setState(() => _error = null);
    PhotoAccess access;
    try {
      access = await widget.source.requestAccess();
    } catch (e) {
      access = PhotoAccess.denied;
    }
    if (!mounted) return;
    setState(() => _access = access);
    if (access == PhotoAccess.denied) return;
    await _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    try {
      final albums = await widget.source.albums();
      if (!mounted) return;
      setState(() {
        _albums = albums;
        _album = albums.isEmpty
            ? null
            : albums.firstWhere(
                (a) => a.id == _album?.id,
                orElse: () => albums.first,
              );
      });
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't load your photos.");
    }
  }

  Future<void> _reload() async {
    setState(() {
      _photos.clear();
      _page = 0;
      _done = false;
    });
    await _more();
  }

  Future<void> _more() async {
    final album = _album;
    if (album == null || _loading || _done) return;
    setState(() => _loading = true);
    try {
      final page = await widget.source.photos(album, page: _page);
      if (!mounted || album != _album) return;
      setState(() {
        _photos.addAll(page);
        _page++;
        _done = page.length < PhotoSource.pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't load your photos.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectAlbum(PhotoAlbum a) {
    if (a.id == _album?.id) return;
    HapticFeedback.selectionClick();
    setState(() => _album = a);
    _reload();
  }

  Future<void> _choose(PhotoItem p) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final path = await p.path();
      if (!mounted) return;
      if (path == null) {
        showLenzoMessage(context, "Couldn't open this photo. Try another.");
        return;
      }
      Navigator.of(context).pop(path);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _chooseMore() async {
    await widget.source.chooseMore();
    if (mounted) await _loadAlbums();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: lenzoSystemUi,
      child: LenzoSwipeBack(
        child: Scaffold(
          backgroundColor: LenzoColors.background,
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    LenzoSpacing.screen,
                    LenzoSpacing.x1,
                    LenzoSpacing.screen,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Choose a photo', style: LenzoType.pageHeading),
                      SizedBox(height: LenzoSpacing.x1),
                      Text(
                        'Pick a clear photo of the person you want to add.',
                        style: LenzoType.secondary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: LenzoSpacing.x4),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 64),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: LenzoBrandLogo(height: 28),
            ),
          ),
          Positioned(
            left: 6,
            child: IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: LenzoColors.textPrimary,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final access = _access;
    if (access == null) return _spinner();
    if (access == PhotoAccess.denied) {
      return _Message(
        icon: Icons.photo_library_outlined,
        title: 'Allow access to your photos',
        text:
            'Lenzo needs your photos to add someone from a picture. They '
            'stay on this phone.',
        action: 'Allow access',
        onAction: _start,
        secondary: 'Open settings',
        onSecondary: widget.source.openSettings,
      );
    }
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline_rounded,
        title: _error!,
        text: 'Check that your photos are available, then try again.',
        action: 'Try again',
        onAction: _start,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (access == PhotoAccess.limited) _limitedBanner(),
        if (_albums.isNotEmpty) ...[
          _albumChips(),
          // Room between the chips and the photos.
          const SizedBox(height: LenzoSpacing.x2),
        ],
        // Photos scrolling up fade out before the chips instead of
        // butting against them.
        Expanded(
          // and a soft shadow at the bottom, above the navigation bar.
          child: FadeEdges(top: _gridFade, bottom: _bottomFade, child: _grid()),
        ),
      ],
    );
  }

  Widget _spinner() => const Center(
    child: SizedBox.square(
      dimension: 26,
      child: CircularProgressIndicator(
        strokeWidth: 2.4,
        color: LenzoColors.accent,
      ),
    ),
  );

  Widget _limitedBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LenzoSpacing.screen,
        0,
        LenzoSpacing.screen,
        LenzoSpacing.x3,
      ),
      child: LenzoCard(
        small: true,
        shadow: false,
        onTap: _chooseMore,
        padding: const EdgeInsets.fromLTRB(
          LenzoSpacing.x4,
          LenzoSpacing.x3,
          LenzoSpacing.x3,
          LenzoSpacing.x3,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: LenzoColors.textSecondary,
            ),
            const SizedBox(width: LenzoSpacing.x3),
            const Expanded(
              child: Text(
                'Lenzo can see only some of your photos.',
                style: LenzoType.secondary,
              ),
            ),
            Text(
              'Choose more',
              style: LenzoType.button.copyWith(
                fontSize: 13,
                color: LenzoColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The album tags side by side, sharing the width equally (no
  /// scrolling).
  Widget _albumChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LenzoSpacing.screen),
      child: Row(
        children: [
          for (var i = 0; i < _albums.length; i++) ...[
            if (i > 0) const SizedBox(width: LenzoSpacing.x2),
            Expanded(child: _chip(_albums[i])),
          ],
        ],
      ),
    );
  }

  Widget _chip(PhotoAlbum a) {
    final on = a.id == _album?.id;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () => _selectAlbum(a),
        child: AnimatedContainer(
          duration: LenzoMotion.of(context, LenzoMotion.tab),
          curve: LenzoMotion.ease,
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: LenzoSpacing.x2),
          decoration: BoxDecoration(
            color: on ? LenzoColors.accent : LenzoColors.surface,
            borderRadius: LenzoRadius.pillAll,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              a.count == null ? a.name : '${a.name}  ${a.count}',
              maxLines: 1,
              style: LenzoType.button.copyWith(
                fontSize: 14,
                color: on ? LenzoColors.onAccent : LenzoColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Height of the soft fade at the top of the photo grid.
  static const _gridFade = 20.0;

  /// Height of the shadow fading the photos out at the bottom.
  static const _bottomFade = 56.0;

  Widget _grid() {
    if (_photos.isEmpty && (_loading || _album == null && _albums.isNotEmpty)) {
      return _spinner();
    }
    if (_photos.isEmpty) {
      return const _Message(
        icon: Icons.image_not_supported_outlined,
        title: 'No photos here',
        text: 'Photos you take or save on this phone will show here.',
      );
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 600) _more();
        return false;
      },
      child: GridView.builder(
        key: PageStorageKey('photos-${_album?.id}'),
        // Starts below the fade, so the first row is fully visible.
        padding: EdgeInsets.fromLTRB(
          LenzoSpacing.screen,
          _gridFade,
          LenzoSpacing.screen,
          _bottomFade + bottom,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: LenzoSpacing.x2,
          crossAxisSpacing: LenzoSpacing.x2,
        ),
        itemCount: _photos.length,
        itemBuilder: (context, i) => _PhotoTile(
          key: ValueKey(_photos[i].id),
          photo: _photos[i],
          index: i,
          onTap: () => _choose(_photos[i]),
        ),
      ),
    );
  }
}

/// A rounded photo tile; the preview fades in once loaded.
class _PhotoTile extends StatefulWidget {
  const _PhotoTile({
    super.key,
    required this.photo,
    required this.index,
    required this.onTap,
  });
  final PhotoItem photo;
  final int index;
  final VoidCallback onTap;

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  late final Future<Uint8List?> _thumb = widget.photo.thumbnail(240);
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final d = LenzoMotion.of(context, LenzoMotion.press);
    return Semantics(
      button: true,
      label: 'Photo ${widget.index + 1}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.95 : 1,
          duration: d,
          curve: LenzoMotion.ease,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LenzoRadius.field),
            child: ColoredBox(
              color: LenzoColors.surface,
              child: FutureBuilder<Uint8List?>(
                future: _thumb,
                builder: (context, snap) {
                  final bytes = snap.data;
                  return AnimatedOpacity(
                    opacity: bytes == null ? 0 : 1,
                    duration: LenzoMotion.of(context, LenzoMotion.tab),
                    child: bytes == null
                        ? const SizedBox.expand()
                        : Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
    this.onAction,
    this.secondary,
    this.onSecondary,
  });
  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LenzoSpacing.major),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: LenzoColors.textSecondary, size: 32),
            const SizedBox(height: LenzoSpacing.x3),
            Text(
              title,
              textAlign: TextAlign.center,
              style: LenzoType.sectionHeading,
            ),
            const SizedBox(height: LenzoSpacing.x1),
            Text(
              text,
              textAlign: TextAlign.center,
              style: LenzoType.body.copyWith(color: LenzoColors.textSecondary),
            ),
            if (action != null) ...[
              const SizedBox(height: LenzoSpacing.x5),
              LenzoButton(label: action!, onPressed: onAction),
            ],
            if (secondary != null) ...[
              const SizedBox(height: LenzoSpacing.x3),
              LenzoButton(
                label: secondary!,
                kind: LenzoButtonKind.outlineAccent,
                onPressed: onSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
