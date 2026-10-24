import 'db_values.dart';
import 'enums.dart';

/// A live (running or paused) stopwatch. Only one row can exist at a time
/// (`singleton` has a UNIQUE constraint). Finished segments live in
/// `time_entries`; the session row is deleted on stop.
class TimerSession {
  const TimerSession({
    required this.id,
    required this.taskId,
    required this.label,
    required this.kind,
    required this.isRunning,
    required this.startedAt,
    required this.segmentStartedAt,
    required this.accumulatedMs,
    required this.createdAt,
  });

  final String id;
  final String? taskId;
  final String label;
  final TimerKind kind;
  final bool isRunning;
  final DateTime startedAt;

  /// Non-null while running; the wall-clock start of the open segment.
  final DateTime? segmentStartedAt;
  final int accumulatedMs;
  final DateTime createdAt;

  Duration elapsedAt(DateTime now) {
    var total = accumulatedMs;
    if (isRunning && segmentStartedAt != null) {
      final open = now.difference(segmentStartedAt!).inMilliseconds;
      if (open > 0) total += open;
    }
    return Duration(milliseconds: total < 0 ? 0 : total);
  }

  int get openSegmentMs {
    if (!isRunning || segmentStartedAt == null) return 0;
    final delta = DateTime.now().difference(segmentStartedAt!).inMilliseconds;
    return delta < 0 ? 0 : delta;
  }

  factory TimerSession.fromMap(Map<String, Object?> map) {
    final status = map['status'] as String? ?? 'running';
    return TimerSession(
      id: stringFromDb(map['id']),
      taskId: map['task_id'] as String?,
      label: stringFromDb(map['label']),
      kind: TimerKind.fromDb(map['kind'] as String?),
      isRunning: status == 'running',
      startedAt: dateFromMs(map['started_at']) ?? DateTime.now(),
      segmentStartedAt: dateFromMs(map['segment_started_at']),
      accumulatedMs: intFromDb(map['accumulated_ms']),
      createdAt: dateFromMs(map['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'task_id': taskId,
      'label': label,
      'kind': kind.db,
      'status': isRunning ? 'running' : 'paused',
      'started_at': msFromDate(startedAt),
      'segment_started_at': msFromDate(segmentStartedAt),
      'accumulated_ms': accumulatedMs,
      'singleton': 1,
      'created_at': msFromDate(createdAt),
    };
  }
}
