import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/enum_ui.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../core/utils/durations.dart';
import '../../core/utils/platform.dart';
import '../../data/models/enums.dart';
import '../../data/models/task_view.dart';
import '../../state/settings_controller.dart';
import '../../state/tasks_controller.dart';
import '../../state/ui_state.dart';
import '../../widgets/quick_capture.dart';
import '../../widgets/task_card.dart';
import '../../widgets/task_editor.dart';

class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key});

  @override
  ConsumerState<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends ConsumerState<PlannerPage> {
  bool _appliedMobileDefault = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedMobileDefault || !Layout.isCompact(context)) return;
    _appliedMobileDefault = true;
    if (ref.read(plannerListModeProvider)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(plannerListModeProvider.notifier).state = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedDateProvider);
    final listMode = ref.watch(plannerListModeProvider);
    final tasksAsync = ref.watch(tasksProvider);
    final views = tasksAsync.value ?? const <TaskView>[];
    final settings = ref.watch(settingsProvider).value;
    final dayTasks = views.forDate(selected).toList();
    final open = dayTasks.where((view) => !view.isDone).toList()
      ..sort(_sortTasks);
    final done = dayTasks.where((view) => view.isDone).toList();
    final summary = dayTasks.loadSummary;
    final backlog =
        views
            .where((view) => !view.isDone && view.task.plannedDate == null)
            .toList()
          ..sort(_sortTasks);
    final overdue =
        views
            .where(
              (view) =>
                  !view.isDone &&
                  view.task.dueAt != null &&
                  view.task.dueAt!.isBefore(DateTime.now()),
            )
            .toList()
          ..sort((a, b) => a.task.dueAt!.compareTo(b.task.dueAt!));
    final target = settings?.dailyWeightTarget ?? 25;

    final header = PageHeader(
      eyebrow: relativeDayLabel(selected).toUpperCase(),
      title: isToday(selected) ? 'Plan today' : 'Plan ${dateLabel(selected)}',
      subtitle:
          'Shape the day, break the work into steps, and leave a record '
          'of what actually happened.',
      actions: [
        OutlinedButton.icon(
          onPressed: () =>
              ref.read(plannerListModeProvider.notifier).state = !listMode,
          icon: Icon(
            listMode ? Icons.view_kanban_outlined : Icons.view_agenda_outlined,
            size: 17,
          ),
          label: Text(listMode ? 'Board' : 'List'),
        ),
        if (!Layout.isCompact(context))
          FilledButton.icon(
            onPressed: () => showQuickCapture(context, plannedDate: selected),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add work'),
          ),
      ],
    );

    final weekStrip = _WeekStrip(
      selected: selected,
      views: views,
      onSelect: (day) =>
          ref.read(selectedDateProvider.notifier).state = startOfDay(day),
      onShift: (days) {
        ref.read(selectedDateProvider.notifier).state = addDays(selected, days);
      },
    );

    if (listMode) {
      return PageWidth(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: AppSpace.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: AppSpace.xl),
              weekStrip,
              const SizedBox(height: AppSpace.xxl),
              if (MediaQuery.sizeOf(context).width >= 1000)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _ListPlan(
                        selected: selected,
                        open: open,
                        done: done,
                        summary: summary,
                        target: target,
                        onAdd: () =>
                            showQuickCapture(context, plannedDate: selected),
                      ),
                    ),
                    const SizedBox(width: AppSpace.x3),
                    Expanded(
                      flex: 3,
                      child: _BacklogRail(
                        backlog: backlog,
                        overdue: overdue,
                        onAdd: () => showQuickCapture(context),
                      ),
                    ),
                  ],
                )
              else ...[
                _ListPlan(
                  selected: selected,
                  open: open,
                  done: done,
                  summary: summary,
                  target: target,
                  onAdd: () => showQuickCapture(context, plannedDate: selected),
                ),
                const SizedBox(height: AppSpace.xl),
                if (Layout.isCompact(context))
                  _MobileBacklogSummary(
                    backlog: backlog,
                    overdue: overdue,
                    onOpen: () => _showBacklog(context, backlog, overdue),
                  )
                else
                  _BacklogRail(
                    backlog: backlog,
                    overdue: overdue,
                    onAdd: () => showQuickCapture(context),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    return PageWidth(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: AppSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: AppSpace.xl),
            weekStrip,
            const SizedBox(height: AppSpace.xl),
            _BoardSummary(summary: summary, target: target, selected: selected),
            const SizedBox(height: AppSpace.lg),
            SizedBox(
              height: 620,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BoardColumn(
                      key: const ValueKey('backlog'),
                      title: 'Backlog',
                      eyebrow: 'No date',
                      icon: Icons.inbox_outlined,
                      color: context.colors.inkMuted,
                      tasks: backlog,
                      dropStatus: TaskStatus.inbox,
                      onDrop: (taskId) => _moveToBacklog(ref, views, taskId),
                      onAdd: () => showQuickCapture(context),
                    ),
                    const SizedBox(width: AppSpace.md),
                    _BoardColumn(
                      key: const ValueKey('planned'),
                      title: 'Planned',
                      eyebrow: 'Ready',
                      icon: Icons.event_available_outlined,
                      color: context.colors.blue,
                      tasks:
                          dayTasks
                              .where(
                                (view) =>
                                    !view.isDone &&
                                    (view.task.status == TaskStatus.planned ||
                                        view.task.status == TaskStatus.inbox),
                              )
                              .toList()
                            ..sort(_sortTasks),
                      dropStatus: TaskStatus.planned,
                      onDrop: (taskId) =>
                          _moveToDay(ref, views, taskId, selected),
                      onAdd: () =>
                          showQuickCapture(context, plannedDate: selected),
                    ),
                    const SizedBox(width: AppSpace.md),
                    _BoardColumn(
                      key: const ValueKey('in-progress'),
                      title: 'In progress',
                      eyebrow: 'Moving',
                      icon: Icons.play_circle_outline_rounded,
                      color: context.colors.accent,
                      tasks: dayTasks
                          .where(
                            (view) =>
                                !view.isDone &&
                                view.task.status == TaskStatus.inProgress,
                          )
                          .toList(),
                      dropStatus: TaskStatus.inProgress,
                      onDrop: (taskId) =>
                          _setStatus(ref, taskId, TaskStatus.inProgress),
                      onAdd: () =>
                          showQuickCapture(context, plannedDate: selected),
                    ),
                    const SizedBox(width: AppSpace.md),
                    _BoardColumn(
                      key: const ValueKey('blocked'),
                      title: 'Blocked',
                      eyebrow: 'Waiting',
                      icon: Icons.block_rounded,
                      color: context.colors.rose,
                      tasks: dayTasks
                          .where(
                            (view) =>
                                !view.isDone &&
                                view.task.status == TaskStatus.blocked,
                          )
                          .toList(),
                      dropStatus: TaskStatus.blocked,
                      onDrop: (taskId) =>
                          _setStatus(ref, taskId, TaskStatus.blocked),
                      onAdd: () =>
                          showQuickCapture(context, plannedDate: selected),
                    ),
                    const SizedBox(width: AppSpace.md),
                    _BoardColumn(
                      key: const ValueKey('done'),
                      title: 'Done',
                      eyebrow: 'Closed',
                      icon: Icons.check_circle_outline_rounded,
                      color: context.colors.green,
                      tasks: done,
                      dropStatus: TaskStatus.done,
                      onDrop: (taskId) =>
                          _setStatus(ref, taskId, TaskStatus.done),
                      onAdd: null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              AppPlatform.isMobile
                  ? 'Hold a card and drop it on another column to move it. '
                        'The backlog is always visible, so nothing gets lost '
                        'between days.'
                  : 'Drag a card onto another column to move it. The backlog '
                        'stays visible, so nothing gets lost between days.',
              style: AppText.bodySmall.copyWith(
                color: context.colors.inkFaint,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBacklog(
    BuildContext context,
    List<TaskView> backlog,
    List<TaskView> overdue,
  ) {
    showAppSheet<void>(
      context,
      (sheetContext) => AppSheet(
        title: 'Backlog & overdue',
        subtitle: overdue.isEmpty
            ? '${backlog.length} ${backlog.length == 1 ? 'loose thread' : 'loose threads'} waiting for a day.'
            : '${overdue.length} overdue · ${backlog.length} in the backlog',
        icon: Icons.inbox_outlined,
        onClose: () => Navigator.of(sheetContext).pop(),
        footer: FilledButton.icon(
          onPressed: () {
            Navigator.of(sheetContext).pop();
            showQuickCapture(context);
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Capture work'),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (overdue.isNotEmpty) ...[
              _ListLabel('OVERDUE', '${overdue.length}'),
              const SizedBox(height: AppSpace.sm),
              for (final view in overdue) ...[
                TaskCard(
                  view: view,
                  compact: true,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    openTaskDetail(context, view.task.id);
                  },
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              const SizedBox(height: AppSpace.lg),
            ],
            _ListLabel('BACKLOG', '${backlog.length}'),
            const SizedBox(height: AppSpace.sm),
            if (backlog.isEmpty)
              Text(
                'The backlog is clear. Nothing is waiting for a day.',
                style: AppText.bodySmall.copyWith(
                  color: sheetContext.colors.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              for (final view in backlog) ...[
                TaskCard(
                  view: view,
                  compact: true,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    openTaskDetail(context, view.task.id);
                  },
                ),
                const SizedBox(height: AppSpace.sm),
              ],
          ],
        ),
      ),
      maxWidth: 560,
    );
  }

  static int _sortTasks(TaskView a, TaskView b) {
    final aStart = a.task.scheduledStart;
    final bStart = b.task.scheduledStart;
    if (aStart != null && bStart != null) return aStart.compareTo(bStart);
    if (aStart != null) return -1;
    if (bStart != null) return 1;
    return a.task.position.compareTo(b.task.position);
  }

  Future<void> _moveToBacklog(
    WidgetRef ref,
    List<TaskView> views,
    String taskId,
  ) async {
    final view = views.where((item) => item.task.id == taskId).firstOrNull;
    if (view == null) return;
    await ref
        .read(tasksProvider.notifier)
        .updateTask(
          view.task.copyWith(
            plannedDate: null,
            scheduledStart: null,
            scheduledEnd: null,
            status: TaskStatus.inbox,
            completedAt: null,
          ),
          summary: 'Returned to the backlog',
        );
  }

  Future<void> _moveToDay(
    WidgetRef ref,
    List<TaskView> views,
    String taskId,
    DateTime day,
  ) async {
    final view = views.where((item) => item.task.id == taskId).firstOrNull;
    if (view == null) return;
    await ref
        .read(tasksProvider.notifier)
        .updateTask(
          view.task.copyWith(
            plannedDate: dateKey(day),
            status: view.isDone ? TaskStatus.done : TaskStatus.planned,
            completedAt: view.isDone ? view.task.completedAt : null,
          ),
          summary: 'Planned for ${relativeDayLabel(day)}',
        );
  }

  Future<void> _setStatus(
    WidgetRef ref,
    String taskId,
    TaskStatus status,
  ) async {
    if (status == TaskStatus.blocked) {
      await ref
          .read(tasksProvider.notifier)
          .setStatus(taskId, status, blockedReason: 'Waiting');
      return;
    }
    await ref
        .read(tasksProvider.notifier)
        .setStatus(taskId, status, completeSteps: status == TaskStatus.done);
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.selected,
    required this.views,
    required this.onSelect,
    required this.onShift,
  });

  final DateTime selected;
  final List<TaskView> views;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final days = weekDays(selected);
    final today = startOfDay(DateTime.now());
    final dayCells = [
      for (final day in days)
        Expanded(
          child: _DayCell(
            day: day,
            selected: isSameDay(day, selected),
            today: isSameDay(day, today),
            count: views.forDate(day).where((view) => !view.isDone).length,
            onTap: () => onSelect(day),
          ),
        ),
    ];
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          if (compact) {
            return Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous week',
                      onPressed: () => onShift(-7),
                      icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    ),
                    Expanded(child: Row(children: dayCells)),
                    IconButton(
                      tooltip: 'Next week',
                      onPressed: () => onShift(7),
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                Row(
                  children: [
                    if (!isSameDay(selected, today))
                      TextButton.icon(
                        onPressed: () => onSelect(today),
                        icon: const Icon(Icons.today_rounded, size: 16),
                        label: const Text('Today'),
                      ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () =>
                          showTaskEditor(context, initialDate: selected),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New task'),
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              IconButton(
                tooltip: 'Previous week',
                onPressed: () => onShift(-7),
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
              ),
              Expanded(child: Row(children: dayCells)),
              IconButton(
                tooltip: 'Next week',
                onPressed: () => onShift(7),
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
              const SizedBox(width: AppSpace.xs),
              if (!isSameDay(selected, today))
                TextButton(
                  onPressed: () => onSelect(today),
                  child: const Text('Today'),
                ),
              const SizedBox(width: AppSpace.sm),
              Container(width: 1, height: 28, color: colors.line),
              const SizedBox(width: AppSpace.sm),
              IconButton(
                tooltip: 'New task',
                onPressed: () => showTaskEditor(context, initialDate: selected),
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.count,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool today;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.onPrimary : colors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              weekdayShort(day).toUpperCase(),
              style: AppText.label.copyWith(
                color: selected
                    ? colors.onPrimary.withValues(alpha: 0.65)
                    : colors.inkFaint,
                fontSize: 8.5,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${day.day}',
              style: AppText.displayS.copyWith(color: foreground, fontSize: 20),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (today)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: selected ? colors.accent : colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                if (count > 0)
                  Text(
                    '$count',
                    style: AppText.monoData.copyWith(
                      color: selected
                          ? colors.onPrimary.withValues(alpha: 0.7)
                          : colors.inkFaint,
                      fontSize: 9,
                    ),
                  )
                else
                  const SizedBox(height: 11),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardSummary extends StatelessWidget {
  const _BoardSummary({
    required this.summary,
    required this.target,
    required this.selected,
  });

  final LoadSummary summary;
  final double target;
  final DateTime selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ratio = target == 0 ? 0.0 : summary.earnedPoints / target;
    return Wrap(
      spacing: AppSpace.md,
      runSpacing: AppSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          longDateLabel(selected),
          style: AppText.bodyMedium.copyWith(color: colors.ink),
        ),
        Text(
          '${summary.doneCount}/${summary.taskCount} done',
          style: AppText.bodySmall.copyWith(color: colors.inkMuted),
        ),
        BadgePill(
          label:
              '${formatPoints(summary.earnedPoints)} / ${formatPoints(target)}',
          icon: Icons.speed_rounded,
          color: ratio >= 1 ? colors.green : colors.primary,
          compact: true,
        ),
        if (summary.taskCount > 0)
          Text(
            '${(summary.completion * 100).round()}%',
            style: AppText.monoData.copyWith(
              color: colors.inkFaint,
              fontSize: 12,
            ),
          ),
      ],
    );
  }
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    super.key,
    required this.title,
    required this.eyebrow,
    required this.icon,
    required this.color,
    required this.tasks,
    required this.dropStatus,
    required this.onDrop,
    required this.onAdd,
  });

  final String title;
  final String eyebrow;
  final IconData icon;
  final Color color;
  final List<TaskView> tasks;
  final TaskStatus dropStatus;
  final Future<void> Function(String taskId) onDrop;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DragTarget<String>(
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, rejected) {
        final hovered = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: AppDurations.fast,
          width: 306,
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: hovered
                ? color.withValues(alpha: 0.08)
                : colors.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: hovered ? color : colors.line,
              width: hovered ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(AppRadius.badge),
                    ),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppText.bodyMedium.copyWith(color: colors.ink),
                        ),
                        Text(
                          eyebrow.toUpperCase(),
                          style: AppText.label.copyWith(
                            color: colors.inkFaint,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${tasks.length}',
                    style: AppText.monoData.copyWith(
                      color: colors.inkFaint,
                      fontSize: 11,
                    ),
                  ),
                  if (onAdd != null)
                    IconButton(
                      tooltip: 'Add to $title',
                      onPressed: onAdd,
                      icon: const Icon(Icons.add_rounded, size: 17),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              if (tasks.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  child: Text(
                    dropStatus == TaskStatus.done
                        ? 'Finished work lands here.'
                        : 'Drop work here, or add something new.',
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkFaint,
                      fontStyle: FontStyle.italic,
                      fontSize: 11.5,
                    ),
                  ),
                )
              else
                for (final view in tasks) ...[
                  LongPressDraggable<String>(
                    data: view.task.id,
                    delay: const Duration(milliseconds: 180),
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(
                        width: 300,
                        child: TaskCard(
                          view: view,
                          compact: true,
                          onTap: () {},
                          dragging: true,
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.35,
                      child: TaskCard(view: view, compact: true, onTap: () {}),
                    ),
                    child: TaskCard(
                      view: view,
                      compact: true,
                      onTap: () => openTaskDetail(context, view.task.id),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _ListPlan extends StatelessWidget {
  const _ListPlan({
    required this.selected,
    required this.open,
    required this.done,
    required this.summary,
    required this.target,
    required this.onAdd,
  });

  final DateTime selected;
  final List<TaskView> open;
  final List<TaskView> done;
  final LoadSummary summary;
  final double target;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheduled = open
        .where((view) => view.task.scheduledStart != null)
        .toList();
    final anytime = open
        .where((view) => view.task.scheduledStart == null)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'PLAN',
                style: AppText.label.copyWith(color: colors.inkFaint),
              ),
            ),
            const Spacer(),
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  BadgePill(
                    label: '${formatPoints(summary.plannedPoints)} planned',
                    icon: Icons.speed_rounded,
                    color: colors.primary,
                    compact: true,
                  ),
                  BadgePill(
                    label: 'target ${formatPoints(target)}',
                    color: colors.inkMuted,
                    compact: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (open.isEmpty)
          EmptyState(
            compact: true,
            icon: Icons.event_note_outlined,
            title: 'Nothing planned for this day',
            message:
                'A day with space is not an empty day. Pull something from the '
                'backlog, or deliberately leave it open.',
            action: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add work'),
            ),
          )
        else ...[
          if (scheduled.isNotEmpty) ...[
            _ListLabel('SCHEDULED', '${scheduled.length}'),
            const SizedBox(height: AppSpace.sm),
            for (final view in scheduled) ...[
              _PlanRow(view: view),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
          if (anytime.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            _ListLabel('ANYTIME', '${anytime.length}'),
            const SizedBox(height: AppSpace.sm),
            for (final view in anytime) ...[
              _PlanRow(view: view),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
        ],
        if (done.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xl),
          if (Layout.isCompact(context))
            _MobileBacklogSummary(
              backlog: const [],
              overdue: const [],
              title: 'Completed',
              subtitle:
                  '${done.length} ${done.length == 1 ? 'loop closed' : 'loops closed'}',
              icon: Icons.check_circle_outline_rounded,
              tone: colors.green,
              onOpen: () => _showDone(context),
            )
          else ...[
            _ListLabel('COMPLETED', '${done.length}'),
            const SizedBox(height: AppSpace.sm),
            for (final view in done) ...[
              TaskCard(
                view: view,
                compact: true,
                onTap: () => openTaskDetail(context, view.task.id),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
        ],
      ],
    );
  }

  void _showDone(BuildContext context) {
    showAppSheet<void>(
      context,
      (sheetContext) => AppSheet(
        title: 'Completed',
        subtitle: 'The loops you closed on this day.',
        icon: Icons.check_circle_outline_rounded,
        onClose: () => Navigator.of(sheetContext).pop(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final view in done) ...[
              TaskCard(
                view: view,
                compact: true,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openTaskDetail(context, view.task.id);
                },
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
        ),
      ),
      maxWidth: 560,
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.view});

  final TaskView view;

  @override
  Widget build(BuildContext context) {
    if (view.task.scheduledStart == null) {
      return TaskCard(
        view: view,
        onTap: () => openTaskDetail(context, view.task.id),
      );
    }
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Padding(
            padding: const EdgeInsets.only(top: 15),
            child: Text(
              timeLabel(view.task.scheduledStart!),
              style: AppText.monoData.copyWith(
                color: colors.inkFaint,
                fontSize: 11,
              ),
            ),
          ),
        ),
        Expanded(
          child: TaskCard(
            view: view,
            onTap: () => openTaskDetail(context, view.task.id),
          ),
        ),
      ],
    );
  }
}

class _ListLabel extends StatelessWidget {
  const _ListLabel(this.label, this.count);

  final String label;
  final String count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Text(
          label,
          style: AppText.label.copyWith(color: colors.inkFaint, fontSize: 9),
        ),
        const SizedBox(width: 6),
        Text(
          count,
          style: AppText.monoData.copyWith(
            color: colors.inkFaint,
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }
}

/// A single tappable row for compact phones. The full backlog lives in a sheet
/// so the planner stays a day view instead of becoming an endless feed.
class _MobileBacklogSummary extends StatelessWidget {
  const _MobileBacklogSummary({
    required this.backlog,
    required this.overdue,
    required this.onOpen,
    this.title,
    this.subtitle,
    this.icon,
    this.tone,
  });

  final List<TaskView> backlog;
  final List<TaskView> overdue;
  final VoidCallback onOpen;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayTone = tone ?? colors.primary;
    final displayIcon = icon ?? Icons.inbox_outlined;
    final displayTitle = title ?? 'Backlog';
    final displaySubtitle =
        subtitle ??
        (overdue.isNotEmpty
            ? '${overdue.length} overdue · ${backlog.length} waiting'
            : backlog.isEmpty
            ? 'Nothing waiting for a day'
            : '${backlog.length} waiting for a day');
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      onTap: onOpen,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: displayTone.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(displayIcon, size: 18, color: displayTone),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.titleM.copyWith(
                    color: colors.ink,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  displaySubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10.6,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: colors.inkFaint),
        ],
      ),
    );
  }
}

class _BacklogRail extends StatelessWidget {
  const _BacklogRail({
    required this.backlog,
    required this.overdue,
    required this.onAdd,
  });

  final List<TaskView> backlog;
  final List<TaskView> overdue;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inbox_outlined, size: 16, color: colors.inkMuted),
                  const SizedBox(width: 6),
                  Text(
                    'BACKLOG',
                    style: AppText.label.copyWith(color: colors.inkFaint),
                  ),
                  const Spacer(),
                  Text(
                    '${backlog.length}',
                    style: AppText.monoData.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              if (backlog.isEmpty)
                Text(
                  'The backlog is clear.',
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                for (final view in backlog.take(8))
                  InkWell(
                    onTap: () => openTaskDetail(context, view.task.id),
                    borderRadius: BorderRadius.circular(AppRadius.badge),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color:
                                  view.category?.colorValue ?? colors.inkFaint,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              view.task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.bodySmall.copyWith(
                                color: colors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 15,
                            color: colors.inkFaint,
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: AppSpace.sm),
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('Capture work'),
              ),
            ],
          ),
        ),
        if (overdue.isNotEmpty) ...[
          const SizedBox(height: AppSpace.lg),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: colors.rose,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'OVERDUE',
                      style: AppText.label.copyWith(color: colors.rose),
                    ),
                    const Spacer(),
                    Text(
                      '${overdue.length}',
                      style: AppText.monoData.copyWith(color: colors.rose),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                for (final view in overdue.take(5))
                  InkWell(
                    onTap: () => openTaskDetail(context, view.task.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              view.task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.bodySmall.copyWith(
                                color: colors.ink,
                              ),
                            ),
                          ),
                          Text(
                            '${-daysBetween(DateTime.now(), view.task.dueAt!)}d',
                            style: AppText.monoData.copyWith(
                              color: colors.rose,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
