import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/utils/date_keys.dart';
import '../data/models/enums.dart';
import '../data/models/subtask.dart';
import '../data/models/task_view.dart';
import '../data/models/time_entry.dart';
import 'repository_providers.dart';
import 'settings_controller.dart';

enum AnalyticsPeriod {
  week('This week'),
  last30('Last 30 days'),
  month('This month');

  const AnalyticsPeriod(this.label);
  final String label;
}

final analyticsPeriodProvider = StateProvider<AnalyticsPeriod>(
  (ref) => AnalyticsPeriod.week,
);

final dayFocusProvider = FutureProvider.family<int, DateTime>((ref, day) {
  final start = startOfDay(day);
  final end = addDays(start, 1);
  return ref.watch(timerRepositoryProvider).totalBetween(start, end);
});

final weekFocusProvider = FutureProvider<Map<String, int>>((ref) {
  final today = startOfDay(DateTime.now());
  return ref
      .watch(timerRepositoryProvider)
      .focusByDay(addDays(today, -6), addDays(today, 1));
});

final monthFocusProvider = FutureProvider.family<Map<String, int>, DateTime>((
  ref,
  month,
) {
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 1);
  return ref.watch(timerRepositoryProvider).focusByDay(start, end);
});

final heatmapFocusProvider = FutureProvider<Map<String, int>>((ref) {
  final today = startOfDay(DateTime.now());
  return ref
      .watch(timerRepositoryProvider)
      .focusByDay(addDays(today, -83), addDays(today, 1));
});

final generalEntriesForDayProvider =
    FutureProvider.family<List<TimeEntry>, DateTime>((ref, day) {
      final start = startOfDay(day);
      return ref
          .watch(timerRepositoryProvider)
          .generalEntriesBetween(start, addDays(start, 1));
    });

/// Time by category for the trailing seven days. `''` means unassigned
/// (a general stopwatch entry or a deleted task).
final weeklyCategoryFocusProvider = FutureProvider<Map<String, int>>((
  ref,
) async {
  final today = startOfDay(DateTime.now());
  final entries = await ref
      .watch(timerRepositoryProvider)
      .entriesBetween(addDays(today, -6), addDays(today, 1));
  final tasks = await ref.watch(taskRepositoryProvider).list();
  final categoryByTask = {
    for (final task in tasks) task.id: task.categoryId ?? '',
  };
  final result = <String, int>{};
  for (final entry in entries) {
    final key = entry.taskId == null
        ? ''
        : (categoryByTask[entry.taskId] ?? '');
    result[key] = (result[key] ?? 0) + entry.durationMs;
  }
  return result;
});

class AnalyticsData {
  const AnalyticsData({
    required this.period,
    required this.start,
    required this.end,
    required this.focusMs,
    required this.previousFocusMs,
    required this.focusByDay,
    required this.dailyPoints,
    required this.categoryFocusMs,
    required this.kindFocusMs,
    required this.unassignedFocusMs,
    required this.completedTasks,
    required this.plannedTasks,
    required this.completedCount,
    required this.completionRate,
    required this.outputPoints,
    required this.estimatedMinutes,
    required this.actualMinutesOnEstimated,
    required this.estimateSamples,
    required this.journalDays,
    required this.activeDays,
    required this.topCategoryId,
  });

  final AnalyticsPeriod period;
  final DateTime start;
  final DateTime end;
  final int focusMs;
  final int previousFocusMs;
  final Map<String, int> focusByDay;
  final Map<String, double> dailyPoints;
  final Map<String, int> categoryFocusMs;
  final Map<WorkKind, int> kindFocusMs;
  final int unassignedFocusMs;
  final List<TaskView> completedTasks;
  final List<TaskView> plannedTasks;
  final int completedCount;
  final double completionRate;
  final double outputPoints;
  final int estimatedMinutes;
  final int actualMinutesOnEstimated;
  final int estimateSamples;
  final int journalDays;
  final int activeDays;
  final String? topCategoryId;

  double get focusDelta =>
      previousFocusMs == 0 ? 0 : (focusMs - previousFocusMs) / previousFocusMs;

  double get estimateRatio =>
      estimatedMinutes == 0 ? 0 : actualMinutesOnEstimated / estimatedMinutes;

  double get estimateDrift => estimatedMinutes == 0 ? 0 : estimateRatio - 1;
}

final analyticsProvider = FutureProvider<AnalyticsData>((ref) async {
  final period = ref.watch(analyticsPeriodProvider);
  final mondayFirst =
      ref.watch(settingsProvider).value?.weekStartsMonday ?? true;
  final now = DateTime.now();
  final today = startOfDay(now);
  final end = addDays(today, 1);
  final start = switch (period) {
    AnalyticsPeriod.week => startOfWeek(today, mondayFirst: mondayFirst),
    AnalyticsPeriod.last30 => addDays(today, -29),
    AnalyticsPeriod.month => DateTime(today.year, today.month, 1),
  };
  final previousStart = start.subtract(end.difference(start));
  final tasks = await ref.watch(taskRepositoryProvider).list();
  final categories = await ref.watch(categoryRepositoryProvider).list();
  final subtasks = await ref.watch(taskRepositoryProvider).allSubtasks();
  final tracked = await ref.watch(taskRepositoryProvider).trackedTotals();
  final timerRepo = ref.watch(timerRepositoryProvider);
  final entries = await timerRepo.entriesBetween(start, end);
  final previousFocus = await timerRepo.totalBetween(previousStart, start);
  final journalDays = await ref
      .watch(journalRepositoryProvider)
      .journaledDays(start, end);

  final categoryById = {
    for (final category in categories) category.id: category,
  };
  final subtasksByTask = <String, List<Subtask>>{};
  for (final step in subtasks) {
    (subtasksByTask[step.taskId] ??= []).add(step);
  }
  final views = [
    for (final task in tasks)
      TaskView(
        task: task,
        category: categoryById[task.categoryId],
        subtasks: subtasksByTask[task.id] ?? const [],
        trackedMs: tracked[task.id] ?? 0,
      ),
  ];
  final taskById = {for (final task in tasks) task.id: task};

  final completed =
      views
          .where(
            (view) =>
                view.task.completedAt != null &&
                !view.task.completedAt!.isBefore(start) &&
                view.task.completedAt!.isBefore(end),
          )
          .toList()
        ..sort((a, b) => b.task.completedAt!.compareTo(a.task.completedAt!));

  final startKey = dateKey(start);
  final endKey = dateKey(addDays(end, -1));
  final planned = views
      .where(
        (view) =>
            view.task.plannedDate != null &&
            view.task.plannedDate!.compareTo(startKey) >= 0 &&
            view.task.plannedDate!.compareTo(endKey) <= 0,
      )
      .toList();

  final relevantIds = <String>{
    for (final view in planned) view.task.id,
    for (final view in completed) view.task.id,
  };
  final relevant = views.where((view) => relevantIds.contains(view.task.id));
  final outputPoints = relevant.fold<double>(
    0,
    (sum, view) => sum + view.earnedPoints,
  );
  final completionRate = relevantIds.isEmpty
      ? 0.0
      : completed.length / relevantIds.length;

  final focusByDay = <String, int>{
    for (var day = start; day.isBefore(end); day = addDays(day, 1))
      dateKey(day): 0,
  };
  final dailyPoints = <String, double>{};
  for (final view in planned) {
    final key = view.task.plannedDate!;
    dailyPoints[key] = (dailyPoints[key] ?? 0) + view.points;
  }
  final categoryFocus = <String, int>{};
  final kindFocus = <WorkKind, int>{};
  var unassigned = 0;
  var totalFocus = 0;
  for (final entry in entries) {
    totalFocus += entry.durationMs;
    focusByDay[dateKey(entry.startedAt)] =
        (focusByDay[dateKey(entry.startedAt)] ?? 0) + entry.durationMs;
    final task = entry.taskId == null ? null : taskById[entry.taskId];
    if (task == null) {
      unassigned += entry.durationMs;
      categoryFocus[''] = (categoryFocus[''] ?? 0) + entry.durationMs;
    } else {
      final category = task.categoryId ?? '';
      categoryFocus[category] =
          (categoryFocus[category] ?? 0) + entry.durationMs;
      kindFocus[task.kind] = (kindFocus[task.kind] ?? 0) + entry.durationMs;
    }
  }

  var estimatedMinutes = 0;
  var actualMinutes = 0;
  var estimateSamples = 0;
  for (final view in completed) {
    final estimate = view.task.estimateMinutes;
    if (estimate == null || estimate <= 0 || view.trackedMs <= 0) continue;
    estimateSamples++;
    estimatedMinutes += estimate;
    actualMinutes += (view.trackedMs / 60000).round();
  }

  String? topCategory;
  var topMs = 0;
  for (final entry in categoryFocus.entries) {
    if (entry.value > topMs) {
      topMs = entry.value;
      topCategory = entry.key.isEmpty ? null : entry.key;
    }
  }

  return AnalyticsData(
    period: period,
    start: start,
    end: end,
    focusMs: totalFocus,
    previousFocusMs: previousFocus,
    focusByDay: focusByDay,
    dailyPoints: dailyPoints,
    categoryFocusMs: categoryFocus,
    kindFocusMs: kindFocus,
    unassignedFocusMs: unassigned,
    completedTasks: completed,
    plannedTasks: planned,
    completedCount: completed.length,
    completionRate: completionRate,
    outputPoints: outputPoints,
    estimatedMinutes: estimatedMinutes,
    actualMinutesOnEstimated: actualMinutes,
    estimateSamples: estimateSamples,
    journalDays: journalDays.length,
    activeDays: focusByDay.values
        .where((milliseconds) => milliseconds > 0)
        .length,
    topCategoryId: topCategory,
  );
});

/// Invalidate every derived time/points view after a mutation.
void invalidateStats(Ref ref) {
  ref.invalidate(dayFocusProvider);
  ref.invalidate(weekFocusProvider);
  ref.invalidate(monthFocusProvider);
  ref.invalidate(heatmapFocusProvider);
  ref.invalidate(generalEntriesForDayProvider);
  ref.invalidate(weeklyCategoryFocusProvider);
  ref.invalidate(analyticsProvider);
}

/// Widget-side variant of [invalidateStats] for screens that mutate data and
/// need every derived time/points view refreshed immediately.
void invalidateStatsWidget(WidgetRef ref) {
  ref.invalidate(dayFocusProvider);
  ref.invalidate(weekFocusProvider);
  ref.invalidate(monthFocusProvider);
  ref.invalidate(heatmapFocusProvider);
  ref.invalidate(generalEntriesForDayProvider);
  ref.invalidate(weeklyCategoryFocusProvider);
  ref.invalidate(analyticsProvider);
}
