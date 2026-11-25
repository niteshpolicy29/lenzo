import 'dart:ui' show Offset, Size;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_crop.dart';

/// Rules for deciding whether a face is clear enough to recognize or save.
/// Every value here can be tuned. Stricter values give fewer wrong names but
/// ask people to position themselves more carefully.
class FaceQualityRules {
  /// Face width as a fraction of the frame width. Smaller faces are too far.
  static const double minFaceWidthFraction = 0.18;

  /// Maximum head turn left/right and up/down, in degrees, for recognition.
  static const double maxYaw = 25;
  static const double maxPitch = 20;

  /// Maximum head (or phone) tilt, in degrees, after the frame is rotated to
  /// the nearest 90°. The crop is straightened using the eyes, so a tilt up
  /// to the 45° point where the rotation switches is fine.
  static const double maxRoll = 45;

  /// Faces whose box goes past the frame edge by more than this fraction of
  /// the face size are treated as cut off.
  static const double maxOutOfFrame = 0.05;

  /// Minimum probability that each eye is open.
  static const double minEyeOpen = 0.35;

  /// Acceptable mean brightness of the face (0–255).
  static const double minBrightness = 55;
  static const double maxBrightness = 215;

  /// Minimum sharpness (variance of the Laplacian). Lower means blurry.
  static const double minSharpness = 18;
}

/// Checks that need only ML Kit's output. Returns a hint telling the person
/// what to fix, or null if the face passes.
String? checkFaceGeometry(Face face, Size frame) {
  final lm = face.landmarks;
  final hasEyes =
      lm[FaceLandmarkType.leftEye] != null &&
      lm[FaceLandmarkType.rightEye] != null;
  final hasNose = lm[FaceLandmarkType.noseBase] != null;
  final hasMouth =
      lm[FaceLandmarkType.bottomMouth] != null ||
      (lm[FaceLandmarkType.leftMouth] != null &&
          lm[FaceLandmarkType.rightMouth] != null);
  if (!hasEyes || !hasNose || !hasMouth) {
    return 'Show your whole face, nothing covering it';
  }

  final b = face.boundingBox;
  final slackX = b.width * FaceQualityRules.maxOutOfFrame;
  final slackY = b.height * FaceQualityRules.maxOutOfFrame;
  if (b.left < -slackX ||
      b.top < -slackY ||
      b.right > frame.width + slackX ||
      b.bottom > frame.height + slackY) {
    return 'Move your face fully into the frame';
  }

  if (b.width < frame.width * FaceQualityRules.minFaceWidthFraction) {
    return 'Come closer to the camera';
  }

  final yaw = face.headEulerAngleY ?? 0;
  final pitch = face.headEulerAngleX ?? 0;
  final roll = face.headEulerAngleZ ?? 0;
  if (yaw.abs() > FaceQualityRules.maxYaw ||
      pitch.abs() > FaceQualityRules.maxPitch) {
    return 'Look straight at the camera';
  }
  if (roll.abs() > FaceQualityRules.maxRoll) {
    return 'Keep your head straight';
  }

  final le = face.leftEyeOpenProbability;
  final re = face.rightEyeOpenProbability;
  if (le != null &&
      re != null &&
      (le < FaceQualityRules.minEyeOpen || re < FaceQualityRules.minEyeOpen)) {
    return 'Keep your eyes open';
  }
  return null;
}

/// Checks on the cropped face pixels. Returns a hint or null if it passes.
String? checkCropQuality(CropQuality q) {
  if (q.brightness < FaceQualityRules.minBrightness) {
    return 'Too dark, move to better light';
  }
  if (q.brightness > FaceQualityRules.maxBrightness) {
    return 'Too bright, avoid direct light';
  }
  if (q.sharpness < FaceQualityRules.minSharpness) {
    return 'Hold still, the image is blurry';
  }
  return null;
}

/// Eye positions for alignment. Only call after [checkFaceGeometry] passed.
(Offset, Offset) eyePositions(Face face) {
  final l = face.landmarks[FaceLandmarkType.leftEye]!.position;
  final r = face.landmarks[FaceLandmarkType.rightEye]!.position;
  return (
    Offset(l.x.toDouble(), l.y.toDouble()),
    Offset(r.x.toDouble(), r.y.toDouble()),
  );
}
