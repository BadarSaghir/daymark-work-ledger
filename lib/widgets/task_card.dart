import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/ui/enum_ui.dart';
import '../core/ui/feedback.dart';
import '../core/ui/layout.dart';
import '../core/ui/surface_card.dart';
import '../core/utils/date_keys.dart';
import '../core/utils/durations.dart';
import '../data/models/enums.dart';
import '../data/models/task_view.dart';
import '../state/timer_controller.dart';
import 'task_actions.dart';

class TaskCard extends ConsumerStatefulWidget {
  const TaskCard({
    super.key,
    required this.view,
    required this.onTap,
    this.compact = false,
    this.showCategory = true,
    this.dragging = false,
    this.onStartDrag,
    this.trailing,
  });

  final TaskView view;
  final VoidCallback onTap;
  final bool compact;
  final bool showCategory;
  final bool dragging;
  final VoidCallback? onStartDrag;
  final Widget? trailing;

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final view = widget.view;
    final task = view.task;
    final category = view.category;
    final active = ref.watch(
      timerProvider.select((value) {
        final session = value.value?.session;
        if (session == null || session.taskId != task.id) {
          return (false, false);
        }
        return (true, session.isRunning);
      }),
    );
    final activeTimer = active.$1;
    final runningTimer = active.$2;
    final done = view.isDone;
    final mobile = Layout.isCompact(context);

    final borderColor = activeTimer
        ? colors.accent.withValues(alpha: 0.55)
        : _hovered
        ? colors.lineStrong
        : colors.line;
    final background = activeTimer
        ? Color.alphaBlend(
            colors.accent.withValues(alpha: 0.035),
            colors.surface,
          )
        : _hovered
        ? colors.surfaceRaised
        : colors.surface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: borderColor),
          boxShadow: widget.dragging
              ? [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: mobile
                ? () => showTaskQuickActions(
                    context,
                    ref,
                    view,
                    onOpen: widget.onTap,
                  )
                : null,
            hoverColor: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                mobile ? 10 : 14,
                widget.compact ? 11 : 14,
                mobile ? 6 : 10,
                widget.compact ? 11 : 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DoneToggle(
                        done: done,
                        color: category?.colorValue ?? colors.primary,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          toggleTaskDone(context, ref, view);
                        },
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (category != null) ...[
                                  Container(
                                    width: 7,
                                    height: 7,
                                    margin: const EdgeInsets.only(top: 7),
                                    decoration: BoxDecoration(
                                      color: category.colorValue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                ],
                                Expanded(
                                  child: Text(
                                    task.title,
                                    maxLines: widget.compact ? 2 : 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.titleM.copyWith(
                                      color: done
                                          ? colors.inkMuted
                                          : colors.ink,
                                      decoration: done
                                          ? TextDecoration.lineThrough
                                          : null,
                                      decorationColor: colors.inkFaint,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!widget.compact) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 7,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  BadgePill(
                                    label: task.kind.label,
                                    icon: task.kind.icon,
                                    color: task.kind.color(colors),
                                    compact: true,
                                  ),
                                  if (task.priority == Priority.high ||
                                      task.priority == Priority.urgent)
                                    BadgePill(
                                      label: task.priority.label,
                                      icon: task.priority.icon,
                                      color: task.priority.color(colors),
                                      compact: true,
                                    ),
                                  if (view.isOverdue)
                                    BadgePill(
                                      label: 'Overdue',
                                      icon: Icons.warning_amber_rounded,
                                      color: colors.rose,
                                      compact: true,
                                    ),
                                  _MetaInline(
                                    icon: Icons.speed_rounded,
                                    label: formatPoints(view.points),
                                    color: colors.inkMuted,
                                  ),
                                  if (task.scheduledStart != null)
                                    _MetaInline(
                                      icon: Icons.schedule_rounded,
                                      label: _scheduleLabel(
                                        task.scheduledStart!,
                                      ),
                                      color: colors.inkMuted,
                                    ),
                                  if (view.hasSteps)
                                    _MetaInline(
                                      icon: Icons.checklist_rounded,
                                      label:
                                          '${view.doneSteps}/${view.totalSteps}',
                                      color: view.progress > 0
                                          ? colors.primary
                                          : colors.inkMuted,
                                    ),
                                  TaskTimeText(view: view),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.trailing != null) ...[
                        const SizedBox(width: 4),
                        widget.trailing!,
                      ] else if (mobile) ...[
                        const SizedBox(width: 2),
                        IconButton(
                          tooltip: 'Task actions',
                          onPressed: () => showTaskQuickActions(
                            context,
                            ref,
                            view,
                            onOpen: widget.onTap,
                          ),
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            size: 22,
                            color: colors.inkMuted,
                          ),
                        ),
                      ] else if (!done) ...[
                        const SizedBox(width: 4),
                        _TimerButton(
                          active: activeTimer,
                          running: runningTimer,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            toggleTaskTimer(context, ref, view);
                          },
                        ),
                      ],
                    ],
                  ),
                  if (view.hasSteps) ...[
                    const SizedBox(height: 11),
                    Padding(
                      padding: const EdgeInsets.only(left: 32, right: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: ProgressHairline(
                              value: view.progress,
                              color: category?.colorValue ?? colors.primary,
                              height: 3,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            '${(view.progress * 100).round()}%',
                            style: AppText.monoData.copyWith(
                              color: colors.inkFaint,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _scheduleLabel(DateTime start) {
    final now = DateTime.now();
    if (isSameDay(start, now)) return timeLabel(start);
    return '${weekdayShort(start)} ${timeLabel(start)}';
  }
}

class _DoneToggle extends StatelessWidget {
  const _DoneToggle({
    required this.done,
    required this.color,
    required this.onTap,
  });

  final bool done;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final touch = Layout.isCompact(context);
    final circle = AnimatedContainer(
      duration: AppDurations.fast,
      width: 23,
      height: 23,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? color : Colors.transparent,
        border: Border.all(color: done ? color : colors.lineStrong, width: 1.5),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 14, color: colors.onPrimary)
          : null,
    );
    return Semantics(
      button: true,
      label: done ? 'Reopen task' : 'Complete task',
      child: Tooltip(
        message: done ? 'Reopen' : 'Complete',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: touch
              ? SizedBox(
                  width: 40,
                  height: 40,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: circle,
                    ),
                  ),
                )
              : circle,
        ),
      ),
    );
  }
}

class _TimerButton extends StatelessWidget {
  const _TimerButton({
    required this.active,
    required this.running,
    required this.onTap,
  });

  final bool active;
  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final icon = running
        ? Icons.pause_rounded
        : active
        ? Icons.play_arrow_rounded
        : Icons.play_arrow_outlined;
    return Tooltip(
      message: running
          ? 'Pause timer'
          : active
          ? 'Resume timer'
          : 'Start timer',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? colors.accent : colors.primarySoft,
            border: Border.all(
              color: active ? colors.accent : colors.primarySoft,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? Colors.white : colors.primary,
          ),
        ),
      ),
    );
  }
}

class _MetaInline extends StatelessWidget {
  const _MetaInline({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppText.bodySmall.copyWith(
            color: color,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class TaskTimeText extends ConsumerWidget {
  const TaskTimeText({super.key, required this.view, this.showZero = false});

  final TaskView view;
  final bool showZero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final liveMs = ref.watch(
      timerProvider.select((value) {
        final current = value.value;
        final session = current?.session;
        if (session == null || session.taskId != view.task.id) return 0;
        return session.elapsedAt(current!.now).inMilliseconds;
      }),
    );
    final total = view.trackedMs + liveMs;
    if (total == 0 && !showZero) return const SizedBox.shrink();
    return _MetaInline(
      icon: Icons.timer_outlined,
      label: formatCompactMs(total),
      color: liveMs > 0 ? colors.accent : colors.inkMuted,
    );
  }
}
