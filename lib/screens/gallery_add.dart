import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../design/design.dart';
import '../services/face_repository.dart';
import '../services/gallery_face.dart';
import '../widgets/lenzo_ui.dart';
import '../widgets/swipe_route.dart';
import 'new_contact_screen.dart';
import 'photo_picker.dart';

/// Adds a person from a gallery photo: pick a photo, find the faces in it,
/// choose one, then fill in the usual Register Person form. The face is
/// saved with the same face model and storage as camera registrations, so
/// the live camera recognises them.
///
/// Returns the form's success message, or null if nothing was saved.
Future<String?> addPersonFromGallery(
  BuildContext context,
  FaceRepository repo, {
  PhotoSource source = const DevicePhotoSource(),
}) async {
  while (context.mounted) {
    // Lenzo's own picker (handles access to the photos itself).
    final path = await pickLenzoPhoto(context, source: source);
    if (path == null || !context.mounted) return null; // backed out

    final found = await _withProgress(context, findGalleryFaces(path));
    if (!context.mounted) return null;
    final choice = await showModalBottomSheet<_Choice>(
      context: context,
      backgroundColor: LenzoColors.backgroundElevated,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(LenzoRadius.card),
        ),
      ),
      builder: (_) => FaceChoiceSheet(found: found),
    );
    if (choice == null || !context.mounted) return null;
    if (choice.anotherPhoto) continue;
    final face = choice.face!;

    final embedding = repo.embed(face.crop);
    final match = repo.match(embedding);
    final id = match.personId;
    if (match.kind == MatchKind.known && id != null) {
      if (id == repo.ownerId) {
        showLenzoMessage(
          context,
          'This is your own face. Choose someone else.',
        );
        continue;
      }
      // Don't create a second contact for someone already saved by
      // accident; their records are never changed here.
      final addAnyway = await showLenzoConfirm(
        context,
        icon: Icons.face_outlined,
        title: 'Looks like ${match.name ?? 'a saved contact'}',
        message:
            'This face matches someone already in Lenzo. Add a new, separate '
            'contact anyway?',
        cancel: 'Choose another',
        confirm: 'Add anyway',
      );
      if (!context.mounted) return null;
      if (!addAnyway) continue;
    }

    return Navigator.of(context).push<String>(
      LenzoSwipeRoute<String>(
        builder: (_) => NewContactScreen(
          repo: repo,
          faceCrop: face.crop,
          embedding: embedding,
          portrait: face.portrait,
        ),
      ),
    );
  }
  return null;
}

Future<T> _withProgress<T>(BuildContext context, Future<T> work) async {
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: LenzoColors.accent,
          ),
        ),
      ),
    ),
  );
  try {
    return await work;
  } finally {
    nav.pop();
  }
}

class _Choice {
  const _Choice.face(GalleryFace this.face) : anotherPhoto = false;
  const _Choice.another() : face = null, anotherPhoto = true;
  final GalleryFace? face;
  final bool anotherPhoto;
}

/// The faces found in a photo: one is shown as a preview, several can be
/// chosen between. With none, explains why and offers another photo.
class FaceChoiceSheet extends StatefulWidget {
  const FaceChoiceSheet({super.key, required this.found});
  final GalleryFaces found;

  @override
  State<FaceChoiceSheet> createState() => _FaceChoiceSheetState();
}

class _FaceChoiceSheetState extends State<FaceChoiceSheet> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final faces = widget.found.faces;
    final none = faces.isEmpty;
    final title = none
        ? (widget.found.error == GalleryFaceError.unreadable
              ? "Couldn't open this photo"
              : 'No face found')
        : faces.length == 1
        ? 'Face found'
        : 'Choose a face';
    final text = none
        ? (widget.found.error == GalleryFaceError.unreadable
              ? 'Choose a different image.'
              : 'Choose a photo where the face is clear, not too small, and '
                    'facing the camera.')
        : faces.length == 1
        ? 'Continue to add this person.'
        : '${faces.length} faces in this photo. Tap the one to add.';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LenzoSpacing.screen,
          LenzoSpacing.x5,
          LenzoSpacing.screen,
          LenzoSpacing.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (none)
              const Icon(
                Icons.face_retouching_off_outlined,
                color: LenzoColors.textSecondary,
                size: 32,
              ),
            if (none) const SizedBox(height: LenzoSpacing.x3),
            Text(
              title,
              textAlign: TextAlign.center,
              style: LenzoType.sectionHeading,
            ),
            const SizedBox(height: LenzoSpacing.x1),
            Text(
              text,
              textAlign: TextAlign.center,
              style: LenzoType.body.copyWith(color: LenzoColors.textSecondary),
            ),
            if (!none) ...[
              const SizedBox(height: LenzoSpacing.x5),
              Center(
                child: Wrap(
                  spacing: LenzoSpacing.x3,
                  runSpacing: LenzoSpacing.x3,
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 0; i < faces.length && i < 8; i++)
                      _FaceOption(
                        bytes: faces[i].thumbnail,
                        size: faces.length == 1 ? 120 : 76,
                        selected: i == _selected,
                        label: 'Face ${i + 1} of ${faces.length}',
                        onTap: () => setState(() => _selected = i),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: LenzoSpacing.x6),
            if (!none) ...[
              LenzoButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onPressed: () =>
                    Navigator.of(context).pop(_Choice.face(faces[_selected])),
              ),
              const SizedBox(height: LenzoSpacing.x3),
            ],
            LenzoButton(
              label: 'Choose another photo',
              icon: Icons.photo_library_outlined,
              kind: none
                  ? LenzoButtonKind.primary
                  : LenzoButtonKind.outlineAccent,
              onPressed: () =>
                  Navigator.of(context).pop(const _Choice.another()),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceOption extends StatelessWidget {
  const _FaceOption({
    required this.bytes,
    required this.size,
    required this.selected,
    required this.label,
    required this.onTap,
  });
  final Uint8List bytes;
  final double size;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: LenzoMotion.of(context, LenzoMotion.press),
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              width: 2,
              color: selected ? LenzoColors.accent : Colors.transparent,
            ),
          ),
          child: ClipOval(child: Image.memory(bytes, fit: BoxFit.cover)),
        ),
      ),
    );
  }
}
