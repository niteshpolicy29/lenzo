import 'dart:io';
import 'dart:typed_data';

import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';

import '../design/design.dart';
import '../theme/lenzo_theme.dart';
import 'page_thread.dart';

/// The Lenzo logo: chain mark and "Lenzo." wordmark, from
/// `assets/brand/lenzo_logo.png`. [height] sets its size; the width follows
/// the logo's own proportions. It is decoded at the screen's pixel density so
/// it stays sharp without using extra memory.
class LenzoBrandLogo extends StatelessWidget {
  const LenzoBrandLogo({super.key, this.height = 30});
  final double height;

  /// Width / height of the logo image.
  static const aspectRatio = 1980 / 501;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.asset(
      'assets/brand/lenzo_logo.png',
      height: height,
      width: height * aspectRatio,
      fit: BoxFit.contain,
      cacheHeight: (height * dpr).round(),
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Lenzo',
    );
  }
}

enum BackdropStyle {
  /// Light-green sweep at the top right and a thin wave at the bottom.
  waves,

  /// The top-right sweep only, for pages with long lists.
  sweep,

  /// The dark-green gradient only.
  plain,
}

/// Dark-green page background with soft emerald light.
class LenzoBackdrop extends StatelessWidget {
  const LenzoBackdrop({super.key, required this.style, required this.child});
  final BackdropStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // On the Settings / Home / Saved People pager the background (and the
    // thread across the pages) is painted once underneath.
    if (SharedBackground.of(context)) return child;
    return CustomPaint(painter: _BackdropPainter(style), child: child);
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter(this.style);
  final BackdropStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    // One clean, solid Lenzo background on every screen.
    canvas.drawRect(Offset.zero & size, Paint()..color = Lenzo.background);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.style != style;
}

/// Soft dark-green drop shadow that lifts a panel off the background.
/// Dark, not bright, so it adds depth without glowing.
/// Soft card shadow (design token).
const List<BoxShadow> lenzoShadow = LenzoShadows.card;

/// Translucent green panel with a hairline emerald border. With [shadow],
/// it also gets [lenzoShadow].
BoxDecoration lenzoPanel({
  double radius = LenzoRadius.cardSmall,
  bool highlighted = false,
  bool shadow = false,
}) {
  // Separated by tone; a hairline only when open/highlighted.
  return BoxDecoration(
    color: LenzoColors.surface,
    borderRadius: BorderRadius.circular(radius),
    border: highlighted
        ? Border.all(color: LenzoColors.accent.withValues(alpha: 0.45))
        : null,
    boxShadow: shadow ? LenzoShadows.card : null,
  );
}

/// Rounded square holding a line icon, used at the start of rows.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.color = Lenzo.accentMuted,
  });
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Just the icon: boxed icon tiles read as template decoration.
    return SizedBox.square(
      dimension: 28,
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// Small rounded status pill, e.g. "Verified Contact".
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        color: Color.alphaBlend(color.withValues(alpha: 0.12), Lenzo.surface),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Color.lerp(color, Lenzo.textPrimary, 0.45),
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Image for a saved face, from a file or from memory. Shows a person icon
/// if there is neither.
class FaceImage extends StatelessWidget {
  const FaceImage({super.key, this.path, this.bytes});
  final String? path;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: Lenzo.surface,
      alignment: Alignment.center,
      child: const Icon(Icons.person, size: 72, color: Lenzo.textSecondary),
    );
    if (bytes != null) {
      return Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true);
    }
    if (path != null) {
      return Image.file(
        File(path!),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return fallback;
  }
}

/// Round portrait with a thin emerald ring.
class RingPortrait extends StatelessWidget {
  const RingPortrait({super.key, required this.size, required this.image});
  final double size;
  final Widget image;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Lenzo.accent.withValues(alpha: 0.55),
      ),
      child: ClipOval(child: image),
    );
  }
}

/// Primary call-to-action: a light-to-emerald gradient pill.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  /// The screen's primary action; see [LenzoButton].
  @override
  Widget build(BuildContext context) =>
      LenzoButton(label: label, icon: icon, busy: busy, onPressed: onPressed);
}

/// Input decoration matching the New Contact page fields.
InputDecoration lenzoInput({
  String? hint,
  Widget? prefix,
  String? error,
  bool dense = false,
  bool raised = false,
}) => lenzoFieldDecoration(
  hint: hint,
  prefix: prefix,
  error: error,
  raised: raised,
);

/// Shows a Lenzo-styled message at the bottom of the screen.
void showLenzoMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Like [showLenzoMessage], for a completed action: the message starts with
/// a small green check that draws itself once (a Lottie animation).
void showLenzoSuccess(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Lottie.asset(
              'assets/lottie/success_check.json',
              width: 28,
              height: 28,
              repeat: false,
              frameRate: FrameRate.max,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
}

/// Shrinks its child slightly while pressed and springs back on release,
/// for tactile buttons. Doesn't handle the tap itself.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (widget.enabled && down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: Lenzo.motion(
          context,
          _down ? const Duration(milliseconds: 90) : Lenzo.medium,
        ),
        curve: Lenzo.ease,
        child: widget.child,
      ),
    );
  }
}

/// Secondary button used in editors (Cancel, Remove).
ButtonStyle lenzoOutlinedStyle() => OutlinedButton.styleFrom(
  foregroundColor: LenzoColors.textPrimary,
  side: const BorderSide(color: LenzoColors.border),
  minimumSize: const Size.fromHeight(40),
  padding: const EdgeInsets.symmetric(horizontal: LenzoSpacing.x3),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: RoundedRectangleBorder(borderRadius: LenzoRadius.buttonAll),
  textStyle: LenzoType.button,
);

/// Primary button used in editors (Save).
ButtonStyle lenzoFilledStyle() => FilledButton.styleFrom(
  backgroundColor: LenzoColors.accent,
  foregroundColor: LenzoColors.onAccent,
  minimumSize: const Size.fromHeight(40),
  padding: const EdgeInsets.symmetric(horizontal: LenzoSpacing.x3),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: RoundedRectangleBorder(borderRadius: LenzoRadius.buttonAll),
  textStyle: LenzoType.button,
);

/// Cancel and Save, side by side.
class EditorActions extends StatelessWidget {
  const EditorActions({
    super.key,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) =>
      LenzoButtonPair(busy: saving, onCancel: onCancel, onConfirm: onSave);
}

/// Fades a scrolling area out over [top] and [bottom] pixels, so content
/// passing under the header or the bottom edge dissolves softly instead of
/// being cut off by a hard line. Give the scroll view at least this much
/// padding so content at rest is fully visible.
class FadeEdges extends StatelessWidget {
  const FadeEdges({
    super.key,
    required this.child,
    this.top = 16,
    this.bottom = 28,
  });
  final Widget child;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final h = bounds.height <= 0 ? 1.0 : bounds.height;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [
            0,
            (top / h).clamp(0.0, 0.5),
            (1 - bottom / h).clamp(0.5, 1.0),
            1,
          ],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

/// A small label + value chip inside an [AmountHero].
class HeroChip {
  const HeroChip(this.label, this.value);
  final String label;
  final String value;
}

/// The one key figure on a screen: a caption, a large light number that
/// counts up to [paise], and optional chips underneath. [bright] fills the
/// card with vibrant green (dark text); otherwise it's a dark card with a
/// green number.
class AmountHero extends StatelessWidget {
  const AmountHero({
    super.key,
    required this.caption,
    required this.paise,
    this.chips = const [],
    this.note,
    this.bright = true,
    this.compact = false,
    this.onTap,
  });

  final String caption;
  final int paise;
  final List<HeroChip> chips;

  /// Short line at the top right, e.g. "3 borrowers".
  final String? note;

  /// Kept for callers; the card is always dark with a mint figure (accent
  /// only on the amount).
  final bool bright;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = LenzoFinancialCard(
      size: compact ? 30 : 34,
      figures: [LenzoFigure(caption, paise, color: LenzoColors.accent)],
      note: note,
      footer: chips.isEmpty
          ? null
          : Wrap(
              spacing: LenzoSpacing.x2,
              runSpacing: LenzoSpacing.x2,
              children: [
                for (final c in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LenzoSpacing.x3,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: LenzoColors.surfaceSecondary,
                      borderRadius: LenzoRadius.pillAll,
                    ),
                    child: Text.rich(
                      TextSpan(
                        text: '${c.label}  ',
                        children: [
                          TextSpan(
                            text: c.value,
                            style: const TextStyle(
                              color: LenzoColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      style: LenzoType.secondary,
                    ),
                  ),
              ],
            ),
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

/// Asks before permanently removing [name]. Returns true only if the user
/// taps Remove.
Future<bool> showRemoveDialog(BuildContext context, {required String name}) {
  return showLenzoConfirm(
    context,
    icon: Icons.delete_outline_rounded,
    title: 'Remove contact?',
    message: "Remove $name and their saved details? This can't be undone.",
    confirm: 'Remove',
    destructive: true,
  );
}

/// Confirmation dialog; see [showLenzoDialog].
Future<bool> showLenzoConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  String cancel = 'Cancel',
  IconData? icon,
  Widget? image,
  bool destructive = false,
}) => showLenzoDialog(
  context,
  title: title,
  message: message,
  confirm: confirm,
  cancel: cancel,
  icon: icon,
  image: image,
  destructive: destructive,
);

/// One compact card with the two open balances side by side: To Receive
/// (mint) and To Pay (amber), split by a hairline. Large amounts shrink to
/// fit instead of being cut.
class BalancePairCard extends StatelessWidget {
  const BalancePairCard({
    super.key,
    required this.receivePaise,
    required this.payPaise,
  });
  final int receivePaise;
  final int payPaise;

  @override
  Widget build(BuildContext context) => LenzoFinancialCard(
    figures: [
      LenzoFigure('To Receive', receivePaise, color: LenzoColors.accent),
      LenzoFigure('To Pay', payPaise, color: LenzoColors.payable),
    ],
  );
}
