import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

import '../design/design.dart';
import '../data/models.dart';
import '../services/camera_choice.dart';
import '../services/device_rotation.dart';
import '../services/face_crop.dart';
import '../services/face_quality.dart';
import '../services/face_repository.dart';
import '../theme/lenzo_theme.dart';
import '../utils/format.dart';
import '../widgets/face_mesh.dart';
import '../widgets/lenzo_ui.dart';
import '../widgets/owner_face_scan.dart';
import '../widgets/page_thread.dart';
import '../widgets/scan_border.dart';
import '../widgets/swipe_route.dart';
import 'new_contact_screen.dart';
import 'owner_screens.dart';
import 'people_screen.dart';
import 'person_detail_screen.dart';

/// Marks the last-frame image shown while switching cameras (for tests).
const cameraStillKey = ValueKey('camera-still');

/// Vote values: a person id (> 0), or one of these.
const int _voteUnknown = 0;
const int _voteAmbiguous = -1;

const Color _green = Lenzo.accent;
const Color _orange = Lenzo.warning;
const Color _amber = Lenzo.caution;
const Color _red = Lenzo.danger;

/// Recognition state for one person in view, kept across frames.
///
/// Before confirmation, a name is only shown after
/// [_CameraScreenState._votesNeeded] clear frames in a row agree.
/// After confirmation the identity is *locked*: it stays while the face is
/// tracked, through head turns, small movements, blur or brief detection
/// gaps. It only changes if several clear checks in a row confidently say it
/// is a different saved person.
class _Track {
  _Track(this.key);

  /// Stable id for drawing. ML Kit tracking ids can change when it briefly
  /// loses a face; this one stays with the person.
  final int key;

  final List<int> votes = [];

  /// Frames this face has been detected in.
  int framesSeen = 0;

  /// Confirmed result (person id, [_voteUnknown] or [_voteAmbiguous]), or null
  /// while still verifying.
  int? decided;
  String? decidedName;

  /// True once a saved person is confirmed.
  bool get locked => decided != null && decided! > 0;

  /// Clear checks in a row that disagreed with the locked person.
  int _contradictions = 0;

  /// Latest reason the face isn't clear, or null if it is clear.
  String? hint;

  /// When the face first became unclear (null while clear).
  DateTime? unclearSince;

  /// Latest clear face and its embedding, saved when the user tags the face.
  img.Image? crop;
  List<double>? embedding;
  _FrameShot? shot;
  DateTime lastCheck = DateTime.fromMillisecondsSinceEpoch(0);

  /// Last time this face was detected, and where (portrait preview coords).
  DateTime lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  Rect? rect;
  FaceMesh? mesh;

  /// Drops the result so the face is recognized again.
  void forget() {
    votes.clear();
    decided = null;
    decidedName = null;
    _contradictions = 0;
    lastCheck = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void markUnclear(String reason, DateTime now) {
    hint = reason;
    unclearSince ??= now;
  }

  void markClear() {
    hint = null;
    unclearSince = null;
  }

  /// Whether to tell the user the face isn't visible. Never for a locked
  /// person, and only once the face has stayed unclear for [grace].
  bool showHint(DateTime now, Duration grace) =>
      !locked &&
      hint != null &&
      unclearSince != null &&
      now.difference(unclearSince!) >= grace;

  /// Adds one clear check. [claimed] says whether another face in view is
  /// already locked to that person, so one person can't be shown twice.
  void addVote(
    int vote,
    String? name, {
    required bool strong,
    required bool veryWeak,
    required bool Function(int personId) claimed,
    required int needed,
    required int window,
    required int switchAfter,
  }) {
    if (locked) {
      if (vote == decided) {
        _contradictions = 0;
        if (name != null) decidedName = name;
      } else if (vote > 0 && strong && !claimed(vote)) {
        // Confidently a different saved person, several times in a row.
        if (++_contradictions >= switchAfter) {
          decided = vote;
          decidedName = name;
          _contradictions = 0;
        }
      } else if (vote == _voteUnknown && veryWeak) {
        // Nothing like anyone saved, several times in a row: probably a
        // different face in the same spot. Recognize again.
        if (++_contradictions >= switchAfter) forget();
      }
      // Moderate "unknown" / "not sure" results are ignored while locked:
      // they happen with head turns and poor light.
      return;
    }

    votes.add(vote);
    if (votes.length > window) votes.removeAt(0);
    final recent = votes.length >= needed
        ? votes.sublist(votes.length - needed)
        : const <int>[];

    // Keep an "unknown"/"not sure" result while most recent checks agree.
    if (decided != null &&
        recent.where((v) => v == decided).length * 2 > recent.length) {
      return;
    }
    decided = null;
    decidedName = null;
    if (recent.isNotEmpty && recent.every((v) => v == vote)) {
      if (vote > 0 && claimed(vote)) {
        decided = _voteAmbiguous;
      } else {
        decided = vote;
        decidedName = name;
      }
    }
  }
}

/// A copy of the camera frame a face was last checked in, so a larger
/// portrait can be cut from it when the face is tapped.
class _FrameShot {
  const _FrameShot({
    required this.nv21,
    required this.width,
    required this.height,
    required this.rotation,
    required this.box,
    required this.leftEye,
    required this.rightEye,
    required this.mirror,
  });
  final Uint8List nv21;
  final int width, height, rotation;
  final Rect box;
  final Offset leftEye, rightEye;

  /// From the front camera: save the photo as the mirrored preview showed it.
  final bool mirror;

  /// Head-and-shoulders photo, upright with level eyes, as JPEG.
  Uint8List portraitJpeg() => portraitJpegFromNv21(
    nv21: nv21,
    width: width,
    height: height,
    rotation: rotation,
    box: box,
    leftEye: leftEye,
    rightEye: rightEye,
    mirror: mirror,
  );
}

/// A face in the current frame, ready to draw. [rect] and [mesh] are in the
/// portrait coordinates of the preview, whatever way the phone is held.
class _LiveFace {
  const _LiveFace(this.rect, this.mesh, this.track);
  final Rect rect;
  final FaceMesh mesh;
  final _Track track;
}

/// Live camera view. Detects faces, checks each is clearly visible, verifies
/// who it is over several frames, then shows their name. Tap a face to save
/// it under a name.
///
/// Works with the phone held upright, sideways or upside down: the frame is
/// rotated for ML Kit to match how the phone is held, and the results are
/// mapped back onto the portrait preview.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.repo});
  final FaceRepository repo;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  /// Clear frames in a row that must agree before a result is shown.
  static const _votesNeeded = 3;

  /// How many recent results to remember per face.
  static const _voteWindow = 5;

  /// How often to re-check a face that is already confirmed.
  static const _recheckInterval = Duration(milliseconds: 1200);

  /// A face that stays unclear this long shows "Face is not visible"
  /// (never for a locked, recognized person).
  static const _unclearGrace = Duration(milliseconds: 1200);

  /// How long a face that disappeared is remembered. If it reappears in the
  /// same place within this time, it keeps its identity.
  static const _lostGrace = Duration(milliseconds: 1500);

  /// How long the dots stay on screen after a face is missed, so a single
  /// missed detection doesn't make them blink.
  static const _holdMesh = Duration(milliseconds: 350);

  /// Clear, confident checks in a row needed to switch a locked identity.
  static const _switchAfter = 4;

  /// How far above the match threshold a check must be to count against a
  /// locked identity.
  static const _switchMargin = 0.08;

  /// Clear checks scoring below this against every saved person count
  /// against a locked identity (head turns usually score 0.4–0.55).
  static const _releaseBelow = 0.30;

  /// A face must be detected in this many frames in a row before it is shown.
  static const _minFramesSeen = 2;

  /// Extra faces per frame that get detailed contour points from a crop.
  /// Faces beyond this use landmark points only, to keep the frame rate up.
  static const _maxContourCrops = 4;

  /// Detections with less than this fraction of their box inside the frame
  /// are ignored. They can't be recognized and are often false detections.
  static const _minInsideFraction = 0.65;

  /// Second detector used only for drawing: ML Kit returns detailed contours
  /// (eyes, brows, lips, nose, face outline) for the most prominent face.
  /// Contours can't be combined with tracking, so it runs separately.
  final _contourDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableContours: true,
      minFaceSize: 0.15,
    ),
  );

  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      // Accurate mode is needed for reliable head-turn angles.
      performanceMode: FaceDetectorMode.accurate,
      enableTracking: true,
      enableLandmarks: true,
      enableClassification: true,
      minFaceSize: 0.1,
    ),
  );

  late final DeviceRotation _deviceRotation = DeviceRotation(
    // ML Kit gives faces new tracking ids after a change of frame
    // rotation, but positions are in portrait preview coordinates either
    // way, so each face is re-acquired by position (see _trackFor) and keeps
    // its confirmed identity, label and info panel. Redraw so the labels
    // turn to match the phone.
    onChanged: (_) {
      if (mounted) setState(() {});
    },
  );

  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  CameraController? _controller;
  String? _error;
  bool _starting = false;

  bool _busy = false;
  bool _paused = false; // true while a dialog / other screen is open
  Size _imageSize = Size.zero; // portrait frame size, matches the preview
  /// Faces in the latest frame. Frame updates go through this notifier so
  /// only the overlay and the status text rebuild, not the whole screen.
  final _live = ValueNotifier<List<_LiveFace>>(const []);

  /// What the camera border shows (searching, recognized, unknown).
  final _scan = ValueNotifier<ScanState>(ScanState.idle);
  List<_LiveFace> get _faces => _live.value;
  set _faces(List<_LiveFace> v) {
    _live.value = v;
    _scan.value = scanStateFor([for (final f in v) f.track.decided]);
  }

  final Map<int, _Track> _tracks = {};

  bool get _isFront =>
      _cameras.isNotEmpty &&
      _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.repo.addListener(_onPeopleChanged);
    cameraBorrowers.addListener(_onCameraBorrowed);
    _loadPeopleCache();
    _deviceRotation.start();
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.repo.removeListener(_onPeopleChanged);
    cameraBorrowers.removeListener(_onCameraBorrowed);
    _deviceRotation.stop();
    _controller?.dispose();
    _detector.close();
    _contourDetector.close();
    _live.dispose();
    _scan.dispose();
    _switchGuard?.cancel();
    _noFrames?.cancel();
    _slowTimer?.cancel();
    _still?.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive && c != null) {
      _controller = null;
      c.dispose();
      _deviceRotation.stop();
      if (mounted) setState(() => _faces = []);
    } else if (state == AppLifecycleState.resumed && c == null) {
      _deviceRotation.start();
      _startCamera();
    }
  }

  /// Saved people changed. Locked faces keep their identity (with the
  /// current name); deleted people and unconfirmed faces are checked again.
  void _onPeopleChanged() {
    _loadPeopleCache();
    // Amounts, notes or reminders may have changed. Reload them in the
    // background and keep showing the old values meanwhile, so info panels
    // update in place instead of fading out and in.
    for (final id in _details.keys.toList()) {
      widget.repo.getPerson(id).then((person) {
        if (!mounted) return;
        setState(() {
          if (person == null) {
            _details.remove(id);
          } else {
            _details[id] = person;
          }
        });
      });
    }
    for (final t in _tracks.values) {
      final name = t.locked ? widget.repo.nameOf(t.decided!) : null;
      if (name != null) {
        t.decidedName = name;
      } else {
        t.forget();
      }
    }
  }

  Future<void> _setup() async {
    try {
      // Only the main rear and main front cameras (no ultra-wide, macro or
      // depth lenses), so switching is always rear ↔ front.
      _cameras = primaryCameras(await availableCameras());
      _camLog(
        'cam: using ${[for (final c in _cameras) '${c.lensDirection.name}:${c.name}']}',
      );
    } on CameraException catch (e) {
      setState(() => _error = 'Camera error: ${e.description}');
      return;
    }
    if (_cameras.isEmpty) {
      setState(() => _error = 'No camera found on this device.');
      return;
    }
    // Start on the rear camera.
    final back = _cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    _cameraIndex = back >= 0 ? back : 0;
    await _startCamera();
  }

  /// Another screen (the owner face scan) needs the camera: close it, and
  /// open it again once that screen is done.
  void _onCameraBorrowed() {
    final c = _controller;
    if (cameraBorrowers.value > 0) {
      if (c == null) return;
      _controller = null;
      c.dispose();
      if (mounted) setState(() => _faces = []);
    } else if (c == null && mounted) {
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    if (_cameras.isEmpty || _starting || cameraBorrowers.value > 0) return;
    _starting = true;
    try {
      await _initController();
    } finally {
      _starting = false;
    }
  }

  Future<void> _initController() async {
    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    try {
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } on CameraException catch (e) {
      await controller.dispose();
      setState(
        () => _error = e.code == 'CameraAccessDenied'
            ? 'Camera permission denied. Allow camera access in Settings.'
            : 'Camera error: ${e.description}',
      );
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    _tracks.clear();
    setState(() {
      _controller = controller;
      _previewShown = false;
      _error = null;
      _faces = [];
    });
    await _startStream();
  }

  Future<void> _startStream() async {
    final c = _controller;
    if (c == null || c.value.isStreamingImages) return;
    await c.startImageStream(_onFrame);
    _watchFrames(c);
  }

  /// Fires if a newly opened camera hasn't delivered a frame in time.
  Timer? _noFrames;

  /// Reopen attempts since the last camera that delivered frames.
  int _reopens = 0;
  bool _reopening = false;

  /// CameraX sometimes opens a camera that never sends frames when it is
  /// reopened quickly (the device reports error 3 and the stream stays
  /// empty). If no frame arrives within 1.5 s, close that camera and open
  /// it again, at most twice in a row.
  void _watchFrames(CameraController c) {
    _noFrames?.cancel();
    _noFrames = Timer(const Duration(milliseconds: 1500), () async {
      if (!mounted ||
          !identical(_controller, c) ||
          identical(_framesFrom, c) ||
          _reopens >= 2) {
        return;
      }
      _reopens++;
      _reopening = true;
      _camLog('cam: no frames after 1500 ms, reopening ($_reopens)');
      try {
        setState(() => _controller = null);
        await c.dispose();
        await _startCamera();
      } finally {
        _reopening = false;
      }
    });
  }

  Future<void> _onFrame(CameraImage image) async {
    // The first frame from a newly opened camera: only now does it have
    // something to show, so only now may its preview fade in.
    final current = _controller;
    if (current != null && !identical(_framesFrom, current) && mounted) {
      _noFrames?.cancel();
      _reopens = 0;
      setState(() => _framesFrom = current);
    }
    _lastImage = image;
    _lastImageFrom = current;
    final grab = _stillGrab;
    if (grab != null && !grab.isCompleted) _grabStill(image, grab);
    // No scanning while Saved People is (even partly) on screen.
    if (_busy || _paused || _awayFromHome || !mounted) return;
    _busy = true;
    try {
      await _processFrame(image);
    } catch (e) {
      debugPrint('Frame processing failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (image.planes.length != 1) return; // expect a single NV21 plane
    final plane = image.planes.first;
    final camera = _cameras[_cameraIndex];

    // Rotation of the preview on screen (always portrait) and the rotation
    // that makes faces upright for the way the phone is actually held.
    final displayRotation = camera.sensorOrientation;
    final rotation = frameRotation(
      sensorOrientation: camera.sensorOrientation,
      deviceDegrees: _deviceRotation.degrees,
      frontCamera: _isFront,
    );
    final mlRotation =
        InputImageRotationValue.fromRawValue(rotation) ??
        InputImageRotation.rotation0deg;

    final input = InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: mlRotation,
        format: InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
    // Both detectors run on the same frame at the same time.
    final results = await Future.wait([
      _detector.processImage(input),
      _contourDetector.processImage(input),
    ]);
    final faces = results[0];
    final contourFaces = results[1];

    // ML Kit's coordinates are in the rotated frame; the preview is portrait.
    final frame = rotatedSize(image.width, image.height, rotation);
    final display = rotatedSize(image.width, image.height, displayRotation);
    final toDisplay = FrameMapper(
      width: image.width,
      height: image.height,
      from: rotation,
      to: displayRotation,
    );

    // Drop detections that are mostly outside the frame.
    final frameRect = Offset.zero & frame;
    final usable = faces.where((face) {
      final box = face.boundingBox;
      final inside = box.intersect(frameRect);
      final area = box.width * box.height;
      return area > 0 &&
          inside.width > 0 &&
          inside.height > 0 &&
          inside.width * inside.height / area >= _minInsideFraction;
    }).toList();

    final now = DateTime.now();
    final seen = <_Track>{};
    var contourCrops = 0;
    // The camera reuses its buffers, so faces keep a copy (one per frame).
    Uint8List? frameCopy;
    for (final face in usable) {
      final displayRect = toDisplay.rect(face.boundingBox);
      final track = _trackFor(face.trackingId, displayRect, now, seen);
      seen.add(track);
      track
        ..framesSeen += 1
        ..lastSeen = now
        ..rect = displayRect;

      // Dots and lines: detailed contours if the full-frame contour detector
      // found this face (it only reports the most prominent one), otherwise
      // contours from a crop around it, otherwise landmarks.
      FaceMesh? mesh;
      for (final cf in contourFaces) {
        if (_overlap(cf.boundingBox, face.boundingBox) > 0.5) {
          final m = meshFromContours(cf);
          if (m != null) mesh = _mapMesh(m, toDisplay);
          break;
        }
      }
      if (mesh == null && contourCrops++ < _maxContourCrops) {
        mesh = await _contourMeshFromCrop(
          image: image,
          nv21: plane.bytes,
          face: face,
          rotation: rotation,
          mlRotation: mlRotation,
          displayRotation: displayRotation,
          displayRect: displayRect,
        );
      }
      final detected = mesh ?? _mapMesh(meshFromLandmarks(face), toDisplay);
      final previous = track.mesh;
      track.mesh = previous == null || previous.kind != detected.kind
          ? detected
          : FaceMesh(
              kind: detected.kind,
              points: smoothPoints(
                previous.points,
                detected.points,
                faceWidth: displayRect.width,
              ),
              edges: detected.edges,
              major: detected.major,
            );

      // 1. Is the face clearly visible? (pose, size, landmarks, eyes)
      // An unclear frame never clears a result; it only pauses checking.
      final geometryHint = checkFaceGeometry(face, frame);
      if (geometryHint != null) {
        track.markUnclear(geometryHint, now);
        continue;
      }

      final due =
          !track.locked || now.difference(track.lastCheck) >= _recheckInterval;
      if (!due) {
        track.markClear();
        continue;
      }

      // 2. Crop and straighten the face, then check light and sharpness.
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
      final pixelHint = checkCropQuality(measureCrop(crop));
      if (pixelHint != null) {
        track.markUnclear(pixelHint, now);
        continue;
      }
      track.markClear();

      // 3. Recognize and add this check as a vote.
      final emb = widget.repo.embed(crop);
      final m = widget.repo.match(emb);
      final vote = switch (m.kind) {
        MatchKind.known => m.personId!,
        MatchKind.unknown => _voteUnknown,
        MatchKind.ambiguous => _voteAmbiguous,
      };
      frameCopy ??= Uint8List.fromList(plane.bytes);
      final wasLocked = track.locked;
      track
        ..crop = crop
        ..embedding = emb
        ..shot = _FrameShot(
          nv21: frameCopy,
          width: image.width,
          height: image.height,
          rotation: rotation,
          box: face.boundingBox,
          leftEye: leftEye,
          rightEye: rightEye,
          mirror: _isFront,
        )
        ..lastCheck = now
        ..addVote(
          vote,
          m.name,
          strong:
              m.kind == MatchKind.known &&
              m.score >= FaceRepository.matchThreshold + _switchMargin,
          veryWeak: m.score < _releaseBelow,
          claimed: (personId) => _tracks.values.any(
            (o) =>
                !identical(o, track) &&
                o.decided == personId &&
                now.difference(o.lastSeen) < _lostGrace,
          ),
          needed: _votesNeeded,
          window: _voteWindow,
          switchAfter: _switchAfter,
        );
      // A newly recognised person: send a pulse along the thread.
      if (!wasLocked && track.locked) ThreadPulse.instance.fire();
      debugPrint(
        'face ${track.key} rot=$rotation: ${m.kind.name} ${m.name ?? ''} '
        'score=${m.score.toStringAsFixed(3)} decided=${track.decided} '
        'locked=${track.locked}',
      );
    }

    // Forget people only after they've been out of view for a while.
    _tracks.removeWhere((_, t) => now.difference(t.lastSeen) > _lostGrace);

    // Draw faces seen now, plus ones missed for a moment so they don't blink.
    final live = <_LiveFace>[
      for (final t in _tracks.values.toSet())
        if (t.framesSeen >= _minFramesSeen &&
            t.rect != null &&
            t.mesh != null &&
            (seen.contains(t) || now.difference(t.lastSeen) < _holdMesh))
          _LiveFace(t.rect!, t.mesh!, t),
    ];

    if (!mounted) return;
    _imageSize = display;
    _live.value = live;
    _scan.value = scanStateFor([for (final f in live) f.track.decided]);
  }

  int _nextTrackKey = 1;

  /// Finds the track for a detected face. Uses ML Kit's tracking id; if the
  /// id is new, looks for a recently lost face in about the same place (ML
  /// Kit sometimes gives a face a new id after a blur or quick turn) so the
  /// person keeps their confirmed identity.
  _Track _trackFor(int? id, Rect rect, DateTime now, Set<_Track> taken) {
    final existing = id == null ? null : _tracks[id];
    if (existing != null && !taken.contains(existing)) return existing;

    _Track? best;
    var bestDist = double.infinity;
    int? bestKey;
    for (final e in _tracks.entries) {
      final t = e.value;
      final r = t.rect;
      if (r == null || taken.contains(t)) continue;
      if (now.difference(t.lastSeen) > _lostGrace) continue;
      if (t.lastSeen == now) continue; // already matched in this frame
      final ratio = rect.width / r.width;
      if (ratio < 0.6 || ratio > 1.67) continue;
      final dist = (rect.center - r.center).distance;
      if (dist < r.width * 0.6 && dist < bestDist) {
        best = t;
        bestDist = dist;
        bestKey = e.key;
      }
    }
    final track = best ?? _Track(_nextTrackKey++);
    if (bestKey != null && bestKey != id) _tracks.remove(bestKey);
    if (id != null) _tracks[id] = track;
    if (best != null) {
      debugPrint('track ${track.key} re-acquired as ml id $id');
    }
    return track;
  }

  static FaceMesh _mapMesh(FaceMesh m, FrameMapper mapper) => FaceMesh(
    kind: m.kind,
    points: mapper.points(m.points),
    edges: m.edges,
    major: m.major,
  );

  /// Crops the raw NV21 frame around [face], runs the contour detector on the
  /// crop and maps the points back onto the portrait preview.
  /// Returns null if no contours were found for this face.
  Future<FaceMesh?> _contourMeshFromCrop({
    required CameraImage image,
    required Uint8List nv21,
    required Face face,
    required int rotation,
    required InputImageRotation mlRotation,
    required int displayRotation,
    required Rect displayRect,
  }) async {
    final w = image.width, h = image.height;
    final toRaw = FrameMapper(width: w, height: h, from: rotation, to: 0);
    final r = toRaw.rect(face.boundingBox);
    // Some context around the face helps the detector; NV21 needs even
    // offsets and sizes because colour is stored per 2x2 block.
    final half = math.max(r.width, r.height) * 0.9;
    final x0 = (r.center.dx - half).floor().clamp(0, w - 2) & ~1;
    final y0 = (r.center.dy - half).floor().clamp(0, h - 2) & ~1;
    final cw = ((r.center.dx + half).ceil().clamp(x0 + 2, w) - x0) & ~1;
    final ch = ((r.center.dy + half).ceil().clamp(y0 + 2, h) - y0) & ~1;
    if (cw < 96 || ch < 96) return null;

    final out = Uint8List(cw * ch * 3 ~/ 2);
    for (var row = 0; row < ch; row++) {
      final src = (y0 + row) * w + x0;
      out.setRange(row * cw, row * cw + cw, nv21, src);
    }
    final uvSrc = w * h, uvDst = cw * ch;
    for (var row = 0; row < ch ~/ 2; row++) {
      final src = uvSrc + (y0 ~/ 2 + row) * w + x0;
      out.setRange(uvDst + row * cw, uvDst + row * cw + cw, nv21, src);
    }

    final found = await _contourDetector.processImage(
      InputImage.fromBytes(
        bytes: out,
        metadata: InputImageMetadata(
          size: Size(cw.toDouble(), ch.toDouble()),
          rotation: mlRotation,
          format: InputImageFormat.nv21,
          bytesPerRow: cw,
        ),
      ),
    );
    if (found.isEmpty) return null;
    final best = found.reduce(
      (a, b) =>
          a.boundingBox.width * a.boundingBox.height >=
              b.boundingBox.width * b.boundingBox.height
          ? a
          : b,
    );
    final mesh = meshFromContours(best);
    if (mesh == null) return null;

    final cropToRaw = FrameMapper(width: cw, height: ch, from: rotation, to: 0);
    final rawToDisplay = FrameMapper(
      width: w,
      height: h,
      from: 0,
      to: displayRotation,
    );
    final offset = Offset(x0.toDouble(), y0.toDouble());
    final points = [
      for (final p in mesh.points)
        rawToDisplay.point(cropToRaw.point(p) + offset),
    ];
    // Make sure the contours belong to this face and not a neighbour.
    var sum = Offset.zero;
    for (final p in points) {
      sum += p;
    }
    if (!displayRect
        .inflate(displayRect.width * 0.1)
        .contains(sum / points.length.toDouble())) {
      return null;
    }
    return FaceMesh(
      kind: mesh.kind,
      points: points,
      edges: mesh.edges,
      major: mesh.major,
    );
  }

  /// Intersection over union of two boxes.
  static double _overlap(Rect a, Rect b) {
    final i = a.intersect(b);
    if (i.width <= 0 || i.height <= 0) return 0;
    final inter = i.width * i.height;
    return inter / (a.width * a.height + b.width * b.height - inter);
  }

  // ---- Labels ----

  /// Saved details of verified people in view, by person id.
  final Map<int, Person> _details = {};
  final Set<int> _loadingDetails = {};
  final _meshHits = MeshHits();

  /// Money and reminder panel for a verified face, or null if the face
  /// isn't verified or the details are still loading.
  FaceInfo? _infoFor(_Track t) {
    if (!t.locked) return null;
    final id = t.decided!;
    if (id == widget.repo.ownerId) return _ownerInfo();
    final p = _details[id];
    if (p == null) {
      if (_loadingDetails.add(id)) {
        widget.repo.getPerson(id).then((person) {
          if (!mounted || !_loadingDetails.contains(id)) return;
          _loadingDetails.remove(id);
          if (person != null) setState(() => _details[id] = person);
        });
      }
      return null;
    }
    return personOverlay(p);
  }

  static Color _colorFor(_Track t, DateTime now) {
    if (t.locked) return _green;
    if (t.showHint(now, _unclearGrace)) return _red;
    return switch (t.decided) {
      null => _green,
      _voteUnknown => _orange,
      _voteAmbiguous => _amber,
      _ => _green,
    };
  }

  /// Text above a face: (label, second line, verified).
  static (String, String?, bool) _labelFor(_Track t, DateTime now) {
    if (t.showHint(now, _unclearGrace)) {
      final detail = t.hint == 'Look straight at the camera' ? null : t.hint;
      return (
        'Face is not visible',
        detail ?? 'Look straight at the camera',
        false,
      );
    }
    return switch (t.decided) {
      null => ('Scanning…', null, false),
      _voteUnknown => ('Unknown', 'Tap to add', false),
      _voteAmbiguous => ('Not sure', 'Tap to add', false),
      _ => (t.decidedName ?? '?', null, true),
    };
  }

  // ---- User actions ----

  Future<void> _onTapPreview(TapUpDetails d, Size widgetSize) async {
    _LiveFace? hit;
    // A verified person's info panel opens their details too.
    final panelKey = _meshHits.panelAt(d.localPosition);
    if (panelKey != null) {
      for (final f in _faces) {
        if (f.track.key == panelKey) hit = f;
      }
      if (hit != null) {
        await _tagFace(hit.track);
        return;
      }
    }
    for (final f in _faces) {
      final r = imageRectToWidget(f.rect, _imageSize, widgetSize, _isFront);
      if (r.inflate(24).contains(d.localPosition)) {
        hit = f;
        break;
      }
    }
    if (hit == null) return;
    await _tagFace(hit.track);
  }

  bool _opening = false;

  /// Opens the person's page for a recognized face, or the New Contact page
  /// for a face Lenzo doesn't know.
  Future<void> _tagFace(_Track t) async {
    if (_opening) return;
    if (_updateFor != null) {
      await _updatePhoto(t);
      return;
    }
    if (t.locked && t.decided == widget.repo.ownerId) {
      _openSettings();
      return;
    }
    if (t.locked) {
      final personId = t.decided!;
      final result = await _openPage<Object?>(
        (portrait) => PersonDetailScreen(
          repo: widget.repo,
          personId: personId,
          scanPortrait: portrait,
        ),
        t.shot,
      );
      // "Update face photo" from their page: tap their face next.
      if (result == PersonDetailScreen.updatePhoto && mounted) {
        setState(() => _updateFor = personId);
      }
      return;
    }

    final crop = t.crop;
    final emb = t.embedding;
    if (t.hint != null || crop == null || emb == null || t.decided == null) {
      showLenzoMessage(
        context,
        t.hint != null
            ? 'Face is not clearly visible. ${t.hint}.'
            : 'Hold steady while Lenzo verifies this face.',
      );
      return;
    }
    final message = await _openPage<String>(
      (portrait) => NewContactScreen(
        repo: widget.repo,
        faceCrop: crop,
        embedding: emb,
        portrait: portrait,
      ),
      t.shot,
    );
    if (message != null && mounted) showLenzoSuccess(context, message);
  }

  /// Pauses scanning and opens a full-screen page, with a portrait cut from
  /// [shot] if there is one. Returns the page's result.
  Future<T?> _openPage<T>(
    Widget Function(Uint8List? portrait) builder,
    _FrameShot? shot,
  ) async {
    _opening = true;
    _paused = true;
    try {
      Uint8List? portrait;
      try {
        portrait = shot?.portraitJpeg();
      } catch (e) {
        debugPrint('Portrait failed: $e');
      }
      if (!mounted) return null;
      return await Navigator.of(context)
          .push<T>(LenzoSwipeRoute<T>(builder: (_) => builder(portrait)));
    } finally {
      _opening = false;
      _paused = false;
    }
  }

  bool _switching = false;

  /// Number of switches, to turn the switch icon half a turn each time.
  int _switches = 0;

  /// Width / height of the camera frame on screen. Set from the first
  /// camera that opens and then kept, so switching never resizes the frame.
  /// Until then 9:16, the shape ResolutionPreset.high gives in portrait.
  double _frameRatio = 9 / 16;
  bool _frameRatioKnown = false;

  /// The camera that has delivered at least one frame. A controller is
  /// "initialized" before its first frame arrives; fading its preview in
  /// before then shows an empty frame.
  CameraController? _framesFrom;

  /// True once any camera has shown a frame (for the start-up prompt).
  bool _everShown = false;

  /// The old camera's last frame, shown (slightly dimmed) until the new
  /// preview fades in over it. Mirrored if it came from the front camera.
  ui.Image? _still;
  bool _stillMirrored = false;
  Completer<void>? _stillGrab;

  /// The latest frame and the camera it came from: the fallback still when
  /// no fresh frame arrives quickly at the start of a switch.
  CameraImage? _lastImage;
  CameraController? _lastImageFrom;

  /// True once a switch has taken long enough to show a small spinner.
  bool _slowSwitch = false;

  void _grabStill(CameraImage image, Completer<void> done) {
    try {
      final shot = previewRgbaFromNv21(
        nv21: image.planes.first.bytes,
        width: image.width,
        height: image.height,
        rotation: _cameras[_cameraIndex].sensorOrientation,
      );
      ui.decodeImageFromPixels(
        shot.rgba,
        shot.width,
        shot.height,
        ui.PixelFormat.rgba8888,
        (img) {
          if (!mounted) {
            img.dispose();
          } else {
            _still?.dispose();
            _still = img;
            _stillMirrored = _isFront;
          }
          if (!done.isCompleted) done.complete();
        },
      );
    } catch (e) {
      if (!done.isCompleted) done.complete();
    }
  }

  /// Switches between front and back cameras without covering the camera
  /// area: the last frame stays visible, the new preview crossfades in
  /// once it has frames, and a small spinner shows only if that takes a
  /// while. Taps during a switch are ignored. If the other camera fails,
  /// the previous one is restored.
  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _switching || _reopening) return;
    // A camera that is still opening (no frame yet) is left alone: closing
    // it while CameraX configures its session can leave CameraX unable to
    // open either camera.
    final current = _controller;
    if (current != null && !identical(_framesFrom, current)) return;
    _switching = true;
    _paused = true;
    final clock = Stopwatch()..start();
    _camLog('cam: switch tapped');
    HapticFeedback.selectionClick();
    setState(() => _switches++);
    _faces = const [];
    _tracks.clear(); // a different camera sees different faces
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && _switching) setState(() => _slowSwitch = true);
    });
    try {
      // One frame of the current camera, if it's still streaming; never
      // waits long.
      final grab = _stillGrab = Completer<void>();
      await grab.future.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () {},
      );
      _stillGrab = null;
      final last = _lastImage;
      if (!grab.isCompleted &&
          last != null &&
          identical(_lastImageFrom, current)) {
        // No fresh frame in time: use the latest one instead.
        final done = Completer<void>();
        _grabStill(last, done);
        await done.future.timeout(
          const Duration(milliseconds: 100),
          onTimeout: () {},
        );
      }
      _lastImage = null;
      _lastImageFrom = null;
      _camLog(
        'cam: still ${_still == null ? 'missing' : 'ready'} '
        'at ${clock.elapsedMilliseconds} ms',
      );
      final previous = _cameraIndex;
      final old = _controller;
      if (mounted) setState(() => _controller = null);
      await old?.dispose();
      _camLog('cam: old closed at ${clock.elapsedMilliseconds} ms');
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
      await _startCamera();
      _camLog(
        'cam: new ${_controller == null ? 'FAILED' : 'ready'} at '
        '${clock.elapsedMilliseconds} ms',
      );
      if (mounted && _controller == null) {
        // The other camera didn't open: go back to the one that worked.
        _cameraIndex = previous;
        setState(() => _error = null);
        await _startCamera();
        if (mounted) showLenzoMessage(context, "Couldn't switch camera");
      }
    } finally {
      _paused = false;
      // Taps stay ignored until the new preview has faded in (see
      // _endSwitch), so a double tap can't start a second switch the moment
      // the first camera opens. Released after 5 s regardless (long enough
      // to cover a reopen by _watchFrames).
      if (_controller == null) {
        _endSwitch();
      } else {
        _switchGuard?.cancel();
        _switchGuard = Timer(const Duration(seconds: 5), _endSwitch);
      }
      _camLog('cam: switch done at ${clock.elapsedMilliseconds} ms');
    }
  }

  Timer? _switchGuard;

  /// Shows the spinner if the new preview hasn't faded in after 1.8 s. A
  /// normal switch on this hardware takes 1.2-1.7 s, so it only appears
  /// when something is slower than usual.
  Timer? _slowTimer;

  void _endSwitch() {
    _switchGuard?.cancel();
    _switchGuard = null;
    _slowTimer?.cancel();
    _slowTimer = null;
    if (!_switching) return;
    _switching = false;
    if (mounted) setState(() => _slowSwitch = false);
  }

  /// Person whose face photo is being updated: the next face tapped is
  /// saved for them. Null when not updating.
  int? _updateFor;

  Future<void> _updatePhoto(_Track t) async {
    final personId = _updateFor!;
    final name = widget.repo.nameOf(personId);
    if (name == null) {
      setState(() => _updateFor = null);
      return;
    }
    if (t.locked && t.decided != personId) {
      showLenzoMessage(
        context,
        'This face is recognized as ${t.decidedName}. '
        'Point the camera at $name.',
      );
      return;
    }
    final crop = t.crop;
    final emb = t.embedding;
    if (t.hint != null || crop == null || emb == null) {
      showLenzoMessage(
        context,
        t.hint != null
            ? 'Face is not clearly visible. ${t.hint}.'
            : 'Hold steady while Lenzo scans this face.',
      );
      return;
    }
    _opening = true;
    _paused = true;
    try {
      Uint8List? portrait;
      try {
        portrait = t.shot?.portraitJpeg();
      } catch (e) {
        debugPrint('Portrait failed: $e');
      }
      final photo = portrait ?? faceThumbnailJpeg(crop);
      final ok = await showLenzoConfirm(
        context,
        image: FaceImage(bytes: photo),
        title: "Update $name's photo?",
        message: 'Lenzo will use this face to recognize $name.',
        confirm: 'Update photo',
      );
      if (!ok || !mounted) return;
      await widget.repo.addFace(
        personId: personId,
        embedding: emb,
        faceCrop: crop,
      );
      if (portrait != null) await widget.repo.setPhoto(personId, portrait);
      t.forget(); // recognize again with the new photo
      if (!mounted) return;
      setState(() => _updateFor = null);
      showLenzoSuccess(context, '$name\'s photo is updated');
    } finally {
      _opening = false;
      _paused = false;
    }
  }

  // ---- Swipe to Saved People ----

  /// How far Saved People has been pulled in by hand (0..1). While the
  /// finger is down this screen draws that page itself; on release the real
  /// page opens from exactly that point. (Opening a page cancels the touch,
  /// so it can't follow the finger.)
  /// Home (0) and Saved People (1), side by side with native page physics.
  /// Settings (0), Home (1) and Saved People (2), side by side.
  final _pages = PageController(initialPage: _homePage);
  static const _settingsPage = 0, _homePage = 1, _peoplePage = 2;

  /// Current scroll position of [_pages] in pages, read without rebuilding.
  /// Home until the page view has been laid out.
  double get _pageOffset => _pages.hasClients && _pages.position.haveDimensions
      ? (_pages.page ?? _homePage.toDouble())
      : _homePage.toDouble();

  /// Saved people, kept ready so the page appears instantly on a swipe.
  List<Person>? _peopleCache;

  /// The owner's panel: the same two totals as Saved People's summary.
  /// Total Lent is what everyone still owes you (each Money Lent minus its
  /// reductions), Total Borrowed what you still owe; so every Add and Less
  /// shows here at once. A total of ₹0 is left out; with nothing open there
  /// is no card. Null until the contacts have loaded.
  FaceInfo? _ownerInfo() {
    final people = _peopleCache;
    if (people == null) return null;
    final m = MoneySummary.of(people);
    final rows = [
      if (m.toReceivePaise > 0)
        InfoRow('Total Lent', formatRupeesCompact(m.toReceivePaise)),
      if (m.toPayPaise > 0)
        InfoRow('Total Borrowed', formatRupeesCompact(m.toPayPaise)),
    ];
    return rows.isEmpty ? null : FaceInfo(rows, compact: true);
  }

  /// Open balances from the owner's side: To Receive and To Pay, never
  /// combined, and a flag when records need review. Zero rows are left out.
  static List<InfoRow> _moneyRows({
    required int receive,
    required int pay,
    int review = 0,
  }) {
    return [
      if (receive > 0)
        InfoRow('To Receive', formatRupeesCompact(receive), color: _green),
      if (pay > 0) InfoRow('To Pay', formatRupeesCompact(pay), color: _amber),
      if (review > 0)
        InfoRow(
          'Needs review',
          review == 1 ? 'Check records' : '$review people',
          color: _orange,
        ),
    ];
  }

  /// The app owner, for the profile button.
  Person? _owner;

  Future<void> _loadPeopleCache() async {
    final people = await widget.repo.getPersons();
    final owner = await widget.repo.getOwner();
    if (!mounted) return;
    _peopleCache = people;
    if (owner?.thumbnailPath != _owner?.thumbnailPath ||
        owner?.name != _owner?.name) {
      setState(() => _owner = owner);
    } else {
      _owner = owner;
    }
  }

  /// How far the pages are from Home (0 = on Home, 1 = a page over).
  double get _fromHome => (_pageOffset - _homePage).abs();

  /// Settings or Saved People is (even partly) on screen.
  bool get _awayFromHome => _fromHome > 0.01;

  void _openSettings() {
    if (_opening || _switching) return;
    _pages.animateToPage(
      _settingsPage,
      duration: _pageDuration,
      curve: Curves.easeOutCubic,
    );
  }

  static const _pageDuration = Duration(milliseconds: 280);

  void _openPeople() {
    if (_opening || _switching) return;
    _pages.animateToPage(
      _peoplePage,
      duration: _pageDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _closePeople() {
    FocusManager.instance.primaryFocus?.unfocus();
    _pages.animateToPage(
      _homePage,
      duration: _pageDuration,
      curve: Curves.easeOutCubic,
    );
  }

  /// Swipes handed over from the first Saved People tab: move the page
  /// with the finger, then settle on Home or Saved People.
  void _peopleEdgeDrag(double delta) {
    if (!_pages.hasClients) return;
    final pos = _pages.position;
    // Between Home and Saved People only; never on into Settings.
    final home = pos.viewportDimension * _homePage;
    _pages.jumpTo((pos.pixels + delta).clamp(home, pos.maxScrollExtent));
  }

  void _peopleEdgeRelease(double velocity) {
    if (!_pages.hasClients) return;
    final home =
        velocity > 400 || (velocity > -400 && _pageOffset < _homePage + 0.6);
    if (home) {
      _closePeople();
    } else {
      _openPeople();
    }
  }

  /// "Update Photo" on Saved People: back to the camera to scan that face.
  void _startPhotoUpdate(int personId) {
    _closePeople();
    setState(() => _updateFor = personId);
  }

  /// Settings, Home and Saved People in a native [PageView]: a swipe right
  /// on Home brings in Settings, a swipe left Saved People; pages follow the
  /// finger and settle with Flutter's page physics. All are kept alive, so
  /// the camera never restarts and the pages are always ready.
  Widget _withPeople(Widget camera) {
    return PopScope(
      // System back returns to Home first.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_awayFromHome) {
          _closePeople(); // back to Home
        } else {
          SystemNavigator.pop();
        }
      },
      // One background and one thread under all three pages, which are
      // transparent, so swiping never shows a seam or a colour change.
      child: ColoredBox(
        color: Lenzo.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageThread(pages: _pages, pageCount: 3),
            SharedBackground(
              child: PageView(
                key: const PageStorageKey('home-pages'),
                controller: _pages,
                // No swiping mid camera switch or while a page is opening.
                physics: _switching
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(parent: ClampingScrollPhysics()),
                onPageChanged: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                children: [
                  _KeepAlive(
                    child: RepaintBoundary(
                      child: ScaffoldMessenger(
                        child: OwnerProfileScreen(
                          repo: widget.repo,
                          onBack: _closePeople,
                        ),
                      ),
                    ),
                  ),
                  // Home stays as it is while a page slides over it: same
                  // background colour everywhere, no dimming.
                  _KeepAlive(child: RepaintBoundary(child: camera)),
                  _KeepAlive(
                    child: RepaintBoundary(
                      // Own messenger, so its messages show on this page only.
                      child: ScaffoldMessenger(
                        child: PeopleScreen(
                          repo: widget.repo,
                          initialPeople: _peopleCache,
                          onBack: _closePeople,
                          onUpdatePhoto: _startPhotoUpdate,
                          onEdgeDrag: _peopleEdgeDrag,
                          onEdgeRelease: _peopleEdgeRelease,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- UI ----

  /// The camera area: one rounded frame of fixed shape. Inside it, the
  /// live preview fades in (180 ms) over the last frame of the previous
  /// camera (during a switch) or the plain surface (at start-up). Nothing
  /// inside changes the frame's size.
  Widget _previewContent(CameraController? c) {
    final ready = c != null && c.value.isInitialized;
    // Has frames, so its preview can be shown.
    final live = ready && identical(_framesFrom, c);
    if (ready && !_frameRatioKnown) {
      // CameraPreview in portrait is 1 / aspectRatio wide per unit height.
      _frameRatio = 1 / c.value.aspectRatio;
      _frameRatioKnown = true;
    }
    final still = _still;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: LenzoShadows.raised,
      ),
      position: DecorationPosition.background,
      child: AspectRatio(
        aspectRatio: _frameRatio,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Lenzo.hairline),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Lenzo.surface),
                    // The previous camera's last frame, filling the frame.
                    if (still != null && !(live && _previewShown))
                      Transform.flip(
                        flipX: _stillMirrored,
                        child: RawImage(
                          key: cameraStillKey,
                          image: still,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                          color: LenzoColors.ink.withValues(alpha: 0.25),
                          colorBlendMode: BlendMode.srcATop,
                        ),
                      ),
                    if (!ready && still == null && !_everShown)
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.face_outlined,
                              color: Lenzo.textSecondary,
                              size: 28,
                            ),
                            SizedBox(height: LenzoSpacing.x3),
                            Text(
                              'Look at the camera',
                              style: LenzoType.secondary,
                            ),
                          ],
                        ),
                      ),
                    if (ready)
                      TweenAnimationBuilder<double>(
                        key: ValueKey(c),
                        // Kept transparent until the camera has frames.
                        tween: Tween(begin: 0, end: live ? 1 : 0),
                        duration: LenzoMotion.of(
                          context,
                          const Duration(milliseconds: 180),
                        ),
                        curve: Curves.easeInOutCubic,
                        onEnd: () {
                          if (mounted && live && identical(c, _controller)) {
                            _camLog('cam: preview faded in');
                            _endSwitch();
                            setState(() {
                              _previewShown = true;
                              _everShown = true;
                              _still?.dispose();
                              _still = null;
                            });
                          }
                        },
                        builder: (_, v, child) =>
                            Opacity(opacity: v, child: child),
                        // Fills the frame; a camera with a different shape is
                        // cropped to it instead of resizing the frame.
                        // At its real size (so face labels keep their size),
                        // just large enough to cover the frame, centred.
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final r = 1 / c.value.aspectRatio; // width / height
                            final w = math.max(box.maxWidth, box.maxHeight * r);
                            return OverflowBox(
                              minWidth: w,
                              maxWidth: w,
                              minHeight: w / r,
                              maxHeight: w / r,
                              child: CameraPreview(c, child: _buildOverlay()),
                            );
                          },
                        ),
                      ),
                    // Only when a switch is slow: a small spinner, nothing else.
                    Center(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _slowSwitch && !(live && _previewShown)
                              ? 1
                              : 0,
                          duration: LenzoMotion.of(context, LenzoMotion.press),
                          child: const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Lenzo.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Scanning glow, outside the clip so it can soften the edge.
            Positioned.fill(child: _scanBorder(live)),
          ],
        ),
      ),
    );
  }

  /// The glow around the camera frame. Animates only while the camera
  /// is live, the app is in front, and Home is the page on screen.
  Widget _scanBorder(bool live) {
    return AnimatedBuilder(
      animation: _pages,
      builder: (context, _) => ValueListenableBuilder<ScanState>(
        valueListenable: _scan,
        builder: (context, state, _) => ScanBorder(
          state: state,
          radius: 24,
          active: live && !_awayFromHome && !_paused,
        ),
      ),
    );
  }

  /// Whether the current camera has finished fading in.
  bool _previewShown = false;

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return _withPeople(
      Scaffold(
        backgroundColor: Colors.transparent,
        // Same height as the old app bar, so the camera keeps its size.
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(_headerHeight),
          child: _ScannerHeader(
            onPeople: _openPeople,
            onSettings: _openSettings,
          ),
        ),
        body: Column(
          children: [
            if (_updateFor != null)
              _UpdateBanner(
                name: widget.repo.nameOf(_updateFor!) ?? 'this person',
                onCancel: () => setState(() => _updateFor = null),
              ),
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Lenzo.textPrimary),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _previewContent(c),
                      ),
              ),
            ),
            ValueListenableBuilder<List<_LiveFace>>(
              valueListenable: _live,
              builder: (_, faces, _) => _BottomBar(
                faceCount: faces.length,
                switches: _switches,
                onSwitch: _cameras.length > 1 && (c != null || _switching)
                    ? _switchCamera
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return ValueListenableBuilder<List<_LiveFace>>(
      valueListenable: _live,
      builder: (_, _, _) => _overlay(),
    );
  }

  Widget _overlay() {
    final now = DateTime.now();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _onTapPreview(d, size),
          child: FaceMeshOverlay(
            imageSize: _imageSize,
            mirror: _isFront,
            labelRotation: _deviceRotation.degrees,
            hits: _meshHits,
            faces: [
              for (final f in _faces)
                () {
                  var (label, sub, verified) = _labelFor(f.track, now);
                  final t = f.track;
                  if (_updateFor != null &&
                      !t.showHint(now, _unclearGrace) &&
                      (!t.locked || t.decided == _updateFor)) {
                    sub = 'Tap to use this face';
                  }
                  return MeshFace(
                    key: f.track.key,
                    mesh: f.mesh,
                    color: _colorFor(f.track, now),
                    label: label,
                    sublabel: sub,
                    verified: verified,
                    info: _infoFor(f.track),
                  );
                }(),
            ],
          ),
        );
      },
    );
  }
}

/// Keeps a page of the home [PageView] built while it is off screen.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Shown while updating someone's face photo from Saved People.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.name, required this.onCancel});
  final String name;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Color.alphaBlend(_orange.withValues(alpha: 0.12), Lenzo.surface),
        border: Border.all(color: _orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.photo_camera_outlined, color: _orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Updating $name\'s photo. ',
                style: const TextStyle(fontWeight: FontWeight.w600),
                children: const [
                  TextSpan(
                    text: 'Tap their face.',
                    style: TextStyle(
                      color: Lenzo.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(color: Lenzo.textPrimary, fontSize: 14),
            ),
          ),
          IconButton(
            tooltip: 'Cancel photo update',
            onPressed: onCancel,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              color: Lenzo.textSecondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

/// Header: Settings on the left, the logo centred on the screen (whatever
/// the icons' widths), Saved People on the right. Plain background, the
/// same as Saved People.
const double _headerHeight = 52;

class _ScannerHeader extends StatelessWidget {
  const _ScannerHeader({required this.onPeople, required this.onSettings});
  final VoidCallback onPeople;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lenzoSystemUi,
      // Transparent: the shared background and thread show through.
      child: ColoredBox(
        color: const Color(0x00000000),
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: SizedBox(
            height: _headerHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 64),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: LenzoBrandLogo(height: 26),
                  ),
                ),
                Positioned(
                  left: 8,
                  child: _HeaderButton(
                    tooltip: 'Settings',
                    icon: Icons.settings_outlined,
                    onTap: onSettings,
                  ),
                ),
                Positioned(
                  right: 8,
                  child: _HeaderButton(
                    tooltip: 'Saved people',
                    icon: Icons.people_outline_rounded,
                    onTap: onPeople,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Header action: a plain outlined icon, no outline or fill.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: LenzoIconButton(
        icon: icon,
        tooltip: tooltip,
        size: 23,
        onPressed: onTap,
      ),
    );
  }
}

/// Slim rounded bar: face count on the left, camera switch on the right.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.faceCount,
    required this.onSwitch,
    this.switches = 0,
  });
  final int faceCount;
  final VoidCallback? onSwitch;

  /// The switch icon turns half a turn per switch.
  final int switches;

  @override
  Widget build(BuildContext context) {
    final active = faceCount > 0;
    final text = !active
        ? 'No faces detected'
        : '$faceCount face${faceCount == 1 ? '' : 's'} detected';
    return SafeArea(
      top: false,
      child: Padding(
        // 8 + 52 + 8 = 68, the same space as before, so the camera keeps
        // its size.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: Lenzo.elevated,
            boxShadow: const [
              BoxShadow(
                color: Color(0x59000000),
                blurRadius: 20,
                spreadRadius: -6,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.center_focus_weak_rounded,
                  key: ValueKey(active),
                  size: 20,
                  color: active ? Lenzo.accent : Lenzo.accentMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    text,
                    key: ValueKey(text),
                    style: TextStyle(
                      color: active ? Lenzo.textPrimary : Lenzo.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Switch camera',
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onSwitch,
                    child: Ink(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Lenzo.accent.withValues(
                          alpha: onSwitch == null ? 0.06 : 0.14,
                        ),
                      ),
                      child: AnimatedRotation(
                        turns: switches * 0.5,
                        duration: LenzoMotion.of(
                          context,
                          const Duration(milliseconds: 200),
                        ),
                        curve: Curves.easeInOutCubic,
                        child: Icon(
                          Icons.cameraswitch_outlined,
                          size: 20,
                          color: onSwitch == null
                              ? Lenzo.accentMuted.withValues(alpha: 0.4)
                              : Lenzo.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Camera timing log for device tests; silent in release builds.
void _camLog(String message) {
  if (!kReleaseMode) debugPrint(message);
}

/// [notes] as shown under a recognised face: whitespace collapsed to single
/// spaces and cut to 140 characters (the pill shows up to three lines), or
/// null when there is no note.
String? noteForOverlay(String? notes) {
  final t = (notes ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return null;
  return t.length <= 140 ? t : '${t.substring(0, 139).trimRight()}…';
}

/// What the camera shows beside a recognised contact: only details that
/// exist, in this order: To Receive, To Pay (outstanding balances, each
/// reduced only by its own repayments; ₹0 is left out), Needs review, the
/// personal note, and the payment reminder. Null when there is nothing but
/// a name, so only the name and check mark show.
FaceInfo? personOverlay(Person p, {DateTime? now}) {
  final rows = _CameraScreenState._moneyRows(
    receive: p.toReceivePaise,
    pay: p.toPayPaise,
    review: p.needsReview ? 1 : 0,
  );
  final note = noteForOverlay(p.notes);
  final reminder = p.reminder;
  final after = [
    if (reminder != null)
      InfoRow('Reminder', formatShortDate(reminder, now: now)),
  ];
  if (rows.isEmpty && after.isEmpty) {
    return note == null ? null : FaceInfo.note(note);
  }
  return FaceInfo(rows, note: note, after: after);
}
