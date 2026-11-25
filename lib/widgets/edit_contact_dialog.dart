import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../design/design.dart';
import '../services/face_repository.dart';
import '../theme/lenzo_theme.dart';
import 'lenzo_ui.dart';

/// What the Edit Contact dialog asked for.
sealed class EditContactResult {
  const EditContactResult();
}

/// Save this new name.
class ContactRename extends EditContactResult {
  const ContactRename(this.name);
  final String name;
}

/// Scan their face again with the camera.
class ContactUpdatePhoto extends EditContactResult {
  const ContactUpdatePhoto();
}

/// Rename a contact, or start updating their face photo.
class EditContactDialog extends StatefulWidget {
  const EditContactDialog({super.key, required this.person});
  final Person person;

  @override
  State<EditContactDialog> createState() => _EditContactDialogState();
}

class _EditContactDialogState extends State<EditContactDialog> {
  late final _ctrl = TextEditingController(text: widget.person.name);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _ctrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name');
      return;
    }
    Navigator.of(context).pop(ContactRename(name));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    return Dialog(
      backgroundColor: Lenzo.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Lenzo.accent.withValues(alpha: 0.3)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: ClipOval(child: FaceImage(path: p.thumbnailPath)),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Contact',
                          style: TextStyle(
                            color: Lenzo.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Update their name or face photo',
                          style: TextStyle(
                            color: Lenzo.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Name',
                style: TextStyle(color: Lenzo.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _ctrl,
                autofocus: true,
                maxLength: 40,
                buildCounter: (
                  _, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: Lenzo.textPrimary, fontSize: 16),
                cursorColor: Lenzo.accent,
                decoration: lenzoInput(
                  hint: 'Full name',
                  dense: true,
                  raised: true,
                  error: _error,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: LenzoSpacing.x4),
              EditorActions(
                saving: false,
                onCancel: () => Navigator.of(context).pop(),
                onSave: _save,
              ),
              const SizedBox(height: LenzoSpacing.x3),
              // A real button, full width, under Cancel and Save.
              LenzoButton(
                label: 'Update face photo',
                icon: Icons.photo_camera_outlined,
                kind: LenzoButtonKind.outlineAccent,
                compact: true,
                onPressed: () =>
                    Navigator.of(context).pop(const ContactUpdatePhoto()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the Edit Contact dialog for [p] and saves a new name. Returns
/// true if the user chose to update the face photo instead.
Future<bool> editContact(
  BuildContext context,
  FaceRepository repo,
  Person p,
) async {
  FocusScope.of(context).unfocus();
  final result = await showDialog<EditContactResult>(
    context: context,
    builder: (_) => EditContactDialog(person: p),
  );
  if (result == null || !context.mounted) return false;
  switch (result) {
    case ContactRename(:final name):
      if (name == p.name) return false;
      final clash = await repo.findPersonByName(name);
      if (!context.mounted) return false;
      if (clash != null && clash != p.id) {
        showLenzoMessage(context, '$name is already saved in Lenzo.');
        return false;
      }
      await repo.renamePerson(p.id, name);
      if (context.mounted) showLenzoSuccess(context, 'Renamed to $name');
      return false;
    case ContactUpdatePhoto():
      return true;
  }
}
