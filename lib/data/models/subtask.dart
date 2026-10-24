import 'db_values.dart';

/// A constituent step of a task. Progress rolls up into the parent.
class Subtask {
  const Subtask({
    required this.id,
    required this.taskId,
    required this.title,
    required this.position,
    required this.isDone,
    required this.completedAt,
    required this.createdAt,
  });

  final String id;
  final String taskId;
  final String title;
  final int position;
  final bool isDone;
  final DateTime? completedAt;
  final DateTime createdAt;

  Subtask copyWith({
    String? title,
    int? position,
    bool? isDone,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return Subtask(
      id: id,
      taskId: taskId,
      title: title ?? this.title,
      position: position ?? this.position,
      isDone: isDone ?? this.isDone,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      createdAt: createdAt,
    );
  }

  factory Subtask.fromMap(Map<String, Object?> map) {
    return Subtask(
      id: stringFromDb(map['id']),
      taskId: stringFromDb(map['task_id']),
      title: stringFromDb(map['title']),
      position: intFromDb(map['position']),
      isDone: boolFromDb(map['is_done']),
      completedAt: dateFromMs(map['completed_at']),
      createdAt: dateFromMs(map['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'task_id': taskId,
      'title': title,
      'position': position,
      'is_done': isDone ? 1 : 0,
      'completed_at': msFromDate(completedAt),
      'created_at': msFromDate(createdAt),
    };
  }
}
