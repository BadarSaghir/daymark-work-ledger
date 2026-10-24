import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../data/models/subtask.dart';
import '../../data/models/task.dart';

/// Effort × priority × kind × category weight.
///
/// The formula is deliberately visible in the UI. Changing multipliers is a
/// product decision, not a theme tweak.
double taskPoints({required Task task, Category? category}) {
  final effort = task.effort.clamp(1, 5);
  final categoryWeight = (category?.weight ?? 1.0).clamp(0.5, 2.0);
  return effort *
      task.priority.multiplier *
      workKindMultiplier(task.kind) *
      categoryWeight;
}

double workKindMultiplier(WorkKind kind) {
  return switch (kind) {
    WorkKind.official => 1.0,
    WorkKind.adhoc => 0.75,
    WorkKind.personal => 0.5,
  };
}

/// A task is 100% when done. With steps, progress is the step ratio; without
/// steps, an open task is 0% (effort starts counting when it is completed).
double taskProgress(Task task, List<Subtask> subtasks) {
  if (task.isDone) return 1;
  if (subtasks.isEmpty) return 0;
  final done = subtasks.where((step) => step.isDone).length;
  return (done / subtasks.length).clamp(0.0, 1.0);
}

double earnedPoints({
  required Task task,
  Category? category,
  required List<Subtask> subtasks,
}) => taskPoints(task: task, category: category) * taskProgress(task, subtasks);

/// Estimate accuracy: actual / estimate. 1.0 is perfect; >1 means overran.
double estimateRatio({
  required int estimatedMinutes,
  required int actualMinutes,
}) {
  if (estimatedMinutes <= 0) return 0;
  return actualMinutes / estimatedMinutes;
}
