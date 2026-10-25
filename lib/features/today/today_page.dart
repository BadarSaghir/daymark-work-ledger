import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/nav.dart';
import '../../app/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/enum_ui.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../core/utils/durations.dart';
import '../../data/models/task_view.dart';
import '../../state/journal_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/stats_providers.dart';
import '../../state/tasks_controller.dart';
import '../../state/timer_controller.dart';
import '../../state/ui_state.dart';
import '../../widgets/task_actions.dart';
import '../../widgets/task_card.dart';
import '../../widgets/quick_capture.dart';
import '../../widgets/timer_dialogs.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = startOfDay(DateTime.now());
    final key = dateKey(today);
    final settings = ref.watch(settingsProvider).value;
    final tasksAsync = ref.watch(tasksProvider);
    final views = tasksAsync.value ?? const <TaskView>[];
    final dayTasks = views.forDate(today).toList()
      ..sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        final aStart = a.task.scheduledStart;
        final bStart = b.task.scheduledStart;
        if (aStart != null && bStart != null) return aStart.compareTo(bStart);
        if (aStart != null) return -1;
        if (bStart != null) return 1;
        return a.task.position.compareTo(b.task.position);
      });
    final openTasks = dayTasks.where((view) => !view.isDone).toList();
    final doneTasks = dayTasks.where((view) => view.isDone).toList();
    final plannedToday = views
        .where((view) => view.task.plannedDate == key)
        .toList();
    final plannedPoints = plannedToday.fold<double>(
      0,
      (sum, view) => sum + view.points,
    );
    final earnedPoints = plannedToday.fold<double>(
      0,
      (sum, view) => sum + view.earnedPoints,
    );
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
    final inbox =
        views
            .where((view) => !view.isDone && view.task.plannedDate == null)
            .toList()
          ..sort((a, b) => b.task.updatedAt.compareTo(a.task.updatedAt));
    final focusAsync = ref.watch(dayFocusProvider(today));
    final focusMs = focusAsync.value ?? 0;
    final journal = ref.watch(journalForDateProvider(key));
    final streak = ref.watch(journalStreakProvider);
    final target = settings?.dailyWeightTarget ?? 25;
    final focusTarget = settings?.dailyFocusMinutes ?? 300;
    final completedCount = plannedToday.where((view) => view.isDone).length;

    final isWide = MediaQuery.sizeOf(context).width >= 1080;

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          eyebrow: weekdayLong(today),
          title:
              '${greetingForHour(DateTime.now().hour)}, '
              '${_firstName(settings?.displayName)}',
          subtitle:
              '${longDateLabel(today)} · '
              '${openTasks.length} ${openTasks.length == 1 ? 'thread' : 'threads'} '
              'open. Choose what deserves the day.',
          actions: [
            if (!Layout.isCompact(context)) ...[
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(selectedDateProvider.notifier).state = today;
                  ref.read(navIndexProvider.notifier).state = NavTarget.planner;
                },
                icon: const Icon(Icons.view_week_outlined, size: 17),
                label: const Text('Plan'),
              ),
              FilledButton.icon(
                onPressed: () => showQuickCapture(context, plannedDate: today),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Capture'),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpace.xxl),
        _PulseStrip(
          plannedPoints: plannedPoints,
          earnedPoints: earnedPoints,
          targetPoints: target,
          focusMs: focusMs,
          focusTargetMinutes: focusTarget,
          doneCount: completedCount,
          openCount: plannedToday.where((v) => !v.isDone).length,
          streak: streak,
        ),
        const SizedBox(height: AppSpace.xxl),
        _FocusPanel(
          settingsName: _firstName(settings?.displayName),
          onOpenFocus: () {
            ref.read(navIndexProvider.notifier).state = NavTarget.focus;
          },
        ),
        if (overdue.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxl),
          _SectionHeading(
            eyebrow: 'Slipping',
            title: 'Overdue',
            trailing: Text(
              '${overdue.length}',
              style: AppText.monoData.copyWith(color: context.colors.rose),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          for (final view in overdue.take(3)) ...[
            TaskCard(
              view: view,
              compact: true,
              onTap: () => openTaskDetail(context, view.task.id),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
        const SizedBox(height: AppSpace.xxl),
        _SectionHeading(
          eyebrow: 'Agenda',
          title: "Today's plan",
          trailing: TextButton.icon(
            onPressed: () => showQuickCapture(context, plannedDate: today),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add'),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (openTasks.isEmpty)
          EmptyState(
            compact: true,
            icon: Icons.wb_sunny_outlined,
            title: 'The day is open',
            message:
                'Nothing is planned yet. Capture one honest piece of work and '
                'give it a time, or leave room for what arrives.',
            action: FilledButton.icon(
              onPressed: () => showQuickCapture(context, plannedDate: today),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Plan one thing'),
            ),
          )
        else
          _Timeline(tasks: openTasks),
        if (doneTasks.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxl),
          _SectionHeading(
            eyebrow: 'Closed loops',
            title: 'Completed today',
            trailing: Text(
              '${doneTasks.length}',
              style: AppText.monoData.copyWith(color: context.colors.primary),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          for (final view in doneTasks) ...[
            TaskCard(
              view: view,
              compact: true,
              onTap: () => openTaskDetail(context, view.task.id),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
      ],
    );

    final rail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayShapeCard(
          plannedPoints: plannedPoints,
          earnedPoints: earnedPoints,
          targetPoints: target,
          focusMs: focusMs,
          focusTargetMinutes: focusTarget,
          doneCount: completedCount,
          plannedCount: plannedToday.length,
        ),
        const SizedBox(height: AppSpace.lg),
        _JournalPrompt(
          body: journal?.bodyMd ?? '',
          streak: streak,
          onOpen: () {
            ref.read(selectedDateProvider.notifier).state = today;
            ref.read(navIndexProvider.notifier).state = NavTarget.journal;
          },
        ),
        const SizedBox(height: AppSpace.lg),
        _InboxCard(
          inbox: inbox,
          onOpenAll: () {
            ref.read(navIndexProvider.notifier).state = NavTarget.planner;
          },
        ),
      ],
    );

    return PageWidth(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: AppSpace.x6),
        child: tasksAsync.isLoading && views.isEmpty
            ? const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [SizedBox(height: 120), LoadingBlock(height: 360)],
              )
            : !isWide
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  main,
                  const SizedBox(height: AppSpace.xxl),
                  rail,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: main),
                  const SizedBox(width: AppSpace.x4),
                  SizedBox(width: 318, child: rail),
                ],
              ),
      ),
    );
  }

  String _firstName(String? name) {
    final clean = (name ?? '').trim();
    if (clean.isEmpty) return 'friend';
    return clean.split(RegExp(r'\s+')).first;
  }
}

class _PulseStrip extends StatelessWidget {
  const _PulseStrip({
    required this.plannedPoints,
    required this.earnedPoints,
    required this.targetPoints,
    required this.focusMs,
    required this.focusTargetMinutes,
    required this.doneCount,
    required this.openCount,
    required this.streak,
  });

  final double plannedPoints;
  final double earnedPoints;
  final double targetPoints;
  final int focusMs;
  final int focusTargetMinutes;
  final int doneCount;
  final int openCount;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ratio = targetPoints <= 0 ? 0.0 : earnedPoints / targetPoints;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: AppSpace.lg,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          final items = [
            _Metric(
              label: 'Weight earned',
              value: formatPoints(earnedPoints),
              hint: '${formatPoints(plannedPoints)} planned',
              accent: colors.primary,
            ),
            _Metric(
              label: 'Focus',
              value: formatCompactMs(focusMs),
              hint: '${focusTargetMinutes ~/ 60}h target',
              accent: colors.accent,
            ),
            _Metric(
              label: 'Threads',
              value: '$openCount open',
              hint: '$doneCount closed',
              accent: colors.blue,
            ),
            _Metric(
              label: 'Journal',
              value: streak == 0
                  ? '—'
                  : '$streak ${streak == 1 ? 'day' : 'days'}',
              hint: 'writing streak',
              accent: colors.gold,
            ),
          ];
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _TargetBar(ratio: ratio.clamp(0.0, 1.2))),
                    const SizedBox(width: AppSpace.lg),
                    Text(
                      '${(ratio * 100).round()}%',
                      style: AppText.monoLarge.copyWith(
                        fontSize: 26,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                Divider(color: colors.line),
                const SizedBox(height: AppSpace.lg),
                Wrap(
                  spacing: AppSpace.xxl,
                  runSpacing: AppSpace.lg,
                  children: [
                    SizedBox(width: 130, child: items[0]),
                    SizedBox(width: 130, child: items[1]),
                    SizedBox(width: 130, child: items[2]),
                    SizedBox(width: 130, child: items[3]),
                  ],
                ),
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _TargetBar(ratio: ratio.clamp(0.0, 1.2)),
                ),
                const SizedBox(width: AppSpace.xl),
                Container(width: 1, color: colors.line),
                const SizedBox(width: AppSpace.xl),
                Expanded(flex: 2, child: items[0]),
                const SizedBox(width: AppSpace.lg),
                Expanded(flex: 2, child: items[1]),
                const SizedBox(width: AppSpace.lg),
                Expanded(flex: 2, child: items[2]),
                const SizedBox(width: AppSpace.lg),
                Expanded(flex: 2, child: items[3]),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TargetBar extends StatelessWidget {
  const _TargetBar({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'THE SHAPE OF TODAY',
          style: AppText.label.copyWith(color: colors.inkFaint),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          '${(ratio * 100).round()}%',
          style: AppText.displayL.copyWith(color: colors.primary, fontSize: 32),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: colors.surfaceSunken),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ratio.clamp(0.0, 1.0),
                  child: ColoredBox(color: colors.primary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'earned against your daily weight target',
          style: AppText.bodySmall.copyWith(
            color: colors.inkMuted,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.hint,
    required this.accent,
  });

  final String label;
  final String value;
  final String hint;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label.toUpperCase(),
                style: AppText.label.copyWith(
                  color: colors.inkFaint,
                  fontSize: 8.8,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.monoLarge.copyWith(fontSize: 21, color: colors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.bodySmall.copyWith(
            color: colors.inkFaint,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _FocusPanel extends ConsumerWidget {
  const _FocusPanel({required this.settingsName, required this.onOpenFocus});

  final String settingsName;
  final VoidCallback onOpenFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final timer = ref.watch(timerProvider).value;
    final session = timer?.session;
    final active = session != null;

    return Container(
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        color: active ? colors.ink : colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: active ? colors.ink : colors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: active
                  ? colors.canvas.withValues(alpha: 0.08)
                  : colors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              active
                  ? (timer!.isRunning
                        ? Icons.graphic_eq_rounded
                        : Icons.pause_rounded)
                  : Icons.timer_outlined,
              color: active ? colors.canvas : colors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active
                      ? (timer!.isRunning ? 'In focus' : 'Focus paused')
                      : 'The focus room',
                  style: AppText.label.copyWith(
                    color: active
                        ? colors.canvas.withValues(alpha: 0.55)
                        : colors.inkFaint,
                  ),
                ),
                const SizedBox(height: 4),
                if (active) ...[
                  Text(
                    session.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleM.copyWith(color: colors.canvas),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatStopwatch(timer?.elapsed ?? Duration.zero),
                    style: AppText.monoData.copyWith(
                      color: colors.accent,
                      fontSize: 15,
                    ),
                  ),
                ] else
                  Text(
                    'Settle into one thing, $settingsName.',
                    style: AppText.titleM.copyWith(color: colors.ink),
                  ),
              ],
            ),
          ),
          if (active) ...[
            IconButton(
              tooltip: timer!.isRunning ? 'Pause' : 'Resume',
              onPressed: () {
                if (timer.isRunning) {
                  ref.read(timerProvider.notifier).pause();
                } else {
                  ref.read(timerProvider.notifier).resume();
                }
              },
              icon: Icon(
                timer.isRunning
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: colors.canvas,
              ),
            ),
            IconButton(
              tooltip: 'Stop and save',
              onPressed: () => confirmStopTimer(context, ref),
              icon: Icon(Icons.stop_rounded, color: colors.canvas),
            ),
          ] else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => showStartFocusDialog(context, ref),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Start'),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Open focus room',
            onPressed: onOpenFocus,
            icon: Icon(
              Icons.arrow_forward_rounded,
              color: active
                  ? colors.canvas.withValues(alpha: 0.6)
                  : colors.inkFaint,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.tasks});

  final List<TaskView> tasks;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        for (var index = 0; index < tasks.length; index++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 54,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: Text(
                      tasks[index].task.scheduledStart == null
                          ? '—'
                          : timeLabel(tasks[index].task.scheduledStart!),
                      textAlign: TextAlign.right,
                      style: AppText.monoData.copyWith(
                        color: colors.inkFaint,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                SizedBox(
                  width: 14,
                  child: Column(
                    children: [
                      const SizedBox(height: 18),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color:
                              tasks[index].category?.colorValue ??
                              colors.inkFaint,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (index != tasks.length - 1)
                        Expanded(
                          child: Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: colors.line,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: TaskCard(
                      view: tasks[index],
                      onTap: () =>
                          openTaskDetail(context, tasks[index].task.id),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: AppText.label.copyWith(color: colors.inkFaint),
              ),
              const SizedBox(height: 3),
              Text(title, style: AppText.displayS.copyWith(color: colors.ink)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _DayShapeCard extends StatelessWidget {
  const _DayShapeCard({
    required this.plannedPoints,
    required this.earnedPoints,
    required this.targetPoints,
    required this.focusMs,
    required this.focusTargetMinutes,
    required this.doneCount,
    required this.plannedCount,
  });

  final double plannedPoints;
  final double earnedPoints;
  final double targetPoints;
  final int focusMs;
  final int focusTargetMinutes;
  final int doneCount;
  final int plannedCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ratio = targetPoints <= 0 ? 0.0 : earnedPoints / targetPoints;
    final focusRatio = focusTargetMinutes <= 0
        ? 0.0
        : focusMs / (focusTargetMinutes * 60000);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'DAY SHAPE',
                  style: AppText.label.copyWith(color: colors.inkFaint),
                ),
              ),
              Text(
                dateLabel(DateTime.now()),
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Center(
            child: SizedBox(
              width: 132,
              height: 132,
              child: CustomPaint(
                painter: _RingPainter(
                  progress: ratio.clamp(0.0, 1.0),
                  color: colors.primary,
                  track: colors.surfaceSunken,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(ratio * 100).round()}%',
                        style: AppText.displayL.copyWith(
                          color: colors.ink,
                          fontSize: 28,
                        ),
                      ),
                      Text(
                        'of target',
                        style: AppText.bodySmall.copyWith(
                          color: colors.inkFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          _RailRow(
            label: 'Weight',
            value:
                '${formatPoints(earnedPoints)} / ${formatPoints(targetPoints)}',
          ),
          const SizedBox(height: AppSpace.sm),
          _RailBar(ratio: ratio),
          const SizedBox(height: AppSpace.lg),
          _RailRow(
            label: 'Focus',
            value:
                '${formatCompactMs(focusMs)} / ${formatMinutes(focusTargetMinutes)}',
          ),
          const SizedBox(height: AppSpace.sm),
          _RailBar(ratio: focusRatio, color: colors.accent),
          const SizedBox(height: AppSpace.lg),
          _RailRow(
            label: 'Threads',
            value:
                '$doneCount done · ${math.max(0, plannedCount - doneCount)} left',
          ),
        ],
      ),
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Text(
          label,
          style: AppText.bodySmall.copyWith(
            color: colors.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: AppText.monoData.copyWith(color: colors.ink, fontSize: 11),
        ),
      ],
    );
  }
}

class _RailBar extends StatelessWidget {
  const _RailBar({required this.ratio, this.color});

  final double ratio;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.surfaceSunken),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio.clamp(0.0, 1.0),
              child: ColoredBox(color: color ?? colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _JournalPrompt extends StatelessWidget {
  const _JournalPrompt({
    required this.body,
    required this.streak,
    required this.onOpen,
  });

  final String body;
  final int streak;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final excerpt = body
        .replaceAll(RegExp(r'[#>*_`\-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return SurfaceCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 17, color: colors.gold),
              const SizedBox(width: 6),
              Text(
                'TODAY’S NOTE',
                style: AppText.label.copyWith(color: colors.inkFaint),
              ),
              const Spacer(),
              if (streak > 0)
                BadgePill(
                  label: '$streak-day streak',
                  icon: Icons.local_fire_department_outlined,
                  color: colors.gold,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            excerpt.isEmpty
                ? 'What did today ask of you? Write the honest version while it is still warm.'
                : excerpt,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: AppText.body.copyWith(
              color: excerpt.isEmpty ? colors.inkFaint : colors.ink,
              fontStyle: excerpt.isEmpty ? FontStyle.italic : null,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Text(
                excerpt.isEmpty ? 'Start writing' : 'Continue',
                style: AppText.bodySmall.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: colors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({required this.inbox, required this.onOpenAll});

  final List<TaskView> inbox;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inbox_outlined, size: 16, color: colors.inkMuted),
              const SizedBox(width: 6),
              Text(
                'INBOX',
                style: AppText.label.copyWith(color: colors.inkFaint),
              ),
              const Spacer(),
              Text(
                '${inbox.length}',
                style: AppText.monoData.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (inbox.isEmpty)
            Text(
              'Nothing loose. The ledger is tidy.',
              style: AppText.bodySmall.copyWith(
                color: colors.inkFaint,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            for (final view in inbox.take(4))
              InkWell(
                onTap: () => openTaskDetail(context, view.task.id),
                borderRadius: BorderRadius.circular(AppRadius.badge),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: view.category?.colorValue ?? colors.inkFaint,
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
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => showQuickCapture(context),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Capture'),
              ),
              const Spacer(),
              if (inbox.isNotEmpty)
                TextButton(
                  onPressed: onOpenAll,
                  child: const Text('Open planner'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
