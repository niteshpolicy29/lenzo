import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/format.dart';
import 'tokens.dart';
import 'typography.dart';

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// The base card: [LenzoColors.surface] on the background, separated by
/// tone and a soft shadow rather than a border. [small] uses the smaller
/// radius (rows, tiles); [outlined] adds a hairline where two surfaces of
/// the same tone meet.
class LenzoCard extends StatelessWidget {
  const LenzoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LenzoSpacing.card),
    this.small = false,
    this.outlined = false,
    this.shadow = true,
    this.color = LenzoColors.surface,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool small;
  final bool outlined;
  final bool shadow;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = small ? LenzoRadius.cardSmallAll : LenzoRadius.cardAll;
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        border: outlined ? Border.all(color: LenzoColors.border) : null,
        boxShadow: shadow ? LenzoShadows.card : null,
      ),
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: radius,
                onTap: onTap,
                splashColor: LenzoColors.textPrimary.withValues(alpha: 0.04),
                highlightColor: LenzoColors.textPrimary.withValues(alpha: 0.03),
                child: content,
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

enum LenzoButtonKind {
  /// Mint fill: the one main action on a screen or dialog.
  primary,

  /// Secondary surface fill.
  secondary,

  /// Hairline outline on the current surface.
  outline,

  /// Mint outline and mint label: the secondary action next to a primary
  /// button (e.g. Scan again under Save). Same size and shape as primary.
  outlineAccent,

  /// Muted coral fill, for removing things.
  destructive,

  /// Text only.
  ghost,
}

/// Lenzo's button. 48 px tall ([compact]: 40 px), 14 px radius, 14 px
/// semibold label. Shrinks a little while pressed. [busy] shows a spinner
/// in place of the label.
class LenzoButton extends StatefulWidget {
  const LenzoButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = LenzoButtonKind.primary,
    this.icon,
    this.busy = false,
    this.compact = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final LenzoButtonKind kind;
  final IconData? icon;
  final bool busy;
  final bool compact;

  /// Fill the available width.
  final bool expand;

  @override
  State<LenzoButton> createState() => _LenzoButtonState();
}

class _LenzoButtonState extends State<LenzoButton> {
  bool _down = false;

  (Color bg, Color fg, Color? side) get _colors => switch (widget.kind) {
    LenzoButtonKind.primary => (LenzoColors.accent, LenzoColors.onAccent, null),
    LenzoButtonKind.secondary => (
      LenzoColors.surfaceSecondary,
      LenzoColors.textPrimary,
      null,
    ),
    LenzoButtonKind.outline => (
      Colors.transparent,
      LenzoColors.textPrimary,
      LenzoColors.border,
    ),
    LenzoButtonKind.destructive => (
      LenzoColors.danger,
      LenzoColors.onDanger,
      null,
    ),
    LenzoButtonKind.ghost => (Colors.transparent, LenzoColors.accent, null),
    LenzoButtonKind.outlineAccent => (
      Colors.transparent,
      LenzoColors.accent,
      LenzoColors.accent.withValues(alpha: 0.55),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final (bg, fg, side) = _colors;
    final height = widget.compact ? 40.0 : 48.0;
    final label = widget.busy
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: fg),
                const SizedBox(width: LenzoSpacing.x2),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LenzoType.button.copyWith(color: fg),
                ),
              ),
            ],
          );
    return Semantics(
      button: true,
      enabled: enabled,
      child: Listener(
        onPointerDown: enabled ? (_) => setState(() => _down = true) : null,
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: LenzoMotion.of(context, LenzoMotion.press),
          curve: LenzoMotion.ease,
          child: AnimatedOpacity(
            duration: LenzoMotion.of(context, LenzoMotion.press),
            opacity: enabled || widget.busy ? 1 : 0.45,
            child: Material(
              color: bg,
              shape: RoundedRectangleBorder(
                borderRadius: LenzoRadius.buttonAll,
                side: side == null ? BorderSide.none : BorderSide(color: side),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? widget.onPressed : null,
                splashColor: fg.withValues(alpha: 0.08),
                highlightColor: fg.withValues(alpha: 0.05),
                child: SizedBox(
                  height: height,
                  width: widget.expand ? double.infinity : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LenzoSpacing.x4,
                    ),
                    child: Center(
                      widthFactor: widget.expand ? null : 1,
                      child: AnimatedSwitcher(
                        duration: LenzoMotion.of(context, LenzoMotion.press),
                        child: KeyedSubtree(
                          key: ValueKey(widget.busy),
                          child: label,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon-only action, 44 px touch target, 20 px icon. [filled] puts
/// it on the secondary surface.
class LenzoIconButton extends StatelessWidget {
  const LenzoIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = LenzoColors.textPrimary,
    this.filled = false,
    this.size = 20,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: size),
      color: color,
      disabledColor: LenzoColors.textTertiary,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(LenzoSpacing.tap),
        backgroundColor: filled ? LenzoColors.surfaceSecondary : null,
        highlightColor: LenzoColors.textPrimary.withValues(alpha: 0.06),
      ),
    );
  }
}

/// Cancel / Save side by side: equal width, the confirm action on the right.
class LenzoButtonPair extends StatelessWidget {
  const LenzoButtonPair({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    this.cancel = 'Cancel',
    this.confirm = 'Save',
    this.busy = false,
    this.destructive = false,
    this.compact = true,
  });

  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final String cancel;
  final String confirm;
  final bool busy;
  final bool destructive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LenzoButton(
            label: cancel,
            kind: LenzoButtonKind.outline,
            compact: compact,
            onPressed: busy ? null : onCancel,
          ),
        ),
        const SizedBox(width: LenzoSpacing.x3),
        Expanded(
          child: LenzoButton(
            label: confirm,
            kind: destructive
                ? LenzoButtonKind.destructive
                : LenzoButtonKind.primary,
            compact: compact,
            busy: busy,
            onPressed: onConfirm,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

/// Fill colour of a text input: [LenzoColors.field] (or the raised pair
/// with [raised], for inputs inside a card, panel or dialog), a step
/// lighter while focused, and tinted red with an error. No outline.
WidgetStateColor lenzoFieldFill({bool raised = false, bool error = false}) {
  final rest = raised ? LenzoColors.fieldRaised : LenzoColors.field;
  final focused = raised
      ? LenzoColors.fieldRaisedFocused
      : LenzoColors.fieldFocused;
  return WidgetStateColor.resolveWith((states) {
    final base = states.contains(WidgetState.focused) ? focused : rest;
    return error
        ? Color.alphaBlend(LenzoColors.danger.withValues(alpha: 0.10), base)
        : base;
  });
}

/// The shape of every text input: [LenzoRadius.input] corners, no line.
final lenzoFieldBorder = OutlineInputBorder(
  borderRadius: LenzoRadius.inputAll,
  borderSide: BorderSide.none,
);

/// Field decoration: a filled surface with card corners and no outline,
/// 48 px tall for single-line fields, 16 px side padding. Focus lightens
/// the fill instead of drawing a border. [raised] for inputs on a card,
/// panel or dialog.
InputDecoration lenzoFieldDecoration({
  String? hint,
  String? error,
  Widget? prefix,
  Widget? suffix,
  bool raised = false,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: LenzoType.input.copyWith(
      color: LenzoColors.textTertiary,
      fontWeight: FontWeight.w400,
    ),
    errorText: error,
    errorStyle: LenzoType.secondary.copyWith(color: LenzoColors.danger),
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
    suffixIcon: suffix,
    isDense: true,
    filled: true,
    fillColor: lenzoFieldFill(raised: raised, error: error != null),
    hoverColor: Colors.transparent,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: LenzoSpacing.x4,
      vertical: 14,
    ),
    border: lenzoFieldBorder,
    enabledBorder: lenzoFieldBorder,
    focusedBorder: lenzoFieldBorder,
    disabledBorder: lenzoFieldBorder,
    errorBorder: lenzoFieldBorder,
    focusedErrorBorder: lenzoFieldBorder,
  );
}

/// A labelled text field. The label sits above (12 px semibold), an
/// optional [helper] below it; [money] adds a ₹ prefix, the number pad and
/// amount-only input. When focused, the page scrolls to keep the field and
/// some room below it (the next field or action) above the keyboard.
class LenzoTextField extends StatelessWidget {
  const LenzoTextField({
    super.key,
    this.label,
    this.helper,
    this.controller,
    this.focusNode,
    this.hint,
    this.error,
    this.money = false,
    this.required = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.keyboardType,
    this.inputFormatters,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.suffix,
    this.leadingIcon,
    this.leadingColor,
    this.raised = false,
  });

  final String? label;
  final String? helper;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final String? error;
  final bool money;
  final bool required;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final Widget? suffix;

  /// Small icon before the label (e.g. the direction of money).
  final IconData? leadingIcon;
  final Color? leadingColor;

  /// On a card, panel or dialog: uses the raised fill.
  final bool raised;

  /// Room kept visible below a focused field.
  static const focusRoom = EdgeInsets.fromLTRB(20, 20, 20, 140);

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      buildCounter: (
        _, {
        required currentLength,
        required isFocused,
        maxLength,
      }) => null,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      keyboardType: money
          ? const TextInputType.numberWithOptions(decimal: true)
          : keyboardType,
      inputFormatters: money ? [MoneyInputFormatter()] : inputFormatters,
      scrollPadding: focusRoom,
      style: LenzoType.input,
      cursorColor: LenzoColors.accent,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      decoration: lenzoFieldDecoration(
        raised: raised,
        hint: hint ?? (money ? '0' : null),
        error: error,
        suffix: suffix,
        prefix: money
            ? Padding(
                padding: const EdgeInsets.only(
                  left: LenzoSpacing.x4,
                  right: LenzoSpacing.x1,
                ),
                child: Text(
                  '₹',
                  style: LenzoType.input.copyWith(
                    color: LenzoColors.textSecondary,
                  ),
                ),
              )
            : null,
      ),
    );
    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LenzoFieldLabel(
          label: label!,
          helper: helper,
          required: required,
          icon: leadingIcon,
          iconColor: leadingColor,
        ),
        const SizedBox(height: LenzoSpacing.x2),
        field,
      ],
    );
  }
}

/// A field's label: one line that shrinks rather than wraps or cuts, an
/// optional small icon, a required mark, and helper text underneath.
class LenzoFieldLabel extends StatelessWidget {
  const LenzoFieldLabel({
    super.key,
    required this.label,
    this.helper,
    this.required = false,
    this.icon,
    this.iconColor,
  });

  final String label;
  final String? helper;
  final bool required;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final indent = icon == null ? 0.0 : 16.0 + LenzoSpacing.x2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: iconColor ?? LenzoColors.textSecondary,
              ),
              const SizedBox(width: LenzoSpacing.x2),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    text: label,
                    children: [
                      if (required)
                        const TextSpan(
                          text: ' *',
                          style: TextStyle(color: LenzoColors.danger),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                  style: LenzoType.label.copyWith(
                    color: LenzoColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (helper != null)
          Padding(
            padding: EdgeInsets.only(left: indent, top: 2),
            child: Text(helper!, style: LenzoType.secondary),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

/// Page header: back button, the centred logo (or [title]), and optional
/// trailing actions. 56 px tall, aligned to the screen margin.
class LenzoHeader extends StatelessWidget {
  const LenzoHeader({
    super.key,
    this.onBack,
    this.center,
    this.trailing = const [],
    this.backTooltip = 'Back',
  });

  final VoidCallback? onBack;
  final Widget? center;
  final List<Widget> trailing;
  final String backTooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        // Icon buttons have their own 12 px inset, so 8 + 12 = the 20 px
        // screen margin.
        padding: const EdgeInsets.symmetric(horizontal: LenzoSpacing.x2),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (center != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: FittedBox(fit: BoxFit.scaleDown, child: center),
              ),
            Row(
              children: [
                if (onBack != null)
                  LenzoIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: backTooltip,
                    size: 22,
                    onPressed: onBack,
                  ),
                const Spacer(),
                ...trailing,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill-shaped segmented control on the secondary surface. The mint
/// indicator follows [controller] while its pages are swiped, and slides
/// over on tap.
class LenzoSegmentedControl extends StatelessWidget {
  const LenzoSegmentedControl({
    super.key,
    required this.controller,
    required this.labels,
    this.selected,
  });

  final PageController controller;
  final List<String> labels;

  /// The selected segment, used whenever the pages can't tell (before they
  /// are laid out, or right after their scroll position is recreated, e.g.
  /// when returning from another page). Without it the pill would fall
  /// back to the controller's initial page.
  final int? selected;

  /// Side padding inside each segment, and the track's inset.
  static const _labelPad = LenzoSpacing.x2;
  static const _inset = 3.0;
  static const maxFontSize = 13.0, minFontSize = 10.0;

  static TextStyle _labelStyle(double size) => LenzoType.button.copyWith(
    fontSize: size,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// One font size for every label: 13 px, or smaller (down to 10) until
  /// the longest label fits its segment. All segments then use it, so no
  /// tab looks bigger or smaller than another, selected or not.
  @visibleForTesting
  static double labelFontSize(
    List<String> labels, {
    required double segmentWidth,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final room = segmentWidth - _inset * 2 / labels.length - _labelPad * 2;
    var widest = 0.0;
    for (final l in labels) {
      final tp = TextPainter(
        text: TextSpan(text: l, style: _labelStyle(maxFontSize)),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, tp.width);
      tp.dispose();
    }
    if (widest <= room || widest == 0) return maxFontSize;
    return (maxFontSize * room / widest).clamp(minFontSize, maxFontSize);
  }

  /// Where the pill is, in segments. Read from the scroll offset whenever
  /// there is one (it doesn't need a finished layout), else [selected].
  double _page() {
    if (controller.positions.length == 1) {
      final p = controller.position;
      if (p.hasPixels && p.hasViewportDimension && p.viewportDimension > 0) {
        return p.pixels / p.viewportDimension;
      }
    }
    return (selected ?? controller.initialPage).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: LenzoColors.surface,
        borderRadius: LenzoRadius.pillAll,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final fontSize = labelFontSize(
            labels,
            segmentWidth: box.maxWidth / n,
            textScaler: MediaQuery.textScalerOf(context),
          );
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final t = _page().clamp(0.0, n - 1.0);
              return Stack(
                children: [
                  Align(
                    alignment: Alignment(n == 1 ? 0 : -1 + 2 * t / (n - 1), 0),
                    child: FractionallySizedBox(
                      widthFactor: 1 / n,
                      heightFactor: 1,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: LenzoColors.accent,
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: (t - i).abs() < 0.5,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => controller.animateToPage(
                                i,
                                duration: LenzoMotion.of(
                                  context,
                                  LenzoMotion.tab,
                                ),
                                curve: LenzoMotion.easeInOut,
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: _labelPad,
                                  ),
                                  child: Text(
                                    labels[i],
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.fade,
                                    textAlign: TextAlign.center,
                                    style: _labelStyle(fontSize).copyWith(
                                      color: Color.lerp(
                                        LenzoColors.onAccent,
                                        LenzoColors.textSecondary,
                                        (t - i).abs().clamp(0.0, 1.0),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

/// An amount that counts to its value when shown and glides after edits.
/// Scales down to fit rather than wrapping or cutting.
class LenzoAmount extends StatelessWidget {
  const LenzoAmount(
    this.paise, {
    super.key,
    this.size = 30,
    this.color = LenzoColors.textPrimary,
    this.wholeRupees = false,
    this.compact = true,
  });

  final int paise;
  final double size;
  final Color color;
  final bool wholeRupees;

  /// ₹49.6K style (display only). False shows the exact amount.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: paise.toDouble()),
      duration: LenzoMotion.of(context, LenzoMotion.count),
      curve: LenzoMotion.ease,
      builder: (_, v, _) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          compact
              ? formatRupeesCompact(v.round())
              : wholeRupees
              ? formatRupeesShort(v.round())
              : formatRupees(v.round()),
          maxLines: 1,
          style: LenzoType.amount(size, color: color),
        ),
      ),
    );
  }
}

/// One figure in a [LenzoFinancialCard].
class LenzoFigure {
  const LenzoFigure(this.label, this.paise, {this.color});
  final String label;
  final int paise;

  /// Amount colour; primary text if null.
  final Color? color;
}

/// The financial summary card. One figure: label over a large amount.
/// Two figures: equal halves split by a hairline. [note] sits at the top
/// right (e.g. "2 borrowers"); [footer] runs under the figures.
class LenzoFinancialCard extends StatelessWidget {
  const LenzoFinancialCard({
    super.key,
    required this.figures,
    this.note,
    this.footer,
    this.size = 26,
  });

  final List<LenzoFigure> figures;
  final String? note;
  final Widget? footer;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget figure(LenzoFigure f) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(f.label, maxLines: 1, softWrap: false, style: LenzoType.cardLabel),
        const SizedBox(height: 6),
        LenzoAmount(
          f.paise,
          size: size,
          color: f.color ?? LenzoColors.textPrimary,
        ),
      ],
    );

    final Widget body;
    if (figures.length == 1) {
      body = figure(figures.single);
    } else {
      body = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < figures.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(
                    horizontal: LenzoSpacing.x4,
                  ),
                  color: LenzoColors.border,
                ),
              Expanded(child: figure(figures[i])),
            ],
          ],
        ),
      );
    }
    return LenzoCard(
      padding: const EdgeInsets.all(LenzoSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (note != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(note!, style: LenzoType.secondary),
            ),
          if (note != null && figures.length > 1)
            const SizedBox(height: LenzoSpacing.x2),
          body,
          if (footer != null) ...[
            const SizedBox(height: LenzoSpacing.x4),
            footer!,
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// People
// ---------------------------------------------------------------------------

/// Circular photo with a fallback initial. [path] is a saved image file.
class LenzoAvatar extends StatelessWidget {
  const LenzoAvatar({super.key, required this.image, this.size = 44});
  final Widget image;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: LenzoColors.surfaceSecondary,
        ),
        child: ClipOval(child: image),
      ),
    );
  }
}

/// A person row: photo, name, one supporting line, an optional trailing
/// amount, and up to two icon actions. Compact (68 px), on a small card.
class LenzoPersonTile extends StatelessWidget {
  const LenzoPersonTile({
    super.key,
    required this.avatar,
    required this.name,
    this.subtitle,
    this.subtitleColor,
    this.actions = const [],
    this.onTap,
  });

  final Widget avatar;
  final String name;
  final String? subtitle;
  final Color? subtitleColor;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LenzoCard(
      small: true,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        LenzoSpacing.x3,
        LenzoSpacing.x3,
        LenzoSpacing.x1,
        LenzoSpacing.x3,
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: LenzoSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LenzoType.cardHeading,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LenzoType.secondary.copyWith(
                      fontSize: 13,
                      color: subtitleColor ?? LenzoColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog
// ---------------------------------------------------------------------------

/// Lenzo's confirmation dialog: compact card (85% of the width, at most
/// 400 px, as tall as its content), optional icon or [image], title,
/// message, Cancel and a confirm button. Fades and scales in over a dark
/// scrim. Returns true only for [confirm].
Future<bool> showLenzoDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  String cancel = 'Cancel',
  IconData? icon,
  Widget? image,
  bool destructive = false,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancel,
    barrierColor: LenzoColors.ink.withValues(alpha: 0.65),
    transitionDuration: LenzoMotion.of(
      context,
      const Duration(milliseconds: 200),
    ),
    pageBuilder: (_, _, _) => _LenzoDialog(
      title: title,
      message: message,
      confirm: confirm,
      cancel: cancel,
      icon: icon,
      image: image,
      destructive: destructive,
    ),
    transitionBuilder: (_, animation, _, child) {
      final a = CurvedAnimation(
        parent: animation,
        curve: LenzoMotion.ease,
        reverseCurve: LenzoMotion.exit,
      );
      return FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.95, end: 1.0).animate(a),
          child: child,
        ),
      );
    },
  ).then((ok) => ok ?? false);
}

class _LenzoDialog extends StatelessWidget {
  const _LenzoDialog({
    required this.title,
    required this.message,
    required this.confirm,
    required this.cancel,
    required this.destructive,
    this.icon,
    this.image,
  });

  final String title, message, confirm, cancel;
  final IconData? icon;
  final Widget? image;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tone = destructive ? LenzoColors.danger : LenzoColors.accent;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.85, 400.0);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: width,
              padding: const EdgeInsets.fromLTRB(
                LenzoSpacing.x5,
                LenzoSpacing.x6,
                LenzoSpacing.x5,
                LenzoSpacing.x5,
              ),
              decoration: BoxDecoration(
                color: LenzoColors.surface,
                borderRadius: LenzoRadius.cardAll,
                border: Border.all(color: LenzoColors.border),
                boxShadow: LenzoShadows.raised,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (image != null) ...[
                    LenzoAvatar(image: image!, size: 88),
                    const SizedBox(height: LenzoSpacing.x4),
                  ] else if (icon != null) ...[
                    Container(
                      width: LenzoSpacing.tap,
                      height: LenzoSpacing.tap,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone.withValues(alpha: 0.12),
                      ),
                      child: Icon(icon, color: tone, size: 20),
                    ),
                    const SizedBox(height: LenzoSpacing.x4),
                  ],
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: LenzoType.sectionHeading,
                  ),
                  const SizedBox(height: LenzoSpacing.x2),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: LenzoType.body.copyWith(
                      color: LenzoColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: LenzoSpacing.x6),
                  LenzoButtonPair(
                    cancel: cancel,
                    confirm: confirm,
                    destructive: destructive,
                    compact: false,
                    onCancel: () => Navigator.of(context).pop(false),
                    onConfirm: () => Navigator.of(context).pop(true),
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
