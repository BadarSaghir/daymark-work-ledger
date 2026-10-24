import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ui/sheets.dart';
import '../data/models/enums.dart';
import '../data/models/task_view.dart';
import '../state/tasks_controller.dart';
import '../state/timer_controller.dart';

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
  final current = ref.read(timerProvider).valueOrNull;
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

/// Stops the current timer with a confirmation and returns true if stopped.
Future<bool> confirmStopTimer(
  BuildContext context,
  WidgetRef ref, {
  String? assignTaskId,
  String? label,
  String? note,
}) async {
  final current = ref.read(timerProvider).valueOrNull;
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
