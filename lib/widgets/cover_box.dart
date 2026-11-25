import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Fills all the space it is given with [child], like `BoxFit.cover`: the
/// child keeps its own shape ([aspectRatio], width / height), is scaled just
/// enough to cover the box, centred, and the overflow is clipped. Nothing is
/// stretched.
///
/// It always takes the full size offered, even under loose constraints
/// (inside a [Stack] or [AnimatedSwitcher]), so it can't shrink into a
/// narrow strip.
class CoverBox extends StatelessWidget {
  const CoverBox({super.key, required this.aspectRatio, required this.child})
    : assert(aspectRatio > 0);

  /// Width / height of the child's content, e.g. 9 / 16 for a portrait
  /// camera picture.
  final double aspectRatio;
  final Widget child;

  /// Size of the child for a box of [box]: the smallest size with
  /// [aspectRatio] that covers it.
  static Size coverSize(Size box, double aspectRatio) {
    final w = math.max(box.width, box.height * aspectRatio);
    return Size(w, w / aspectRatio);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, box) {
            final s = coverSize(box.biggest, aspectRatio);
            return OverflowBox(
              minWidth: s.width,
              maxWidth: s.width,
              minHeight: s.height,
              maxHeight: s.height,
              child: child,
            );
          },
        ),
      ),
    );
  }
}
