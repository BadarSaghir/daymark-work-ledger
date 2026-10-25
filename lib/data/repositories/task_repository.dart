import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/ids.dart';
import '../db/app_database.dart';
import '../models/activity_event.dart';
import '../models/enums.dart';
import '../models/subtask.dart';
import '../models/task.dart';
import '../models/time_entry.dart';
import 'activity_repository.dart';

class TaskRepository {
  TaskRepository(this._appDb);

  final AppDatabase _appDb;

  Database get _db => _appDb.db;

  Future<List<Task>> list({bool includeArchived = false}) async {
    final rows = await _db.query(
      'tasks',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'position ASC, created_at DESC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<Task?> byId(String id) async {
    final rows = await _db.query('tasks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Task.fromMap(rows.first);
  }

  Future<List<Subtask>> allSubtasks() async {
    final rows = await _db.query(
      'subtasks',
      orderBy: 'position ASC, created_at ASC',
    );
    return rows.map(Subtask.fromMap).toList();
  }

  Future<List<Subtask>> subtasksFor(String taskId) async {
    final rows = await _db.query(
      'subtasks',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'position ASC, created_at ASC',
    );
    return rows.map(Subtask.fromMap).toList();
  }

  Future<Map<String, int>> trackedTotals() async {
    final rows = await _db.rawQuery(
      'SELECT task_id, SUM(duration_ms) AS total_ms FROM time_entries '
      'WHERE task_id IS NOT NULL GROUP BY task_id',
    );
    return {
      for (final row in rows)
        if (row['task_id'] != null)
          row['task_id'] as String: (row['total_ms'] as num).toInt(),
    };
  }

  Future<int> trackedForTask(String taskId) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(duration_ms), 0) AS total FROM time_entries '
      'WHERE task_id = ?',
      [taskId],
    );
    return (rows.first['total'] as num).toInt();
  }

  Future<List<TimeEntry>> entriesForTask(String taskId) async {
    final rows = await _db.query(
      'time_entries',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'started_at DESC',
    );
    return rows.map(TimeEntry.fromMap).toList();
  }

  Future<List<ActivityEvent>> activityFor(
    String taskId, {
    int limit = 40,
  }) async {
    final rows = await _db.query(
      'activity_events',
      where: 'entity_id = ?',
      whereArgs: [taskId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ActivityEvent.fromMap).toList();
  }

  Future<int> _nextPosition() async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next FROM tasks',
    );
    return (rows.first['next'] as num).toInt();
  }

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
    DateTime? reminderAt,
    String? reminderNote,
    String notesMd = '',
    List<String> stepTitles = const [],
  }) async {
    final now = DateTime.now();
    final task = Task(
      id: newId(),
      title: title.trim(),
      notesMd: notesMd,
      categoryId: categoryId,
      kind: kind,
      status: status,
      priority: priority,
      effort: effort.clamp(1, 5),
      estimateMinutes: estimateMinutes,
      plannedDate: plannedDate,
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledEnd,
      dueAt: dueAt,
      blockedReason: null,
      position: await _nextPosition(),
      completedAt: status == TaskStatus.done ? now : null,
      archived: false,
      createdAt: now,
      updatedAt: now,
      reminderAt: reminderAt,
      reminderNote: reminderNote,
    );
    await _db.transaction((txn) async {
      await txn.insert('tasks', task.toMap());
      for (var i = 0; i < stepTitles.length; i++) {
        final title = stepTitles[i].trim();
        if (title.isEmpty) continue;
        await txn.insert('subtasks', {
          'id': newId(),
          'task_id': task.id,
          'title': title,
          'position': i,
          'is_done': 0,
          'completed_at': null,
          'created_at': now.toUtc().millisecondsSinceEpoch,
        });
      }
      await writeActivity(
        txn,
        entityType: 'task',
        entityId: task.id,
        action: 'created',
        summary:
            'Created “${task.title}”'
            '${status == TaskStatus.inbox ? ' in the inbox' : ''}',
      );
    });
    return task;
  }

  Future<void> update(Task task, {String? summary}) async {
    final updated = task.copyWith(updatedAt: DateTime.now());
    await _db.transaction((txn) async {
      await txn.update(
        'tasks',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      if (summary != null && summary.isNotEmpty) {
        await writeActivity(
          txn,
          entityType: 'task',
          entityId: updated.id,
          action: 'updated',
          summary: summary,
        );
      }
    });
  }

  Future<void> setStatus(
    String taskId,
    TaskStatus status, {
    bool completeSteps = false,
    String? blockedReason,
  }) async {
    final task = await byId(taskId);
    if (task == null) return;
    final now = DateTime.now();
    final statusChanged = task.status != status;
    await _db.transaction((txn) async {
      await txn.update(
        'tasks',
        {
          'status': status.db,
          'completed_at': status == TaskStatus.done
              ? (task.completedAt ?? now).toUtc().millisecondsSinceEpoch
              : null,
          'blocked_reason': status == TaskStatus.blocked
              ? blockedReason?.trim()
              : null,
          'updated_at': now.toUtc().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );
      if (status == TaskStatus.done && completeSteps) {
        await txn.update(
          'subtasks',
          {'is_done': 1, 'completed_at': now.toUtc().millisecondsSinceEpoch},
          where: 'task_id = ? AND is_done = 0',
          whereArgs: [taskId],
        );
      }
      if (statusChanged) {
        final detail =
            status == TaskStatus.blocked &&
                blockedReason != null &&
                blockedReason.trim().isNotEmpty
            ? ' — ${blockedReason.trim()}'
            : '';
        await writeActivity(
          txn,
          entityType: 'task',
          entityId: taskId,
          action: status == TaskStatus.done ? 'completed' : 'status',
          summary: 'Moved to ${status.label}$detail',
        );
      }
    });
  }

  Future<Subtask> addSubtask(String taskId, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) throw ArgumentError('Step title cannot be empty');
    final rows = await _db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next FROM subtasks '
      'WHERE task_id = ?',
      [taskId],
    );
    final now = DateTime.now();
    final subtask = Subtask(
      id: newId(),
      taskId: taskId,
      title: clean,
      position: (rows.first['next'] as num).toInt(),
      isDone: false,
      completedAt: null,
      createdAt: now,
    );
    await _db.transaction((txn) async {
      await txn.insert('subtasks', subtask.toMap());
      await txn.update(
        'tasks',
        {'updated_at': now.toUtc().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [taskId],
      );
      await writeActivity(
        txn,
        entityType: 'task',
        entityId: taskId,
        action: 'step_added',
        summary: 'Added step “$clean”',
      );
    });
    return subtask;
  }

  Future<void> toggleSubtask(Subtask subtask) async {
    final now = DateTime.now();
    final nextDone = !subtask.isDone;
    await _db.transaction((txn) async {
      await txn.update(
        'subtasks',
        {
          'is_done': nextDone ? 1 : 0,
          'completed_at': nextDone ? now.toUtc().millisecondsSinceEpoch : null,
        },
        where: 'id = ?',
        whereArgs: [subtask.id],
      );
      await txn.update(
        'tasks',
        {'updated_at': now.toUtc().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [subtask.taskId],
      );
      await writeActivity(
        txn,
        entityType: 'task',
        entityId: subtask.taskId,
        action: nextDone ? 'step_done' : 'step_reopened',
        summary:
            '${nextDone ? 'Completed' : 'Reopened'} step “${subtask.title}”',
      );
    });
  }

  Future<void> deleteSubtask(Subtask subtask) async {
    await _db.transaction((txn) async {
      await txn.delete('subtasks', where: 'id = ?', whereArgs: [subtask.id]);
      await txn.update(
        'tasks',
        {'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [subtask.taskId],
      );
      await writeActivity(
        txn,
        entityType: 'task',
        entityId: subtask.taskId,
        action: 'step_deleted',
        summary: 'Removed step “${subtask.title}”',
      );
    });
  }

  Future<void> setArchived(String taskId, bool archived) async {
    final task = await byId(taskId);
    if (task == null) return;
    await _db.transaction((txn) async {
      await txn.update(
        'tasks',
        {
          'archived': archived ? 1 : 0,
          'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );
      await writeActivity(
        txn,
        entityType: 'task',
        entityId: taskId,
        action: archived ? 'archived' : 'restored',
        summary: '${archived ? 'Archived' : 'Restored'} “${task.title}”',
      );
    });
  }

  Future<void> deleteTask(String taskId) async {
    final task = await byId(taskId);
    if (task == null) return;
    await _db.transaction((txn) async {
      await writeActivity(
        txn,
        entityType: 'task',
        entityId: taskId,
        action: 'deleted',
        summary: 'Deleted “${task.title}”',
      );
      await txn.delete('tasks', where: 'id = ?', whereArgs: [taskId]);
    });
  }

  /// Moves open steps above/below a sibling. Used by the checklist's reorder
  /// controls (drag handles are a roadmap item).
  Future<void> moveSubtask(Subtask subtask, int delta) async {
    final siblings = await subtasksFor(subtask.taskId);
    final index = siblings.indexWhere((step) => step.id == subtask.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= siblings.length) return;
    final reordered = [...siblings];
    final item = reordered.removeAt(index);
    reordered.insert(target, item);
    await _db.transaction((txn) async {
      for (var i = 0; i < reordered.length; i++) {
        await txn.update(
          'subtasks',
          {'position': i},
          where: 'id = ?',
          whereArgs: [reordered[i].id],
        );
      }
    });
  }
}
