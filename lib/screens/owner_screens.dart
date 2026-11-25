import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../services/face_repository.dart';
import '../theme/lenzo_theme.dart';
import '../design/design.dart';
import '../widgets/lenzo_ui.dart';
import '../widgets/owner_face_scan.dart';
import '../widgets/swipe_route.dart';

/// [s] trimmed, with runs of spaces made single.
String cleanPersonName(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

/// If the scanned face is already saved as a contact, asks what to do.
/// Returns the contact's id to turn into the owner, 0 to continue without
/// linking, or null to scan again.
Future<int?> resolveOwnerMatch(
  BuildContext context,
  FaceRepository repo,
  OwnerScan scan, {
  required bool updating,
}) async {
  final m = scan.match;
  final id = m.personId;
  if (m.kind != MatchKind.known || id == null || id == repo.ownerId) {
    return 0;
  }
  final name = m.name ?? 'a saved contact';
  final choice = await showLenzoConfirm(
    context,
    icon: Icons.face_outlined,
    title: 'This face is saved as $name',
    message: updating
        ? 'Lenzo may confuse you with $name. Scan again, or use this scan '
              'anyway.'
        : 'Is $name you? Lenzo can make that contact the app owner. Their '
              'saved details stay on this phone.',
    cancel: 'Scan again',
    confirm: updating ? 'Use anyway' : "Yes, that's me",
  );
  if (!choice) return null;
  return updating ? 0 : id;
}

Widget _page({required Widget child, Widget? header}) {
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: lenzoSystemUi,
    child: LenzoBackdrop(
      style: BackdropStyle.plain,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              header ??
                  const SizedBox(
                    height: _headerHeight,
                    child: Center(child: LenzoBrandLogo(height: 28)),
                  ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Height of the top bar on Settings and Update Face Scan (the same as
/// Saved People).
const _headerHeight = 56.0;

/// Top bar: back button (28 px icon, 48 px touch area) on the left and the
/// logo centred on the screen, as on Saved People.
class _BackHeader extends StatelessWidget {
  const _BackHeader({this.onBack, this.tooltip = 'Back'});
  final VoidCallback? onBack;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _headerHeight,
      width: double.infinity,
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
              tooltip: tooltip,
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Lenzo.textPrimary,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page heading and its one-line explanation: 24 px heading, 4 px gap,
/// 14 px secondary text. [centered] for focused tasks (face scan); pages
/// in the main navigation (Settings) align left, like Saved People.
class _Title extends StatelessWidget {
  const _Title(this.title, this.subtitle, {this.centered = true});
  final String title;
  final String subtitle;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final align = centered ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, textAlign: align, style: LenzoType.pageHeading),
        ),
        const SizedBox(height: LenzoSpacing.x1),
        Text(
          subtitle,
          textAlign: align,
          style: LenzoType.body.copyWith(color: LenzoColors.textSecondary),
        ),
      ],
    );
  }
}

/// Padding of the content under the header on both screens.
const _contentPadding = EdgeInsets.fromLTRB(
  LenzoSpacing.screen,
  LenzoSpacing.x2,
  LenzoSpacing.screen,
  LenzoSpacing.x6,
);

/// Scan circle size: fits narrow phones and leaves room for the buttons.
double _scanSize(BoxConstraints c) =>
    math.min(c.maxWidth * 0.62, c.maxHeight * 0.4).clamp(170.0, 280.0);

// ---------------------------------------------------------------------------
// Update the owner's face
// ---------------------------------------------------------------------------

/// Scans the owner's face again and replaces the saved one. Pops true once
/// saved.
class OwnerFaceUpdateScreen extends StatefulWidget {
  const OwnerFaceUpdateScreen({super.key, required this.repo});
  final FaceRepository repo;

  /// Shown after a capture: the name is already saved, so only Save is
  /// asked for.
  static const capturedMessage =
      'Face captured successfully. Save to update your face scan.';

  @override
  State<OwnerFaceUpdateScreen> createState() => _OwnerFaceUpdateScreenState();
}

class _OwnerFaceUpdateScreenState extends State<OwnerFaceUpdateScreen> {
  OwnerScan? _scan;
  bool _saving = false;

  Future<void> _save() async {
    final scan = _scan;
    if (scan == null || _saving) return;
    final ok = await resolveOwnerMatch(
      context,
      widget.repo,
      scan,
      updating: true,
    );
    if (!mounted) return;
    if (ok == null) {
      setState(() => _scan = null);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repo.updateOwnerFace(
        faces: scan.faces,
        portraitJpeg: scan.portrait,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showLenzoMessage(context, 'Couldn\'t update your face: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanned = _scan != null;
    return LenzoSwipeBack(
      child: _page(
        header: const _BackHeader(),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: _contentPadding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(
                  0,
                  constraints.maxHeight - _contentPadding.vertical,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Title(
                        'Update your face scan',
                        'Look straight at the camera in good light.',
                      ),
                      const SizedBox(height: LenzoSpacing.section),
                      Center(
                        child: OwnerFaceScan(
                          repo: widget.repo,
                          size: _scanSize(constraints),
                          scan: _scan,
                          capturedMessage:
                              OwnerFaceUpdateScreen.capturedMessage,
                          onCaptured: (s) => setState(() => _scan = s),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: LenzoSpacing.section),
                  AnimatedOpacity(
                    duration: LenzoMotion.of(context, LenzoMotion.tab),
                    curve: LenzoMotion.ease,
                    opacity: scanned ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !scanned,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LenzoButton(
                            label: 'Save Face Scan',
                            icon: Icons.check_rounded,
                            busy: _saving,
                            onPressed: _save,
                          ),
                          const SizedBox(height: LenzoSpacing.x3),
                          LenzoButton(
                            label: 'Scan again',
                            icon: Icons.refresh_rounded,
                            kind: LenzoButtonKind.outlineAccent,
                            onPressed: _saving
                                ? null
                                : () => setState(() => _scan = null),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings (with the owner's profile)
// ---------------------------------------------------------------------------

/// Settings: the owner's photo and name, and Profile Settings to change the
/// name or update the face scan. Opened from the home screen's settings
/// icon or by swiping right on Home; [onBack] returns to Home when it is a
/// page beside Home rather than a pushed route.
class OwnerProfileScreen extends StatefulWidget {
  const OwnerProfileScreen({super.key, required this.repo, this.onBack});
  final FaceRepository repo;
  final VoidCallback? onBack;

  @override
  State<OwnerProfileScreen> createState() => _OwnerProfileScreenState();
}

class _OwnerProfileScreenState extends State<OwnerProfileScreen> {
  Person? _owner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.repo.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.repo.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await widget.repo.getOwner();
    if (mounted) {
      setState(() {
        _owner = p;
        _loaded = true;
      });
    }
  }

  Future<void> _rename() async {
    final p = _owner;
    if (p == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: p.name),
    );
    if (name == null || name == p.name || !mounted) return;
    await widget.repo.renamePerson(p.id, name);
    await _load();
    if (mounted) showLenzoSuccess(context, 'Your name is now $name');
  }

  Future<void> _rescan() async {
    final saved = await Navigator.of(context).push<bool>(
      LenzoSwipeRoute<bool>(
        builder: (_) => OwnerFaceUpdateScreen(repo: widget.repo),
      ),
    );
    if (saved != true || !mounted) return;
    await _load();
    if (mounted) showLenzoSuccess(context, 'Your face scan is updated');
  }

  @override
  Widget build(BuildContext context) {
    final p = _owner;
    final page = _page(
      header: _BackHeader(
        onBack: widget.onBack,
        tooltip: widget.onBack == null ? 'Back' : 'Back to camera',
      ),
      child: !_loaded
          ? const Center(child: CircularProgressIndicator(color: Lenzo.accent))
          : SingleChildScrollView(
              padding: _contentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Title(
                    'Settings',
                    'Manage your profile',
                    centered: false,
                  ),
                  if (p != null) ...[
                    const SizedBox(height: LenzoSpacing.section),
                    Center(
                      child: RingPortrait(
                        size: 104,
                        image: FaceImage(path: p.thumbnailPath),
                      ),
                    ),
                    const SizedBox(height: LenzoSpacing.x3),
                    Text(
                      p.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LenzoType.sectionHeading,
                    ),
                    const SizedBox(height: LenzoSpacing.section),
                    const Padding(
                      padding: EdgeInsets.only(
                        left: LenzoSpacing.x1,
                        bottom: LenzoSpacing.x2,
                      ),
                      child: Text('Profile Settings', style: LenzoType.label),
                    ),
                    _row(
                      icon: Icons.person_outline_rounded,
                      title: 'Name',
                      action: 'Change',
                      onTap: _rename,
                    ),
                    _row(
                      icon: Icons.face_retouching_natural_outlined,
                      title: 'Face Scan',
                      action: 'Update',
                      onTap: _rescan,
                    ),
                    const SizedBox(height: LenzoSpacing.x3),
                    const Text(
                      'Your face and name stay on this phone.',
                      textAlign: TextAlign.center,
                      style: LenzoType.secondary,
                    ),
                  ],
                ],
              ),
            ),
    );
    // As a pushed page it swipes back; as a page beside Home the page view
    // handles the swipe.
    return widget.onBack == null ? LenzoSwipeBack(child: page) : page;
  }

  /// A Profile Settings card: icon, title (and an optional value under it),
  /// and the action on the right. Always 64 px tall, so cards with and
  /// without a second line match.
  Widget _row({
    required IconData icon,
    required String title,
    String? subtitle,
    required String action,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LenzoSpacing.x2),
      child: LenzoCard(
        small: true,
        shadow: false,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(
          LenzoSpacing.x4,
          LenzoSpacing.x3,
          LenzoSpacing.x2,
          LenzoSpacing.x3,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Icon(icon, size: 20, color: LenzoColors.textSecondary),
              const SizedBox(width: LenzoSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: LenzoType.cardHeading),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LenzoType.secondary,
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                action,
                style: LenzoType.button.copyWith(
                  fontSize: 13,
                  color: LenzoColors.accent,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: LenzoColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = cleanPersonName(_ctrl.text);
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Lenzo.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Lenzo.accent.withValues(alpha: 0.3)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Change your name',
                style: TextStyle(
                  color: Lenzo.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                autofocus: true,
                maxLength: 40,
                buildCounter: (
                  _, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: Lenzo.textPrimary, fontSize: 16),
                cursorColor: Lenzo.accent,
                decoration: lenzoInput(
                  hint: 'Your name',
                  dense: true,
                  raised: true,
                  error: _error,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              EditorActions(
                saving: false,
                onCancel: () => Navigator.of(context).pop(),
                onSave: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
