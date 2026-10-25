import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/nav.dart';
import '../../app/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../core/utils/durations.dart';
import '../../data/models/task_view.dart';
import '../../state/settings_controller.dart';
import '../../state/stats_providers.dart';
import '../../state/tasks_controller.dart';
import '../../state/ui_state.dart';
import '../../widgets/quick_capture.dart';
import '../../widgets/task_card.dart';

class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDateProvider);
    final weekMode = ref.watch(calendarWeekModeProvider);
    final views = ref.watch(tasksProvider).value ?? const <TaskView>[];
    final settings = ref.watch(settingsProvider).value;
    final mondayFirst = settings?.weekStartsMonday ?? true;
    final month = DateTime(selected.year, selected.month);
    final focusAsync = ref.watch(monthFocusProvider(month));
    final focusByDay = focusAsync.value ?? const <String, int>{};
    final dayTasks = views.forDate(selected).toList();
    final dayFocus = ref.watch(dayFocusProvider(selected)).value ?? 0;
    final monthTotal = focusByDay.values.fold<int>(0, (a, b) => a + b);
    final activeDays = focusByDay.values.where((ms) => ms > 0).length;

    final header = PageHeader(
      eyebrow: weekMode ? 'Week view' : 'Month view',
      title: monthLong(month),
      subtitle: weekMode
          ? 'Seven days at a glance. Follow the rhythm, not just the list.'
          : 'Work has a shape across time. See where the weight landed.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.read(calendarWeekModeProvider.notifier).state = !weekMode;
          },
          icon: Icon(
            weekMode ? Icons.calendar_month_outlined : Icons.view_week_outlined,
            size: 17,
          ),
          label: Text(weekMode ? 'Month' : 'Week'),
        ),
        FilledButton.icon(
          onPressed: () => showQuickCapture(context, plannedDate: selected),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add work'),
        ),
      ],
    );

    final navigator = _CalendarNav(
      month: month,
      selected: selected,
      weekMode: weekMode,
      onPrevious: () => ref.read(selectedDateProvider.notifier).state = weekMode
          ? addDays(selected, -7)
          : DateTime(month.year, month.month - 1, 1),
      onNext: () => ref.read(selectedDateProvider.notifier).state = weekMode
          ? addDays(selected, 7)
          : DateTime(month.year, month.month + 1, 1),
      onToday: () => ref.read(selectedDateProvider.notifier).state = startOfDay(
        DateTime.now(),
      ),
      onAdd: () => showQuickCapture(context, plannedDate: selected),
    );

    final content = weekMode
        ? _WeekAgenda(
            anchor: selected,
            views: views,
            focusByDay: focusByDay,
            onSelect: (day) =>
                ref.read(selectedDateProvider.notifier).state = day,
          )
        : _MonthGrid(
            anchor: selected,
            mondayFirst: mondayFirst,
            views: views,
            focusByDay: focusByDay,
            onSelect: (day) =>
                ref.read(selectedDateProvider.notifier).state = day,
          );

    final rail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                relativeDayLabel(selected).toUpperCase(),
                style: AppText.label.copyWith(color: colors(context).inkFaint),
              ),
              const SizedBox(height: 4),
              Text(
                longDateLabel(selected),
                style: AppText.displayS.copyWith(color: colors(context).ink),
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: 'Focus',
                      value: formatCompactMs(dayFocus),
                      color: colors(context).accent,
                    ),
                  ),
                  Container(width: 1, height: 34, color: colors(context).line),
                  Expanded(
                    child: _MiniStat(
                      label: 'Tasks',
                      value: '${dayTasks.where((v) => !v.isDone).length} open',
                      color: colors(context).primary,
                    ),
                  ),
                ],
              ),
              if (dayTasks.isNotEmpty) ...[
                const SizedBox(height: AppSpace.lg),
                for (final view in dayTasks.take(5)) ...[
                  TaskCard(
                    view: view,
                    compact: true,
                    onTap: () => openTaskDetail(context, view.task.id),
                  ),
                  const SizedBox(height: AppSpace.sm),
                ],
                if (dayTasks.length > 5)
                  TextButton(
                    onPressed: () {
                      ref.read(selectedDateProvider.notifier).state = selected;
                      ref.read(navIndexProvider.notifier).state =
                          NavTarget.planner;
                    },
                    child: Text('+${dayTasks.length - 5} more'),
                  ),
              ] else ...[
                const SizedBox(height: AppSpace.lg),
                Text(
                  'No work planned. Leave it open, or capture one thing.',
                  style: AppText.bodySmall.copyWith(
                    color: colors(context).inkMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                OutlinedButton.icon(
                  onPressed: () =>
                      showQuickCapture(context, plannedDate: selected),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add to this day'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THIS MONTH',
                style: AppText.label.copyWith(color: colors(context).inkFaint),
              ),
              const SizedBox(height: AppSpace.md),
              _MonthStatRow(
                label: 'Focus time',
                value: formatCompactMs(monthTotal),
              ),
              _MonthStatRow(label: 'Active days', value: '$activeDays'),
              _MonthStatRow(
                label: 'Average',
                value: activeDays == 0
                    ? '—'
                    : formatCompactMs(monthTotal ~/ activeDays),
              ),
              _MonthStatRow(
                label: 'Planned weight',
                value: formatPoints(
                  views
                      .where(
                        (view) =>
                            view.task.plannedDate != null &&
                            view.task.plannedDate!.startsWith(
                              '${month.year}-${month.month.toString().padLeft(2, '0')}',
                            ),
                      )
                      .fold<double>(0, (sum, view) => sum + view.points),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return PageWidth(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: AppSpace.lg),
            navigator,
            const SizedBox(height: AppSpace.lg),
            if (MediaQuery.sizeOf(context).width >= 1050)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: content),
                  const SizedBox(width: AppSpace.x3),
                  SizedBox(width: 330, child: rail),
                ],
              )
            else ...[
              content,
              const SizedBox(height: AppSpace.xl),
              rail,
            ],
            const SizedBox(height: AppSpace.lg),
            _Legend(),
          ],
        ),
      ),
    );
  }

  AppColors colors(BuildContext context) => context.colors;
}

class _CalendarNav extends StatelessWidget {
  const _CalendarNav({
    required this.month,
    required this.selected,
    required this.weekMode,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onAdd,
  });

  final DateTime month;
  final DateTime selected;
  final bool weekMode;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        IconButton(
          tooltip: weekMode ? 'Previous week' : 'Previous month',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded, size: 21),
        ),
        Text(
          weekMode
              ? '${dateLabel(weekDays(selected).first)} – '
                    '${dateLabel(weekDays(selected).last)}'
              : monthLong(month),
          style: AppText.bodyMedium.copyWith(color: colors.ink),
        ),
        IconButton(
          tooltip: weekMode ? 'Next week' : 'Next month',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded, size: 21),
        ),
        const SizedBox(width: AppSpace.sm),
        OutlinedButton(onPressed: onToday, child: const Text('Today')),
        const Spacer(),
        Text(
          'Click a day to inspect it',
          style: AppText.bodySmall.copyWith(
            color: colors.inkFaint,
            fontSize: 11,
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        IconButton.filledTonal(
          tooltip: 'Add work',
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.anchor,
    required this.mondayFirst,
    required this.views,
    required this.focusByDay,
    required this.onSelect,
  });

  final DateTime anchor;
  final bool mondayFirst;
  final List<TaskView> views;
  final Map<String, int> focusByDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final days = monthGrid(anchor, mondayFirst: mondayFirst);
    final labels = mondayFirst
        ? const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']
        : const ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    final maxFocus = focusByDay.values.fold<int>(1, (a, b) => b > a ? b : a);
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in labels)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppText.label.copyWith(
                        color: colors.inkFaint,
                        fontSize: 8.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Divider(color: colors.line, height: 1),
          for (var row = 0; row < 6; row++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: _DayTile(
                      day: days[row * 7 + column],
                      anchor: anchor,
                      views: views,
                      maxFocus: maxFocus,
                      focusMs: focusByDay[dateKey(days[row * 7 + column])] ?? 0,
                      selected: isSameDay(days[row * 7 + column], anchor),
                      onTap: () => onSelect(days[row * 7 + column]),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.anchor,
    required this.views,
    required this.focusMs,
    required this.maxFocus,
    required this.selected,
    required this.onTap,
  });

  final DateTime day;
  final DateTime anchor;
  final List<TaskView> views;
  final int focusMs;
  final int maxFocus;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final inMonth = day.month == anchor.month;
    final dayTasks = views.forDate(day).toList();
    final open = dayTasks.where((view) => !view.isDone).length;
    final done = dayTasks.where((view) => view.isDone).length;
    final intensity = focusMs == 0
        ? 0.0
        : (focusMs / maxFocus).clamp(0.08, 1.0);
    return SizedBox(
      height: 84,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.badge),
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected
                ? colors.primarySoft.withValues(alpha: 0.75)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.badge),
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${day.day}',
                    style: AppText.monoData.copyWith(
                      color: !inMonth
                          ? colors.inkFaint.withValues(alpha: 0.45)
                          : isToday(day)
                          ? colors.accent
                          : colors.ink,
                      fontSize: 12,
                      fontWeight: isToday(day)
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (focusMs > 0)
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(
                          alpha: 0.12 + intensity * 0.35,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(
                              alpha: 0.5 + intensity * 0.5,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              if (dayTasks.isNotEmpty)
                Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: [
                    if (open > 0)
                      _CountPill(label: '$open', color: colors.inkMuted),
                    if (done > 0)
                      _CountPill(label: '✓$done', color: colors.green),
                  ],
                ),
              if (focusMs > 0) ...[
                const SizedBox(height: 3),
                Text(
                  formatCompactMs(focusMs),
                  style: AppText.monoData.copyWith(
                    color: colors.inkFaint,
                    fontSize: 8.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppText.monoData.copyWith(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _WeekAgenda extends StatelessWidget {
  const _WeekAgenda({
    required this.anchor,
    required this.views,
    required this.focusByDay,
    required this.onSelect,
  });

  final DateTime anchor;
  final List<TaskView> views;
  final Map<String, int> focusByDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final days = weekDays(anchor);
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        children: [
          for (var index = 0; index < days.length; index++) ...[
            if (index > 0) Divider(color: colors.line, height: 1),
            InkWell(
              onTap: () => onSelect(days[index]),
              borderRadius: BorderRadius.circular(AppRadius.input),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpace.md,
                  horizontal: AppSpace.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 58,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            weekdayShort(days[index]).toUpperCase(),
                            style: AppText.label.copyWith(
                              color: isToday(days[index])
                                  ? colors.accent
                                  : colors.inkFaint,
                              fontSize: 8.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${days[index].day}',
                            style: AppText.displayS.copyWith(
                              color: isToday(days[index])
                                  ? colors.accent
                                  : colors.ink,
                              fontSize: 22,
                            ),
                          ),
                          Text(
                            formatCompactMs(
                              focusByDay[dateKey(days[index])] ?? 0,
                            ),
                            style: AppText.monoData.copyWith(
                              color: colors.inkFaint,
                              fontSize: 8.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: () {
                        final tasks = views.forDate(days[index]).toList();
                        if (tasks.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Open space',
                              style: AppText.bodySmall.copyWith(
                                color: colors.inkFaint,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final view in tasks.take(3)) ...[
                              TaskCard(
                                view: view,
                                compact: true,
                                onTap: () =>
                                    openTaskDetail(context, view.task.id),
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (tasks.length > 3)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '+${tasks.length - 3} more',
                                  style: AppText.bodySmall.copyWith(
                                    color: colors.primary,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        );
                      }(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppText.label.copyWith(color: colors.inkFaint, fontSize: 8.5),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppText.monoData.copyWith(color: color, fontSize: 14),
        ),
      ],
    );
  }
}

class _MonthStatRow extends StatelessWidget {
  const _MonthStatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: AppText.bodySmall.copyWith(color: colors.inkMuted),
          ),
          const Spacer(),
          Text(
            value,
            style: AppText.monoData.copyWith(color: colors.ink, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      spacing: AppSpace.lg,
      runSpacing: AppSpace.sm,
      children: [
        _LegendItem(color: colors.inkMuted, label: 'Open tasks'),
        _LegendItem(color: colors.green, label: 'Completed'),
        _LegendItem(color: colors.primary, label: 'Focus intensity'),
        _LegendItem(color: colors.accent, label: 'Today'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppText.bodySmall.copyWith(
            color: colors.inkFaint,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
