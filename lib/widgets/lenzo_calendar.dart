import 'package:material_ui/material_ui.dart';

import '../design/design.dart';
import '../theme/lenzo_theme.dart';
import '../utils/format.dart';
import 'fade_swap.dart';
import 'lenzo_ui.dart';

const Color _muted = Lenzo.textSecondary;
const Color _onAccent = Lenzo.onHighlight;
const Color _coral = Lenzo.dangerMuted;

/// Compact inline calendar for picking a payment reminder date.
///
/// Shows the selected date, a month header (previous arrow on the left,
/// next on the right, the month name in the middle on one line; tap it to
/// jump to another month or year), a Sunday-first day grid, and Cancel /
/// Save. Swipe left or right on the days to change month. Days outside
/// [firstDate]..[lastDate] can't be picked.
///
/// The grid always has six rows, so its size never changes between months;
/// a month change is a 180 ms fade (old month out, then new month in),
/// with no sliding numbers.
class LenzoCalendar extends StatefulWidget {
  const LenzoCalendar({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.onSave,
    required this.onCancel,
    this.onRemove,
    this.saving = false,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onSave;
  final VoidCallback onCancel;

  /// Shown as "Remove reminder" when a reminder is already set.
  final VoidCallback? onRemove;
  final bool saving;

  @override
  State<LenzoCalendar> createState() => _LenzoCalendarState();
}

class _LenzoCalendarState extends State<LenzoCalendar> {
  late DateTime _selected = _day(widget.initialDate);
  late DateTime _month = DateTime(_selected.year, _selected.month);

  /// True while the month/year grid is shown instead of the days.
  bool _pickingMonth = false;

  /// Year shown in the month grid.
  late int _year = _month.year;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get _first => _day(widget.firstDate);
  DateTime get _last => _day(widget.lastDate);

  bool _monthAllowed(int year, int month) {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1, 0);
    return !end.isBefore(_first) && !start.isAfter(_last);
  }

  bool get _canGoBack => _pickingMonth
      ? _year > _first.year
      : _monthAllowed(_month.year, _month.month - 1);

  bool get _canGoForward => _pickingMonth
      ? _year < _last.year
      : _monthAllowed(_month.year, _month.month + 1);

  void _step(int delta) {
    if (delta < 0 ? !_canGoBack : !_canGoForward) return;
    setState(() {
      if (_pickingMonth) {
        _year += delta;
      } else {
        _month = DateTime(_month.year, _month.month + delta);
      }
    });
  }

  void _toggleMonthPicker() => setState(() {
    _pickingMonth = !_pickingMonth;
    _year = _month.year;
  });

  void _showSelectedMonth() => setState(() {
    _pickingMonth = false;
    _month = DateTime(_selected.year, _selected.month);
  });

  static const _weekdayRow = 28.0;
  static const _rows = 6;

  @override
  Widget build(BuildContext context) {
    // Day numbers sit in fixed cells; cap text scaling so they can't clip.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: LayoutBuilder(
        builder: (context, box) {
          final cellW = box.maxWidth / 7;
          final circle = (cellW - 4).clamp(28.0, 34.0);
          final rowH = circle + 4;
          final gridH = _weekdayRow + _rows * rowH;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _selectedField(),
              const SizedBox(height: LenzoSpacing.x3),
              _monthHeader(box.maxWidth),
              const SizedBox(height: LenzoSpacing.x1),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: _pickingMonth
                    ? null
                    : (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v < -250) _step(1);
                        if (v > 250) _step(-1);
                      },
                child: SizedBox(
                  height: gridH,
                  child: FadeSwap(
                    contentKey: _pickingMonth
                        ? 'y$_year'
                        : 'm${_month.year}-${_month.month}',
                    child: _pickingMonth
                        ? _monthGrid(gridH)
                        : _dayGrid(circle, rowH),
                  ),
                ),
              ),
              if (widget.onRemove != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.saving ? null : widget.onRemove,
                    style: TextButton.styleFrom(
                      foregroundColor: _coral,
                      padding: const EdgeInsets.symmetric(
                        horizontal: LenzoSpacing.x2,
                      ),
                      minimumSize: const Size(0, Lenzo.tap),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: LenzoType.button.copyWith(fontSize: 13),
                    ),
                    icon: const Icon(Icons.event_busy_outlined, size: 18),
                    label: const Text('Remove reminder'),
                  ),
                ),
              const SizedBox(height: LenzoSpacing.x3),
              EditorActions(
                saving: widget.saving,
                onCancel: widget.onCancel,
                onSave: () => widget.onSave(_selected),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The chosen date, on one line, styled like the text inputs (raised
  /// fill, as it sits in a panel; no outline). Tap to show its month again.
  Widget _selectedField() {
    return Material(
      color: LenzoColors.fieldRaised,
      borderRadius: LenzoRadius.inputAll,
      child: InkWell(
        borderRadius: LenzoRadius.inputAll,
        onTap: _showSelectedMonth,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: LenzoSpacing.x4),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: _muted,
              ),
              const SizedBox(width: LenzoSpacing.x3),
              Expanded(
                child: Text(
                  formatLongDate(_selected),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LenzoType.input,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Previous arrow, month name (one line, never wraps), next arrow.
  Widget _monthHeader(double width) {
    final name = width >= 240
        ? monthNames[_month.month - 1]
        : shortMonth(_month.month);
    final title = _pickingMonth ? '$_year' : '$name ${_month.year}';
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          _arrow(Icons.chevron_left_rounded, 'Previous', _canGoBack, -1),
          Expanded(
            child: Center(
              child: Semantics(
                button: true,
                label: _pickingMonth
                    ? 'Choose a month in $_year'
                    : '$title, choose another month',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: LenzoRadius.pillAll,
                  onTap: _toggleMonthPicker,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LenzoSpacing.x2,
                      vertical: LenzoSpacing.x1,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            softWrap: false,
                            style: LenzoType.cardHeading,
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            _pickingMonth
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: _muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _arrow(Icons.chevron_right_rounded, 'Next', _canGoForward, 1),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, String tooltip, bool enabled, int delta) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? () => _step(delta) : null,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 22),
      color: Lenzo.textPrimary,
      disabledColor: LenzoColors.textTertiary.withValues(alpha: 0.5),
    );
  }

  /// Weekday letters and six rows of days (blank where the month has none).
  Widget _dayGrid(double circle, double rowH) {
    final now = today();
    final leading = DateTime(_month.year, _month.month).weekday % 7;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    return Column(
      children: [
        SizedBox(
          height: _weekdayRow,
          child: Row(
            children: [
              for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Expanded(
                  child: Center(
                    child: ExcludeSemantics(
                      child: Text(d, style: LenzoType.label),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var w = 0; w < _rows; w++)
          SizedBox(
            height: rowH,
            child: Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: _dayCell(w * 7 + c - leading + 1, days, now, circle),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dayCell(int day, int days, DateTime now, double circle) {
    if (day < 1 || day > days) return const SizedBox.shrink();
    final date = DateTime(_month.year, _month.month, day);
    final enabled = !date.isBefore(_first) && !date.isAfter(_last);
    final selected = date == _selected;
    final isToday = date == now;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: formatLongDate(date),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => setState(() => _selected = date) : null,
        child: Center(
          child: Container(
            width: circle,
            height: circle,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? Lenzo.accent : null,
              border: isToday && !selected
                  ? Border.all(color: Lenzo.accent, width: 1.5)
                  : null,
            ),
            child: Text(
              '$day',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: LenzoType.family,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: selected
                    ? _onAccent
                    : !enabled
                    ? LenzoColors.textTertiary.withValues(alpha: 0.6)
                    : isToday
                    ? Lenzo.accent
                    : Lenzo.textPrimary,
                fontSize: 14,
                height: 1,
                fontWeight: selected || isToday
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Twelve months in a 4 × 3 grid, filling the same space as the days.
  Widget _monthGrid(double height) {
    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          SizedBox(
            height: height / 3,
            child: Row(
              children: [
                for (var col = 0; col < 4; col++)
                  Expanded(child: _monthCell(row * 4 + col + 1)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _monthCell(int month) {
    final enabled = _monthAllowed(_year, month);
    final current = _year == _month.year && month == _month.month;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LenzoSpacing.x1),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: LenzoRadius.pillAll,
            onTap: enabled
                ? () => setState(() {
                    _month = DateTime(_year, month);
                    _pickingMonth = false;
                  })
                : null,
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: LenzoRadius.pillAll,
                color: current ? Lenzo.accent : LenzoColors.surfaceSecondary,
              ),
              child: Text(
                shortMonth(month),
                maxLines: 1,
                style: LenzoType.button.copyWith(
                  color: current
                      ? _onAccent
                      : enabled
                      ? Lenzo.textPrimary
                      : LenzoColors.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
