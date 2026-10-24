import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/ids.dart';
import '../../core/utils/date_keys.dart';
import '../db/app_database.dart';
import '../models/enums.dart';
import '../models/time_entry.dart';
import '../models/timer_session.dart';
import 'activity_repository.dart';

/// Owns live stopwatches and finished time segments.
class TimerRepository {
  TimerRepository(this._appDb);

  final AppDatabase _appDb;

  Database get _db => _appDb.db;

  Future<TimerSession?> liveSession() async {
    final rows = await _db.query('timer_sessions', limit: 1);
    if (rows.isEmpty) return null;
    return TimerSession.fromMap(rows.first);
  }

  /// Starts a session, auto-finishing any previous live one. Callers may warn
  /// the user first; the repository enforces the one-timer invariant.
  Future<TimerSession> start({
    String? taskId,
    required String label,
    required TimerKind kind,
  }) async {
    return _db.transaction((txn) async {
      await _finishLive(txn);
      final now = DateTime.now();
      final session = TimerSession(
        id: newId(),
        taskId: taskId,
        label: label.trim().isEmpty ? 'Focus' : label.trim(),
        kind: kind,
        isRunning: true,
        startedAt: now,
        segmentStartedAt: now,
        accumulatedMs: 0,
        createdAt: now,
      );
      await txn.insert('timer_sessions', session.toMap());
      return session;
    });
  }

  Future<TimerSession> pause(TimerSession session) async {
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'timer_sessions',
        where: 'id = ?',
        whereArgs: [session.id],
      );
      if (rows.isEmpty) return session;
      final current = TimerSession.fromMap(rows.first);
      if (!current.isRunning || current.segmentStartedAt == null) {
        return current;
      }
      final now = DateTime.now();
      final segmentMs = now
          .difference(current.segmentStartedAt!)
          .inMilliseconds;
      if (segmentMs > 0) {
        await _insertSegment(
          txn,
          session: current,
          startedAt: current.segmentStartedAt!,
          endedAt: now,
          durationMs: segmentMs,
          taskId: current.taskId,
          note: '',
        );
      }
      final accumulated =
          current.accumulatedMs + (segmentMs > 0 ? segmentMs : 0);
      await txn.update(
        'timer_sessions',
        {
          'status': 'paused',
          'segment_started_at': null,
          'accumulated_ms': accumulated,
        },
        where: 'id = ?',
        whereArgs: [current.id],
      );
      return TimerSession(
        id: current.id,
        taskId: current.taskId,
        label: current.label,
        kind: current.kind,
        isRunning: false,
        startedAt: current.startedAt,
        segmentStartedAt: null,
        accumulatedMs: accumulated,
        createdAt: current.createdAt,
      );
    });
  }

  Future<TimerSession> resume(TimerSession session) async {
    final now = DateTime.now();
    await _db.update(
      'timer_sessions',
      {
        'status': 'running',
        'segment_started_at': now.toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
    return TimerSession(
      id: session.id,
      taskId: session.taskId,
      label: session.label,
      kind: session.kind,
      isRunning: true,
      startedAt: session.startedAt,
      segmentStartedAt: now,
      accumulatedMs: session.accumulatedMs,
      createdAt: session.createdAt,
    );
  }

  /// Saves the open segment (if any) and removes the live session. Optionally
  /// assigns the whole session to a task and applies a note/label.
  Future<void> stop(
    TimerSession session, {
    String? assignTaskId,
    String? label,
    String? note,
  }) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'timer_sessions',
        where: 'id = ?',
        whereArgs: [session.id],
      );
      if (rows.isEmpty) return;
      final current = TimerSession.fromMap(rows.first);
      final now = DateTime.now();
      final targetTaskId = assignTaskId ?? current.taskId;
      final cleanLabel = (label ?? current.label).trim();
      final cleanNote = note?.trim() ?? '';
      if (current.isRunning && current.segmentStartedAt != null) {
        final segmentMs = now
            .difference(current.segmentStartedAt!)
            .inMilliseconds;
        if (segmentMs > 0) {
          await _insertSegment(
            txn,
            session: current,
            startedAt: current.segmentStartedAt!,
            endedAt: now,
            durationMs: segmentMs,
            taskId: targetTaskId,
            label: cleanLabel,
            note: cleanNote,
          );
        }
      }
      await txn.update(
        'time_entries',
        {'task_id': targetTaskId, 'label': cleanLabel, 'note': cleanNote},
        where: 'session_id = ?',
        whereArgs: [current.id],
      );
      await txn.delete(
        'timer_sessions',
        where: 'id = ?',
        whereArgs: [current.id],
      );

      final totalMs =
          current.accumulatedMs +
          (current.isRunning && current.segmentStartedAt != null
              ? now.difference(current.segmentStartedAt!).inMilliseconds
              : 0);
      if (targetTaskId != null && totalMs > 0) {
        final taskRows = await txn.query(
          'tasks',
          columns: ['title'],
          where: 'id = ?',
          whereArgs: [targetTaskId],
        );
        final title = taskRows.isEmpty
            ? 'a task'
            : taskRows.first['title'] as String? ?? 'a task';
        await writeActivity(
          txn,
          entityType: 'task',
          entityId: targetTaskId,
          action: 'time_logged',
          summary: 'Logged ${_humanMs(totalMs)} on “$title”',
        );
      }
    });
  }

  /// Removes the session and all of its saved segments without logging.
  Future<void> discard(TimerSession session) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'time_entries',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      await txn.delete(
        'timer_sessions',
        where: 'id = ?',
        whereArgs: [session.id],
      );
    });
  }

  Future<void> renameLive(String sessionId, String label) async {
    await _db.update(
      'timer_sessions',
      {'label': label.trim()},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<TimeEntry> addManualEntry({
    String? taskId,
    String label = '',
    String note = '',
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    final duration = endedAt.difference(startedAt).inMilliseconds;
    if (duration <= 0) {
      throw ArgumentError('End time must be after start time');
    }
    final entry = TimeEntry(
      id: newId(),
      sessionId: null,
      taskId: taskId,
      label: label.trim(),
      note: note.trim(),
      source: EntrySource.manual,
      startedAt: startedAt,
      endedAt: endedAt,
      durationMs: duration,
      createdAt: DateTime.now(),
    );
    await _db.transaction((txn) async {
      await txn.insert('time_entries', entry.toMap());
      if (taskId != null) {
        await writeActivity(
          txn,
          entityType: 'task',
          entityId: taskId,
          action: 'time_manual',
          summary: 'Added ${_humanMs(duration)} manually',
        );
      }
    });
    return entry;
  }

  Future<void> updateEntry(
    TimeEntry entry, {
    DateTime? startedAt,
    DateTime? endedAt,
    String? note,
    String? taskId,
    bool clearTask = false,
  }) async {
    final start = startedAt ?? entry.startedAt;
    final end = endedAt ?? entry.endedAt;
    final duration = end.difference(start).inMilliseconds;
    if (duration <= 0) {
      throw ArgumentError('End time must be after start time');
    }
    await _db.update(
      'time_entries',
      {
        'started_at': start.toUtc().millisecondsSinceEpoch,
        'ended_at': end.toUtc().millisecondsSinceEpoch,
        'duration_ms': duration,
        'note': note ?? entry.note,
        'task_id': clearTask ? null : (taskId ?? entry.taskId),
      },
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> deleteEntry(String id) async {
    await _db.delete('time_entries', where: 'id = ?', whereArgs: [id]);
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

  Future<List<TimeEntry>> entriesBetween(DateTime start, DateTime end) async {
    final rows = await _db.query(
      'time_entries',
      where: 'started_at >= ? AND started_at < ?',
      whereArgs: [
        start.toUtc().millisecondsSinceEpoch,
        end.toUtc().millisecondsSinceEpoch,
      ],
      orderBy: 'started_at ASC',
    );
    return rows.map(TimeEntry.fromMap).toList();
  }

  Future<int> totalBetween(DateTime start, DateTime end) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(duration_ms), 0) AS total FROM time_entries '
      'WHERE started_at >= ? AND started_at < ?',
      [
        start.toUtc().millisecondsSinceEpoch,
        end.toUtc().millisecondsSinceEpoch,
      ],
    );
    return (rows.first['total'] as num).toInt();
  }

  Future<Map<String, int>> focusByDay(DateTime start, DateTime end) async {
    final entries = await entriesBetween(start, end);
    final result = <String, int>{};
    for (final entry in entries) {
      final key = dateKey(entry.startedAt);
      result[key] = (result[key] ?? 0) + entry.durationMs;
    }
    return result;
  }

  Future<List<TimeEntry>> generalEntriesBetween(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _db.query(
      'time_entries',
      where: 'task_id IS NULL AND started_at >= ? AND started_at < ?',
      whereArgs: [
        start.toUtc().millisecondsSinceEpoch,
        end.toUtc().millisecondsSinceEpoch,
      ],
      orderBy: 'started_at DESC',
    );
    return rows.map(TimeEntry.fromMap).toList();
  }

  Future<void> _finishLive(DatabaseExecutor txn) async {
    final rows = await txn.query('timer_sessions', limit: 1);
    if (rows.isEmpty) return;
    final current = TimerSession.fromMap(rows.first);
    if (current.isRunning && current.segmentStartedAt != null) {
      final now = DateTime.now();
      final segmentMs = now
          .difference(current.segmentStartedAt!)
          .inMilliseconds;
      if (segmentMs > 0) {
        await _insertSegment(
          txn,
          session: current,
          startedAt: current.segmentStartedAt!,
          endedAt: now,
          durationMs: segmentMs,
          taskId: current.taskId,
        );
      }
    }
    await txn.delete(
      'timer_sessions',
      where: 'id = ?',
      whereArgs: [current.id],
    );
  }

  Future<void> _insertSegment(
    DatabaseExecutor txn, {
    required TimerSession session,
    required DateTime startedAt,
    required DateTime endedAt,
    required int durationMs,
    String? taskId,
    String? label,
    String note = '',
  }) async {
    await txn.insert('time_entries', {
      'id': newId(),
      'session_id': session.id,
      'task_id': taskId,
      'label': label ?? session.label,
      'note': note,
      'source': EntrySource.timer.db,
      'started_at': startedAt.toUtc().millisecondsSinceEpoch,
      'ended_at': endedAt.toUtc().millisecondsSinceEpoch,
      'duration_ms': durationMs,
      'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  String _humanMs(int ms) {
    final minutes = ms ~/ 60000;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  }
}
