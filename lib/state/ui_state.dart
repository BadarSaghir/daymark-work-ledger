import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/date_keys.dart';

/// Shell destination index.
final navIndexProvider = StateProvider<int>((ref) => 0);

/// Calendar/planner focus day.
final selectedDateProvider = StateProvider<DateTime>(
  (ref) => startOfDay(DateTime.now()),
);

/// Planner presentation: false = board, true = list.
final plannerListModeProvider = StateProvider<bool>((ref) => false);

final calendarWeekModeProvider = StateProvider<bool>((ref) => false);

final commandPaletteOpenProvider = StateProvider<bool>((ref) => false);
