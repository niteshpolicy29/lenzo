import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:sensors_plus/sensors_plus.dart';

/// Tracks how the phone is physically held, from the accelerometer.
///
/// The app UI is locked to portrait, so Android's screen rotation never
/// changes. This reads gravity instead and reports the rotation in degrees:
/// 0 = upright portrait, 90 = turned counter-clockwise (top to the left),
/// 180 = upside down, 270 = turned clockwise (top to the right).
class DeviceRotation {
  DeviceRotation({required this.onChanged});

  final void Function(int degrees) onChanged;
  StreamSubscription<AccelerometerEvent>? _sub;
  int _degrees = 0;

  int get degrees => _degrees;

  /// How far past the halfway point (45°) the phone must tilt before the
  /// rotation switches, so it doesn't flicker near the diagonal.
  static const double _hysteresis = 15;

  void start() {
    _sub ??= accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen(_onEvent, onError: (_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _onEvent(AccelerometerEvent e) {
    // Ignore readings when the phone lies nearly flat; keep the last value.
    if (math.sqrt(e.x * e.x + e.y * e.y) < 4.0) return;

    // 0° when upright, +90° when the top points left.
    final angle = (math.atan2(e.x, e.y) * 180 / math.pi + 360) % 360;
    final diff = ((angle - _degrees + 540) % 360) - 180; // -180..180
    if (diff.abs() < 45 + _hysteresis) return;

    final next = ((angle / 90).round() % 4) * 90;
    if (next != _degrees) {
      _degrees = next;
      onChanged(next);
    }
  }
}

/// Rotation to give ML Kit so faces in the frame are upright for the way the
/// phone is held. Formula from the ML Kit Android docs.
int frameRotation({
  required int sensorOrientation,
  required int deviceDegrees,
  required bool frontCamera,
}) {
  return frontCamera
      ? (sensorOrientation + deviceDegrees) % 360
      : (sensorOrientation - deviceDegrees + 360) % 360;
}

/// Size of a [width]x[height] raw frame after rotating it by [rotation].
Size rotatedSize(int width, int height, int rotation) =>
    (rotation == 90 || rotation == 270)
    ? Size(height.toDouble(), width.toDouble())
    : Size(width.toDouble(), height.toDouble());

/// Converts points between two rotations of the same raw camera frame, e.g.
/// from the frame ML Kit analysed to the portrait frame shown on screen.
class FrameMapper {
  FrameMapper({
    required this.width,
    required this.height,
    required this.from,
    required this.to,
  });

  final int width;
  final int height;
  final int from;
  final int to;

  bool get isIdentity => from == to;

  Offset point(Offset p) {
    if (isIdentity) return p;
    return _rawToUpright(_uprightToRaw(p, from), to);
  }

  Rect rect(Rect r) {
    if (isIdentity) return r;
    return Rect.fromPoints(point(r.topLeft), point(r.bottomRight));
  }

  List<Offset> points(List<Offset> ps) =>
      isIdentity ? ps : [for (final p in ps) point(p)];

  Offset _uprightToRaw(Offset u, int r) {
    final w = width.toDouble(), h = height.toDouble();
    return switch (r) {
      90 => Offset(u.dy, h - u.dx),
      180 => Offset(w - u.dx, h - u.dy),
      270 => Offset(w - u.dy, u.dx),
      _ => u,
    };
  }

  Offset _rawToUpright(Offset raw, int r) {
    final w = width.toDouble(), h = height.toDouble();
    return switch (r) {
      90 => Offset(h - raw.dy, raw.dx),
      180 => Offset(w - raw.dx, h - raw.dy),
      270 => Offset(raw.dy, w - raw.dx),
      _ => raw,
    };
  }
}
