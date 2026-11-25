import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../services/face_repository.dart';
import '../theme/lenzo_theme.dart';
import '../utils/format.dart';
import '../design/design.dart';
import '../widgets/lenzo_ui.dart';
import 'gallery_add.dart';
import '../widgets/swipe_route.dart';
import 'person_detail_screen.dart';

const Color _amber = Lenzo.warning;

/// Everyone saved on this phone. Search by name, tap a card for the
/// person's details, tap the trash icon to remove them, or
/// tap the edit icon to rename them or update their face photo.
///
/// "Update face photo" closes this page and returns the person's id, so
/// the camera can take a new face photo for them.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({
    super.key,
    required this.repo,
    this.initialPeople,
    this.animateEntrance = true,
    this.onBack,
    this.onUpdatePhoto,
    this.onEdgeDrag,
    this.onEdgeRelease,
  });
  final FaceRepository repo;

  /// A rightward swipe that starts on the first tab (To Receive) and has
  /// nowhere left to go: hands the drag to the page underneath (Home), in
  /// pixels, then its release velocity (px/s, positive = rightward).
  final ValueChanged<double>? onEdgeDrag;
  final ValueChanged<double>? onEdgeRelease;

  /// Back arrow; pops the page if null.
  final VoidCallback? onBack;

  /// "Update face photo"; pops with the person's id if null.
  final ValueChanged<int>? onUpdatePhoto;

  /// Shown straight away (then refreshed), so a page opened by a swipe
  /// doesn't flash a loading indicator.
  final List<Person>? initialPeople;

  /// Cards rise in one by one when the page opens. Off for a page pulled in
  /// by hand, which already shows its cards while it follows the finger.
  final bool animateEntrance;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  late List<Person>? _people = widget.initialPeople;

  /// Search text and tab, kept for the whole time the app is open, so
  /// coming back from a contact (or the page being rebuilt) shows the same
  /// tab and search. Each tab's list keeps its scroll position by its own
  /// storage key.
  late final _search = TextEditingController(text: PeopleMemory.query);
  late final _tabs = PageController(initialPage: PeopleMemory.tab);

  /// The "No open balance" group under each tab, collapsed by default.

  /// True while a rightward swipe from the first tab is moving Home.
  bool _edging = false;
  late String _query = PeopleMemory.query;

  @override
  void initState() {
    super.initState();
    widget.repo.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.repo.removeListener(_refresh);
    _search.dispose();
    _tabs.dispose();
    super.dispose();
  }

  /// Bumped per refresh, so an older, slower query can't overwrite a newer
  /// one (e.g. two quick deletes).
  int _loadId = 0;

  /// Reloads from the database. Runs whenever the repository changes (add,
  /// edit, delete), so the list, total, borrower count and empty state all
  /// follow the saved data. The search text is kept.
  Future<void> _refresh() async {
    final id = ++_loadId;
    final people = await widget.repo.getPersons();
    if (mounted && id == _loadId) setState(() => _people = people);
  }

  List<Person> get _visible {
    final all = _people ?? const <Person>[];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _openDetails(Person p) async {
    FocusScope.of(context).unfocus();
    final tab = PeopleMemory.tab;
    // Opens with the same right-to-left slide; swipe right to come back.
    final result = await Navigator.of(context).push<Object?>(
      LenzoSwipeRoute<Object?>(
        builder: (_) => PersonDetailScreen(repo: widget.repo, personId: p.id),
      ),
    );
    _refresh();
    _restoreTab(tab);
    // "Update face photo" from their page's Edit: back to the camera.
    if (result == PersonDetailScreen.updatePhoto && mounted) _updatePhoto(p);
  }

  /// Puts the tabs back on [tab] if anything moved them, with no
  /// animation (so the pill doesn't slide).
  void _restoreTab(int tab) {
    PeopleMemory.tab = tab;
    if (!mounted || !_tabs.hasClients) return;
    if ((_tabs.page ?? tab.toDouble()).round() != tab) _tabs.jumpToPage(tab);
  }

  void _updatePhoto(Person p) {
    final cb = widget.onUpdatePhoto;
    if (cb != null) {
      cb(p.id);
    } else {
      Navigator.of(context).pop(p.id);
    }
  }

  /// Asks first; nothing changes unless the user taps Remove.
  Future<void> _remove(Person p) async {
    FocusScope.of(context).unfocus();
    if (!await showRemoveDialog(context, name: p.name)) return;
    if (!mounted) return;
    await _delete(p);
  }

  Future<void> _delete(Person p) async {
    await widget.repo.deletePerson(p.id);
    if (mounted) showLenzoMessage(context, '${p.name} removed from Lenzo');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lenzoSystemUi,
      // Swipe right anywhere to go back to the camera.
      child: LenzoSwipeBack(
        child: LenzoBackdrop(
          style: BackdropStyle.sweep,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              bottom: false,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LenzoSpacing.screen,
                        LenzoSpacing.x1,
                        LenzoSpacing.screen,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Saved People', style: LenzoType.pageHeading),
                          SizedBox(height: LenzoSpacing.x1),
                          Text(
                            'Manage your contacts',
                            style: LenzoType.secondary,
                          ),
                        ],
                      ),
                    ),
                    // Always shown, even with no people or while searching.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LenzoSpacing.screen,
                        LenzoSpacing.section,
                        LenzoSpacing.screen,
                        0,
                      ),
                      child: _summary(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LenzoSpacing.screen,
                        LenzoSpacing.cardGap,
                        LenzoSpacing.screen,
                        0,
                      ),
                      child: LenzoSegmentedControl(
                        controller: _tabs,
                        // The tab chosen last; kept until the app closes.
                        selected: PeopleMemory.tab,
                        labels: [
                          'To Receive (${_count(PeopleTab.receive)})',
                          'To Pay (${_count(PeopleTab.pay)})',
                          'Others (${_count(PeopleTab.others)})',
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LenzoSpacing.screen,
                        LenzoSpacing.cardGap,
                        LenzoSpacing.screen,
                        0,
                      ),
                      child: _searchBar(),
                    ),
                    Expanded(
                      child: FadeEdges(
                        top: _fadeTop,
                        bottom: _fadeBottom,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onTabScroll,
                          child: PageView(
                            // Its own storage slot, separate from the Home
                            // pager's, so neither restores the other's page.
                            key: const PageStorageKey('people-tabs'),
                            controller: _tabs,
                            physics: const PageScrollPhysics(
                              parent: ClampingScrollPhysics(),
                            ),
                            onPageChanged: (i) {
                              setState(() => PeopleMemory.tab = i);
                              FocusScope.of(context).unfocus();
                            },
                            children: [
                              _KeepAlive(child: _list(PeopleTab.receive)),
                              _KeepAlive(child: _list(PeopleTab.pay)),
                              _KeepAlive(child: _list(PeopleTab.others)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What saved contacts still owe me, with what I still owe them as a
  /// chip. Always shown, even with nobody saved (₹0, 0 borrowers).
  Widget _summary() {
    final m = MoneySummary.of(_people ?? const <Person>[]);
    return BalancePairCard(
      receivePaise: m.toReceivePaise,
      payPaise: m.toPayPaise,
    );
  }

  Widget _header() {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Clear of the back button on both sides; shrinks on narrow phones.
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
              tooltip: 'Back to camera',
              onPressed:
                  widget.onBack ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Lenzo.textPrimary,
                size: 28,
              ),
            ),
          ),
          Positioned(
            right: 6,
            child: IconButton(
              tooltip: 'Add a person from a photo',
              onPressed: _addFromGallery,
              icon: const Icon(
                Icons.add_rounded,
                color: Lenzo.textPrimary,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _adding = false;

  /// "+": register someone from a gallery photo.
  Future<void> _addFromGallery() async {
    if (_adding) return;
    _adding = true;
    FocusScope.of(context).unfocus();
    try {
      final message = await addPersonFromGallery(context, widget.repo);
      if (message != null && mounted) showLenzoSuccess(context, message);
    } finally {
      _adding = false;
    }
  }

  /// Search: the same surface, corners and side padding as the To Receive
  /// / To Pay card above it, 48 px tall, no outline. Focus lightens the
  /// fill. The icon is muted grey, the text white.
  Widget _searchBar() {
    return SizedBox(
      height: 48,
      child: TextField(
        expands: true,
        maxLines: null,
        controller: _search,
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        style: LenzoType.input,
        cursorColor: LenzoColors.accent,
        onChanged: (v) => setState(() => _query = PeopleMemory.query = v),
        decoration: lenzoFieldDecoration(hint: 'Search people…').copyWith(
          contentPadding: const EdgeInsets.only(right: LenzoSpacing.x4),
          prefixIconConstraints: const BoxConstraints(minWidth: 48),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(
              left: LenzoSpacing.x4,
              right: LenzoSpacing.x3,
            ),
            child: Icon(
              Icons.search_rounded,
              color: LenzoColors.textSecondary,
              size: 20,
            ),
          ),
          suffixIcon: _query.isEmpty
              ? null
              : LenzoIconButton(
                  tooltip: 'Clear search',
                  icon: Icons.close_rounded,
                  size: 18,
                  color: LenzoColors.textSecondary,
                  onPressed: () => setState(() {
                    _search.clear();
                    _query = PeopleMemory.query = '';
                  }),
                ),
        ),
      ),
    );
  }

  static const _fadeTop = 14.0;
  static const _fadeBottom = 28.0;

  /// Hands a rightward swipe on the first tab, past its edge, to the page
  /// underneath, so Saved People still swipes back to Home from there.
  bool _onTabScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.horizontal) return false;
    if (n is OverscrollNotification &&
        n.dragDetails != null &&
        n.overscroll < 0 &&
        n.metrics.pixels <= n.metrics.minScrollExtent) {
      _edging = true;
      widget.onEdgeDrag?.call(n.overscroll);
    } else if (_edging && n is ScrollUpdateNotification) {
      // Finger moving back left while Home is showing: move Home back
      // first, and keep the tabs where they are.
      final d = n.scrollDelta ?? 0;
      if (d != 0) {
        widget.onEdgeDrag?.call(d);
        _tabs.jumpTo(0);
      }
    } else if (_edging && n is ScrollEndNotification) {
      _edging = false;
      widget.onEdgeRelease?.call(n.dragDetails?.primaryVelocity ?? 0);
    }
    return false;
  }

  int _count(PeopleTab tab) =>
      (_people ?? const <Person>[]).where((p) => p.isIn(tab)).length;

  Widget _list(PeopleTab tab) {
    final all = _people;
    if (all == null) {
      return const Center(
        child: CircularProgressIndicator(color: Lenzo.accent),
      );
    }
    if (all.isEmpty) {
      return _Empty(
        icon: Icons.people_outline_rounded,
        title: 'No people yet',
        text: 'Scan a face to add your first contact.',
        action: 'Open camera',
        onAction: widget.onBack ?? () => Navigator.of(context).maybePop(),
      );
    }
    final people = [
      for (final p in _visible)
        if (p.isIn(tab)) p,
    ];
    final searching = _query.trim().isNotEmpty;
    if (people.isEmpty) {
      return searching
          ? _Empty(
              icon: Icons.search_off_rounded,
              title: 'No matches',
              text: 'No one named "${_query.trim()}" here.',
            )
          : switch (tab) {
              PeopleTab.receive => const _Empty(
                icon: Icons.south_west_rounded,
                title: 'No one owes you',
                text: 'Money you lend shows here until it is repaid.',
              ),
              PeopleTab.pay => const _Empty(
                icon: Icons.north_east_rounded,
                title: "You don't owe anyone",
                text: 'Money you borrow shows here until you repay it.',
              ),
              PeopleTab.others => const _Empty(
                icon: Icons.people_outline_rounded,
                title: 'No one else',
                text:
                    'People with nothing owed either way show here, '
                    'including settled contacts.',
              ),
            };
    }

    final items = <Widget>[
      for (final p in people)
        _PersonCard(
          key: ValueKey('${tab.name}-${p.id}'),
          person: p,
          detail: switch (tab) {
            PeopleTab.receive => (
              'Owes you ${formatRupeesCompact(p.toReceivePaise)}',
              Lenzo.accent,
            ),
            PeopleTab.pay => (
              'You owe ${formatRupeesCompact(p.toPayPaise)}',
              Lenzo.caution,
            ),
            PeopleTab.others => null, // what's saved for them (note, settled…)
          },
          onTap: () => _openDetails(p),
          onRemove: () => _remove(p),
        ),
    ];
    final animate =
        widget.animateEntrance &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return AnimationLimiter(
      child: ListView.separated(
        // Each tab remembers where it was scrolled.
        key: PageStorageKey('people-${tab.name}'),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          LenzoSpacing.screen,
          _fadeTop,
          LenzoSpacing.screen,
          _fadeBottom + 12 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: LenzoSpacing.x2),
        itemBuilder: (context, i) {
          if (!animate) return items[i];
          return AnimationConfiguration.staggeredList(
            position: i,
            duration: const Duration(milliseconds: 380),
            delay: const Duration(milliseconds: 60),
            child: SlideAnimation(
              verticalOffset: 18,
              curve: Lenzo.ease,
              child: FadeInAnimation(child: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    // Sits a little above centre, so it balances with the card above.
    return Align(
      alignment: const Alignment(0, -0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Lenzo.accentMuted, size: 30),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Lenzo.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Lenzo.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: Lenzo.accent,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(action!),
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 240.ms);
  }
}

/// One saved person: photo, name and what's saved for them, with a small
/// Remove action. Editing is on their page.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    super.key,
    required this.person,
    this.detail,
    required this.onTap,
    required this.onRemove,
  });
  final Person person;

  /// The second line, if the tab decides it; otherwise what's saved.
  final (String, Color)? detail;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  /// One short line of what's saved, or null if there's nothing to say.
  static (String, Color)? _detail(Person p) {
    if (p.needsReview) return ('Needs review', _amber);
    if (p.hasMoney) {
      final receive = p.toReceivePaise, pay = p.toPayPaise;
      final parts = [
        if (receive > 0) 'Owes you ${formatRupeesCompact(receive)}',
        if (pay > 0) 'You owe ${formatRupeesCompact(pay)}',
      ];
      if (parts.isEmpty) return ('All settled', Lenzo.accent);
      return (parts.join(' · '), Lenzo.textSecondary);
    }
    if (p.usableSampleCount == 0) return ('Needs a new face photo', _amber);
    final note = p.notes?.trim() ?? '';
    if (note.isNotEmpty) {
      // One line; the full note is on their page.
      return (note.replaceAll(RegExp(r'\s+'), ' '), Lenzo.textSecondary);
    }
    if (p.reminder != null) {
      return ('Reminder ${formatDate(p.reminder!)}', Lenzo.textSecondary);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = person;
    final detail = this.detail ?? _detail(p);
    return LenzoPersonTile(
      onTap: onTap,
      avatar: LenzoAvatar(image: FaceImage(path: p.thumbnailPath)),
      name: p.name,
      subtitle: detail?.$1,
      subtitleColor: detail?.$2,
      actions: [
        LenzoIconButton(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Remove ${p.name}',
          color: LenzoColors.danger,
          onPressed: onRemove,
        ),
      ],
    );
  }
}

/// Keeps a tab page alive (and its scroll position) while off screen.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// What Saved People remembers while the app is open: the selected tab
/// (0 To Receive, 1 To Pay, 2 Others) and the search text. Starts fresh
/// each time the app starts.
abstract final class PeopleMemory {
  static int tab = 0;
  static String query = '';

  /// Back to the defaults (for tests).
  @visibleForTesting
  static void reset() {
    tab = 0;
    query = '';
  }
}
