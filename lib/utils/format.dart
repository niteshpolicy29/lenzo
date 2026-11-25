import 'package:flutter/services.dart';

/// Largest amount accepted in a money field: ₹99,99,99,999.99.
const int kMaxPaise = 999999999999;

/// Rupees with Indian digit grouping, e.g. 2500000 paise → "₹25,000",
/// 12345678 → "₹1,23,456.78". Paise are shown only when not zero.
String formatRupees(int paise) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = (abs ~/ 100).toString();
  final rest = abs % 100;

  String grouped;
  if (rupees.length <= 3) {
    grouped = rupees;
  } else {
    final last3 = rupees.substring(rupees.length - 3);
    var head = rupees.substring(0, rupees.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    grouped = '${parts.join(',')},$last3';
  }
  final decimals = rest == 0 ? '' : '.${rest.toString().padLeft(2, '0')}';
  return '${negative ? '−' : ''}₹$grouped$decimals';
}

/// Short Indian form for display: below ₹10,000 the exact amount
/// (paise included when not zero), then K (thousands), L (lakhs) and Cr
/// (crores) with at most one decimal and no trailing zero:
/// ₹9,999 · ₹10K · ₹49.6K · ₹1L · ₹25.5L · ₹1Cr.
///
/// Display only: the decimal is cut, not rounded up, so an amount is never
/// shown as more than it is. Stored values and calculations always use the
/// exact paise; edit forms and entry history show [formatRupees].
String formatRupeesCompact(int paise) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  if (rupees < 10000) {
    final exact = formatRupees(abs);
    return negative ? '−$exact' : exact;
  }
  final (unit, suffix) = rupees >= 10000000
      ? (10000000, 'Cr')
      : rupees >= 100000
      ? (100000, 'L')
      : (1000, 'K');
  // Tenths of the unit, cut toward zero.
  final tenths = rupees * 10 ~/ unit;
  final whole = tenths ~/ 10, frac = tenths % 10;
  final body = frac == 0 ? '$whole' : '$whole.$frac';
  final grouped = whole >= 1000 && suffix == 'Cr'
      ? formatRupees(whole * 100).substring(1) + (frac == 0 ? '' : '.$frac')
      : body;
  return '${negative ? '−' : ''}₹$grouped$suffix';
}

/// Like [formatRupees] but rounded to whole rupees, for large figures.
String formatRupeesShort(int paise) =>
    formatRupees((paise / 100).round() * 100);

/// Plain amount for an input field, e.g. 2500050 → "25000.50".
String paiseToInput(int paise) {
  final rupees = paise ~/ 100;
  final rest = paise % 100;
  return rest == 0 ? '$rupees' : '$rupees.${rest.toString().padLeft(2, '0')}';
}

/// Parses "25000", "25,000" or "25000.5" into paise. Empty text is 0.
/// Returns null if the text isn't a valid amount.
int? parsePaise(String text) {
  final t = text.replaceAll(',', '').trim();
  if (t.isEmpty || t == '.') return 0;
  final m = RegExp(r'^(\d{0,10})(?:\.(\d{0,2}))?$').firstMatch(t);
  if (m == null) return null;
  final rupees = int.parse(m.group(1)!.isEmpty ? '0' : m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final paise = rupees * 100 + int.parse(frac);
  return paise > kMaxPaise ? null : paise;
}

/// Allows only amounts: digits with at most two decimal places.
class MoneyInputFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^\d{0,10}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return _pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// e.g. "15 Feb 2027".
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "25 Nov", with the year only when it isn't [now]'s year ("25 Nov 2027").
String formatShortDate(DateTime d, {DateTime? now}) {
  final year = (now ?? DateTime.now()).year;
  final s = '${d.day} ${_months[d.month - 1]}';
  return d.year == year ? s : '$s ${d.year}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Short month name, 1-based: 1 → "Jan".
String shortMonth(int month) => _months[month - 1];

/// e.g. "Tue, Nov 24, 2026".
String formatLongDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';

/// Today at midnight, local time.
DateTime today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Short status for a reminder date, e.g. "Due today", "In 3 days",
/// "Overdue by 2 days".
String reminderStatus(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  final days = d.difference(today()).inDays;
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  if (days > 1) return 'In $days days';
  if (days == -1) return 'Overdue by 1 day';
  return 'Overdue by ${-days} days';
}
