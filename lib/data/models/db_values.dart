/// Small conversion helpers shared by model mappers.
library;

DateTime? dateFromMs(Object? value) {
  if (value == null) return null;
  final ms = value as num;
  return DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true).toLocal();
}

int? msFromDate(DateTime? value) => value?.toUtc().millisecondsSinceEpoch;

bool boolFromDb(Object? value) => (value as num?)?.toInt() == 1;

int intFromDb(Object? value, [int fallback = 0]) =>
    (value as num?)?.toInt() ?? fallback;

double doubleFromDb(Object? value, [double fallback = 0]) =>
    (value as num?)?.toDouble() ?? fallback;

String stringFromDb(Object? value, [String fallback = '']) =>
    value as String? ?? fallback;
