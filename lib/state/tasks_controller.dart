import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/category.dart';
import '../data/models/enums.dart';
import '../data/models/subtask.dart';
import '../data/models/task.dart';
import '../data/models/task_view.dart';
import 'categories_controller.dart';
import 'repository_providers.dart';
import 'stats_providers.dart';

class TasksController extends AsyncNotifier<List<TaskView>> {
  @override
  Future<List<TaskView>> build() async {
    final repo = ref.watch(taskRepositoryProvider);
    final categories = await ref.watch(categoriesProvider.future);
    final tasks = await repo.list();
    final subtasks = await repo.allSubtasks();
    final tracked = await repo.trackedTotals();
    final categoryById = <String, Category>{
      for (final category in categories) category.id: category,
    };
    final stepsByTask = <String, List<Subtask>>{};
    for (final step in subtasks) {
      (stepsByTask[step.taskId] ??= []).add(step);
    }
    return [
      for (final task in tasks)
        TaskView(
          task: task,
          category: categoryById[task.categoryId],
          subtasks: stepsByTask[task.id] ?? const [],
          trackedMs: tracked[task.id] ?? 0,
        ),
    ];
  }

  List<TaskView> get views => state.value ?? const [];

  TaskView? byId(String id) {
    for (final view in views) {
      if (view.task.id == id) return view;
    }
    return null;
  }

  List<TaskView> forDate(DateTime day) {
    final key = dayKey(day);
    final result = views
        .where(
          (view) =>
              view.task.plannedDate == key ||
              (view.task.scheduledStart != null &&
                  view.task.scheduledStart!.year == day.year &&
                  view.task.scheduledStart!.month == day.month &&
                  view.task.scheduledStart!.day == day.day) ||
              (view.task.completedAt != null &&
                  view.task.completedAt!.year == day.year &&
                  view.task.completedAt!.month == day.month &&
                  view.task.completedAt!.day == day.day),
        )
        .toList();
    result.sort((a, b) {
      final aStart = a.task.scheduledStart;
      final bStart = b.task.scheduledStart;
      if (aStart != null && bStart != null) return aStart.compareTo(bStart);
      if (aStart != null) return -1;
      if (bStart != null) return 1;
      return a.task.position.compareTo(b.task.position);
    });
    return result;
  }

  String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Future<Task> createNew({
    required String title,
    String? categoryId,
    WorkKind kind = WorkKind.official,
    TaskStatus status = TaskStatus.inbox,
    Priority priority = Priority.normal,
    int effort = 2,
    int? estimateMinutes,
    String? plannedDate,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    DateTime? dueAt,
    String notesMd = '',
    List<String> stepTitles = const [],
  }) async {
    final task = await ref
        .read(taskRepositoryProvider)
        .createNew(
          title: title,
          categoryId: categoryId,
          kind: kind,
          status: status,
          priority: priority,
          effort: effort,
          estimateMinutes: estimateMinutes,
          plannedDate: plannedDate,
          scheduledStart: scheduledStart,
          scheduledEnd: scheduledEnd,
          dueAt: dueAt,
          notesMd: notesMd,
          stepTitles: stepTitles,
        );
    await refresh();
    return task;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    invalidateStats(ref);
  }

  Future<void> updateTask(Task task, {String? summary}) async {
    await ref.read(taskRepositoryProvider).update(task, summary: summary);
    await refresh();
  }

  Future<void> saveNotes(String taskId, String notesMd) async {
    final view = byId(taskId);
    if (view == null) return;
    if (view.task.notesMd == notesMd) return;
    await ref
        .read(taskRepositoryProvider)
        .update(view.task.copyWith(notesMd: notesMd));
    await refresh();
  }

  Future<void> setStatus(
    String taskId,
    TaskStatus status, {
    bool completeSteps = false,
    String? blockedReason,
  }) async {
    await ref
        .read(taskRepositoryProvider)
        .setStatus(
          taskId,
          status,
          completeSteps: completeSteps,
          blockedReason: blockedReason,
        );
    await refresh();
  }

  Future<void> addStep(String taskId, String title) async {
    await ref.read(taskRepositoryProvider).addSubtask(taskId, title);
    await refresh();
  }

  Future<void> toggleStep(Subtask step) async {
    await ref.read(taskRepositoryProvider).toggleSubtask(step);
    await refresh();
  }

  Future<void> deleteStep(Subtask step) async {
    await ref.read(taskRepositoryProvider).deleteSubtask(step);
    await refresh();
  }

  Future<void> moveStep(Subtask step, int delta) async {
    await ref.read(taskRepositoryProvider).moveSubtask(step, delta);
    await refresh();
  }

  Future<void> setArchived(TaskView view, bool archived) async {
    await ref.read(taskRepositoryProvider).setArchived(view.task.id, archived);
    await refresh();
  }

  Future<void> deleteTask(TaskView view) async {
    await ref.read(taskRepositoryProvider).deleteTask(view.task.id);
    await refresh();
  }
}

final tasksProvider = AsyncNotifierProvider<TasksController, List<TaskView>>(
  TasksController.new,
);
