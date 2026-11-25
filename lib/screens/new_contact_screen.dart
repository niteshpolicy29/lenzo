import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../services/face_repository.dart';
import '../theme/lenzo_theme.dart';
import '../utils/format.dart';
import '../widgets/lenzo_calendar.dart';
import '../design/design.dart';
import '../widgets/lenzo_ui.dart';
import '../widgets/page_thread.dart';

/// Soft coral for the "New Contact" status.
const Color _coral = Lenzo.dangerMuted;

/// Full-screen form for a face Lenzo doesn't know yet. Saving registers the
/// person with this face so they are recognized in future scans.
///
/// Pops with a short confirmation message, or null if the user went back.
class NewContactScreen extends StatefulWidget {
  const NewContactScreen({
    super.key,
    required this.repo,
    required this.faceCrop,
    required this.embedding,
    this.portrait,
  });

  final FaceRepository repo;

  /// Aligned face crop and its embedding, saved for recognition.
  final img.Image faceCrop;
  final List<double> embedding;

  /// Larger photo of the face for display and the profile photo.
  final Uint8List? portrait;

  @override
  State<NewContactScreen> createState() => _NewContactScreenState();
}

class _NewContactScreenState extends State<NewContactScreen> {
  final _nameCtrl = TextEditingController();
  final _lentCtrl = TextEditingController();
  final _borrowedCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _nameFocus = FocusNode();

  DateTime? _reminder;
  bool _calendarOpen = false;
  final _calendarKey = GlobalKey();
  String? _nameError;
  bool _saving = false;

  /// Shown when no larger portrait was captured.
  late final Uint8List _photo =
      widget.portrait ?? Uint8List.fromList(img.encodeJpg(widget.faceCrop));

  @override
  void dispose() {
    _nameCtrl.dispose();
    _lentCtrl.dispose();
    _borrowedCtrl.dispose();
    _notesCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Opens or closes the inline calendar under the reminder field.
  void _toggleCalendar() {
    FocusScope.of(context).unfocus();
    setState(() => _calendarOpen = !_calendarOpen);
    if (_calendarOpen) {
      // Once it has expanded, bring the whole calendar into view.
      Future.delayed(const Duration(milliseconds: 260), () {
        if (!mounted || !_calendarOpen) return;
        final ctx = _calendarKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      });
    }
  }

  void _setReminder(DateTime? date) => setState(() {
    _reminder = date;
    _calendarOpen = false;
  });

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      setState(() => _nameError = 'Please enter a name');
      _nameFocus.requestFocus();
      return;
    }
    final lent = parsePaise(_lentCtrl.text);
    final borrowed = parsePaise(_borrowedCtrl.text);
    if (lent == null || borrowed == null) {
      showLenzoMessage(context, 'Enter valid amounts.');
      return;
    }
    final notes = _notesCtrl.text.trim();
    FocusScope.of(context).unfocus();

    setState(() => _saving = true);
    try {
      final existingId = await widget.repo.findPersonByName(name);
      String message;
      if (existingId != null) {
        final link = await _confirmLink(name);
        if (link != true) {
          if (mounted) {
            setState(() => _saving = false);
            _nameFocus.requestFocus();
          }
          return;
        }
        message = await _linkToExisting(
          existingId,
          name,
          lent,
          borrowed,
          notes,
        );
      } else {
        await widget.repo.registerPerson(
          name: name,
          embedding: widget.embedding,
          faceCrop: widget.faceCrop,
          portraitJpeg: widget.portrait,
          lentPaise: lent,
          borrowedPaise: borrowed,
          notes: notes.isEmpty ? null : notes,
          reminder: _reminder,
        );
        message = '$name is now saved in Lenzo';
      }
      // A new connection: a pulse along the thread behind the pages.
      ThreadPulse.instance.fire();
      if (mounted) Navigator.of(context).pop(message);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showLenzoMessage(context, 'Couldn\'t save this contact: $e');
      }
    }
  }

  /// Adds this face to a contact with the same name, and adds the entered
  /// amounts to their totals. Notes and reminder are replaced only if filled.
  Future<String> _linkToExisting(
    int id,
    String name,
    int lent,
    int borrowed,
    String notes,
  ) async {
    final person = await widget.repo.getPerson(id);
    await widget.repo.addFace(
      personId: id,
      embedding: widget.embedding,
      faceCrop: widget.faceCrop,
    );
    if (widget.portrait != null) {
      await widget.repo.setPhoto(id, widget.portrait!, onlyIfMissing: true);
    }
    // Recorded as new entries on their own accounts.
    await widget.repo.addEntry(id, MoneyKind.lent, lent);
    await widget.repo.addEntry(id, MoneyKind.borrowed, borrowed);
    await widget.repo.updateDetails(
      id,
      notes: notes.isEmpty ? null : notes,
      reminder: _reminder,
    );
    return 'This face is now linked to ${person?.name ?? name}';
  }

  Future<bool?> _confirmLink(String name) {
    return showLenzoConfirm(
      context,
      icon: Icons.link_rounded,
      title: '$name is already saved',
      message:
          "Link this face to $name's contact? It helps Lenzo recognize them, "
          'and the amounts you entered are added to their totals.',
      cancel: 'Change name',
      confirm: 'Link face',
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lenzoSystemUi,
      child: LenzoBackdrop(
        style: BackdropStyle.plain,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => _form(constraints),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Back to camera',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Lenzo.textPrimary,
              size: 28,
            ),
          ),
          const SizedBox(width: 6),
          const Flexible(child: LenzoBrandLogo(height: 30)),
        ],
      ),
    );
  }

  Widget _form(BoxConstraints constraints) {
    final photo = (constraints.maxWidth * 0.42).clamp(140.0, 190.0);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      // Smooth scrolling that also works while the keyboard is open.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      child:
          Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: _FramedPortrait(size: photo, bytes: _photo)
                        .animate()
                        .fadeIn(duration: 320.ms)
                        .scaleXY(
                          begin: 0.94,
                          end: 1,
                          duration: 420.ms,
                          curve: Lenzo.ease,
                        ),
                  ),
                  const SizedBox(height: Lenzo.s16),
                  Text(
                    'Add their details to start tracking payments.',
                    textAlign: TextAlign.center,
                    style: LenzoType.body.copyWith(
                      color: LenzoColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Lenzo.s24),
                  const _FieldLabel(
                    icon: Icons.person_outline_rounded,
                    label: 'Name',
                    required: true,
                  ),
                  TextField(
                    controller: _nameCtrl,
                    focusNode: _nameFocus,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    scrollPadding: _focusRoom,
                    maxLength: 40,
                    buildCounter: (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                    style: LenzoType.input,
                    cursorColor: Lenzo.accent,
                    decoration: lenzoInput(
                      hint: 'Enter full name',
                      error: _nameError,
                    ),
                    onChanged: (_) {
                      if (_nameError != null) setState(() => _nameError = null);
                    },
                  ),
                  const SizedBox(height: Lenzo.s16),

                  _moneyFields(),
                  const SizedBox(height: Lenzo.s16),

                  const _FieldLabel(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Personal Notes (optional)',
                  ),
                  TextField(
                    controller: _notesCtrl,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 500,
                    scrollPadding: _focusRoom,
                    buildCounter: (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                    textCapitalization: TextCapitalization.sentences,
                    style: LenzoType.input,
                    cursorColor: Lenzo.accent,
                    decoration: lenzoInput(hint: 'Add a private note'),
                  ),
                  const SizedBox(height: Lenzo.s16),

                  const _FieldLabel(
                    icon: Icons.calendar_month_outlined,
                    label: 'Payment Reminder (optional)',
                  ),
                  _reminderField(),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _calendarOpen
                        ? Container(
                            key: _calendarKey,
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                            decoration: lenzoPanel(highlighted: true),
                            child: LenzoCalendar(
                              initialDate:
                                  _reminder ??
                                  today().add(const Duration(days: 7)),
                              firstDate: today(),
                              lastDate: DateTime(today().year + 10, 12, 31),
                              onCancel: () =>
                                  setState(() => _calendarOpen = false),
                              onSave: _setReminder,
                              onRemove: _reminder == null
                                  ? null
                                  : () => _setReminder(null),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: Lenzo.s24),

                  GradientButton(
                    label: 'Save Contact',
                    icon: Icons.person_add_alt_1_outlined,
                    busy: _saving,
                    onPressed: _save,
                  ),
                ],
              )
              .animate()
              .fadeIn(duration: 300.ms, delay: 60.ms)
              .slideY(
                begin: 0.02,
                end: 0,
                duration: 380.ms,
                curve: Curves.easeOutCubic,
              ),
    );
  }

  /// When a field gets focus, the page scrolls so the field and some room
  /// below it (the next field, or Save) clear the keyboard.
  static const _focusRoom = EdgeInsets.fromLTRB(20, 20, 20, 140);

  /// Money Lent and Money Borrowed: two separate directions, one under the
  /// other so the labels always fit.
  Widget _moneyFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _moneyField(
          label: 'Money Lent (₹)',
          icon: Icons.south_west_rounded,
          iconColor: Lenzo.accent,
          controller: _lentCtrl,
          action: TextInputAction.next,
        ),
        const SizedBox(height: Lenzo.s12),
        _moneyField(
          label: 'Money Borrowed (₹)',
          icon: Icons.north_east_rounded,
          iconColor: Lenzo.dangerMuted,
          controller: _borrowedCtrl,
          action: TextInputAction.next,
        ),
      ],
    );
  }

  Widget _moneyField({
    required String label,
    required IconData icon,
    required Color iconColor,
    required TextEditingController controller,
    required TextInputAction action,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(icon: icon, iconColor: iconColor, label: label),
        LenzoTextField(
          controller: controller,
          money: true,
          textInputAction: action,
        ),
      ],
    );
  }

  /// The reminder date, styled like the text inputs: filled, no outline,
  /// a step lighter while the calendar is open.
  Widget _reminderField() {
    final set = _reminder != null;
    return Material(
      color: _calendarOpen ? LenzoColors.fieldFocused : LenzoColors.field,
      borderRadius: LenzoRadius.inputAll,
      child: InkWell(
        borderRadius: LenzoRadius.inputAll,
        onTap: _toggleCalendar,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.only(left: LenzoSpacing.x4, right: 4),
          child: Row(
            children: [
              const Icon(
                Icons.event_outlined,
                size: 20,
                color: LenzoColors.textSecondary,
              ),
              const SizedBox(width: LenzoSpacing.x3),
              Expanded(
                child: Text(
                  set
                      ? '${formatDate(_reminder!)} · '
                            '${reminderStatus(_reminder!)}'
                      : 'Select a date',
                  // Wraps to a second line on large text sizes.
                  style: LenzoType.input.copyWith(
                    color: set
                        ? LenzoColors.textPrimary
                        : LenzoColors.textTertiary,
                    fontWeight: set ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              if (set && !_calendarOpen)
                IconButton(
                  tooltip: 'Remove reminder',
                  onPressed: () => setState(() => _reminder = null),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: LenzoColors.textSecondary,
                    size: 20,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: AnimatedRotation(
                    turns: _calendarOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: LenzoColors.textSecondary,
                      size: 22,
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({
    required this.icon,
    required this.label,
    this.required = false,
    this.iconColor = LenzoColors.textSecondary,
  });
  final IconData icon;
  final String label;
  final bool required;

  /// Muted grey, except the money directions (mint / coral arrows).
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: LenzoSpacing.x2),
          Flexible(
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (required)
                    const TextSpan(
                      text: ' *',
                      style: TextStyle(color: _coral),
                    ),
                ],
              ),
              style: LenzoType.cardHeading.copyWith(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Captured face inside scan-frame corners, with an add-person badge.
class _FramedPortrait extends StatelessWidget {
  const _FramedPortrait({required this.size, required this.bytes});
  final double size;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return RingPortrait(
      size: size,
      image: FaceImage(bytes: bytes),
    );
  }
}
