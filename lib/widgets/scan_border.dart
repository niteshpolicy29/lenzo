import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// What the camera border tells the user.
enum ScanState {
  /// No face in view: the plain border, nothing animates.
  idle,

  /// A face is in view and still being checked: mint glow with a
  /// highlight travelling around the border.
  searching,

  /// Every face in view is a confirmed saved person: one bright mint
  /// pulse, then the plain border.
  recognized,

  /// A face confirmed as not saved: a still, soft amber glow (scanning is
  /// finished, so nothing moves).
  unknown,
}

/// The border state for the faces in view, from each face's recognition
/// result: a person id (> 0), 0 for a confirmed unknown face, -1 for "not
/// sure", or null while still checking.
///
/// No faces: idle. Any face still being checked (or not sure) keeps the
/// border searching, so a face is never shown as unknown just because
/// recognition hasn't finished. Otherwise one confirmed unknown face makes
/// it amber, and only when everyone is recognized does it show success.
ScanState scanStateFor(Iterable<int?> results) {
  var any = false, unknown = false;
  for (final r in results) {
    any = true;
    if (r == null || r < 0) return ScanState.searching;
    if (r == 0) unknown = true;
  }
  if (!any) return ScanState.idle;
  return unknown ? ScanState.unknown : ScanState.recognized;
}

/// Animated glow around a rounded-rectangle camera frame. Fill its parent
/// with it (it ignores touches); it draws only near the edge.
///
/// - [ScanState.idle]: nothing is drawn and nothing animates.
/// - [ScanState.searching]: a 1.6 px mint line at 15–30% opacity that
///   breathes, with a brighter highlight going once round the border every
///   2 s, following the corners. The only state that animates continuously.
/// - [ScanState.recognized]: the highlight fades while the border lights up
///   once (≈ 0.25 s up, 0.7 s down), then nothing is drawn.
/// - [ScanState.unknown]: the glow turns amber and holds still at 30%.
///
/// Changes fade (about 0.45 s); nothing jumps.
///
/// A state must hold for [settle] before it is shown, so one odd frame
/// never makes the colour flicker (recognition is shown at once).
/// Animations stop while [active] is false (camera closed, app in the
/// background, another page on screen).
class ScanBorder extends StatefulWidget {
  const ScanBorder({
    super.key,
    required this.state,
    required this.radius,
    this.active = true,
    this.settle = const Duration(milliseconds: 250),
  });

  final ScanState state;
  final double radius;
  final bool active;
  final Duration settle;

  static const loop = Duration(milliseconds: 2000);

  @override
  State<ScanBorder> createState() => _ScanBorderState();
}

class _ScanBorderState extends State<ScanBorder> with TickerProviderStateMixin {
  /// 0 → 1 once per [ScanBorder.loop]: highlight position and breathing.
  late final _loop = AnimationController(
    vsync: this,
    duration: ScanBorder.loop,
  );

  /// How visible the scanning glow is (0 = hidden).
  late final _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  /// 0 = mint, 1 = amber.
  late final _tone = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  /// How much the scan is moving: the travelling highlight and the
  /// breathing (1 while searching, 0 otherwise).
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  /// The success pulse, 0 → 1 → 0.
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  late ScanState _shown = widget.state;

  /// 0 = mint, 1 = amber (for tests).
  @visibleForTesting
  double get toneValue => _tone.value;
  Timer? _pending;

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _glow.value = _glowFor(_shown);
    _motion.value = _shown == ScanState.searching ? 1 : 0;
    _tone.value = _shown == ScanState.unknown ? 1 : 0;
    _motion.addStatusListener((_) => _updateLoop());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateLoop();
  }

  @override
  void didUpdateWidget(ScanBorder old) {
    super.didUpdateWidget(old);
    if (widget.state != old.state) _schedule(widget.state);
    if (widget.active != old.active) _updateLoop();
  }

  @override
  void dispose() {
    _pending?.cancel();
    _loop.dispose();
    _glow.dispose();
    _tone.dispose();
    _pulse.dispose();
    _motion.dispose();
    super.dispose();
  }

  void _schedule(ScanState next) {
    _pending?.cancel();
    if (next == _shown) return;
    if (next == ScanState.recognized || widget.settle == Duration.zero) {
      _show(next);
    } else {
      _pending = Timer(widget.settle, () {
        if (mounted && widget.state == next) _show(next);
      });
    }
  }

  static double _glowFor(ScanState s) =>
      s == ScanState.searching || s == ScanState.unknown ? 1 : 0;

  void _show(ScanState next) {
    final before = _shown;
    _shown = next;
    Duration? d(Duration? normal) => _reduceMotion ? Duration.zero : normal;
    _glow.animateTo(_glowFor(next), duration: d(null));
    _motion.animateTo(next == ScanState.searching ? 1 : 0, duration: d(null));
    if (next == ScanState.unknown) {
      _tone.animateTo(1, duration: d(null));
    } else if (next == ScanState.searching) {
      _tone.animateTo(0, duration: d(null));
    }
    if (next == ScanState.recognized) {
      _tone.animateTo(0, duration: d(null));
      if (before != ScanState.recognized && widget.active && !_reduceMotion) {
        _pulse.forward(from: 0);
      }
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
    _updateLoop();
  }

  /// The travelling highlight runs only while it can be seen: when
  /// searching, and while it fades out after.
  void _updateLoop() {
    if (!mounted) return;
    final moving = _motion.value > 0 || _motion.isAnimating;
    if (widget.active && moving && !_reduceMotion) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
    }
    if (!widget.active) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ScanBorderPainter(
            loop: _loop,
            glow: _glow,
            tone: _tone,
            pulse: _pulse,
            motion: _motion,
            radius: widget.radius,
            moving: !_reduceMotion,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _ScanBorderPainter extends CustomPainter {
  _ScanBorderPainter({
    required this.loop,
    required this.glow,
    required this.tone,
    required this.pulse,
    required this.motion,
    required this.radius,
    required this.moving,
  }) : super(repaint: Listenable.merge([loop, glow, tone, pulse, motion]));

  final Animation<double> loop, glow, tone, pulse, motion;
  final double radius;
  final bool moving;

  /// Fraction of the border the highlight covers.
  static const _tail = 0.18;
  static const _pieces = 10;

  Path? _path;
  ui.PathMetric? _metric;
  Size? _forSize;

  ui.PathMetric _metricFor(Size size) {
    if (_forSize != size || _metric == null) {
      final inset = (Offset.zero & size).deflate(0.8);
      _path = Path()
        ..addRRect(RRect.fromRectAndRadius(inset, Radius.circular(radius)));
      _metric = _path!.computeMetrics().first;
      _forSize = size;
    }
    return _metric!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = glow.value;
    final p = _pulseCurve(pulse.value);
    if (g <= 0.001 && p <= 0.001) return;
    final color = Color.lerp(
      LenzoColors.accent,
      LenzoColors.payable,
      Curves.easeInOut.transform(tone.value),
    )!;
    final metric = _metricFor(size);
    final t = loop.value;
    final m = motion.value;
    // Breathing while searching: 15% → 30% → 15% once per loop (seamless
    // as t wraps); still at 30% otherwise (the amber result).
    final breathing = 0.15 + 0.15 * (0.5 - 0.5 * math.cos(2 * math.pi * t));
    final breath = 0.3 + (breathing - 0.3) * m;

    // Base line and soft glow.
    final baseAlpha = (breath * g + 0.65 * p).clamp(0.0, 1.0);
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.8),
      Radius.circular(radius),
    );
    // Soft glow from three wider, fainter strokes (no blur filter: a blur
    // would be re-rasterised every frame).
    for (final (width, share) in const [
      (9.0, 0.10),
      (6.0, 0.16),
      (3.5, 0.24),
    ]) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color.withValues(alpha: baseAlpha * share),
      );
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 + 0.4 * p
        ..color = color.withValues(alpha: baseAlpha),
    );

    // Travelling highlight with a fading tail (scanning only).
    if (!moving || g * m <= 0.001) return;
    final total = metric.length;
    final head = t * total;
    final piece = total * _tail / _pieces;
    for (var i = 0; i < _pieces; i++) {
      final a = (1 - i / _pieces) * 0.85 * g * m;
      var end = head - i * piece;
      var start = end - piece;
      // Wrap round the start of the path.
      if (end < 0) {
        end += total;
        start += total;
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: a);
      if (start < 0) {
        canvas.drawPath(metric.extractPath(start + total, total), paint);
        canvas.drawPath(metric.extractPath(0, end), paint);
      } else {
        canvas.drawPath(metric.extractPath(start, end), paint);
      }
    }
  }

  /// 0 → 1 quickly, then back to 0 slowly.
  static double _pulseCurve(double v) {
    if (v <= 0) return 0;
    if (v < 0.25) return Curves.easeOut.transform(v / 0.25);
    return 1 - Curves.easeInOut.transform((v - 0.25) / 0.75);
  }

  @override
  bool shouldRepaint(_ScanBorderPainter old) =>
      old.radius != radius || old.moving != moving;
}
