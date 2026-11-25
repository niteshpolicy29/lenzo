import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../design/design.dart';
import '../theme/lenzo_theme.dart';
import '../services/face_repository.dart';
import '../services/onboarding_store.dart';
import '../widgets/lenzo_ui.dart';
import '../widgets/owner_face_scan.dart';
import 'owner_screens.dart';

// ---------------------------------------------------------------------------
// Flow
// ---------------------------------------------------------------------------

/// First-run onboarding: Welcome → face setup → tutorial. Progress is saved
/// after each step, so a restart continues where the user left off. Calls
/// [onFinished] with the owner's name when the tutorial is done.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.repo,
    required this.store,
    required this.initialStep,
    required this.initialProgress,
    required this.onFinished,
  });

  final FaceRepository repo;
  final OnboardingStore store;
  final OnboardingStep initialStep;
  final OnboardingProgress initialProgress;
  final ValueChanged<String?> onFinished;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late OnboardingStep _step = widget.initialStep;
  late OnboardingProgress _progress = widget.initialProgress;

  /// Saves [p]. A failed write only means the step may be shown again
  /// after a restart, so the user is not blocked.
  Future<void> _save(OnboardingProgress p) async {
    _progress = p;
    try {
      await widget.store.save(p);
    } catch (e) {
      debugPrint('Could not save onboarding progress: $e');
    }
  }

  Future<void> _start() async {
    await _save(_progress.copyWith(welcomeDone: true));
    if (mounted) setState(() => _step = OnboardingStep.faceSetup);
  }

  /// Called only after the owner is saved in the database.
  void _enrolled() => setState(() => _step = OnboardingStep.tutorial);

  Future<void> _finish() async {
    await _save(_progress.copyWith(tutorialDone: true));
    final id = widget.repo.ownerId;
    widget.onFinished(id == null ? null : widget.repo.nameOf(id));
  }

  void _back() => setState(() => _step = OnboardingStep.welcome);

  @override
  Widget build(BuildContext context) {
    final Widget page = switch (_step) {
      OnboardingStep.welcome => WelcomeScreen(onStart: _start),
      OnboardingStep.faceSetup => FaceSetupScreen(
        repo: widget.repo,
        onBack: _back,
        onEnrolled: _enrolled,
      ),
      OnboardingStep.tutorial ||
      OnboardingStep.done => TutorialScreen(onDone: _finish),
    };
    return PopScope(
      // System back on the face scan returns to Welcome; elsewhere it
      // leaves the app as usual.
      canPop: _step != OnboardingStep.faceSetup,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == OnboardingStep.faceSetup) _back();
      },
      child: AnimatedSwitcher(
        duration: LenzoMotion.of(context, LenzoMotion.page),
        switchInCurve: LenzoMotion.ease,
        switchOutCurve: LenzoMotion.exit,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(a),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(_step), child: page),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared parts
// ---------------------------------------------------------------------------

/// Text scale above which the onboarding screens scroll instead of fitting
/// on one screen.
const _maxFitTextScale = 1.35;

/// Dark-green onboarding page, centred and at most 440 wide, inside the
/// status and navigation bars.
///
/// [body] is built for the space under [header]. Unless text is scaled
/// past 1.35×, it is laid out to fill that space exactly (`fit` is true;
/// flexible parts use [Expanded]), so nothing scrolls; if the space is
/// shorter than [minFitHeight] (small phone, keyboard open) it keeps that
/// height and scrolls. With very large text it is laid out at its natural
/// height and scrolls (`fit` is false; flexible parts get a fixed height).
class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.body,
    required this.minFitHeight,
    this.header,
  });
  final Widget? header;
  final double minFitHeight;
  final Widget Function(BuildContext context, bool fit) body;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lenzoSystemUi,
      child: LenzoBackdrop(
        style: BackdropStyle.sweep,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: [
                    ?header,
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          const pad = EdgeInsets.fromLTRB(
                            LenzoSpacing.screen,
                            0,
                            LenzoSpacing.screen,
                            LenzoSpacing.x4,
                          );
                          // The same widgets in every case (only sizes
                          // change), so nothing is rebuilt from scratch
                          // when the keyboard opens: a rebuilt text field
                          // loses focus and Android closes the keyboard.
                          final fit = scale <= _maxFitTextScale;
                          final height = math.max(
                            box.maxHeight - pad.vertical,
                            minFitHeight,
                          );
                          return SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.manual,
                            padding: pad,
                            child: SizedBox(
                              height: fit ? height : null,
                              child: body(context, fit),
                            ),
                          );
                        },
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
}

/// [child] takes the free space when the page fits ([fit]), or
/// [scrollHeight] when it scrolls.
Widget _flexible(bool fit, Widget child, {required double scrollHeight}) =>
    fit ? Expanded(child: child) : SizedBox(height: scrollHeight, child: child);

/// Back button (or a spacer), the centred logo, an optional action, and the
/// step dots underneath. 64 px tall.
class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({required this.step, this.onBack, this.action});
  final int step;
  final VoidCallback? onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LenzoSpacing.x1,
        0,
        LenzoSpacing.x1,
        LenzoSpacing.x2,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: onBack == null
                      ? null
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: 'Back',
                            onPressed: onBack,
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: LenzoColors.textPrimary,
                            ),
                          ),
                        ),
                ),
                const Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: LenzoBrandLogo(height: 24),
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Align(alignment: Alignment.centerRight, child: action),
                ),
              ],
            ),
          ),
          OnboardingSteps(current: step),
        ],
      ),
    );
  }
}

/// Progress dots joined by short lines; steps up to [current] are mint.
/// Read out as "Step [current] of [total]".
class OnboardingSteps extends StatelessWidget {
  const OnboardingSteps({super.key, required this.current, this.total = 3});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final d = LenzoMotion.of(context, LenzoMotion.tab);
    Color tone(bool on) => on ? LenzoColors.accent : LenzoColors.border;
    return Semantics(
      label: 'Step $current of $total',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= total; i++) ...[
              if (i > 1)
                AnimatedContainer(
                  duration: d,
                  width: 28,
                  height: 2,
                  color: tone(i <= current),
                ),
              AnimatedContainer(
                duration: d,
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone(i <= current),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool _motionOn(BuildContext context) =>
    !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

/// Fade and rise for entering content, [order] steps after the first.
/// Off with "Remove animations".
Widget _enter(BuildContext context, Widget child, int order) {
  if (!_motionOn(context)) return child;
  return child
      .animate(delay: (50 * order).ms)
      .fadeIn(duration: 260.ms, curve: LenzoMotion.ease)
      .slideY(begin: 0.05, end: 0, duration: 300.ms, curve: LenzoMotion.ease);
}

/// Supporting text under a page title.
TextStyle get _lead =>
    LenzoType.body.copyWith(color: LenzoColors.textSecondary, height: 1.4);

// ---------------------------------------------------------------------------
// 1. Welcome
// ---------------------------------------------------------------------------

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      header: const _OnboardingHeader(step: 1),
      minFitHeight: 360,
      body: (context, fit) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _flexible(
            fit,
            scrollHeight: 200,
            LayoutBuilder(
              builder: (context, box) {
                // As large as the space allows, up to 176; hidden when
                // there's no room for it.
                final tile = math.min(
                  176.0,
                  math.min(box.maxWidth * 0.46, box.maxHeight * 0.66),
                );
                if (tile < 64) return const SizedBox.shrink();
                return Center(child: WelcomeArt(tile: tile));
              },
            ),
          ),
          _enter(
            context,
            Semantics(
              header: true,
              child: const Text(
                'Track money\nwith a face',
                textAlign: TextAlign.center,
                style: LenzoType.display,
              ),
            ),
            1,
          ),
          const SizedBox(height: LenzoSpacing.x2),
          _enter(
            context,
            Text(
              'See what you lent and borrowed by pointing your camera at '
              'someone.',
              textAlign: TextAlign.center,
              style: _lead,
            ),
            2,
          ),
          const SizedBox(height: LenzoSpacing.x6),
          _enter(
            context,
            LenzoButton(
              label: 'Get Started',
              icon: Icons.arrow_forward_rounded,
              onPressed: onStart,
            ),
            3,
          ),
          const SizedBox(height: LenzoSpacing.x3),
          const Text(
            'Takes about a minute · Stays on this phone',
            textAlign: TextAlign.center,
            style: LenzoType.secondary,
          ),
        ],
      ),
    );
  }
}

/// Face-scan tile with "Lent" and "Borrowed" chips beside it, drawn with
/// Flutter shapes, sized from [tile].
class WelcomeArt extends StatelessWidget {
  const WelcomeArt({super.key, required this.tile});

  /// Width of the face tile; the chips are sized from it.
  final double tile;

  @override
  Widget build(BuildContext context) {
    final motion = _motionOn(context);
    Widget pop(Widget w, int delay) => motion
        ? w
              .animate(delay: delay.ms)
              .fadeIn(duration: 260.ms, curve: LenzoMotion.ease)
              .scaleXY(
                begin: 0.94,
                end: 1,
                duration: 300.ms,
                curve: LenzoMotion.ease,
              )
        : w;
    final chip = (tile * 0.46).clamp(56.0, 80.0);
    return ExcludeSemantics(
      child: SizedBox(
        width: tile + chip * 0.85,
        height: tile * 1.08,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: tile * 0.04,
              child: pop(_FaceTile(size: tile), 120),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: pop(
                _MoneyChip(
                  size: chip,
                  label: 'Lent',
                  icon: Icons.north_east_rounded,
                  color: LenzoColors.accent,
                ),
                220,
              ),
            ),
            Positioned(
              right: chip * 0.12,
              bottom: 0,
              child: pop(
                _MoneyChip(
                  size: chip,
                  label: 'Borrowed',
                  icon: Icons.south_east_rounded,
                  color: LenzoColors.payable,
                ),
                300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded tile with a soft mint edge, used for the onboarding pictures.
BoxDecoration _tileDecoration(double size, {double glow = 1}) => BoxDecoration(
  borderRadius: BorderRadius.circular(size * 0.24),
  gradient: const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [LenzoColors.surfaceSecondary, LenzoColors.backgroundElevated],
  ),
  border: Border.all(
    color: LenzoColors.accent.withValues(alpha: 0.12 + 0.33 * glow),
  ),
  boxShadow: LenzoShadows.raised,
);

class _FaceTile extends StatelessWidget {
  const _FaceTile({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: _tileDecoration(size),
      child: const CustomPaint(painter: _FaceGlyphPainter(1)),
    );
  }
}

class _MoneyChip extends StatelessWidget {
  const _MoneyChip({
    required this.size,
    required this.label,
    required this.icon,
    required this.color,
  });
  final double size;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(LenzoSpacing.x2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LenzoRadius.cardSmall),
        color: Color.alphaBlend(
          color.withValues(alpha: 0.10),
          LenzoColors.surface,
        ),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: LenzoShadows.card,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: size * 0.34),
          const SizedBox(height: LenzoSpacing.x1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: LenzoType.label.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Face setup
// ---------------------------------------------------------------------------

/// Scan the owner's face, then ask their name. The owner is saved only once
/// both are done and the database write succeeds; then [onEnrolled] runs.
///
/// States: scanning (live circle, one instruction at a time) → captured
/// (photo, "not saved yet", name field) → saving → saved, or a failed save
/// with Try again. A failed capture shows Try again inside the scan.
class FaceSetupScreen extends StatefulWidget {
  const FaceSetupScreen({
    super.key,
    required FaceRepository this.repo,
    required this.onBack,
    required this.onEnrolled,
  }) : scanBuilder = null,
       enroll = null;

  /// For widget tests: a stand-in for the camera scan and for saving, so
  /// the layout and states can be checked without a camera or database.
  @visibleForTesting
  const FaceSetupScreen.test({
    super.key,
    required ScanBuilder this.scanBuilder,
    required Future<void> Function(String name, OwnerScan scan) this.enroll,
    required this.onBack,
    required this.onEnrolled,
  }) : repo = null;

  final FaceRepository? repo;
  final VoidCallback onBack;
  final VoidCallback onEnrolled;
  final ScanBuilder? scanBuilder;
  final Future<void> Function(String name, OwnerScan scan)? enroll;

  @override
  State<FaceSetupScreen> createState() => _FaceSetupScreenState();
}

/// Builds the scan circle: [size], the finished scan (or null while
/// scanning) and the callback for a capture.
typedef ScanBuilder = Widget Function(
  BuildContext context,
  double size,
  OwnerScan? scan,
  ValueChanged<OwnerScan> onCaptured,
);

class _FaceSetupScreenState extends State<FaceSetupScreen> {
  OwnerScan? _scan;
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  String? _nameError;
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _captured(OwnerScan scan) {
    setState(() {
      _scan = scan;
      _saveFailed = false;
    });
    // Suggest the saved contact's name if this face is already saved.
    final m = scan.match;
    if (m.kind == MatchKind.known && m.name != null && _name.text.isEmpty) {
      _name.text = m.name!;
    }
  }

  void _rescan() {
    FocusScope.of(context).unfocus();
    setState(() {
      _scan = null;
      _nameError = null;
      _saveFailed = false;
    });
  }

  Future<void> _save() async {
    final scan = _scan;
    if (scan == null || _saving) return;
    final name = cleanPersonName(_name.text);
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter your name to continue');
      _nameFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    final repo = widget.repo;
    final link = repo == null
        ? 0
        : await resolveOwnerMatch(context, repo, scan, updating: false);
    if (!mounted) return;
    if (link == null) {
      _rescan();
      return;
    }
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      final enroll = widget.enroll;
      if (enroll != null) {
        await enroll(name, scan);
      } else {
        await repo!.registerOwner(
          name: name,
          faces: scan.faces,
          portraitJpeg: scan.portrait,
          existingId: link == 0 ? null : link,
        );
      }
    } catch (e) {
      debugPrint('Owner save failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    HapticFeedback.lightImpact();
    showLenzoSuccess(context, 'Your face is saved');
    widget.onEnrolled();
  }

  @override
  Widget build(BuildContext context) {
    final scanned = _scan != null;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return _OnboardingPage(
      header: _OnboardingHeader(
        step: 2,
        onBack: _saving ? null : widget.onBack,
      ),
      minFitHeight: 300,
      body: (context, fit) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: LenzoSpacing.x2),
          Semantics(
            header: true,
            child: Text(
              scanned ? 'Add your name' : 'Set up your face',
              textAlign: TextAlign.center,
              style: LenzoType.pageHeading,
            ),
          ),
          // Hidden while typing, but always the same widget, so the scan
          // and the name field below are never rebuilt.
          Visibility(
            visible: !keyboard,
            child: Padding(
              padding: const EdgeInsets.only(top: LenzoSpacing.x1),
              child: Text(
                scanned
                    ? 'Shown when Lenzo recognizes you.'
                    : 'Your face stays on this phone.',
                textAlign: TextAlign.center,
                style: _lead,
              ),
            ),
          ),
          const SizedBox(height: LenzoSpacing.x4),
          _flexible(
            fit,
            scrollHeight: 320,
            LayoutBuilder(
              builder: (context, box) {
                // Room for the ring (+22), the gap and two-line message
                // (60), and, while scanning, a Try again button (48).
                final reserve = 22 + 60 + (scanned ? 0 : 48);
                // While typing, the circle may get small so the field and
                // Save stay above the keyboard.
                final target = math
                    .min(box.maxWidth * 0.72, box.maxHeight - reserve)
                    .clamp(keyboard ? 40.0 : 72.0, 280.0);
                return TweenAnimationBuilder<double>(
                  tween: Tween(end: target),
                  duration: LenzoMotion.of(context, LenzoMotion.expand),
                  curve: LenzoMotion.ease,
                  // Centred while scanning; moves up when the form appears.
                  builder: (context, size, _) => AnimatedAlign(
                    duration: LenzoMotion.of(context, LenzoMotion.expand),
                    curve: LenzoMotion.ease,
                    alignment: scanned
                        ? Alignment.topCenter
                        : const Alignment(0, -0.35),
                    child:
                        widget.scanBuilder?.call(
                          context,
                          size,
                          _scan,
                          _captured,
                        ) ??
                        OwnerFaceScan(
                          repo: widget.repo!,
                          size: size,
                          scan: _scan,
                          onCaptured: _captured,
                        ),
                  ),
                );
              },
            ),
          ),
          if (scanned) ..._form(keyboard),
        ],
      ),
    );
  }

  List<Widget> _form(bool keyboard) => [
    LenzoTextField(
      label: 'Your name',
      controller: _name,
      focusNode: _nameFocus,
      hint: 'Enter your name',
      error: _nameError,
      maxLength: 40,
      leadingIcon: Icons.person_outline_rounded,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      onChanged: (_) {
        if (_nameError != null) setState(() => _nameError = null);
      },
      onSubmitted: (_) => _save(),
    ),
    const SizedBox(height: LenzoSpacing.x3),
    if (_saveFailed) ...[
      Text(
        "Couldn't save your profile. Nothing was saved, so you can try "
        'again.',
        textAlign: TextAlign.center,
        style: LenzoType.secondary.copyWith(color: LenzoColors.danger),
      ),
      const SizedBox(height: LenzoSpacing.x2),
    ],
    LenzoButton(
      label: _saveFailed ? 'Try again' : 'Save and continue',
      icon: _saveFailed ? Icons.refresh_rounded : Icons.arrow_forward_rounded,
      busy: _saving,
      onPressed: _save,
    ),
    // Hidden while typing, so the field and Save stay above the keyboard.
    if (!keyboard) ...[
      const SizedBox(height: LenzoSpacing.x2),
      LenzoButton(
        label: 'Scan again',
        icon: Icons.refresh_rounded,
        kind: LenzoButtonKind.outlineAccent,
        onPressed: _saving ? null : _rescan,
      ),
    ],
  ];
}

// ---------------------------------------------------------------------------
// 3. Tutorial
// ---------------------------------------------------------------------------

/// Which drawing a tutorial slide shows.
enum GuideIconKind { recognize, money, organize }

/// One tutorial slide.
@immutable
class TutorialSlide {
  const TutorialSlide(this.icon, this.title, this.text);
  final GuideIconKind icon;
  final String title;
  final String text;
}

const tutorialSlides = [
  TutorialSlide(
    GuideIconKind.recognize,
    'Recognize People',
    'Point your camera at someone to recognize them.',
  ),
  TutorialSlide(
    GuideIconKind.money,
    'Track Money',
    'Track money you lend and borrow.',
  ),
  TutorialSlide(
    GuideIconKind.organize,
    'Stay Organized',
    'See who owes you and who you owe.',
  ),
];

/// A swipeable three-slide carousel. The pictures follow the finger: the
/// current one is large in the middle, its neighbours small and dim at the
/// sides. "Next" moves on; on the last slide it becomes "Start Lenzo".
/// "Skip" finishes at any time.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  /// Slide change time.
  static const transition = Duration(milliseconds: 300);

  /// The new slide's icon draws itself in this time, starting halfway
  /// through the slide change, so both finish within 350 ms.
  static const iconDraw = Duration(milliseconds: 200);

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen>
    with SingleTickerProviderStateMixin {
  final _pages = PageController();
  late final _draw = AnimationController(
    vsync: this,
    duration: TutorialScreen.iconDraw,
  );
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draw.status == AnimationStatus.dismissed) {
      _motionOn(context) ? _draw.forward() : _draw.value = 1;
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _draw.dispose();
    super.dispose();
  }

  void _changed(int i) {
    setState(() => _index = i);
    if (_motionOn(context)) {
      _draw.forward(from: 0);
    } else {
      _draw.value = 1;
    }
  }

  void _next() {
    if (_index == tutorialSlides.length - 1) {
      widget.onDone();
      return;
    }
    final d = LenzoMotion.of(context, TutorialScreen.transition);
    if (d == Duration.zero) {
      _pages.jumpToPage(_index + 1);
    } else {
      _pages.animateToPage(_index + 1, duration: d, curve: LenzoMotion.ease);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Title (17 px) + gap + two lines of 14 px text.
    // (+4 for line-metric rounding.)
    final textH =
        scaler.scale(17) * 1.3 +
        LenzoSpacing.x2 +
        scaler.scale(14) * 1.4 * 2 +
        4;
    final last = _index == tutorialSlides.length - 1;
    return _OnboardingPage(
      header: _OnboardingHeader(
        step: 3,
        action: TextButton(
          onPressed: widget.onDone,
          style: TextButton.styleFrom(
            foregroundColor: LenzoColors.textSecondary,
            minimumSize: const Size(48, 48),
          ),
          child: const Text('Skip', style: LenzoType.button),
        ),
      ),
      minFitHeight: 380,
      body: (context, fit) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: LenzoSpacing.x2),
          Semantics(
            header: true,
            child: const Text(
              'How Lenzo works',
              textAlign: TextAlign.center,
              style: LenzoType.pageHeading,
            ),
          ),
          const SizedBox(height: LenzoSpacing.x1),
          Text(
            'A quick look at the basics.',
            textAlign: TextAlign.center,
            style: _lead,
          ),
          _flexible(
            fit,
            scrollHeight: 300,
            LayoutBuilder(
              builder: (context, box) {
                final stageH = math.max(0.0, box.maxHeight - textH - 16);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: -LenzoSpacing.screen,
                      right: -LenzoSpacing.screen,
                      top: 0,
                      height: stageH,
                      child: IgnorePointer(
                        child: _Stage(pages: _pages, draw: _draw),
                      ),
                    ),
                    PageView.builder(
                      controller: _pages,
                      itemCount: tutorialSlides.length,
                      onPageChanged: _changed,
                      itemBuilder: (context, i) =>
                          _SlideText(slide: tutorialSlides[i], height: textH),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: LenzoSpacing.x3),
          Center(
            child: _Dots(count: tutorialSlides.length, index: _index),
          ),
          const SizedBox(height: LenzoSpacing.x5),
          LenzoButton(
            label: last ? 'Start Lenzo' : 'Next',
            icon: Icons.arrow_forward_rounded,
            onPressed: _next,
          ),
        ],
      ),
    );
  }
}

/// A slide's title and sentence, at the bottom of its page.
class _SlideText extends StatelessWidget {
  const _SlideText({required this.slide, required this.height});
  final TutorialSlide slide;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Text(
              slide.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: LenzoType.sectionHeading,
            ),
            const SizedBox(height: LenzoSpacing.x2),
            Text(
              slide.text,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: _lead,
            ),
          ],
        ),
      ),
    );
  }
}

/// The three slide pictures. Positions, sizes and brightness follow the
/// page position continuously, so they move with a swipe. The current
/// picture's icon draws itself with [draw].
class _Stage extends StatelessWidget {
  const _Stage({required this.pages, required this.draw});
  final PageController pages;
  final Animation<double> draw;

  // Exactly one attached page view (briefly two while the layout switches
  // between fitting and scrolling).
  double _page() => pages.positions.length == 1 && pages.position.haveDimensions
      ? pages.page ?? 0
      : pages.initialPage.toDouble();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final big = math.min(
          132.0,
          math.min(box.maxHeight * 0.82, box.maxWidth * 0.36),
        );
        if (big < 48) return const SizedBox.shrink();
        final small = big * 0.62;
        final gap = big * 0.5 + small * 0.5 + LenzoSpacing.x3;
        return ClipRect(
          child: AnimatedBuilder(
            animation: Listenable.merge([pages, draw]),
            builder: (context, _) {
              final page = _page();
              final t = LenzoMotion.ease.transform(draw.value);
              // Farther tiles first, so the current one is drawn on top.
              final order = [for (var i = 0; i < tutorialSlides.length; i++) i]
                ..sort((a, b) => (b - page).abs().compareTo((a - page).abs()));
              return Stack(
                children: [
                  for (final i in order)
                    _tile(
                      box,
                      i,
                      d: i - page,
                      big: big,
                      small: small,
                      gap: gap,
                      t: (i - page).abs() < 0.5 ? t : 1,
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _tile(
    BoxConstraints box,
    int i, {
    required double d,
    required double big,
    required double small,
    required double gap,
    required double t,
  }) {
    final near = (1 - d.abs()).clamp(0.0, 1.0); // 1 = current
    final size = small + (big - small) * near;
    final cx = box.maxWidth / 2 + d * gap;
    final opacity = (0.45 + 0.55 * near) * (d.abs() > 1.6 ? 0 : 1);
    return Positioned(
      left: cx - size / 2,
      top: (box.maxHeight - size) / 2,
      width: size,
      height: size,
      child: Opacity(
        opacity: opacity,
        child: DecoratedBox(
          decoration: _tileDecoration(size, glow: near),
          child: Padding(
            padding: EdgeInsets.all(size * 0.14),
            child: CustomPaint(
              painter: switch (tutorialSlides[i].icon) {
                GuideIconKind.recognize => _FaceGlyphPainter(
                  math.max(t, 0.001),
                ),
                GuideIconKind.money => _ArrowsPainter(t),
                GuideIconKind.organize => _BarsPainter(t),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Pagination dots; the current one is a short mint pill. Read out as
/// "Slide x of n".
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final d = LenzoMotion.of(context, const Duration(milliseconds: 180));
    return Semantics(
      label: 'Slide ${index + 1} of $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: d,
                curve: LenzoMotion.ease,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: LenzoRadius.pillAll,
                  color: i == index
                      ? LenzoColors.accent
                      : LenzoColors.textTertiary.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Drawings
// ---------------------------------------------------------------------------

/// Corner brackets around a simple face. [t] (0–1) draws the brackets in
/// and fades the face up.
class _FaceGlyphPainter extends CustomPainter {
  const _FaceGlyphPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = math.max(1.6, s * 0.035);
    final line = Paint()
      ..color = LenzoColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final inset = s * 0.24, arm = s * 0.13 * t;
    final l = inset, r = size.width - inset;
    final top = inset, b = size.height - inset;
    for (final (x, y, dx, dy) in [
      (l, top, 1.0, 1.0),
      (r, top, -1.0, 1.0),
      (l, b, 1.0, -1.0),
      (r, b, -1.0, -1.0),
    ]) {
      canvas.drawLine(Offset(x, y), Offset(x + dx * arm, y), line);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * arm), line);
    }
    final face = Paint()
      ..color = LenzoColors.textPrimary.withValues(alpha: 0.9 * t)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final c = size.center(Offset.zero);
    final eye = s * 0.07;
    canvas.drawLine(
      c + Offset(-s * 0.09, -eye),
      c + Offset(-s * 0.09, -eye * 0.2),
      face,
    );
    canvas.drawLine(
      c + Offset(s * 0.09, -eye),
      c + Offset(s * 0.09, -eye * 0.2),
      face,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: c + Offset(0, s * 0.03),
        width: s * 0.22,
        height: s * 0.14,
      ),
      0.25,
      math.pi - 0.5,
      false,
      face,
    );
  }

  @override
  bool shouldRepaint(_FaceGlyphPainter old) => old.t != t;
}

/// Money moving both ways: a mint arrow out (lent) above an amber arrow in
/// (borrowed), sliding into place as [t] goes 0 → 1.
class _ArrowsPainter extends CustomPainter {
  const _ArrowsPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final o = Offset((size.width - s) / 2, (size.height - s) / 2);
    void arrow(Color color, double y, double dir) {
      final p = Paint()
        ..color = color.withValues(alpha: t)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, s * 0.05)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      // Slides in from the side it points away from.
      final shift = (1 - t) * s * 0.12 * -dir;
      final x0 = s * 0.24 + shift, x1 = s * 0.76 + shift;
      final from = o + Offset(dir > 0 ? x0 : x1, y);
      final to = o + Offset(dir > 0 ? x1 : x0, y);
      canvas.drawLine(from, to, p);
      final head = s * 0.11;
      canvas.drawPath(
        Path()
          ..moveTo(to.dx - dir * head, to.dy - head)
          ..lineTo(to.dx, to.dy)
          ..lineTo(to.dx - dir * head, to.dy + head),
        p,
      );
    }

    arrow(LenzoColors.accent, s * 0.38, 1);
    arrow(LenzoColors.payable, s * 0.62, -1);
  }

  @override
  bool shouldRepaint(_ArrowsPainter old) => old.t != t;
}

/// A short contact list: avatar dots and name bars, the bars growing in
/// turn as [t] goes 0 → 1.
class _BarsPainter extends CustomPainter {
  const _BarsPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final o = Offset((size.width - s) / 2, (size.height - s) / 2);
    const colors = [
      LenzoColors.accent,
      LenzoColors.payable,
      LenzoColors.textSecondary,
    ];
    const lengths = [0.46, 0.32, 0.4];
    for (var i = 0; i < 3; i++) {
      final y = s * (0.3 + 0.2 * i);
      final local = ((t * 1.4) - i * 0.2).clamp(0.0, 1.0);
      canvas.drawCircle(
        o + Offset(s * 0.22, y),
        s * 0.055,
        Paint()..color = colors[i].withValues(alpha: math.max(0.25, local)),
      );
      canvas.drawLine(
        o + Offset(s * 0.36, y),
        o + Offset(s * 0.36 + s * lengths[i] * local, y),
        Paint()
          ..color = LenzoColors.textSecondary.withValues(alpha: 0.8)
          ..strokeWidth = math.max(2.0, s * 0.05)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.t != t;
}
