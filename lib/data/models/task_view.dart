import '../../core/utils/date_keys.dart';
import '../../core/utils/weightage.dart';
import 'category.dart';
import 'subtask.dart';
import 'task.dart';

/// A task joined with the data the interface needs: its category, steps, and
/// all-time tracked milliseconds. Built by the tasks controller, consumed by
/// widgets. Never persisted.
class TaskView {
  const TaskView({
    required this.task,
    required this.category,
    required this.subtasks,
    required this.trackedMs,
  });

  final Task task;
  final Category? category;
  final List<Subtask> subtasks;
  final int trackedMs;

  int get doneSteps => subtasks.where((step) => step.isDone).length;
  int get totalSteps => subtasks.length;
  int get trackedMinutes => (trackedMs / 60000).round();

  /// Effort points before completion is considered.
  double get points => taskPoints(task: task, category: category);

  /// 0..1.
  double get progress => taskProgress(task, subtasks);

  double get earnedPoints => points * progress;

  bool get hasSteps => subtasks.isNotEmpty;
  bool get isDone => task.isDone;
  bool get isOverdue => task.isOverdue;

  String? get plannedDate => task.plannedDate;

  TaskView copyWith({
    Task? task,
    Category? category,
    List<Subtask>? subtasks,
    int? trackedMs,
    bool clearCategory = false,
  }) {
    return TaskView(
      task: task ?? this.task,
      category: clearCategory ? null : (category ?? this.category),
      subtasks: subtasks ?? this.subtasks,
      trackedMs: trackedMs ?? this.trackedMs,
    );
  }
}

/// Aggregate plan for a day or period.
class LoadSummary {
  const LoadSummary({
    required this.plannedPoints,
    required this.donePoints,
    required this.earnedPoints,
    required this.plannedMinutes,
    required this.taskCount,
    required this.doneCount,
  });

  final double plannedPoints;
  final double donePoints;
  final double earnedPoints;
  final int plannedMinutes;
  final int taskCount;
  final int doneCount;

  bool get isEmpty => taskCount == 0;
  double get completion => taskCount == 0 ? 0 : doneCount / taskCount;
}

extension TaskViewList on Iterable<TaskView> {
  LoadSummary get loadSummary {
    var plannedPoints = 0.0;
    var donePoints = 0.0;
    var earned = 0.0;
    var plannedMinutes = 0;
    var done = 0;
    var count = 0;
    for (final view in this) {
      count++;
      plannedPoints += view.points;
      plannedMinutes += view.task.estimateMinutes ?? 0;
      if (view.isDone) {
        done++;
        donePoints += view.points;
        earned += view.points;
      } else {
        earned += view.earnedPoints;
      }
    }
    return LoadSummary(
      plannedPoints: plannedPoints,
      donePoints: donePoints,
      earnedPoints: earned,
      plannedMinutes: plannedMinutes,
      taskCount: count,
      doneCount: done,
    );
  }

  Iterable<TaskView> forDate(DateTime date) =>
      where((view) => view.task.plannedDate == dateKey(date));

  Iterable<TaskView> get active => where((view) => !view.task.archived);

  Iterable<TaskView> get open => where((view) => !view.isDone);

  Iterable<TaskView> get done => where((view) => view.isDone);
}
