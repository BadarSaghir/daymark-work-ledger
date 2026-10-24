import 'db_values.dart';
import 'enums.dart';

/// A unit of work. Large tasks can be broken into [Subtask]s.
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.notesMd,
    required this.categoryId,
    required this.kind,
    required this.status,
    required this.priority,
    required this.effort,
    required this.estimateMinutes,
    required this.plannedDate,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.dueAt,
    required this.blockedReason,
    required this.position,
    required this.completedAt,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  static const Object _unset = Object();

  final String id;
  final String title;
  final String notesMd;
  final String? categoryId;
  final WorkKind kind;
  final TaskStatus status;
  final Priority priority;

  /// Effort size 1–5.
  final int effort;
  final int? estimateMinutes;

  /// Local `YYYY-MM-DD` key, or null for the inbox.
  final String? plannedDate;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? dueAt;
  final String? blockedReason;
  final int position;
  final DateTime? completedAt;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDone => status == TaskStatus.done;
  bool get isScheduled => plannedDate != null;

  bool get isOverdue =>
      !isDone && dueAt != null && dueAt!.isBefore(DateTime.now());

  Task copyWith({
    String? title,
    String? notesMd,
    Object? categoryId = _unset,
    WorkKind? kind,
    TaskStatus? status,
    Priority? priority,
    int? effort,
    Object? estimateMinutes = _unset,
    Object? plannedDate = _unset,
    Object? scheduledStart = _unset,
    Object? scheduledEnd = _unset,
    Object? dueAt = _unset,
    Object? blockedReason = _unset,
    int? position,
    Object? completedAt = _unset,
    bool? archived,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      notesMd: notesMd ?? this.notesMd,
      categoryId: identical(categoryId, _unset)
          ? this.categoryId
          : categoryId as String?,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      effort: effort ?? this.effort,
      estimateMinutes: identical(estimateMinutes, _unset)
          ? this.estimateMinutes
          : estimateMinutes as int?,
      plannedDate: identical(plannedDate, _unset)
          ? this.plannedDate
          : plannedDate as String?,
      scheduledStart: identical(scheduledStart, _unset)
          ? this.scheduledStart
          : scheduledStart as DateTime?,
      scheduledEnd: identical(scheduledEnd, _unset)
          ? this.scheduledEnd
          : scheduledEnd as DateTime?,
      dueAt: identical(dueAt, _unset) ? this.dueAt : dueAt as DateTime?,
      blockedReason: identical(blockedReason, _unset)
          ? this.blockedReason
          : blockedReason as String?,
      position: position ?? this.position,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Task.fromMap(Map<String, Object?> map) {
    return Task(
      id: stringFromDb(map['id']),
      title: stringFromDb(map['title'], 'Untitled task'),
      notesMd: stringFromDb(map['notes_md']),
      categoryId: map['category_id'] as String?,
      kind: WorkKind.fromDb(map['kind'] as String?),
      status: TaskStatus.fromDb(map['status'] as String?),
      priority: Priority.fromDb(map['priority'] as String?),
      effort: intFromDb(map['effort'], 2),
      estimateMinutes: (map['estimate_minutes'] as num?)?.toInt(),
      plannedDate: map['planned_date'] as String?,
      scheduledStart: dateFromMs(map['scheduled_start']),
      scheduledEnd: dateFromMs(map['scheduled_end']),
      dueAt: dateFromMs(map['due_at']),
      blockedReason: map['blocked_reason'] as String?,
      position: intFromDb(map['position']),
      completedAt: dateFromMs(map['completed_at']),
      archived: boolFromDb(map['archived']),
      createdAt: dateFromMs(map['created_at']) ?? DateTime.now(),
      updatedAt: dateFromMs(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'notes_md': notesMd,
      'category_id': categoryId,
      'kind': kind.db,
      'status': status.db,
      'priority': priority.db,
      'effort': effort,
      'estimate_minutes': estimateMinutes,
      'planned_date': plannedDate,
      'scheduled_start': msFromDate(scheduledStart),
      'scheduled_end': msFromDate(scheduledEnd),
      'due_at': msFromDate(dueAt),
      'blocked_reason': blockedReason,
      'position': position,
      'completed_at': msFromDate(completedAt),
      'archived': archived ? 1 : 0,
      'created_at': msFromDate(createdAt),
      'updated_at': msFromDate(updatedAt),
    };
  }
}
