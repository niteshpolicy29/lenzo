import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// Swaps [child] when [contentKey] changes: the old content fades out
/// completely, then the new content fades in. Unlike a crossfade, the two
/// are never drawn on top of each other, and nothing moves or resizes; give
/// it a fixed size. [duration] is the whole swap (out + in). Changes while
/// a swap runs jump straight to the latest content. Instant with Android's
/// "Remove animations".
class FadeSwap extends StatefulWidget {
  const FadeSwap({
    super.key,
    required this.contentKey,
    required this.child,
    this.duration = const Duration(milliseconds: 180),
  });

  final Object contentKey;
  final Widget child;
  final Duration duration;

  @override
  State<FadeSwap> createState() => _FadeSwapState();
}

class _FadeSwapState extends State<FadeSwap>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, value: 1);
  late Object _shownKey = widget.contentKey;
  late Widget _shown = widget.child;
  bool _running = false;

  @override
  void didUpdateWidget(FadeSwap old) {
    super.didUpdateWidget(old);
    if (widget.contentKey == _shownKey) {
      // Same content, new state (e.g. another day selected): show it now.
      _shown = widget.child;
    } else {
      _swap();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Future<void> _swap() async {
    if (_running) return;
    _running = true;
    final half = LenzoMotion.of(context, widget.duration) * 0.5;
    while (mounted && widget.contentKey != _shownKey) {
      await _fade.animateTo(0, duration: half, curve: LenzoMotion.exit);
      if (!mounted) return;
      setState(() {
        _shownKey = widget.contentKey;
        _shown = widget.child;
      });
    }
    if (!mounted) return;
    await _fade.animateTo(1, duration: half, curve: LenzoMotion.ease);
    _running = false;
    // Content may have changed during the fade-in.
    if (mounted && widget.contentKey != _shownKey) _swap();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: KeyedSubtree(key: ValueKey(_shownKey), child: _shown),
    );
  }
}
