import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:image/image.dart' as img;

/// Size of the aligned face crop (pixels, square). Also used as the saved
/// thumbnail. The embedder resizes it to the model's input size.
const int kFaceCropSize = 160;

/// Crops a face from a camera NV21 frame and rotates it so the eyes are level.
///
/// [box], [leftEye] and [rightEye] are in the *upright* coordinate system
/// ML Kit reports when given [rotation] (degrees the raw frame must be rotated
/// clockwise to be upright). Only the face region is converted to RGB, so this
/// is cheap enough to run on every frame.
img.Image cropAlignedFaceFromNv21({
  required Uint8List nv21,
  required int width,
  required int height,
  required int rotation,
  required Rect box,
  required Offset leftEye,
  required Offset rightEye,
  double margin = 1.15,
  int size = kFaceCropSize,
  bool smooth = false,
}) {
  final swap = rotation == 90 || rotation == 270;
  final uprightW = swap ? height : width;
  final uprightH = swap ? width : height;

  // Angle of the line between the eyes (left-most eye in the image first).
  final a = leftEye.dx <= rightEye.dx ? leftEye : rightEye;
  final b = leftEye.dx <= rightEye.dx ? rightEye : leftEye;
  final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);

  final side = math.max(box.width, box.height) * margin;
  final cx = box.center.dx;
  final cy = box.center.dy;
  final n = size;
  final out = img.Image(width: n, height: n);
  final uvStart = width * height;

  for (var oy = 0; oy < n; oy++) {
    final v = ((oy + 0.5) / n - 0.5) * side;
    for (var ox = 0; ox < n; ox++) {
      final u = ((ox + 0.5) / n - 0.5) * side;
      // Rotate the sampling grid so its x-axis follows the eye line.
      final fx = cx + u * cosA - v * sinA;
      final fy = cy + u * sinA + v * cosA;
      final ux = fx.round();
      final uy = fy.round();
      if (ux < 0 || uy < 0 || ux >= uprightW || uy >= uprightH) {
        out.setPixelRgb(ox, oy, 0, 0, 0);
        continue;
      }
      // Map upright (ux, uy) back to raw sensor (rx, ry).
      int rx, ry;
      switch (rotation) {
        case 90:
          rx = uy;
          ry = height - 1 - ux;
          break;
        case 180:
          rx = width - 1 - ux;
          ry = height - 1 - uy;
          break;
        case 270:
          rx = width - 1 - uy;
          ry = ux;
          break;
        default:
          rx = ux;
          ry = uy;
      }

      final yVal = smooth
          ? _lumaBilinear(nv21, width, height, rotation, fx, fy)
          : nv21[ry * width + rx];
      final uvIndex = uvStart + (ry >> 1) * width + (rx & ~1);
      final vv = nv21[uvIndex] - 128;
      final uu = nv21[uvIndex + 1] - 128;

      final r = (yVal + 1.402 * vv).round().clamp(0, 255);
      final g = (yVal - 0.344136 * uu - 0.714136 * vv).round().clamp(0, 255);
      final bl = (yVal + 1.772 * uu).round().clamp(0, 255);
      out.setPixelRgb(ox, oy, r, g, bl);
    }
  }
  return out;
}

/// Luma at upright position ([x], [y]), interpolated between the four
/// nearest sensor pixels, so an enlarged crop is smooth instead of blocky.
int _lumaBilinear(
  Uint8List nv21,
  int width,
  int height,
  int rotation,
  double x,
  double y,
) {
  // Upright → raw sensor coordinates (same mapping as the nearest case).
  final (double rx, double ry) = switch (rotation) {
    90 => (y, height - 1 - x),
    180 => (width - 1 - x, height - 1 - y),
    270 => (width - 1 - y, x),
    _ => (x, y),
  };
  final x0 = rx.floor().clamp(0, width - 1);
  final y0 = ry.floor().clamp(0, height - 1);
  final x1 = math.min(x0 + 1, width - 1);
  final y1 = math.min(y0 + 1, height - 1);
  final ax = (rx - x0).clamp(0.0, 1.0), ay = (ry - y0).clamp(0.0, 1.0);
  final top = nv21[y0 * width + x0] * (1 - ax) + nv21[y0 * width + x1] * ax;
  final bottom = nv21[y1 * width + x0] * (1 - ax) + nv21[y1 * width + x1] * ax;
  return (top * (1 - ay) + bottom * ay).round();
}

/// Brightness and sharpness of the central part of a face crop.
class CropQuality {
  const CropQuality(this.brightness, this.sharpness);

  /// Mean luminance, 0–255.
  final double brightness;

  /// Variance of the Laplacian. Low values mean a blurry image.
  final double sharpness;
}

CropQuality measureCrop(img.Image crop) {
  // Use the middle 60% so background and hair don't skew the numbers.
  final x0 = (crop.width * 0.2).round();
  final y0 = (crop.height * 0.2).round();
  final w = (crop.width * 0.6).round();
  final h = (crop.height * 0.6).round();

  final lum = Float64List(w * h);
  var sum = 0.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = crop.getPixel(x0 + x, y0 + y);
      final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      lum[y * w + x] = l;
      sum += l;
    }
  }
  final brightness = sum / lum.length;

  var lapSum = 0.0;
  var lapSq = 0.0;
  var count = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final lap =
          lum[i - 1] + lum[i + 1] + lum[i - w] + lum[i + w] - 4 * lum[i];
      lapSum += lap;
      lapSq += lap * lap;
      count++;
    }
  }
  final mean = lapSum / count;
  final sharpness = lapSq / count - mean * mean;
  return CropQuality(brightness, sharpness);
}

/// JPEG bytes of a face crop for storage and display.
Uint8List faceThumbnailJpeg(img.Image crop) => img.encodeJpg(crop, quality: 90);

/// Head-and-shoulders photo of a face, upright with level eyes, as JPEG
/// (512 px). Arguments are as for [cropAlignedFaceFromNv21].
///
/// [mirror] flips it left-to-right. Use it for the front camera: its
/// preview is shown mirrored (like a mirror), while the raw frame is not,
/// so without it the saved photo looks flipped compared with what the
/// person saw while scanning. Only this photo is mirrored; the face crops
/// used for recognition are not, so saved faces still match.
Uint8List portraitJpegFromNv21({
  required Uint8List nv21,
  required int width,
  required int height,
  required int rotation,
  required Rect box,
  required Offset leftEye,
  required Offset rightEye,
  bool mirror = false,
}) {
  // Upright frame size (the box is in upright coordinates).
  final swap = rotation == 90 || rotation == 270;
  final fw = (swap ? height : width).toDouble();
  final fh = (swap ? width : height).toDouble();
  // A square around the head, a little above the face box so the hair
  // fits. Shrink and shift it to stay inside the frame, so a face near the
  // edge doesn't get black bars.
  final side = math.min(
    math.max(box.width, box.height) * 1.9,
    math.min(fw, fh),
  );
  final cx = box.center.dx.clamp(side / 2, fw - side / 2).toDouble();
  final cy = (box.center.dy - box.height * 0.08)
      .clamp(side / 2, fh - side / 2)
      .toDouble();
  final photo = cropAlignedFaceFromNv21(
    nv21: nv21,
    width: width,
    height: height,
    rotation: rotation,
    box: Rect.fromCenter(center: Offset(cx, cy), width: side, height: side),
    leftEye: leftEye,
    rightEye: rightEye,
    margin: 1.0,
    size: 512,
    smooth: true,
  );
  if (mirror) img.flipHorizontal(photo);
  return img.encodeJpg(photo, quality: 90);
}

/// A small RGBA picture of a whole NV21 frame, turned upright by
/// [rotation] (clockwise degrees) and scaled down by [step]. Used to keep
/// the last camera frame on screen while switching cameras; about 1/16 of
/// the pixels, so it takes a few milliseconds.
({Uint8List rgba, int width, int height}) previewRgbaFromNv21({
  required Uint8List nv21,
  required int width,
  required int height,
  required int rotation,
  int step = 4,
}) {
  final swap = rotation == 90 || rotation == 270;
  final rw = width ~/ step, rh = height ~/ step; // raw, scaled
  final ow = swap ? rh : rw, oh = swap ? rw : rh; // upright, scaled
  final out = Uint8List(ow * oh * 4);
  final uvStart = width * height;
  var o = 0;
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      // Upright (x, y) back to scaled raw (sx, sy).
      int sx, sy;
      switch (rotation) {
        case 90:
          sx = y;
          sy = rh - 1 - x;
        case 180:
          sx = rw - 1 - x;
          sy = rh - 1 - y;
        case 270:
          sx = rw - 1 - y;
          sy = x;
        default:
          sx = x;
          sy = y;
      }
      final rx = sx * step, ry = sy * step;
      final yv = nv21[ry * width + rx];
      final uv = uvStart + (ry >> 1) * width + (rx & ~1);
      final v = nv21[uv] - 128, u = nv21[uv + 1] - 128;
      out[o++] = (yv + 1.402 * v).round().clamp(0, 255);
      out[o++] = (yv - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
      out[o++] = (yv + 1.772 * u).round().clamp(0, 255);
      out[o++] = 255;
    }
  }
  return (rgba: out, width: ow, height: oh);
}
