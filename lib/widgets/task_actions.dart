import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/ui/enum_ui.dart';
import '../core/ui/sheets.dart';
import '../core/utils/date_keys.dart';
import '../data/models/enums.dart';
import '../data/models/task_view.dart';
import '../state/tasks_controller.dart';
import '../state/timer_controller.dart';
import 'task_editor.dart';

Future<void> toggleTaskDone(
  BuildContext context,
  WidgetRef ref,
  TaskView view,
) async {
  final notifier = ref.read(tasksProvider.notifier);
  if (view.isDone) {
    final reopenStatus = view.task.plannedDate == null
        ? TaskStatus.inbox
        : TaskStatus.planned;
    await notifier.setStatus(view.task.id, reopenStatus);
    if (context.mounted) showToast(context, 'Reopened “${view.task.title}”');
    return;
  }
  final openSteps = view.subtasks.where((step) => !step.isDone).length;
  if (openSteps > 0) {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Finish this task?',
      message:
          '${view.task.title} still has $openSteps unfinished '
          '${openSteps == 1 ? 'step' : 'steps'}. Completing the task will also check '
          'them off.',
      confirmLabel: 'Complete all',
      icon: Icons.checklist_rounded,
    );
    if (!confirmed) return;
  }
  await notifier.setStatus(view.task.id, TaskStatus.done, completeSteps: true);
  if (context.mounted) {
    showToast(
      context,
      'Done · ${view.task.title}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          notifier.setStatus(
            view.task.id,
            view.task.plannedDate == null
                ? TaskStatus.inbox
                : TaskStatus.planned,
          );
        },
      ),
    );
  }
}

Future<void> toggleTaskTimer(
  BuildContext context,
  WidgetRef ref,
  TaskView view,
) async {
  final current = ref.read(timerProvider).value;
  final session = current?.session;
  final notifier = ref.read(timerProvider.notifier);

  if (session != null && session.taskId == view.task.id) {
    if (session.isRunning) {
      await notifier.pause();
      if (context.mounted) {
        showToast(context, 'Paused · ${view.task.title}');
      }
    } else {
      await notifier.resume();
      if (context.mounted) {
        showToast(context, 'Resumed · ${view.task.title}');
      }
    }
    return;
  }

  if (session != null) {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Switch timer?',
      message:
          '“${session.label}” is ${session.isRunning ? 'running' : 'paused'}. '
          'Stop it and start “${view.task.title}”?',
      confirmLabel: 'Switch',
      icon: Icons.swap_horiz_rounded,
    );
    if (!confirmed) return;
  }

  try {
    await notifier.startForTask(view.task);
    if (context.mounted) {
      showToast(context, 'Tracking · ${view.task.title}');
    }
  } catch (error) {
    if (context.mounted) {
      showToast(context, 'Could not start the timer: $error');
    }
  }
}

/// Mobile quick actions. Long-pressing or tapping the overflow control on a
/// task card opens this sheet, keeping common actions within thumb reach.
Future<void> showTaskQuickActions(
  BuildContext context,
  WidgetRef ref,
  TaskView view, {
  VoidCallback? onOpen,
}) async {
  HapticFeedback.mediumImpact();
  final today = dateKey(DateTime.now());
  final timerActive =
      ref.read(timerProvider).value?.session?.taskId == view.task.id;
  await showAppSheet<void>(
    context,
    (sheetContext) => AppSheet(
      title: view.task.title,
      subtitle: '${view.task.kind.label} · ${view.task.status.label}',
      icon: view.task.kind.icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onOpen != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 54,
              leading: const Icon(Icons.open_in_new_rounded, size: 21),
              title: const Text('Open task'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onOpen();
              },
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 54,
            leading: Icon(
              view.isDone
                  ? Icons.undo_rounded
                  : Icons.check_circle_outline_rounded,
              size: 21,
              color: view.isDone
                  ? sheetContext.colors.inkMuted
                  : sheetContext.colors.green,
            ),
            title: Text(view.isDone ? 'Reopen task' : 'Mark complete'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              toggleTaskDone(context, ref, view);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 54,
            leading: Icon(
              timerActive
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
              size: 21,
              color: sheetContext.colors.accent,
            ),
            title: const Text('Track time'),
            subtitle: Text(
              timerActive
                  ? 'Pause or resume this task’s timer'
                  : 'Start a timer for this task',
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              toggleTaskTimer(context, ref, view);
            },
          ),
          if (view.task.plannedDate != today)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 54,
              leading: Icon(
                Icons.today_rounded,
                size: 21,
                color: sheetContext.colors.primary,
              ),
              title: const Text('Plan for today'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref
                    .read(tasksProvider.notifier)
                    .updateTask(
                      view.task.copyWith(
                        plannedDate: today,
                        status: view.isDone
                            ? view.task.status
                            : TaskStatus.planned,
                      ),
                      summary: 'Planned for today',
                    );
              },
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 54,
            leading: const Icon(Icons.edit_outlined, size: 21),
            title: const Text('Edit task'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showTaskEditor(context, existing: view);
            },
          ),
        ],
      ),
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
    maxWidth: 560,
  );
}

/// Stops the current timer with a confirmation and returns true if stopped.
Future<bool> confirmStopTimer(
  BuildContext context,
  WidgetRef ref, {
  String? assignTaskId,
  String? label,
  String? note,
}) async {
  final current = ref.read(timerProvider).value;
  if (current?.session == null) return false;
  final confirmed = await showConfirmDialog(
    context,
    title: 'Stop the clock?',
    message:
        '${formatTimerPreview(current!)} on “${current.label}” will be saved to your record.',
    confirmLabel: 'Stop & save',
    icon: Icons.stop_circle_outlined,
  );
  if (!confirmed) return false;
  await ref
      .read(timerProvider.notifier)
      .stop(assignTaskId: assignTaskId, label: label, note: note);
  if (context.mounted) showToast(context, 'Timer saved');
  return true;
}

String formatTimerPreview(TimerState state) {
  final duration = state.elapsed;
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0
      ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}
