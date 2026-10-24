import 'db_values.dart';
import 'enums.dart';

/// A finished contiguous work segment. Pauses split a stopwatch session into
/// multiple entries so the timeline stays honest.
class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.sessionId,
    required this.taskId,
    required this.label,
    required this.note,
    required this.source,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
    required this.createdAt,
  });

  final String id;
  final String? sessionId;
  final String? taskId;
  final String label;
  final String note;
  final EntrySource source;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationMs;
  final DateTime createdAt;

  Duration get duration => Duration(milliseconds: durationMs);

  factory TimeEntry.fromMap(Map<String, Object?> map) {
    return TimeEntry(
      id: stringFromDb(map['id']),
      sessionId: map['session_id'] as String?,
      taskId: map['task_id'] as String?,
      label: stringFromDb(map['label']),
      note: stringFromDb(map['note']),
      source: EntrySource.fromDb(map['source'] as String?),
      startedAt: dateFromMs(map['started_at']) ?? DateTime.now(),
      endedAt: dateFromMs(map['ended_at']) ?? DateTime.now(),
      durationMs: intFromDb(map['duration_ms']),
      createdAt: dateFromMs(map['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'task_id': taskId,
      'label': label,
      'note': note,
      'source': source.db,
      'started_at': msFromDate(startedAt),
      'ended_at': msFromDate(endedAt),
      'duration_ms': durationMs,
      'created_at': msFromDate(createdAt),
    };
  }
}
