import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'face_crop.dart' show kFaceCropSize;

/// A face found in a photo from the gallery.
class GalleryFace {
  GalleryFace({
    required this.box,
    required this.crop,
    required this.portrait,
    required this.thumbnail,
  });

  /// Where the face is in the upright photo.
  final Rect box;

  /// Aligned crop for the face model (same framing as the live camera).
  final img.Image crop;

  /// Head-and-shoulders profile photo, JPEG, never mirrored.
  final Uint8List portrait;

  /// Small square preview for choosing between faces, JPEG.
  final Uint8List thumbnail;
}

/// Why a photo couldn't be used.
enum GalleryFaceError { unreadable, noFace }

/// Faces in a photo, largest first, or the reason there are none.
class GalleryFaces {
  const GalleryFaces(this.faces, [this.error]);
  final List<GalleryFace> faces;
  final GalleryFaceError? error;
}

/// Smallest face (side of its box, in photo pixels) worth registering.
const kMinGalleryFace = 64.0;

/// Longest side photos are scaled down to before detection.
const _maxSide = 1600;

/// Finds faces in the photo at [path].
///
/// The photo is turned upright using its EXIF orientation first, so faces
/// from sideways or upside-down photos are detected and saved the right
/// way up. Gallery photos are not mirrored, so nothing is flipped.
Future<GalleryFaces> findGalleryFaces(String path) async {
  final upright = await loadUprightImage(path);
  if (upright == null) {
    return const GalleryFaces([], GalleryFaceError.unreadable);
  }
  // ML Kit reads files: give it the upright copy (no EXIF rotation left).
  final dir = await getTemporaryDirectory();
  final file = File(
    p.join(
      dir.path,
      'lenzo_gallery_${DateTime.now().microsecondsSinceEpoch}.jpg',
    ),
  );
  await file.writeAsBytes(img.encodeJpg(upright, quality: 92));
  final detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      minFaceSize: 0.05,
    ),
  );
  try {
    final found = await detector.processImage(
      InputImage.fromFilePath(file.path),
    );
    final faces =
        <GalleryFace>[
          for (final f in found)
            if (math.min(f.boundingBox.width, f.boundingBox.height) >=
                kMinGalleryFace)
              faceFromImage(upright, f.boundingBox, _eyes(f)),
        ]..sort(
          (a, b) => (b.box.width * b.box.height).compareTo(
            a.box.width * a.box.height,
          ),
        );
    return GalleryFaces(faces, faces.isEmpty ? GalleryFaceError.noFace : null);
  } finally {
    await detector.close();
    if (await file.exists()) await file.delete();
  }
}

/// The photo at [path], decoded, turned upright from its EXIF orientation
/// and scaled down to at most 1600 px on its longest side. Null if it isn't
/// an image Lenzo can read.
Future<img.Image?> loadUprightImage(String path) async {
  try {
    final decoded = img.decodeImage(await File(path).readAsBytes());
    if (decoded == null) return null;
    var upright = img.bakeOrientation(decoded);
    final longest = math.max(upright.width, upright.height);
    if (longest > _maxSide) {
      upright = upright.width >= upright.height
          ? img.copyResize(upright, width: _maxSide)
          : img.copyResize(upright, height: _maxSide);
    }
    return upright;
  } catch (_) {
    return null;
  }
}

/// Eye centres from the landmarks, or estimated from the box.
(Offset, Offset) _eyes(Face f) {
  final l = f.landmarks[FaceLandmarkType.leftEye]?.position;
  final r = f.landmarks[FaceLandmarkType.rightEye]?.position;
  if (l != null && r != null) {
    return (
      Offset(l.x.toDouble(), l.y.toDouble()),
      Offset(r.x.toDouble(), r.y.toDouble()),
    );
  }
  final b = f.boundingBox;
  final y = b.top + b.height * 0.4;
  return (
    Offset(b.left + b.width * 0.32, y),
    Offset(b.right - b.width * 0.32, y),
  );
}

/// Crop, profile photo and preview for the face in [box] of [photo].
GalleryFace faceFromImage(img.Image photo, Rect box, (Offset, Offset) eyes) {
  final (leftEye, rightEye) = eyes;
  final crop = cropAlignedFaceFromImage(
    photo,
    box: box,
    leftEye: leftEye,
    rightEye: rightEye,
  );
  // Same framing as the live camera's profile photo: a square about twice
  // the face, a little above it, kept inside the photo.
  final side = math.min(
    math.max(box.width, box.height) * 1.9,
    math.min(photo.width, photo.height).toDouble(),
  );
  final cx = box.center.dx.clamp(side / 2, photo.width - side / 2).toDouble();
  final cy = (box.center.dy - box.height * 0.08)
      .clamp(side / 2, photo.height - side / 2)
      .toDouble();
  final portrait = cropAlignedFaceFromImage(
    photo,
    box: Rect.fromCenter(center: Offset(cx, cy), width: side, height: side),
    leftEye: leftEye,
    rightEye: rightEye,
    margin: 1.0,
    size: 512,
  );
  return GalleryFace(
    box: box,
    crop: crop,
    portrait: img.encodeJpg(portrait, quality: 90),
    thumbnail: img.encodeJpg(img.copyResize(portrait, width: 160), quality: 85),
  );
}

/// Like `cropAlignedFaceFromNv21`, for an upright RGB photo: a square of
/// `max(box) × margin` around the box centre, turned so the eyes are level,
/// sampled smoothly. Outside the photo is black.
img.Image cropAlignedFaceFromImage(
  img.Image photo, {
  required Rect box,
  required Offset leftEye,
  required Offset rightEye,
  double margin = 1.15,
  int size = kFaceCropSize,
}) {
  final a = leftEye.dx <= rightEye.dx ? leftEye : rightEye;
  final b = leftEye.dx <= rightEye.dx ? rightEye : leftEye;
  final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
  final cosA = math.cos(angle), sinA = math.sin(angle);
  final side = math.max(box.width, box.height) * margin;
  final cx = box.center.dx, cy = box.center.dy;
  final out = img.Image(width: size, height: size);
  for (var oy = 0; oy < size; oy++) {
    final v = ((oy + 0.5) / size - 0.5) * side;
    for (var ox = 0; ox < size; ox++) {
      final u = ((ox + 0.5) / size - 0.5) * side;
      final x = cx + u * cosA - v * sinA - 0.5;
      final y = cy + u * sinA + v * cosA - 0.5;
      if (x < 0 || y < 0 || x > photo.width - 1 || y > photo.height - 1) {
        out.setPixelRgb(ox, oy, 0, 0, 0);
        continue;
      }
      final px = photo.getPixelLinear(x, y);
      out.setPixelRgb(ox, oy, px.r, px.g, px.b);
    }
  }
  return out;
}
