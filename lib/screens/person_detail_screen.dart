import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../services/face_repository.dart';
import '../theme/lenzo_theme.dart';
import '../utils/format.dart';
import '../widgets/lenzo_calendar.dart';
import '../design/design.dart';
import '../widgets/edit_contact_dialog.dart';
import '../widgets/lenzo_ui.dart';
import '../widgets/swipe_route.dart';

/// Which row on the page is open for editing.
enum _Editing { none, lent, repaid, borrowed, paidBack, notes, reminder }

/// The money rows. Each is its own account of entries; the two directions
/// (lent to them / borrowed from them) are never combined.
extension on _Editing {
  MoneyKind? get kind => switch (this) {
    _Editing.lent => MoneyKind.lent,
    _Editing.repaid => MoneyKind.repaid,
    _Editing.borrowed => MoneyKind.borrowed,
    _Editing.paidBack => MoneyKind.paidBack,
    _ => null,
  };

  int total(Person p) => switch (this) {
    _Editing.lent => p.lentPaise,
    _Editing.repaid => p.repaidPaise,
    _Editing.borrowed => p.borrowedPaise,
    _Editing.paidBack => p.paidBackPaise,
    _ => 0,
  };

  String get title => kind?.label ?? '';

  /// What is still open on this account: To Receive for Money Lent, To Pay
  /// for Money Borrowed (each reduced only by its own repayments).
  int balance(Person p) => switch (this) {
    _Editing.lent => p.toReceivePaise,
    _Editing.borrowed => p.toPayPaise,
    _ => total(p),
  };

  /// The kind a "Less" on this account is saved as: a repayment of it.
  /// Saving Less this way keeps every earlier record and calculation as
  /// it was.
  MoneyKind? get lessKind => switch (this) {
    _Editing.lent => MoneyKind.repaid,
    _Editing.borrowed => MoneyKind.paidBack,
    _ => null,
  };
}

/// Full-screen page for a recognized person: photo, name, money given and
/// returned, notes and a payment reminder. Every value can be edited in
/// place and is saved to the person's record straight away.
class PersonDetailScreen extends StatefulWidget {
  const PersonDetailScreen({
    super.key,
    required this.repo,
    required this.personId,
    this.scanPortrait,
  });

  final FaceRepository repo;
  final int personId;

  /// Returned when the user chose "Update face photo": the camera should
  /// scan this person's face again.
  static const updatePhoto = 'update-photo';

  /// Photo from the current scan. Used as the profile photo if the person
  /// doesn't have one yet.
  final Uint8List? scanPortrait;

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen>
    with WidgetsBindingObserver {
  Person? _person;

  /// The person's money records, newest first.
  List<MoneyEntry> _entries = const [];
  bool _missing = false;
  bool _saving = false;
  _Editing _editing = _Editing.none;

  /// Less (true) or Add (false) on the open money row; Add when it opens.
  bool _less = false;

  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _amountFocus = FocusNode();
  final _notesFocus = FocusNode();
  final _scroll = ScrollController();
  final _rowKeys = {for (final r in _Editing.values) r: GlobalKey()};

  /// Heights of the soft fades under the header and at the bottom edge.
  static const _fadeTop = 18.0;
  static const _fadeBottom = 28.0;

  /// Keyboard height last seen, to notice when it opens or grows.
  double _keyboard = 0;
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(firstLoad: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revealTimer?.cancel();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _amountFocus.dispose();
    _notesFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The keyboard opened or changed height: once it settles, scroll so the
  /// open card (input, total, Cancel and Save) sits above it.
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final keyboard = View.of(context).viewInsets.bottom;
    final grew = keyboard > _keyboard;
    _keyboard = keyboard;
    if (grew && _editing != _Editing.none) _scheduleReveal();
  }

  void _scheduleReveal([Duration delay = const Duration(milliseconds: 90)]) {
    _revealTimer?.cancel();
    _revealTimer = Timer(delay, _revealOpenRow);
  }

  /// Smoothly scrolls the least distance that shows the whole open card,
  /// with a small margin. If the card is taller than the visible area, its
  /// bottom (the buttons) is shown.
  void _revealOpenRow() {
    if (!mounted || !_scroll.hasClients) return;
    final box = _rowKeys[_editing]?.currentContext?.findRenderObject();
    if (box == null || !box.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    // Keep the card clear of the faded edges.
    final showTop = viewport.getOffsetToReveal(box, 0).offset - _fadeTop - 6;
    final showBottom =
        viewport.getOffsetToReveal(box, 1).offset + _fadeBottom + 6;
    final current = _scroll.offset;
    final target = showBottom > showTop
        ? showBottom
        : current.clamp(showBottom, showTop);
    final pos = _scroll.position;
    final clamped = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((clamped - current).abs() < 1) return;
    _scroll.animateTo(
      clamped,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _load({bool firstLoad = false}) async {
    if (firstLoad && widget.scanPortrait != null) {
      await widget.repo.setPhoto(
        widget.personId,
        widget.scanPortrait!,
        onlyIfMissing: true,
      );
    }
    final p = await widget.repo.getPerson(widget.personId);
    final entries = p == null
        ? const <MoneyEntry>[]
        : await widget.repo.getEntries(widget.personId);
    if (!mounted) return;
    setState(() {
      _person = p;
      _entries = entries;
      _missing = p == null;
    });
  }

  // ---- Editing ----

  /// The header's Edit: rename, or go back to the camera to scan their
  /// face again (returns [PersonDetailScreen.updatePhoto]).
  Future<void> _edit() async {
    final p = _person;
    if (p == null) return;
    final photo = await editContact(context, widget.repo, p);
    if (!mounted) return;
    if (photo) {
      Navigator.of(context).pop(PersonDetailScreen.updatePhoto);
    } else {
      await _load();
    }
  }

  void _open(_Editing row) {
    final p = _person;
    if (p == null || _saving) return;
    if (_editing == row) {
      _close();
      return;
    }
    setState(() {
      _editing = row;
      _less = false;
      switch (row) {
        case _Editing.lent:
        case _Editing.repaid:
        case _Editing.borrowed:
        case _Editing.paidBack:
          _amountCtrl.clear();
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _amountFocus.requestFocus(),
          );
        case _Editing.notes:
          _notesCtrl.text = p.notes ?? '';
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _notesFocus.requestFocus(),
          );
        case _Editing.reminder:
        case _Editing.none:
          FocusScope.of(context).unfocus();
      }
    });
    // After the card finishes expanding. If the keyboard opens, it
    // reveals again once the keyboard settles.
    _scheduleReveal(const Duration(milliseconds: 280));
  }

  void _close() {
    FocusScope.of(context).unfocus();
    setState(() => _editing = _Editing.none);
  }

  /// The open money row's balance after the entered amount is added or
  /// taken off, or null if the input is invalid, too large, or (for Less)
  /// more than is still open.
  int? _newTotal() {
    final p = _person!;
    final entered = parsePaise(_amountCtrl.text);
    if (entered == null) return null;
    final current = _editing.balance(p);
    final total = _less ? current - entered : current + entered;
    return total < 0 || total > kMaxPaise ? null : total;
  }

  /// Why [_newTotal] is null, for the line under the amount.
  String _totalProblem() {
    final p = _person!;
    final entered = parsePaise(_amountCtrl.text);
    final current = _editing.balance(p);
    if (_less && entered != null && entered > current) {
      return current == 0
          ? 'Nothing is outstanding to reduce.'
          : "That's more than the ${formatRupees(current)} outstanding.";
    }
    return 'That amount is too large.';
  }

  Future<void> _run(
    Future<void> Function() save,
    String message, {
    bool close = true,
  }) async {
    setState(() => _saving = true);
    try {
      await save();
      await _load();
      if (!mounted) return;
      if (close) {
        FocusScope.of(context).unfocus();
        setState(() => _editing = _Editing.none);
      }
      showLenzoSuccess(context, message);
    } catch (e) {
      if (mounted) showLenzoMessage(context, 'Couldn\'t save changes: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAmount() async {
    final p = _person;
    final row = _editing;
    final kind = _less ? row.lessKind : row.kind;
    final entered = parsePaise(_amountCtrl.text);
    if (p == null || kind == null) return;
    if (entered == null || entered == 0) {
      showLenzoMessage(context, 'Enter an amount.');
      return;
    }
    if (_newTotal() == null) {
      showLenzoMessage(context, _totalProblem());
      return;
    }
    await _run(
      () => widget.repo.addEntry(widget.personId, kind, entered),
      _less
          ? 'Reduced ${row.title} by ${formatRupees(entered)}'
          : 'Added ${formatRupees(entered)} to ${row.title}',
    );
  }

  Future<void> _deleteEntry(MoneyEntry e) async {
    final ok = await showLenzoConfirm(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Remove this entry?',
      message:
          '${formatRupees(e.amountPaise)} from ${e.kind.label} will be '
          'removed and the balances updated.',
      confirm: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
      () => widget.repo.deleteEntry(e.id),
      'Entry removed',
      close: false,
    );
  }

  /// Re-files every [from] record as [to], after the user confirms. Only
  /// offered when [from] has nothing to repay (its account is empty).
  Future<void> _move(MoneyKind from, MoneyKind to, int amount) async {
    final ok = await showLenzoConfirm(
      context,
      icon: Icons.swap_horiz_rounded,
      title: 'Move to ${to.label}?',
      message:
          '${formatRupees(amount)} is saved as ${from.label}, but nothing '
          'was recorded under ${from.repays!.label}. Move it to ${to.label} '
          'if that is what it was.',
      confirm: 'Move',
    );
    if (!ok || !mounted) return;
    await _run(
      () => widget.repo.moveEntries(widget.personId, from, to),
      'Moved to ${to.label}',
    );
  }

  Future<void> _saveNotes() async {
    final text = _notesCtrl.text.trim();
    await _run(
      () => widget.repo.updateDetails(
        widget.personId,
        notes: text.isEmpty ? null : text,
        clearNotes: text.isEmpty,
      ),
      text.isEmpty ? 'Note removed' : 'Note saved',
    );
  }

  Future<void> _saveReminder(DateTime date) => _run(
    () => widget.repo.updateDetails(widget.personId, reminder: date),
    'Reminder set for ${formatDate(date)}',
  );

  Future<void> _clearReminder() => _run(
    () => widget.repo.updateDetails(widget.personId, clearReminder: true),
    'Reminder removed',
  );

  /// Offers to use the photo from this scan as the profile photo.
  Future<void> _offerNewPhoto() async {
    final scan = widget.scanPortrait;
    if (scan == null || _saving) return;
    final ok = await showLenzoConfirm(
      context,
      image: FaceImage(bytes: scan),
      title: 'Update profile photo?',
      message: 'Use the photo from this scan.',
      cancel: 'Keep current',
      confirm: 'Use this photo',
    );
    if (!ok || !mounted) return;
    await _run(
      () => widget.repo.setPhoto(widget.personId, scan),
      'Profile photo updated',
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lenzoSystemUi,
      // Swipe right to go back, unless a card is open (its inputs and the
      // calendar use horizontal swipes themselves).
      child: LenzoSwipeBack(
        enabled: _editing == _Editing.none,
        child: LenzoBackdrop(
          style: BackdropStyle.waves,
          child: PopScope(
            canPop: _editing == _Editing.none,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _close();
            },
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: Column(
                  children: [
                    _Header(
                      onBack: () => Navigator.of(context).maybePop(),
                      onEdit: _person == null ? null : _edit,
                    ),
                    Expanded(
                      child: FadeEdges(
                        top: _fadeTop,
                        bottom: _fadeBottom,
                        child: _body(),
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

  Widget _body() {
    if (_missing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'This contact is no longer saved in Lenzo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Lenzo.textSecondary, fontSize: 16),
          ),
        ),
      );
    }
    final p = _person;
    if (p == null) {
      return const Center(
        child: CircularProgressIndicator(color: Lenzo.accent),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scroll,
          // The page stays scrollable while the keyboard is open; scrolling
          // doesn't close the keyboard.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          // At rest the photo sits fully below the faded top edge, and the
          // last card fully above the faded bottom edge.
          padding: const EdgeInsets.fromLTRB(
            LenzoSpacing.screen,
            _fadeTop + 4,
            LenzoSpacing.screen,
            _fadeBottom + 12,
          ),
          child: Column(
            // Photo, name and cards rise and fade in one after another once
            // the person loads. Rebuilds (editing, saving) don't replay it.
            children:
                <Widget>[
                      _profileHeader(p),
                      const SizedBox(height: LenzoSpacing.section),
                      if (p.hasMoney) ...[
                        _balances(p),
                        const SizedBox(height: LenzoSpacing.cardGap),
                      ],
                      // Two accounts, each showing what is still open. Add and
                      // Less (repayments) both happen inside them.
                      _moneyRow(p, _Editing.lent, Icons.south_west_rounded),
                      _moneyRow(p, _Editing.borrowed, Icons.north_east_rounded),
                      _row(
                        row: _Editing.notes,
                        icon: Icons.sticky_note_2_outlined,
                        title: 'Personal Notes',
                        subtitle: p.notes ?? 'Add a private note',
                        subtitleMuted: p.notes == null,
                        editor: _notesEditor(),
                      ),
                      _row(
                        row: _Editing.reminder,
                        icon: Icons.calendar_month_outlined,
                        title: 'Payment Reminder',
                        subtitle: _editing == _Editing.reminder
                            ? 'Choose a reminder date'
                            : p.reminder == null
                            ? 'No reminder set'
                            : '${formatDate(p.reminder!)} · '
                                  '${reminderStatus(p.reminder!)}',
                        subtitleMuted:
                            p.reminder == null || _editing == _Editing.reminder,
                        subtitleColor:
                            _editing != _Editing.reminder &&
                                p.reminder != null &&
                                p.reminder!.isBefore(today())
                            ? Lenzo.warning
                            : null,
                        editor: _reminderEditor(p),
                      ),
                    ]
                    .animate(interval: 40.ms)
                    .fadeIn(duration: 320.ms, curve: Curves.easeOut)
                    .slideY(
                      begin: 0.05,
                      end: 0,
                      duration: 380.ms,
                      curve: Curves.easeOutCubic,
                    ),
          ),
        );
      },
    );
  }

  /// The person's balance as the page's key figure, with what makes it up.
  /// The open balance in each direction, side by side and never combined,
  /// plus a notice when a repayment is larger than what it repays.
  Widget _balances(Person p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p.needsReview) ...[
          _reviewNotice(p),
          const SizedBox(height: LenzoSpacing.cardGap),
        ],
        LenzoFinancialCard(
          note: p.isSettled ? 'All settled' : null,
          figures: [
            LenzoFigure(
              'To Receive',
              p.toReceivePaise,
              color: LenzoColors.accent,
            ),
            LenzoFigure('To Pay', p.toPayPaise, color: LenzoColors.payable),
          ],
        ),
      ],
    );
  }

  /// Photo (tap to use this scan's photo), name and a small verified mark.
  Widget _profileHeader(Person p) {
    return Row(
      children: [
        GestureDetector(
          onTap: widget.scanPortrait == null ? null : _offerNewPhoto,
          child: LenzoAvatar(size: 72, image: FaceImage(path: p.thumbnailPath)),
        ),
        const SizedBox(width: LenzoSpacing.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LenzoType.profileName,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: LenzoColors.accent.withValues(alpha: 0.1),
                  borderRadius: LenzoRadius.pillAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: LenzoColors.accent,
                    ),
                    const SizedBox(width: 6),
                    // Shrinks with large text rather than overflowing.
                    Flexible(
                      child: Text(
                        'Verified Contact',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LenzoType.label.copyWith(
                          color: LenzoColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Explains which records disagree, with a way to fix each one.
  Widget _reviewNotice(Person p) {
    final lines = <(String, Widget?)>[
      if (p.overRepaidPaise > 0)
        (
          'Reductions (${formatRupees(p.repaidPaise)}) are more than Money '
              'Lent (${formatRupees(p.lentPaise)}).',
          p.lentPaise == 0
              ? _noticeAction(
                  'Move to Money Borrowed',
                  () => _move(
                    MoneyKind.repaid,
                    MoneyKind.borrowed,
                    p.repaidPaise,
                  ),
                )
              : _noticeAction('Review history', () => _open(_Editing.lent)),
        ),
      if (p.overPaidBackPaise > 0)
        (
          'Reductions (${formatRupees(p.paidBackPaise)}) are more than Money '
              'Borrowed (${formatRupees(p.borrowedPaise)}).',
          p.borrowedPaise == 0
              ? _noticeAction(
                  'Move to Money Lent',
                  () => _move(
                    MoneyKind.paidBack,
                    MoneyKind.lent,
                    p.paidBackPaise,
                  ),
                )
              : _noticeAction('Review history', () => _open(_Editing.borrowed)),
        ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Lenzo.caution.withValues(alpha: 0.08),
          Lenzo.surface,
        ),
        borderRadius: BorderRadius.circular(Lenzo.rCard),
        border: Border.all(color: Lenzo.caution.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Lenzo.caution, size: 18),
              SizedBox(width: Lenzo.s8),
              Flexible(
                child: Text(
                  'Needs review',
                  style: TextStyle(
                    color: Lenzo.caution,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          for (final (text, action) in lines) ...[
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                color: Lenzo.textPrimary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            ?action,
          ],
        ],
      ),
    );
  }

  Widget _noticeAction(String label, VoidCallback onTap) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: _saving ? null : onTap,
      style: TextButton.styleFrom(
        foregroundColor: Lenzo.accent,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, Lenzo.tap),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    ),
  );

  Widget _moneyRow(Person p, _Editing row, IconData icon) => _row(
    row: row,
    icon: icon,
    title: row.title,
    amount: row.balance(p),
    editor: _amountEditor(row.balance(p), row: row),
  );

  Widget _row({
    required _Editing row,
    required IconData icon,
    required String title,
    int? amount,
    String? subtitle,
    bool subtitleMuted = false,
    Color? subtitleColor,
    VoidCallback? onTap,
    required Widget editor,
  }) {
    final open = _editing == row;
    return Padding(
      padding: const EdgeInsets.only(bottom: LenzoSpacing.x2),
      child: AnimatedContainer(
        key: _rowKeys[row],
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: lenzoPanel(highlighted: open),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              InkWell(
                borderRadius: LenzoRadius.cardSmallAll,
                onTap: _saving ? null : (onTap ?? () => _open(row)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      LenzoSpacing.x4,
                      LenzoSpacing.x3,
                      LenzoSpacing.x2,
                      LenzoSpacing.x3,
                    ),
                    child: Row(
                      children: [
                        // [icon] [label] [amount] [chevron]
                        SizedBox.square(
                          dimension: 24,
                          child: Icon(
                            icon,
                            size: 20,
                            color: LenzoColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: LenzoSpacing.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // One line: shrinks slightly rather than wrap.
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: LenzoType.cardHeading,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: open ? 1 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: LenzoType.secondary.copyWith(
                                    color: subtitleColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (amount != null) ...[
                          const SizedBox(width: LenzoSpacing.x3),
                          // Compact (₹49.6K), so it never pushes the label.
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              // New totals cross-fade in after a save.
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                transitionBuilder: (child, a) => FadeTransition(
                                  opacity: a,
                                  child: SlideTransition(
                                    position: Tween(
                                      begin: const Offset(0, 0.25),
                                      end: Offset.zero,
                                    ).animate(a),
                                    child: child,
                                  ),
                                ),
                                child: Text(
                                  formatRupeesCompact(amount),
                                  key: ValueKey(amount),
                                  style: LenzoType.amount(15),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: LenzoSpacing.x1),
                        AnimatedRotation(
                          turns: open ? 0.25 : 0,
                          duration: LenzoMotion.of(context, LenzoMotion.tab),
                          curve: LenzoMotion.ease,
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: LenzoColors.textTertiary,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: LenzoMotion.of(context, LenzoMotion.expand),
                curve: LenzoMotion.ease,
                alignment: Alignment.topCenter,
                child: open
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        // Content fades in as the card grows (250 ms).
                        child: editor.animate().fadeIn(
                          duration: 220.ms,
                          delay: 30.ms,
                          curve: Curves.easeOut,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountEditor(int current, {required _Editing row}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: Color(0x1FA6BDAE)),
        const SizedBox(height: 12),
        AddLessToggle(
          less: _less,
          onChanged: _saving
              ? null
              : (less) {
                  HapticFeedback.selectionClick();
                  setState(() => _less = less);
                },
        ),
        const SizedBox(height: 12),
        const Text(
          'Enter amount',
          style: TextStyle(color: Lenzo.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _amountCtrl,
          focusNode: _amountFocus,
          // The phone's own number pad, with a decimal point.
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [MoneyInputFormatter()],
          style: const TextStyle(color: Lenzo.textPrimary, fontSize: 16),
          cursorColor: Lenzo.accent,
          // When the field gets focus, keep the total and buttons below it
          // in view as well, not just the field.
          scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
          decoration: lenzoInput(
            hint: '0',
            dense: true,
            raised: true,
            prefix: const Padding(
              padding: EdgeInsets.only(left: 14, right: 6),
              child: Text(
                '₹',
                style: TextStyle(color: Lenzo.textSecondary, fontSize: 16),
              ),
            ),
          ),
          onTap: () => _scheduleReveal(const Duration(milliseconds: 350)),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _saveAmount(),
        ),
        const SizedBox(height: 6),
        Builder(
          builder: (_) {
            final total = _newTotal();
            if (total == null) {
              return Text(
                _totalProblem(),
                style: const TextStyle(color: Lenzo.danger, fontSize: 12.5),
              );
            }
            return Text.rich(
              TextSpan(
                text: 'New total: ',
                children: [
                  TextSpan(
                    text: formatRupees(total),
                    style: const TextStyle(
                      color: Lenzo.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(color: Lenzo.textSecondary, fontSize: 13),
            );
          },
        ),
        const SizedBox(height: 10),
        EditorActions(saving: _saving, onCancel: _close, onSave: _saveAmount),
        ..._history(row),
      ],
    );
  }

  /// The account's history, newest first: date, +/− amount, Added or
  /// Reduced, and the balance it left. Each entry can be removed.
  List<Widget> _history(_Editing row) {
    final account = row.kind;
    if (account == null) return const [];
    final lines = ledgerOf(_entries, account);
    if (lines.isEmpty) return const [];
    return [
      const SizedBox(height: Lenzo.s16),
      const Text('History', style: Lenzo.caption),
      const SizedBox(height: 4),
      for (final l in lines)
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l.entry.legacy ? 'Earlier total' : formatDate(l.entry.at)}'
                    ' · ${l.added ? 'Added' : 'Reduced'}',
                    style: const TextStyle(
                      color: Lenzo.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Balance ${formatRupees(l.balancePaise)}',
                    style: const TextStyle(
                      color: Lenzo.textSecondary,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${l.added ? '+' : '−'}${formatRupees(l.entry.amountPaise)}',
              style: TextStyle(
                color: l.added ? Lenzo.textPrimary : LenzoColors.accent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            IconButton(
              tooltip: 'Remove entry',
              onPressed: _saving ? null : () => _deleteEntry(l.entry),
              icon: const Icon(Icons.close_rounded, size: 18),
              color: Lenzo.textSecondary,
              style: IconButton.styleFrom(
                minimumSize: const Size(Lenzo.tap, Lenzo.tap),
              ),
            ),
          ],
        ),
    ];
  }

  Widget _notesEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: Color(0x1FA6BDAE)),
        const SizedBox(height: 14),
        TextField(
          controller: _notesCtrl,
          focusNode: _notesFocus,
          minLines: 3,
          maxLines: 6,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: Lenzo.textPrimary, fontSize: 16),
          cursorColor: Lenzo.accent,
          decoration: lenzoInput(
            hint: 'e.g. For the laptop payment',
            raised: true,
          ),
        ),
        const SizedBox(height: 8),
        EditorActions(saving: _saving, onCancel: _close, onSave: _saveNotes),
      ],
    );
  }

  Widget _reminderEditor(Person p) {
    final start = today();
    final current = p.reminder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: Color(0x1FA6BDAE)),
        const SizedBox(height: 12),
        LenzoCalendar(
          initialDate: current ?? start.add(const Duration(days: 7)),
          // An overdue reminder stays selectable so it can be kept.
          firstDate: current != null && current.isBefore(start)
              ? current
              : start,
          lastDate: DateTime(start.year + 10, 12, 31),
          saving: _saving,
          onCancel: _close,
          onSave: _saveReminder,
          onRemove: current == null ? null : _clearReminder,
        ),
      ],
    );
  }
}

/// Top bar: back arrow and a centred wordmark.
class _Header extends StatelessWidget {
  const _Header({required this.onBack, this.onEdit});
  final VoidCallback onBack;

  /// Edit this contact (name, face photo); hidden while loading.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
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
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Lenzo.textPrimary,
                size: 28,
              ),
            ),
          ),
          if (onEdit != null)
            Positioned(
              right: 6,
              child: IconButton(
                tooltip: 'Edit contact',
                onPressed: onEdit,
                icon: const Icon(
                  Icons.edit_outlined,
                  color: Lenzo.textPrimary,
                  size: 24,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Add | Less: two pills in the style of Lenzo's tabs. The selected one is
/// mint with dark text, the other dark with muted text; the mint pill
/// slides between them in 180 ms.
class AddLessToggle extends StatelessWidget {
  const AddLessToggle({super.key, required this.less, required this.onChanged});
  final bool less;
  final ValueChanged<bool>? onChanged;

  static const duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final d = LenzoMotion.of(context, duration);
    Widget option(String label, IconData icon, bool value) {
      final on = less == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onChanged == null ? null : () => onChanged!(value),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: d,
                curve: LenzoMotion.ease,
                style: LenzoType.button.copyWith(
                  fontSize: 13,
                  color: on ? LenzoColors.onAccent : LenzoColors.textSecondary,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<Color?>(
                      tween: ColorTween(
                        end: on
                            ? LenzoColors.onAccent
                            : LenzoColors.textSecondary,
                      ),
                      duration: d,
                      builder: (_, c, _) => Icon(icon, size: 16, color: c),
                    ),
                    const SizedBox(width: 6),
                    Text(label),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: LenzoColors.fieldRaised,
        borderRadius: LenzoRadius.pillAll,
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: d,
            curve: LenzoMotion.ease,
            alignment: less ? Alignment.centerRight : Alignment.centerLeft,
            child: const FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: LenzoColors.accent,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
              ),
            ),
          ),
          Row(
            children: [
              option('Add', Icons.add_rounded, false),
              option('Less', Icons.remove_rounded, true),
            ],
          ),
        ],
      ),
    );
  }
}
