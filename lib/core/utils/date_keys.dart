/// Local-date helpers. Daymark groups planning and journaling by the user's
/// local day, while storing precise instants as UTC epoch milliseconds.
library;

const List<String> _weekdayShort = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
const List<String> _weekdayLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const List<String> _monthShort = [
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
const List<String> _monthLong = [
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

String _two(int value) => value.toString().padLeft(2, '0');

/// Stable local date key: `YYYY-MM-DD`.
String dateKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${_two(local.month)}-${_two(local.day)}';
}

/// Parses a `YYYY-MM-DD` key into local midnight.
DateTime parseDateKey(String value) {
  final parts = value.split('-');
  if (parts.length != 3) {
    throw FormatException('Invalid date key', value);
  }
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

DateTime startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime endOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

DateTime startOfWeek(DateTime value, {bool mondayFirst = true}) {
  final day = startOfDay(value);
  final weekday = day.weekday; // 1 = Monday
  final offset = mondayFirst ? weekday - 1 : weekday % 7;
  return day.subtract(Duration(days: offset));
}

DateTime addDays(DateTime value, int days) {
  final local = value.toLocal();
  return DateTime(
    local.year,
    local.month,
    local.day + days,
    local.hour,
    local.minute,
    local.second,
    local.millisecond,
  );
}

DateTime addMonths(DateTime value, int months) =>
    DateTime(value.year, value.month + months, 1);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isToday(DateTime value) => isSameDay(value, DateTime.now());

bool isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

int daysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// 42 days covering the month, starting on Monday (or Sunday).
List<DateTime> monthGrid(DateTime month, {bool mondayFirst = true}) {
  final first = DateTime(month.year, month.month, 1);
  final offset = mondayFirst ? first.weekday - 1 : first.weekday % 7;
  final gridStart = first.subtract(Duration(days: offset));
  return List<DateTime>.generate(
    42,
    (index) => DateTime(gridStart.year, gridStart.month, gridStart.day + index),
  );
}

List<DateTime> weekDays(DateTime anchor, {bool mondayFirst = true}) {
  final start = startOfWeek(anchor, mondayFirst: mondayFirst);
  return List<DateTime>.generate(
    7,
    (index) => DateTime(start.year, start.month, start.day + index),
  );
}

String weekdayShort(DateTime value) => _weekdayShort[value.weekday - 1];
String weekdayLong(DateTime value) => _weekdayLong[value.weekday - 1];
String monthShort(DateTime value) => _monthShort[value.month - 1];
String monthLong(DateTime value) => _monthLong[value.month - 1];

/// `24 Oct` / `24 Oct 2025`.
String dateLabel(DateTime value, {bool includeYear = false}) {
  final base = '${value.day} ${monthShort(value)}';
  return includeYear ? '$base ${value.year}' : base;
}

/// `Saturday, 24 October`.
String longDateLabel(DateTime value) =>
    '${weekdayLong(value)}, ${value.day} ${monthLong(value)}';

/// `09:30`.
String timeLabel(DateTime value) => '${_two(value.hour)}:${_two(value.minute)}';

/// `09:30 – 11:00`, or a single start.
String timeRangeLabel(DateTime? start, DateTime? end) {
  if (start == null && end == null) return 'Unscheduled';
  if (start == null) return 'Due ${timeLabel(end!)}';
  if (end == null) return timeLabel(start);
  return '${timeLabel(start)} – ${timeLabel(end)}';
}

/// Relative day name for agenda headers.
String relativeDayLabel(
  DateTime value, {
  DateTime? now,
  bool lowercaseToday = false,
}) {
  final reference = startOfDay(now ?? DateTime.now());
  final target = startOfDay(value);
  final difference = daysBetween(reference, target);
  return switch (difference) {
    0 => lowercaseToday ? 'today' : 'Today',
    1 => lowercaseToday ? 'tomorrow' : 'Tomorrow',
    -1 => lowercaseToday ? 'yesterday' : 'Yesterday',
    _ => dateLabel(value),
  };
}

String greetingForHour(int hour) {
  if (hour < 5) return 'Still up';
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  if (hour < 22) return 'Good evening';
  return 'Winding down';
}
