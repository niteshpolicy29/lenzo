import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

import '../design/design.dart';
import '../services/camera_choice.dart';
import '../services/device_rotation.dart';
import '../services/face_crop.dart';
import '../services/face_quality.dart';
import '../services/face_repository.dart';
import '../theme/lenzo_theme.dart';
import 'cover_box.dart';
import 'lenzo_ui.dart';
import 'single_message.dart';

/// Number of screens currently using the camera on their own (owner scan).
/// The main scanner closes its camera while this is above 0, because the
/// phone can't keep two cameras open.
final cameraBorrowers = ValueNotifier<int>(0);

/// Result of an owner face scan.
class OwnerScan {
  const OwnerScan({
    required this.faces,
    required this.portrait,
    required this.match,
  });

  /// Aligned face crops and their embeddings, from separate frames.
  final List<(img.Image, List<double>)> faces;

  /// Head-and-shoulders photo for the profile, as JPEG.
  final Uint8List portrait;

  /// How the scanned face compares with the saved people.
  final FaceMatch match;
}

/// Round live selfie view that scans one face. It waits for a clear,
/// straight-on face, captures [samples] good frames a moment apart (a ring
/// fills as it goes), then calls [onCaptured] and shows the captured photo.
class OwnerFaceScan extends StatefulWidget {
  const OwnerFaceScan({
    super.key,
    required this.repo,
    required this.size,
    required this.onCaptured,
    this.scan,
    this.capturedMessage = 'Face captured. Add your name to save it.',
  });

  /// Shown once a face is captured (it isn't saved yet).
  final String capturedMessage;

  final FaceRepository repo;
  final double size;
  final ValueChanged<OwnerScan> onCaptured;

  /// A finished scan to show instead of the camera, or null to scan.
  final OwnerScan? scan;

  static const samples = 3;

  @override
  State<OwnerFaceScan> createState() => _OwnerFaceScanState();
}

class _OwnerFaceScanState extends State<OwnerFaceScan>
    with WidgetsBindingObserver {
  static const _gap = Duration(milliseconds: 280);

  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      enableClassification: true,
      minFaceSize: 0.15,
    ),
  );

  CameraController? _controller;
  CameraDescription? _camera;
  String? _error;
  bool _busy = false;
  bool _starting = false;
  bool _borrowed = false;

  static const _position = GuideMessage('Position your face in the circle');
  GuideMessage _status = _position;
  final List<(img.Image, List<double>)> _faces = [];
  DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
  Uint8List? _portrait;

  /// Sharpness of the face in the frame [_portrait] came from; the profile
  /// photo is taken from the sharpest of the captured frames.
  double _portraitSharpness = -1;

  /// Frames in a row that failed to process. Three means the capture is
  /// failing, not just one bad frame.
  int _failures = 0;

  bool get _scanning => widget.scan == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_scanning) _start();
  }

  @override
  void didUpdateWidget(OwnerFaceScan old) {
    super.didUpdateWidget(old);
    if (old.scan != null && widget.scan == null) {
      // "Scan again".
      _resetCapture();
      _start();
    } else if (old.scan == null && widget.scan != null) {
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    _detector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // Still this screen's turn with the camera when the app comes back.
      _stop(release: false);
    } else if (state == AppLifecycleState.resumed && _scanning) {
      _start();
    }
  }

  void _borrow(bool on) {
    if (on == _borrowed) return;
    _borrowed = on;
    cameraBorrowers.value += on ? 1 : -1;
  }

  Future<void> _start() async {
    if (_controller != null || _starting) return;
    _starting = true;
    _borrow(true);
    try {
      // Give the main scanner a moment to close its camera.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final cameras = primaryCameras(await availableCameras());
      if (cameras.isEmpty) throw CameraException('none', 'No camera found.');
      _camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final c = CameraController(
        _camera!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await c.initialize();
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted || !_scanning) {
        await c.dispose();
        _borrow(false);
        return;
      }
      setState(() {
        _controller = c;
        _error = null;
      });
      await c.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'CameraAccessDenied'
              ? 'Allow camera access in Settings to scan your face.'
              : 'Camera error: ${e.description}',
        );
      }
    } finally {
      _starting = false;
    }
  }

  void _stop({bool release = true}) {
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.dispose().whenComplete(() {
        if (release) _borrow(false);
      });
    } else if (!_starting && release) {
      _borrow(false);
    }
    if (mounted) setState(() {});
  }

  void _say(String text, {bool warn = false}) {
    final m = GuideMessage(
      text,
      color: warn ? LenzoColors.warning : LenzoColors.textSecondary,
    );
    if (m != _status) setState(() => _status = m);
  }

  void _resetCapture() {
    _faces.clear();
    _portrait = null;
    _portraitSharpness = -1;
    _failures = 0;
    _status = _position;
  }

  /// After a camera error or a failed capture: start over.
  void _retry() {
    setState(() {
      _error = null;
      _resetCapture();
    });
    _start();
  }

  /// The capture can't finish: stop, drop what was collected (nothing has
  /// been saved), and offer Try again.
  void _fail() {
    _stop();
    if (!mounted) return;
    setState(() {
      _resetCapture();
      _error = "Couldn't capture your face.";
    });
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || !mounted || !_scanning || _controller == null) return;
    _busy = true;
    try {
      await _process(image);
      _failures = 0;
    } catch (e) {
      debugPrint('Owner scan frame failed: $e');
      if (++_failures >= 3) _fail();
    } finally {
      _busy = false;
    }
  }

  Future<void> _process(CameraImage image) async {
    if (image.planes.length != 1) return;
    final plane = image.planes.first;
    final rotation = frameRotation(
      sensorOrientation: _camera!.sensorOrientation,
      deviceDegrees: 0,
      frontCamera: _camera!.lensDirection == CameraLensDirection.front,
    );
    final faces = await _detector.processImage(
      InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation:
              InputImageRotationValue.fromRawValue(rotation) ??
              InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      ),
    );
    if (!mounted || !_scanning) return;
    if (faces.isEmpty) {
      _faces.clear();
      _say(_position.text);
      return;
    }
    if (faces.length > 1) {
      _say('Only you should be in view', warn: true);
      return;
    }
    final face = faces.first;
    final frame = rotatedSize(image.width, image.height, rotation);
    final hint = checkFaceGeometry(face, frame);
    if (hint != null) {
      _say(hint, warn: true);
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastSample) < _gap) return;

    final (leftEye, rightEye) = eyePositions(face);
    final crop = cropAlignedFaceFromNv21(
      nv21: plane.bytes,
      width: image.width,
      height: image.height,
      rotation: rotation,
      box: face.boundingBox,
      leftEye: leftEye,
      rightEye: rightEye,
    );
    final quality = measureCrop(crop);
    final pixelHint = checkCropQuality(quality);
    if (pixelHint != null) {
      _say(pixelHint, warn: true);
      return;
    }
    final emb = widget.repo.embed(crop);
    // Every sample must be the same person as the first.
    if (_faces.isNotEmpty) {
      var dot = 0.0;
      final first = _faces.first.$2;
      for (var i = 0; i < emb.length; i++) {
        dot += emb[i] * first[i];
      }
      if (dot < FaceRepository.matchThreshold) {
        _faces.clear();
        _say('Hold still and look at the camera', warn: true);
        return;
      }
    }
    _lastSample = now;
    if (quality.sharpness > _portraitSharpness) {
      _portrait = portraitJpegFromNv21(
        nv21: plane.bytes,
        width: image.width,
        height: image.height,
        rotation: rotation,
        box: face.boundingBox,
        leftEye: leftEye,
        rightEye: rightEye,
        // As seen in the (mirrored) selfie preview.
        mirror: _camera!.lensDirection == CameraLensDirection.front,
      );
      _portraitSharpness = quality.sharpness;
    }
    setState(() {
      _faces.add((crop, emb));
      _status = const GuideMessage('Hold still…');
    });
    if (_faces.length < OwnerFaceScan.samples) return;

    // Captured means: enough good frames, all the same person, and a
    // profile photo. Anything missing is a failed capture, not a success.
    final portrait = _portrait;
    if (portrait == null || portrait.isEmpty) {
      _fail();
      return;
    }
    final result = OwnerScan(
      faces: List.of(_faces),
      portrait: portrait,
      match: widget.repo.match(_faces.first.$2),
    );
    HapticFeedback.mediumImpact();
    _stop();
    widget.onCaptured(result);
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scan;
    final progress = scan != null ? 1.0 : _faces.length / OwnerFaceScan.samples;
    final s = widget.size;
    final c = _controller;
    final Widget inside;
    if (scan != null) {
      inside = FaceImage(key: const ValueKey('photo'), bytes: scan.portrait);
    } else if (c != null && c.value.isInitialized) {
      // Fill the circle with the middle of the camera picture, at its own
      // shape (portrait: 1 / aspectRatio wide per unit of height).
      inside = CoverBox(
        key: const ValueKey('camera'),
        aspectRatio: 1 / c.value.aspectRatio,
        child: CameraPreview(c),
      );
    } else {
      inside = Container(
        key: const ValueKey('wait'),
        color: Lenzo.surface,
        alignment: Alignment.center,
        child: _error == null
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Lenzo.accent,
                ),
              )
            : const Icon(
                Icons.no_photography_outlined,
                color: Lenzo.textSecondary,
                size: 36,
              ),
      );
    }

    final ring = s + 22;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: ring,
          height: ring,
          child: Stack(
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => CustomPaint(
                  size: Size.square(ring),
                  painter: _RingPainter(v),
                ),
              ),
              ScanCircle(size: s, child: inside),
              if (scan != null)
                Positioned(
                  right: ring * 0.1,
                  bottom: ring * 0.1,
                  child: Container(
                    width: s * 0.2,
                    height: s * 0.2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Lenzo.accent,
                      border: Border.all(color: Lenzo.surface, width: 3),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: Lenzo.onHighlight,
                      size: s * 0.12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: LenzoSpacing.x4),
        // Room for two lines, so the layout below doesn't jump as hints
        // change.
        SizedBox(
          height: 44,
          width: ring + 60,
          child: Center(
            child: SingleMessage(
              message: _error != null
                  ? GuideMessage(_error!, color: LenzoColors.warning)
                  : scan != null
                  ? GuideMessage(
                      widget.capturedMessage,
                      color: LenzoColors.accent,
                    )
                  : _status,
            ),
          ),
        ),
        if (_error != null && scan == null) ...[
          const SizedBox(height: LenzoSpacing.x2),
          LenzoButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            kind: LenzoButtonKind.secondary,
            compact: true,
            expand: false,
            onPressed: _starting ? null : _retry,
          ),
        ],
      ],
    );
  }
}

/// Thin track with an emerald arc for scan progress.
class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Lenzo.accent.withValues(alpha: 0.16),
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0, 1),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Lenzo.accent,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// The round frame of the face scan: [child] fills a circle of [size],
/// and changes of child (camera, captured photo) crossfade. Every child is
/// given the whole circle, so none can shrink into a strip.
class ScanCircle extends StatelessWidget {
  const ScanCircle({super.key, required this.size, required this.child});
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: ColoredBox(
          color: LenzoColors.surface,
          child: AnimatedSwitcher(
            duration: LenzoMotion.of(context, LenzoMotion.page),
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: child,
          ),
        ),
      ),
    );
  }
}
