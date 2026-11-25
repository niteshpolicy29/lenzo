import 'dart:async';

import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// One line of guidance and its colour.
@immutable
class GuideMessage {
  const GuideMessage(this.text, {this.color = LenzoColors.textSecondary});
  final String text;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is GuideMessage && other.text == text && other.color == color;

  @override
  int get hashCode => Object.hash(text, color);
}

/// Shows exactly one [GuideMessage] at a time. A new message replaces the
/// old one in sequence: the old one fades out completely (90 ms), then the
/// new one fades in (140 ms). Two messages are never on screen together.
///
/// Each message stays at least [minHold] so fast-changing hints (one per
/// camera frame) don't flicker; only the latest waiting message is shown
/// next. With Android's "Remove animations" on, messages swap instantly.
/// Changes are announced to screen readers.
class SingleMessage extends StatefulWidget {
  const SingleMessage({
    super.key,
    required this.message,
    this.minHold = const Duration(milliseconds: 450),
    this.style = const TextStyle(
      fontFamily: 'Manrope',
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.35,
    ),
  });

  final GuideMessage message;
  final Duration minHold;
  final TextStyle style;

  static const fadeOut = Duration(milliseconds: 90);
  static const fadeIn = Duration(milliseconds: 140);

  @override
  State<SingleMessage> createState() => _SingleMessageState();
}

class _SingleMessageState extends State<SingleMessage>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, value: 1);
  late GuideMessage _shown = widget.message;
  Timer? _hold;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    _startHold();
  }

  @override
  void didUpdateWidget(SingleMessage old) {
    super.didUpdateWidget(old);
    _next();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _fade.dispose();
    super.dispose();
  }

  void _startHold() {
    _hold?.cancel();
    _hold = Timer(widget.minHold, () {
      _hold = null;
      _next();
    });
  }

  /// Moves to the latest message, unless one is still changing or being
  /// held; those call this again when they finish.
  Future<void> _next() async {
    if (!mounted || _changing || _hold != null) return;
    if (widget.message == _shown) return;
    _changing = true;
    await _fade.animateTo(
      0,
      duration: LenzoMotion.of(context, SingleMessage.fadeOut),
    );
    if (!mounted) return;
    setState(() => _shown = widget.message);
    await _fade.animateTo(
      1,
      duration: LenzoMotion.of(context, SingleMessage.fadeIn),
    );
    if (!mounted) return;
    _changing = false;
    _startHold();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: FadeTransition(
        opacity: _fade,
        child: Text(
          _shown.text,
          key: const ValueKey('single-message'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: widget.style.copyWith(color: _shown.color),
        ),
      ),
    );
  }
}
