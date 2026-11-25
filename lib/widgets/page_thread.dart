import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// Marks a subtree whose page background is painted once underneath it
/// (by the pager on Home), so [LenzoBackdrop] inside it stays transparent
/// and the thread behind the pages shows through.
class SharedBackground extends InheritedWidget {
  const SharedBackground({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SharedBackground>() != null;

  @override
  bool updateShouldNotify(SharedBackground old) => false;
}

/// Sends a pulse of light along the thread: a new connection. Fired when a
/// face is recognised and when a person is saved, never on a timer.
class ThreadPulse {
  ThreadPulse._();
  static final instance = ThreadPulse._();

  final _count = ValueNotifier<int>(0);

  /// Number of pulses sent so far; listen to it to play them.
  ValueListenable<int> get pulses => _count;

  void fire() => _count.value++;
}

/// The thread of connections behind Lenzo's three main pages.
///
/// The three pages are one wide canvas (Settings, Home, Saved People, side
/// by side) and the thread is one line across all of it: it comes in from
/// beyond the left edge of Settings (your identity), passes behind the
/// camera on Home (recognising people), and leaves past the right edge of
/// Saved People (your connections and money). It is drawn in the pages'
/// own coordinates, so a swipe moves it exactly with the pages, either way,
/// and it never restarts. It is behind all content and never touches it:
/// on Settings and Saved People it runs low, through the empty space under
/// the cards.
///
/// It drifts slowly in soft curves on its own; with "Remove animations" it
/// stays still. A [ThreadPulse] sends one soft light along it, left to
/// right.
class PageThread extends StatefulWidget {
  const PageThread({super.key, required this.pages, required this.pageCount});

  final PageController pages;
  final int pageCount;

  /// How long a pulse takes to cross all the pages.
  static const pulseDuration = Duration(milliseconds: 1800);

  @override
  State<PageThread> createState() => _PageThreadState();
}

class _PageThreadState extends State<PageThread> with TickerProviderStateMixin {
  /// Seconds since the thread appeared (grows forever, no loop to restart).
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((elapsed) {
    _time.value = elapsed.inMicroseconds / 1e6;
  });
  late final _pulse = AnimationController(
    vsync: this,
    duration: PageThread.pulseDuration,
  );

  /// Whether a pulse is travelling (for tests).
  @visibleForTesting
  bool get pulsing => _pulse.isAnimating;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    ThreadPulse.instance.pulses.addListener(_onPulse);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still && _ticker.isActive) _ticker.stop();
    if (!_still && !_ticker.isActive) _ticker.start();
  }

  void _onPulse() {
    if (!mounted || _still) return;
    _pulse.forward(from: 0);
  }

  @override
  void dispose() {
    ThreadPulse.instance.pulses.removeListener(_onPulse);
    _ticker.dispose();
    _pulse.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: PageThreadPainter(
            pages: widget.pages,
            pageCount: widget.pageCount,
            time: _time,
            pulse: _pulse,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class PageThreadPainter extends CustomPainter {
  PageThreadPainter({
    required this.pages,
    required this.pageCount,
    required this.time,
    required this.pulse,
    double? page,
  }) : _fixedPage = page,
       super(repaint: Listenable.merge([pages, time, pulse]));

  final PageController pages;
  final int pageCount;
  final ValueListenable<double> time;
  final Animation<double> pulse;
  final double? _fixedPage;

  /// The course (fraction of the page height) at the middle of each page:
  /// low on Settings, under the profile cards; behind the camera on Home;
  /// low again on Saved People, under the list.
  static const course = [0.84, 0.46, 0.88];

  /// Where the thread starts and ends, in page widths: beyond the left edge
  /// of the first page and the right edge of the last.
  static const start = -0.25;
  double get end => pageCount + 0.25;

  /// How far the drift moves the thread, as a fraction of the height.
  static const drift = 0.035;

  double get _page {
    if (_fixedPage != null) return _fixedPage;
    return pages.hasClients && pages.position.haveDimensions
        ? pages.page ?? pages.initialPage.toDouble()
        : pages.initialPage.toDouble();
  }

  /// The course height (fraction of the page) at [xWorld]: smooth S-curves
  /// joining the points in [course]; level beyond the first and last.
  static double courseAt(double xWorld) {
    final p = (xWorld - 0.5).clamp(0.0, course.length - 1.0);
    final i = p.floor().clamp(0, course.length - 2);
    final f = p - i;
    final s = 0.5 - 0.5 * math.cos(math.pi * f);
    return course[i] + (course[i + 1] - course[i]) * s;
  }

  /// The slow wander at [xWorld] and [t] seconds, in −1…1: three waves of
  /// unrelated speeds and lengths, so the shape never repeats exactly.
  static double wander(double xWorld, double t) =>
      (math.sin(2 * math.pi * (xWorld * 0.55 + t * 0.045)) * 0.5 +
      math.sin(2 * math.pi * (xWorld * 1.3 - t * 0.071) + 1.7) * 0.32 +
      math.sin(2 * math.pi * (xWorld * 2.9 + t * 0.113) + 4.1) * 0.18);

  /// Thread height at [xWorld] for a page area [height] tall at time [t].
  static double lineY(double xWorld, double t, double height) =>
      height * (courseAt(xWorld) + drift * wander(xWorld, t));

  /// Where the pulse's light is (in page widths) at [progress] 0–1: it
  /// enters from beyond the left end and leaves beyond the right one.
  double pulseAt(double progress) =>
      start - pulseLength + (end - start + 2 * pulseLength) * progress;

  /// Length of the pulse's light, in page widths.
  static const pulseLength = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final page = _page;
    final t = time.value;
    // Slightly brighter mid-swipe.
    final between = math.sin(math.pi * (page - page.floorToDouble()));
    final strength = 1 + 0.35 * between;

    // The visible part, extended a step past both edges so the line runs
    // off the screen.
    Path pathBetween(double fromWorld, double toWorld) {
      const step = 8.0;
      final x0 = (fromWorld - page) * w, x1 = (toWorld - page) * w;
      final path = Path()..moveTo(x0, lineY(fromWorld, t, h));
      for (var x = x0 + step; x < x1; x += step) {
        path.lineTo(x, lineY(x / w + page, t, h));
      }
      path.lineTo(x1, lineY(toWorld, t, h));
      return path;
    }

    final from = math.max(start, page - 0.05);
    final to = math.min(end, page + 1.05);
    if (to <= from) return;
    final line = pathBetween(from, to);
    for (final (width, alpha) in const [(7.0, 0.05), (3.2, 0.1), (1.2, 0.42)]) {
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = LenzoColors.accent.withValues(
            alpha: (alpha * strength).clamp(0.0, 1.0),
          ),
      );
    }

    // The pulse: a soft light travelling along the same line.
    final pv = pulse.value;
    if (pv <= 0 || pv >= 1) return;
    final head = pulseAt(Curves.easeInOut.transform(pv));
    final tail = head - pulseLength;
    final a = math.max(tail, from), b = math.min(head, to);
    if (b <= a) return;
    // Fades in and out over its run, so it never pops.
    final life = math.sin(math.pi * pv);
    final hx0 = (tail - page) * w, hx1 = (head - page) * w;
    final shader = LinearGradient(
      colors: [
        LenzoColors.accent.withValues(alpha: 0),
        LenzoColors.accent.withValues(alpha: 0.9 * life),
      ],
    ).createShader(Rect.fromLTRB(hx0, 0, math.max(hx1, hx0 + 1), h));
    final glow = pathBetween(a, b);
    for (final (width, alpha) in const [(10.0, 0.18), (4.0, 0.4), (1.6, 1.0)]) {
      canvas.drawPath(
        glow,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = shader
          ..color = Color.fromRGBO(0, 0, 0, alpha),
      );
    }
  }

  @override
  bool shouldRepaint(PageThreadPainter old) =>
      old.pageCount != pageCount ||
      old._fixedPage != _fixedPage ||
      old.time != time ||
      old.pulse != pulse ||
      old.pages != pages;
}
