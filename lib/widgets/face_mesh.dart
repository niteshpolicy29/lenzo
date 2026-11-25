import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/scheduler.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/lenzo_theme.dart';

// ---------------------------------------------------------------------------
// Mesh geometry
// ---------------------------------------------------------------------------

/// Tracking points for one face, all taken from detected facial features.
class FaceMesh {
  const FaceMesh({
    required this.kind,
    required this.points,
    required this.edges,
    required this.major,
  });

  /// 'contour' (dense, follows expressions) or 'landmark' (sparse).
  final String kind;

  /// Points in upright image coordinates (same as [Face.boundingBox]).
  final List<Offset> points;

  /// Thin lines between point indexes.
  final List<(int, int)> edges;

  /// Points drawn slightly larger, with a small number beside them.
  final List<int> major;
}

Offset _o(math.Point<int> p) => Offset(p.x.toDouble(), p.y.toDouble());

/// Mesh from ML Kit contours: face outline, eyebrows, eyes, nose and lips.
/// These points move with head turns and expressions (smiling, talking,
/// raising eyebrows). Returns null if the face has no contours.
FaceMesh? meshFromContours(Face face) {
  List<Offset> c(FaceContourType t) =>
      face.contours[t]?.points.map(_o).toList() ?? const [];

  final oval = c(FaceContourType.face);
  final browA = c(FaceContourType.leftEyebrowTop);
  final browB = c(FaceContourType.rightEyebrowTop);
  final eyeA = c(FaceContourType.leftEye);
  final eyeB = c(FaceContourType.rightEye);
  final bridge = c(FaceContourType.noseBridge);
  final noseBottom = c(FaceContourType.noseBottom);
  final upperLip = c(FaceContourType.upperLipTop);
  final lowerLip = c(FaceContourType.lowerLipBottom);
  if ([
    oval,
    browA,
    browB,
    eyeA,
    eyeB,
    bridge,
    noseBottom,
    upperLip,
    lowerLip,
  ].any((l) => l.length < 2)) {
    return null;
  }

  // Sample evenly so the mesh stays light: a point at fraction f of a list.
  Offset at(List<Offset> l, double f) => l[(f * (l.length - 1)).round()];

  final pts = <Offset>[];
  int add(Offset p) {
    pts.add(p);
    return pts.length - 1;
  }

  // Face outline: 12 points, starting at the top of the forehead.
  const ovalN = 12;
  final ovalIdx = [
    for (var k = 0; k < ovalN; k++)
      add(oval[(k * oval.length / ovalN).floor()]),
  ];
  final bA = [
    for (final f in [0.0, 0.5, 1.0]) add(at(browA, f)),
  ];
  final bB = [
    for (final f in [0.0, 0.5, 1.0]) add(at(browB, f)),
  ];
  final eA = [
    for (final f in [0.0, 0.25, 0.5, 0.75]) add(at(eyeA, f)),
  ];
  final eB = [
    for (final f in [0.0, 0.25, 0.5, 0.75]) add(at(eyeB, f)),
  ];
  final noseTop = add(bridge.first);
  final noseTip = add(bridge.last);
  final nB = [
    for (final f in [0.0, 0.5, 1.0]) add(at(noseBottom, f)),
  ];
  final mouthA = add(upperLip.first);
  final mouthTop = add(at(upperLip, 0.5));
  final mouthB = add(upperLip.last);
  final mouthBottom = add(at(lowerLip, 0.5));

  int nearest(int from, List<int> among) {
    var best = among.first;
    var bestD = double.infinity;
    for (final i in among) {
      final d = (pts[i] - pts[from]).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  final edges = <(int, int)>[
    for (var k = 0; k < ovalN; k++) (ovalIdx[k], ovalIdx[(k + 1) % ovalN]),
    (bA[0], bA[1]),
    (bA[1], bA[2]),
    (bB[0], bB[1]),
    (bB[1], bB[2]),
    for (final e in [eA, eB])
      for (var k = 0; k < 4; k++) (e[k], e[(k + 1) % 4]),
    (noseTop, noseTip),
    (noseTip, nB[0]),
    (noseTip, nB[2]),
    (nB[0], nB[1]),
    (nB[1], nB[2]),
    (mouthA, mouthTop),
    (mouthTop, mouthB),
    (mouthA, mouthBottom),
    (mouthBottom, mouthB),
  ];
  for (final brow in [bA, bB]) {
    // Inner brow end to the top of the nose, outer end to the face outline.
    final inner = nearest(noseTop, [brow.first, brow.last]);
    final outer = inner == brow.first ? brow.last : brow.first;
    edges
      ..add((inner, noseTop))
      ..add((outer, nearest(outer, ovalIdx)));
  }
  for (final eye in [eA, eB]) {
    final inner = nearest(noseTop, eye);
    final outer = eye.reduce(
      (a, b) =>
          (pts[a] - pts[noseTop]).distanceSquared >
              (pts[b] - pts[noseTop]).distanceSquared
          ? a
          : b,
    );
    edges
      ..add((inner, noseTop))
      ..add((outer, nearest(outer, ovalIdx)));
  }
  for (final corner in [mouthA, mouthB]) {
    edges
      ..add((corner, nearest(corner, [nB[0], nB[2]])))
      ..add((corner, nearest(corner, ovalIdx)));
  }
  edges.add((mouthBottom, nearest(mouthBottom, ovalIdx)));

  return FaceMesh(
    kind: 'contour',
    points: pts,
    edges: edges,
    major: [
      ovalIdx[0],
      ovalIdx[ovalN ~/ 4],
      ovalIdx[ovalN * 3 ~/ 4],
      noseTip,
      ovalIdx[ovalN ~/ 2],
    ],
  );
}

/// Sparse mesh from ML Kit landmarks only (eyes, nose, mouth, cheeks, ears).
/// Used for faces that have no contours. No points are invented.
FaceMesh meshFromLandmarks(Face face) {
  const types = [
    FaceLandmarkType.leftEye,
    FaceLandmarkType.rightEye,
    FaceLandmarkType.noseBase,
    FaceLandmarkType.leftMouth,
    FaceLandmarkType.rightMouth,
    FaceLandmarkType.bottomMouth,
    FaceLandmarkType.leftCheek,
    FaceLandmarkType.rightCheek,
    FaceLandmarkType.leftEar,
    FaceLandmarkType.rightEar,
  ];
  const links = [
    (FaceLandmarkType.leftEye, FaceLandmarkType.rightEye),
    (FaceLandmarkType.leftEye, FaceLandmarkType.noseBase),
    (FaceLandmarkType.rightEye, FaceLandmarkType.noseBase),
    (FaceLandmarkType.leftEye, FaceLandmarkType.leftCheek),
    (FaceLandmarkType.rightEye, FaceLandmarkType.rightCheek),
    (FaceLandmarkType.leftCheek, FaceLandmarkType.noseBase),
    (FaceLandmarkType.rightCheek, FaceLandmarkType.noseBase),
    (FaceLandmarkType.noseBase, FaceLandmarkType.leftMouth),
    (FaceLandmarkType.noseBase, FaceLandmarkType.rightMouth),
    (FaceLandmarkType.leftMouth, FaceLandmarkType.bottomMouth),
    (FaceLandmarkType.rightMouth, FaceLandmarkType.bottomMouth),
    (FaceLandmarkType.leftCheek, FaceLandmarkType.leftMouth),
    (FaceLandmarkType.rightCheek, FaceLandmarkType.rightMouth),
    (FaceLandmarkType.leftEar, FaceLandmarkType.leftEye),
    (FaceLandmarkType.rightEar, FaceLandmarkType.rightEye),
  ];
  final index = <FaceLandmarkType, int>{};
  final pts = <Offset>[];
  for (final t in types) {
    final p = face.landmarks[t]?.position;
    if (p == null) continue;
    index[t] = pts.length;
    pts.add(_o(p));
  }
  return FaceMesh(
    kind: 'landmark',
    points: pts,
    edges: [
      for (final (a, b) in links)
        if (index[a] != null && index[b] != null) (index[a]!, index[b]!),
    ],
    major: [
      for (final t in const [
        FaceLandmarkType.leftEye,
        FaceLandmarkType.rightEye,
        FaceLandmarkType.noseBase,
      ])
        if (index[t] != null) index[t]!,
    ],
  );
}

/// Steadies a newly detected set of face points against the previous one.
///
/// Detections wobble by a pixel or two even when the face is still, while
/// real movement shifts every point together. So the amount kept from the
/// new detection depends on how far the points moved, relative to the face
/// width: tiny moves (noise) take 35% of the new position, moves of 6% of
/// the face or more take all of it, with no lag. Different point sets
/// (another mesh kind, a new face) are returned unchanged.
List<Offset> smoothPoints(
  List<Offset>? previous,
  List<Offset> next, {
  required double faceWidth,
}) {
  if (previous == null ||
      previous.length != next.length ||
      next.isEmpty ||
      faceWidth <= 0) {
    return next;
  }
  var moved = 0.0;
  for (var i = 0; i < next.length; i++) {
    moved += (next[i] - previous[i]).distance;
  }
  moved /= next.length * faceWidth;
  final k = (0.35 + 0.65 * (moved / 0.06)).clamp(0.35, 1.0);
  if (k >= 1) return next;
  return [
    for (var i = 0; i < next.length; i++) Offset.lerp(previous[i], next[i], k)!,
  ];
}

/// Per-second rate of the overlay's easing toward new points:
/// ln(10) / 0.12 s, i.e. 90% of the way in 0.12 s.
const meshEaseRate = 19.2;

/// Mesh appearance: mint, lines at 20% and dots at 35% opacity.
const meshColor = Lenzo.accent;
const meshLineOpacity = 0.2;
const meshDotOpacity = 0.35;

/// Maps a rect from image coordinates to widget coordinates.
Rect imageRectToWidget(Rect r, Size imageSize, Size widgetSize, bool mirror) {
  final a = _mapPoint(r.topLeft, imageSize, widgetSize, mirror);
  final c = _mapPoint(r.bottomRight, imageSize, widgetSize, mirror);
  return Rect.fromPoints(a, c);
}

Offset _mapPoint(Offset p, Size imageSize, Size widgetSize, bool mirror) {
  final x = p.dx * widgetSize.width / imageSize.width;
  final y = p.dy * widgetSize.height / imageSize.height;
  return Offset(mirror ? widgetSize.width - x : x, y);
}

// ---------------------------------------------------------------------------
// Overlay widget
// ---------------------------------------------------------------------------

/// One line of the info panel beside a face, e.g. "Lent  ₹25,000".
class InfoRow {
  const InfoRow(this.label, this.value, {this.color, this.divider = false});
  final String label;
  final String value;

  /// Draws a hairline above this row (used before the balance).
  final bool divider;

  /// Colour of [value]; defaults to the primary text colour.
  final Color? color;

  @override
  bool operator ==(Object other) =>
      other is InfoRow &&
      other.label == label &&
      other.value == value &&
      other.color == color &&
      other.divider == divider;

  @override
  int get hashCode => Object.hash(label, value, color, divider);
}

/// Details shown in a small panel beside a verified face: [rows] (e.g. To
/// Receive, To Pay), then a personal [note], then [after] (e.g. Reminder).
/// Only what is given is drawn, and the panel is sized to it.
class FaceInfo {
  const FaceInfo(
    this.rows, {
    this.compact = false,
    this.note,
    this.after = const [],
  });

  /// Only a personal note: a small pill, placed below the face.
  const FaceInfo.note(String this.note)
    : rows = const [],
      after = const [],
      compact = true;

  /// Tighter padding and row spacing, for a short card.
  final bool compact;
  final List<InfoRow> rows;

  /// Personal note, shown with a note icon (up to three lines), or null.
  final String? note;

  /// Rows under the note.
  final List<InfoRow> after;

  bool get isEmpty => rows.isEmpty && after.isEmpty && note == null;

  /// Just a note: drawn as a caption under the face.
  bool get noteOnly => note != null && rows.isEmpty && after.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is FaceInfo &&
      other.compact == compact &&
      other.note == note &&
      listEquals(other.rows, rows) &&
      listEquals(other.after, after);

  @override
  int get hashCode =>
      Object.hash(compact, note, Object.hashAll(rows), Object.hashAll(after));
}

/// Where each info panel was last drawn, so taps on a panel can be matched
/// to its face. Pass the same instance to [FaceMeshOverlay.hits].
class MeshHits {
  final Map<Object, ({Offset center, Size size, double angle})> _panels = {};

  /// Key of the face whose info panel is at [position] (widget
  /// coordinates), or null.
  Object? panelAt(Offset position) {
    for (final e in _panels.entries) {
      final v = e.value;
      // Undo the panel's rotation, then test against its box.
      final d = position - v.center;
      final c = math.cos(-v.angle), s = math.sin(-v.angle);
      final local = Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
      final box = Rect.fromCenter(
        center: Offset.zero,
        width: v.size.width,
        height: v.size.height,
      ).inflate(6);
      if (box.contains(local)) return e.key;
    }
    return null;
  }
}

/// One face to draw.
class MeshFace {
  const MeshFace({
    required this.key,
    required this.mesh,
    required this.color,
    this.label,
    this.sublabel,
    this.verified = false,
    this.info,
  });

  /// Panel beside the face, or null for none. Only set for verified people.
  final FaceInfo? info;

  /// Stable id (e.g. ML Kit tracking id) so the mesh animates smoothly.
  final Object key;
  final FaceMesh mesh;
  final Color color;

  /// Small text shown above the face (name or status).
  final String? label;

  /// Optional second, smaller line under [label].
  final String? sublabel;

  /// Shows a check mark next to [label].
  final bool verified;
}

class _Anim {
  _Anim(this.points, this.color, this.kind);
  List<Offset> points;
  Color color;
  String kind;
  double opacity = 0;

  /// 0 = not verified, 1 = verified; eases between the two.
  double verified = 0;

  /// Info panel: last details shown (kept while fading out), its opacity,
  /// and laid-out text for each row (label, value).
  FaceInfo? info;
  double infoOpacity = 0;
  List<(TextPainter, TextPainter)>? infoText;

  /// The note's icon and wrapped text, and the width it was wrapped to.
  (TextPainter, TextPainter)? noteText;
  double noteWidth = 0;
  Offset? infoCenter;
}

/// Minimal face-tracking overlay: thin lines and small dots on the detected
/// facial features of every face, with a small name pill above each. Nothing is
/// drawn around the face.
///
/// Detection runs a few times per second; this widget animates at the screen
/// refresh rate and glides each point and color toward its latest value.
class FaceMeshOverlay extends StatefulWidget {
  const FaceMeshOverlay({
    super.key,
    required this.faces,
    required this.imageSize,
    required this.mirror,
    this.labelRotation = 0,
    this.hits,
  });

  /// Filled in with where info panels are drawn, for tap handling.
  final MeshHits? hits;

  final List<MeshFace> faces;
  final Size imageSize;
  final bool mirror;

  /// How far the phone is turned, in degrees (0, 90, 180, 270; 90 = top to
  /// the left). Labels are rotated by this much so they read horizontally
  /// for the person holding the phone.
  final int labelRotation;

  @override
  State<FaceMeshOverlay> createState() => _FaceMeshOverlayState();
}

class _FaceMeshOverlayState extends State<FaceMeshOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  final Map<Object, _Anim> _anim = {};
  Duration _last = Duration.zero;

  /// Current label rotation in radians, easing toward
  /// [FaceMeshOverlay.labelRotation].
  late double _labelAngle = widget.labelRotation * math.pi / 180;

  /// Fraction of the way info panels move toward their target this frame.
  double _panelEase = 1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    // Frame-rate independent easing: 90% of the way in 0.12 s (detections
    // are already steadied by [smoothPoints], so this only fills the gaps
    // between them).
    final k = 1 - math.exp(-meshEaseRate * dt);
    final fade = dt / 0.25;

    final keys = <Object>{};
    for (final f in widget.faces) {
      keys.add(f.key);
      final target = f.mesh.points;
      final a = _anim[f.key];
      if (a == null) {
        // New face: start at its points and fade in.
        _anim[f.key] = _Anim(List.of(target), f.color, f.mesh.kind)
          ..verified = f.verified ? 1 : 0;
        continue;
      }
      if (a.kind != f.mesh.kind || a.points.length != target.length) {
        // Same face, different set of points (e.g. full contours ↔
        // landmarks). Keep its colour, opacity, label and info panel, and
        // start the new points where the old mesh was, so it glides there
        // instead of jumping or fading in again.
        a.points = _placeLike(target, a.points);
        a.kind = f.mesh.kind;
      }
      for (var i = 0; i < target.length; i++) {
        a.points[i] = Offset.lerp(a.points[i], target[i], k)!;
      }
      a.color = Color.lerp(a.color, f.color, k)!;
      a.opacity = math.min(1, a.opacity + fade);
      // Verified label: 0 → 1 over 0.2 s; drives the pill's scale pop.
      a.verified = f.verified
          ? math.min(1, a.verified + dt / 0.2)
          : math.max(0, a.verified - dt / 0.2);
      // The info panel fades in once details arrive and out when they go.
      final info = f.info;
      if (info != null) {
        if (info != a.info) {
          a.info = info;
          for (final (l, v)
              in a.infoText ?? const <(TextPainter, TextPainter)>[]) {
            l.dispose();
            v.dispose();
          }
          a.infoText = null;
          final note = a.noteText;
          if (note != null) {
            note.$1.dispose();
            note.$2.dispose();
          }
          a.noteText = null;
        }
        a.infoOpacity = math.min(1, a.infoOpacity + fade);
      } else {
        a.infoOpacity = math.max(0, a.infoOpacity - fade);
      }
    }
    _anim.removeWhere((key, _) => !keys.contains(key));
    // Turn the labels smoothly, the short way round.
    final target = widget.labelRotation * math.pi / 180;
    var diff = (target - _labelAngle) % (2 * math.pi);
    if (diff > math.pi) diff -= 2 * math.pi;
    _labelAngle = (diff.abs() < 0.001)
        ? target
        : _labelAngle + diff * (1 - math.pow(0.0005, dt).toDouble());
    // Info panels glide a little slower than the mesh so a change of side
    // looks deliberate.
    _panelEase = 1 - math.pow(0.002, dt).toDouble();
    _time.value = elapsed.inMicroseconds / 1e6;
  }

  /// [target] moved and scaled so its bounding box matches [previous]'s.
  static List<Offset> _placeLike(List<Offset> target, List<Offset> previous) {
    Rect box(List<Offset> pts) {
      var l = double.infinity, t = double.infinity;
      var r = -double.infinity, b = -double.infinity;
      for (final p in pts) {
        l = math.min(l, p.dx);
        t = math.min(t, p.dy);
        r = math.max(r, p.dx);
        b = math.max(b, p.dy);
      }
      return Rect.fromLTRB(l, t, r, b);
    }

    if (target.isEmpty || previous.isEmpty) return List.of(target);
    final from = box(target), to = box(previous);
    final sx = from.width > 1 ? to.width / from.width : 1.0;
    final sy = from.height > 1 ? to.height / from.height : 1.0;
    return [
      for (final p in target)
        Offset(
          to.center.dx + (p.dx - from.center.dx) * sx,
          to.center.dy + (p.dy - from.center.dy) * sy,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.infinite, painter: _MeshPainter(this));
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(this.s) : super(repaint: s._time);
  final _FaceMeshOverlayState s;

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = s.widget.imageSize;
    if (imageSize.isEmpty) return;
    final t = s._time.value;
    _size = size;
    s.widget.hits?._panels.clear();

    for (final f in s.widget.faces) {
      final a = s._anim[f.key];
      if (a == null || a.opacity <= 0) continue;
      final pts = [
        for (final p in a.points)
          _mapPoint(p, imageSize, size, s.widget.mirror),
      ];
      _paintFace(canvas, pts, f, a.color, a.opacity, t, a.verified);
      if (a.info != null && a.infoOpacity > 0 && pts.isNotEmpty) {
        _paintInfo(canvas, f.key, a, pts, a.opacity * a.infoOpacity);
      }
    }
  }

  static const _panelPadX = 11.0, _panelPadY = 8.0;
  static const _rowGap = 4.0, _colGap = 14.0, _faceGap = 14.0;

  /// Widest a note may be drawn; it wraps within this, up to three lines.
  static const _noteMaxWidth = 190.0;
  static const _noteGap = 6.0; // note icon → text

  static TextPainter _row(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  /// Lays out the panel text once per change of details: one (label,
  /// value) pair per row, [FaceInfo.rows] then [FaceInfo.after].
  List<(TextPainter, TextPainter)> _infoText(_Anim a) {
    return a.infoText ??= [
      for (final r in [...a.info!.rows, ...a.info!.after])
        (
          _row(
            r.label,
            const TextStyle(
              fontFamily: Lenzo.font,
              color: Lenzo.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
          _row(
            r.value,
            TextStyle(
              fontFamily: Lenzo.font,
              color: r.color ?? Lenzo.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
    ];
  }

  /// The note's icon and text, wrapped to [width], or null without a note.
  (TextPainter, TextPainter)? _noteText(_Anim a, double width) {
    final note = a.info!.note;
    if (note == null) return null;
    final cached = a.noteText;
    if (cached != null && a.noteWidth == width) return cached;
    if (cached != null) {
      cached.$1.dispose();
      cached.$2.dispose();
    }
    const icon = Icons.sticky_note_2_outlined;
    final iconText = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 13,
          color: Lenzo.textSecondary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final text = TextPainter(
      text: TextSpan(
        text: note,
        style: const TextStyle(
          fontFamily: Lenzo.font,
          color: Lenzo.textPrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: math.max(40, width - iconText.width - _noteGap));
    a.noteWidth = width;
    return a.noteText = (iconText, text);
  }

  /// Small panel with the person's details beside the face, on the
  /// viewer's left; moves right, then below, then above when there isn't
  /// room. A panel with only a note goes below the face first, like a
  /// caption. Turns with the phone like the name label.
  void _paintInfo(
    Canvas canvas,
    Object key,
    _Anim a,
    List<Offset> points,
    double opacity,
  ) {
    final size = _size;
    final info = a.info!;
    final rows = _infoText(a);
    final firstCount = info.rows.length;
    final compact = info.compact;
    final padX = compact ? 10.0 : _panelPadX;
    final padY = compact ? 6.0 : _panelPadY;
    final rowGap = compact ? 2.0 : _rowGap;
    final colGap = compact ? 12.0 : _colGap;

    var labelW = 0.0, valueW = 0.0;
    for (final (l, v) in rows) {
      labelW = math.max(labelW, l.width);
      valueW = math.max(valueW, v.width);
    }
    final rowsW = rows.isEmpty ? 0.0 : labelW + colGap + valueW;
    // The note wraps to the rows' width, or up to its own maximum.
    final note = _noteText(a, math.max(rowsW, _noteMaxWidth));
    final noteW = note == null ? 0.0 : note.$1.width + _noteGap + note.$2.width;
    if (rows.isEmpty && note == null) return;

    double rowH((TextPainter, TextPainter) r) =>
        math.max(r.$1.height, r.$2.height);
    // Blocks, top to bottom: rows, note, rows after.
    final blocks = <double>[
      for (var i = 0; i < firstCount; i++) rowH(rows[i]),
      if (note != null) math.max(note.$1.height, note.$2.height),
      for (var i = firstCount; i < rows.length; i++) rowH(rows[i]),
    ];
    final contentH =
        blocks.fold(0.0, (s, h) => s + h) + rowGap * (blocks.length - 1);
    final w = padX * 2 + math.max(rowsW, noteW);
    final h = padY * 2 + contentH;

    final angle = s._labelAngle;
    final cosA = math.cos(angle), sinA = math.sin(angle);
    // Viewer's right and up directions in screen coordinates.
    final right = Offset(cosA, sinA);
    final up = Offset(sinA, -cosA);
    double dot(Offset p, Offset q) => p.dx * q.dx + p.dy * q.dy;

    var sum = Offset.zero;
    for (final q in points) {
      sum += q;
    }
    final c = sum / points.length.toDouble();
    var leftExt = 0.0, rightExt = 0.0, topExt = 0.0, bottomExt = 0.0;
    for (final q in points) {
      final x = dot(q - c, right), y = dot(q - c, up);
      rightExt = math.max(rightExt, x);
      leftExt = math.min(leftExt, x);
      topExt = math.max(topExt, y);
      bottomExt = math.min(bottomExt, y);
    }

    // Screen-space half extents of the rotated panel.
    final halfX = (cosA.abs() * w + sinA.abs() * h) / 2;
    final halfY = (sinA.abs() * w + cosA.abs() * h) / 2;
    bool fits(Offset o) =>
        o.dx - halfX >= 6 &&
        o.dy - halfY >= 6 &&
        o.dx + halfX <= size.width - 6 &&
        o.dy + halfY <= size.height - 6;

    final left = c + right * (leftExt - _faceGap - w / 2);
    final rightOf = c + right * (rightExt + _faceGap + w / 2);
    final below = c + up * (bottomExt - _faceGap - h / 2);
    final above = c + up * (topExt + _faceGap + 34 + h / 2); // past the name
    final candidates = info.noteOnly
        ? [below, left, rightOf, above]
        : [left, rightOf, below, above];
    var target = candidates.firstWhere(fits, orElse: () => candidates.first);
    target = Offset(
      target.dx.clamp(halfX + 6, math.max(halfX + 6, size.width - halfX - 6)),
      target.dy.clamp(halfY + 6, math.max(halfY + 6, size.height - halfY - 6)),
    );

    // Glide toward the target so the panel follows the face smoothly.
    final ac = a.infoCenter;
    final center = ac == null || a.infoOpacity < 0.05
        ? target
        : Offset.lerp(ac, target, s._panelEase)!;
    a.infoCenter = center;
    if (opacity > 0.5) {
      s.widget.hits?._panels[key] = (
        center: center,
        size: Size(w, h),
        angle: angle,
      );
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final box = RRect.fromRectAndRadius(
      rect,
      Radius.circular(compact ? 10 : 12),
    );
    // Flat translucent surface with a hairline edge.
    canvas.drawRRect(
      box,
      Paint()..color = Lenzo.surface.withValues(alpha: 0.72 * opacity),
    );
    canvas.drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Lenzo.accent.withValues(alpha: 0.32 * opacity),
    );

    var y = rect.top + padY;
    void paintRow(int i) {
      final (l, v) = rows[i];
      final rh = rowH(rows[i]);
      final all = [...info.rows, ...info.after];
      if (i > 0 && all[i].divider) {
        final ly = y - rowGap / 2;
        canvas.drawLine(
          Offset(rect.left + padX, ly),
          Offset(rect.right - padX, ly),
          Paint()
            ..strokeWidth = 0.6
            ..color = Lenzo.accent.withValues(alpha: 0.22 * opacity),
        );
      }
      _paintText(
        canvas,
        l,
        Offset(rect.left + padX, y + (rh - l.height) / 2),
        opacity,
      );
      _paintText(
        canvas,
        v,
        Offset(rect.right - padX - v.width, y + (rh - v.height) / 2),
        opacity,
      );
      y += rh + rowGap;
    }

    for (var i = 0; i < firstCount; i++) {
      paintRow(i);
    }
    if (note != null) {
      final (icon, text) = note;
      final x = rect.left + padX;
      _paintText(
        canvas,
        icon,
        Offset(x, y + (text.preferredLineHeight - icon.height) / 2),
        opacity,
      );
      _paintText(canvas, text, Offset(x + icon.width + _noteGap, y), opacity);
      y += math.max(icon.height, text.height) + rowGap;
    }
    for (var i = firstCount; i < rows.length; i++) {
      paintRow(i);
    }
    canvas.restore();
  }

  /// Paints laid-out text at [opacity] by drawing it into a faded layer.
  static void _paintText(
    Canvas canvas,
    TextPainter tp,
    Offset at,
    double opacity,
  ) {
    if (opacity >= 0.99) {
      tp.paint(canvas, at);
      return;
    }
    canvas.saveLayer(
      (at & tp.size).inflate(2),
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    tp.paint(canvas, at);
    canvas.restore();
  }

  void _paintFace(
    Canvas canvas,
    List<Offset> p,
    MeshFace f,
    Color color,
    double opacity,
    double t,
    double verified,
  ) {
    if (p.isEmpty) return;
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final q in p) {
      minX = math.min(minX, q.dx);
      maxX = math.max(maxX, q.dx);
      minY = math.min(minY, q.dy);
      maxY = math.max(maxY, q.dy);
    }
    final scale = ((maxX - minX) / 300).clamp(0.7, 1.4);
    // A light AR trace, not a mask: always mint (state colours are on the
    // label and the camera border), lines at 20%, dots at 35%, thin and
    // small so the face stays clearly visible.
    final line = Paint()
      ..color = meshColor.withValues(alpha: meshLineOpacity * opacity)
      ..strokeWidth = 0.6 * scale
      ..isAntiAlias = true;
    for (final (i, j) in f.mesh.edges) {
      // The face's mesh can change kind (landmarks ↔ contours) between the
      // build and the next tick that resizes the animated points; for that
      // one frame, skip edges the old points don't have.
      if (i < p.length && j < p.length) canvas.drawLine(p[i], p[j], line);
    }
    final dot = Paint()
      ..color = meshColor.withValues(alpha: meshDotOpacity * opacity);
    final major = f.mesh.major.toSet();
    for (var i = 0; i < p.length; i++) {
      canvas.drawCircle(p[i], (major.contains(i) ? 1.6 : 1.0) * scale, dot);
    }
    final label = f.label;
    if (label != null) {
      _paintLabel(canvas, f, label, color, opacity, p, scale, verified);
    }
  }

  /// Small pill with the person's name (and a check mark once verified),
  /// next to the face on the side that is "up" for the person holding the
  /// phone. The text turns with the phone, never with the face, so it always
  /// reads horizontally. Moves with the smoothed mesh.
  void _paintLabel(
    Canvas canvas,
    MeshFace f,
    String label,
    Color color,
    double opacity,
    List<Offset> points,
    double scale,
    double verified,
  ) {
    final size = _size;
    final angle = s._labelAngle; // clockwise, radians
    final cosA = math.cos(angle), sinA = math.sin(angle);
    // Viewer's "up" direction in screen coordinates.
    final up = Offset(sinA, -cosA);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontFamily: Lenzo.font,
          color: Lenzo.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        children: [
          if (f.sublabel != null)
            TextSpan(
              text: '\n${f.sublabel}',
              style: const TextStyle(
                fontFamily: Lenzo.font,
                color: Lenzo.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 190);

    const padX = 12.0, padY = 6.0, badge = 15.0, gap = 6.0;
    final badgeW = f.verified ? badge + gap : 0.0;
    final w = tp.width + padX * 2 + badgeW;
    final h = math.max(tp.height, f.verified ? badge : 0.0) + padY * 2;

    // Face extent along the viewer's up and right directions.
    var sum = Offset.zero;
    for (final q in points) {
      sum += q;
    }
    final c = sum / points.length.toDouble();
    double dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
    var topExt = 0.0, bottomExt = 0.0;
    for (final q in points) {
      final d = dot(q - c, up);
      topExt = math.max(topExt, d);
      bottomExt = math.min(bottomExt, d);
    }
    final space = 12 * scale + h / 2;

    // Screen-space half extents of the rotated pill, for keeping it on screen.
    final halfX = (cosA.abs() * w + sinA.abs() * h) / 2;
    final halfY = (sinA.abs() * w + cosA.abs() * h) / 2;
    bool fits(Offset o) =>
        o.dx - halfX >= 4 &&
        o.dy - halfY >= 4 &&
        o.dx + halfX <= size.width - 4 &&
        o.dy + halfY <= size.height - 4;

    // Above the face for the viewer; below it if there's no room above.
    var center = c + up * (topExt + space);
    if (!fits(center)) {
      final below = c + up * (bottomExt - space);
      if (fits(below)) center = below;
    }
    center = Offset(
      center.dx.clamp(halfX + 4, math.max(halfX + 4, size.width - halfX - 4)),
      center.dy.clamp(halfY + 4, math.max(halfY + 4, size.height - halfY - 4)),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    // On verification the pill eases up from 94% to full size.
    if (f.verified && verified < 1) {
      final pop = 0.94 + 0.06 * Curves.easeOutQuart.transform(verified);
      canvas.scale(pop);
    }
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final pill = RRect.fromRectAndRadius(rect, Radius.circular(h / 2));

    canvas.drawRRect(
      pill,
      Paint()..color = Lenzo.surface.withValues(alpha: 0.85 * opacity),
    );
    canvas.drawRRect(
      pill,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.5 * opacity),
    );
    tp.paint(canvas, Offset(rect.left + padX, -tp.height / 2));

    if (f.verified) {
      final bc = Offset(rect.right - padX - badge / 2, 0);
      canvas.drawCircle(
        bc,
        badge / 2,
        Paint()..color = color.withValues(alpha: opacity),
      );
      final check = Path()
        ..moveTo(bc.dx - 3.6, bc.dy + 0.2)
        ..lineTo(bc.dx - 1.0, bc.dy + 2.8)
        ..lineTo(bc.dx + 3.8, bc.dy - 2.4);
      canvas.drawPath(
        check,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Lenzo.background.withValues(alpha: opacity),
      );
    }
    canvas.restore();
  }

  Size _size = Size.zero;

  @override
  bool shouldRepaint(_MeshPainter old) => true;
}
