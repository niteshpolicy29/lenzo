import 'package:camera/camera.dart';

/// The two cameras Lenzo uses: the main rear camera and the main front
/// camera, rear first. Extra lenses (ultra-wide, macro, depth, telephoto)
/// are left out, so switching always goes rear ↔ front.
///
/// For each side: a camera reported as the standard wide lens wins; then
/// the lowest Camera2 id, since Android lists each side's default camera
/// first (macro and depth sensors get later ids); then list order. If a
/// side has no camera, the result has only the other one.
List<CameraDescription> primaryCameras(List<CameraDescription> all) {
  CameraDescription? pick(CameraLensDirection side) {
    final list = all.where((c) => c.lensDirection == side).toList();
    if (list.isEmpty) return null;
    int rank(CameraDescription c) => switch (c.lensType) {
      CameraLensType.wide => 0,
      CameraLensType.unknown => 1,
      _ => 2, // ultra-wide, telephoto
    };
    int id(CameraDescription c) => int.tryParse(c.name) ?? 1 << 30;
    final order = [for (var i = 0; i < list.length; i++) i]
      ..sort((a, b) {
        final r = rank(list[a]).compareTo(rank(list[b]));
        if (r != 0) return r;
        final d = id(list[a]).compareTo(id(list[b]));
        return d != 0 ? d : a.compareTo(b);
      });
    return list[order.first];
  }

  final back = pick(CameraLensDirection.back);
  final front = pick(CameraLensDirection.front);
  final chosen = [?back, ?front];
  // No front or back camera at all (e.g. only an external one).
  return chosen.isEmpty && all.isNotEmpty ? [all.first] : chosen;
}
