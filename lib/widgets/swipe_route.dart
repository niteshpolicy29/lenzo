import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show VelocityTracker;
import 'package:material_ui/material_ui.dart';

import '../theme/lenzo_theme.dart';

/// Page route that slides in from the right over the current page, which
/// drifts a little to the left and darkens (parallax). Swiping the page to
/// the right (see [LenzoSwipeBack]) drags it back off, following the finger.
///
/// [startAt] continues a page the user has already pulled part way in by
/// hand (see the camera screen) from that point.
class LenzoSwipeRoute<T> extends PageRoute<T> {
  LenzoSwipeRoute({required this.builder, this.startAt = 0, super.settings});

  final WidgetBuilder builder;
  final double startAt;

  static const forwardDuration = Duration(milliseconds: 260);
  static const reverseDuration = Duration(milliseconds: 220);

  /// How far the page underneath moves left, as a fraction of its width.
  static const parallax = 0.28;

  /// True while the user is dragging this route back.
  bool _gesture = false;

  @override
  Duration get transitionDuration => forwardDuration;
  @override
  Duration get reverseTransitionDuration => reverseDuration;
  @override
  bool get opaque => true;
  @override
  bool get maintainState => true;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;

  static Duration _scaled(Duration d, double fraction) =>
      d * fraction.clamp(0.35, 1.0);

  // The controller is driven directly: drags set its value, and the easing
  // is applied when animating, so the transition itself stays linear and a
  // drag maps 1:1 to the finger.

  @override
  TickerFuture didPush() {
    super.didPush();
    final c = controller!..stop();
    if (startAt <= 0) {
      c.value = 0;
      return c.animateTo(
        1,
        duration: forwardDuration,
        curve: Curves.easeOutCubic,
      );
    }
    // Continue from the finger's position. The controller is left stopped
    // there for this moment: the page underneath links its parallax to this
    // route right after this call (it follows directly only if this route
    // isn't animating then), and a route that isn't at 0 is never hidden
    // for a frame by the Hero logic. The slide starts straight after.
    c.value = startAt;
    scheduleMicrotask(() {
      if (!isActive || c.isAnimating) return;
      c.animateTo(
        1,
        duration: _scaled(forwardDuration, 1 - startAt),
        curve: Curves.easeOutCubic,
      );
    });
    return TickerFuture.complete();
  }

  /// How far the page is in, 0 (off screen) to 1 (fully open).
  double get progress => controller?.value ?? 0;

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    final c = controller!..stop();
    c.animateBack(
      0,
      duration: _scaled(reverseDuration, c.value),
      // A released drag is already moving, so only ease out.
      curve: _gesture ? Curves.easeOutCubic : Curves.easeInOutCubic,
    );
    return popped;
  }

  void _backStart() {
    _gesture = true;
    controller!.stop();
    navigator?.didStartUserGesture();
  }

  void _backUpdate(double value) => controller!.value = value.clamp(0.0, 1.0);

  void _backEnd({required bool stay}) {
    final c = controller!;
    if (stay) {
      c
          .animateTo(
            1,
            duration: _scaled(forwardDuration, 1 - c.value),
            curve: Curves.easeOutCubic,
          )
          .whenCompleteOrCancel(_stopGesture);
    } else {
      navigator?.pop();
      _stopGesture();
    }
  }

  void _stopGesture() {
    if (!_gesture) return;
    _gesture = false;
    navigator?.didStopUserGesture();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final page = SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(animation),
      child: pageFrame(child),
    );
    // A page opening on top (another swipe route) pushes this one aside.
    return AnimatedBuilder(
      animation: secondaryAnimation,
      builder: (_, child) => underneath(secondaryAnimation.value, child!),
      child: page,
    );
  }

  /// The page underneath follows this route's progress.
  @override
  DelegatedTransitionBuilder? get delegatedTransition => _delegated;

  static Widget? _delegated(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    return AnimatedBuilder(
      animation: secondaryAnimation,
      builder: (_, child) => underneath(secondaryAnimation.value, child!),
      child: child,
    );
  }

  /// The page underneath at progress [t] (0 = untouched, 1 = covered).
  /// Always the same widget structure, so its state is kept at t = 0.
  static Widget underneath(double t, Widget child) {
    return FractionalTranslation(
      translation: Offset(-parallax * t, 0),
      // Not dimmed: both pages keep the one background colour.
      child: child,
    );
  }

  /// The incoming page, on the one background colour.
  static Widget pageFrame(Widget child) {
    return ColoredBox(color: Lenzo.background, child: child);
  }
}

/// Lets the user drag the current [LenzoSwipeRoute] page to the right to go
/// back. The page follows the finger; letting go past halfway, or with a
/// quick flick, finishes going back, otherwise it settles in place again.
class LenzoSwipeBack extends StatelessWidget {
  const LenzoSwipeBack({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final usable = enabled && route is LenzoSwipeRoute;
    return HorizontalSwipe(
      toLeft: false,
      enabled: usable,
      onStart: () {
        final r = route as LenzoSwipeRoute;
        if (!r.isCurrent || (r.navigator?.userGestureInProgress ?? true)) {
          return false;
        }
        FocusManager.instance.primaryFocus?.unfocus();
        r._backStart();
        return true;
      },
      onUpdate: (distance) {
        final w = MediaQuery.sizeOf(context).width;
        (route as LenzoSwipeRoute)._backUpdate(1 - distance / w);
      },
      onEnd: (velocity) {
        final r = route as LenzoSwipeRoute;
        final value = r.progress;
        final back = velocity > 650 || (velocity > -650 && value < 0.5);
        r._backEnd(stay: !back);
      },
      child: child,
    );
  }
}

/// Recognizes a horizontal swipe in one direction without taking part in
/// the gesture arena, so it works over lists, cards and the camera preview.
/// Vertical movement or a swipe the other way is ignored.
class HorizontalSwipe extends StatefulWidget {
  const HorizontalSwipe({
    super.key,
    required this.child,
    required this.toLeft,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.enabled = true,
  });

  final Widget child;

  /// Direction that starts the swipe: right-to-left if true.
  final bool toLeft;
  final bool enabled;

  /// Return false to ignore this swipe.
  final bool Function() onStart;

  /// Distance moved in the swipe direction since it started (never < 0).
  final ValueChanged<double> onUpdate;

  /// Velocity in the swipe direction when released, in px/s (negative if
  /// moving back the other way).
  final ValueChanged<double> onEnd;

  @override
  State<HorizontalSwipe> createState() => _HorizontalSwipeState();
}

class _HorizontalSwipeState extends State<HorizontalSwipe> {
  static const _slop = 12.0;

  int? _pointer;
  Offset _start = Offset.zero;
  bool _active = false;
  VelocityTracker? _velocity;

  double _along(Offset d) => widget.toLeft ? -d.dx : d.dx;

  void _reset() {
    _pointer = null;
    _active = false;
    _velocity = null;
  }

  void _down(PointerDownEvent e) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = e.pointer;
    _start = e.position;
    _active = false;
    _velocity = VelocityTracker.withKind(e.kind)
      ..addPosition(e.timeStamp, e.position);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _velocity?.addPosition(e.timeStamp, e.position);
    final d = e.position - _start;
    if (_active) {
      widget.onUpdate(math.max(0, _along(d)));
      return;
    }
    final along = _along(d);
    if (d.dy.abs() > _slop && d.dy.abs() > d.dx.abs()) {
      _reset(); // vertical: leave it to scrolling
    } else if (along < -_slop) {
      _reset(); // the other direction
    } else if (along > _slop && along > d.dy.abs() * 1.4) {
      if (!widget.onStart()) {
        _reset();
        return;
      }
      _active = true;
      _start = e.position; // start from 0, without a jump
    }
  }

  void _up(PointerEvent e, {required bool cancelled}) {
    if (e.pointer != _pointer) return;
    if (_active) {
      final v = cancelled ? 0.0 : _velocity!.getVelocity().pixelsPerSecond.dx;
      _reset();
      widget.onEnd(widget.toLeft ? -v : v);
      return;
    }
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (e) => _up(e, cancelled: false),
      onPointerCancel: (e) => _up(e, cancelled: true),
      child: widget.child,
    );
  }
}
