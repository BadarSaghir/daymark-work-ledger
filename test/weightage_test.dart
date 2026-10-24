import 'package:daymark/core/utils/date_keys.dart';
import 'package:daymark/core/utils/durations.dart';
import 'package:daymark/core/utils/weightage.dart';
import 'package:daymark/data/models/category.dart';
import 'package:daymark/data/models/enums.dart';
import 'package:daymark/data/models/subtask.dart';
import 'package:daymark/data/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

Task _task({
  String id = 'task-1',
  int effort = 3,
  Priority priority = Priority.normal,
  WorkKind kind = WorkKind.official,
  TaskStatus status = TaskStatus.planned,
  DateTime? completedAt,
}) {
  final now = DateTime(2026, 10, 24, 9);
  return Task(
    id: id,
    title: 'Draft the brief',
    notesMd: '',
    categoryId: 'cat-1',
    kind: kind,
    status: status,
    priority: priority,
    effort: effort,
    estimateMinutes: 90,
    plannedDate: '2026-10-24',
    scheduledStart: null,
    scheduledEnd: null,
    dueAt: null,
    blockedReason: null,
    position: 0,
    completedAt: completedAt,
    archived: false,
    createdAt: now,
    updatedAt: now,
  );
}

Subtask _step({required bool done}) {
  final now = DateTime(2026, 10, 24, 9);
  return Subtask(
    id: 'step-${done ? 'done' : 'open'}',
    taskId: 'task-1',
    title: 'Step',
    isDone: done,
    completedAt: done ? now : null,
    position: 0,
    createdAt: now,
  );
}

void main() {
  group('weightage', () {
    test('multiplies effort by priority, kind, and category weight', () {
      final category = Category(
        id: 'cat-1',
        name: 'Client work',
        color: 0xFF335C4A,
        icon: 'briefcase',
        weight: 1.5,
        position: 0,
        archived: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final points = taskPoints(
        task: _task(effort: 4, priority: Priority.high),
        category: category,
      );
      expect(points, closeTo(4 * Priority.high.multiplier * 1.5, 0.0001));
    });

    test('clamps effort and category weight to the documented range', () {
      final category = Category(
        id: 'cat-1',
        name: 'Heavy',
        color: 0,
        icon: 'work',
        weight: 3.5,
        position: 0,
        archived: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final points = taskPoints(task: _task(effort: 99), category: category);
      expect(points, closeTo(5 * Priority.normal.multiplier * 2, 0.0001));
    });

    test('progress is step ratio until the task is done', () {
      expect(
        taskProgress(_task(), [_step(done: true), _step(done: false)]),
        0.5,
      );
      expect(
        taskProgress(
          _task(status: TaskStatus.done, completedAt: DateTime(2026, 10, 24)),
          [_step(done: false)],
        ),
        1,
      );
    });
  });

  group('date and duration helpers', () {
    test('date keys stay on the local calendar day', () {
      expect(dateKey(DateTime(2026, 1, 2, 23, 59)), '2026-01-02');
      expect(parseDateKey('2026-01-02'), DateTime(2026, 1, 2));
    });

    test('clock formatting grows past an hour without breaking', () {
      expect(formatClock(const Duration(seconds: 65)), '01:05');
      expect(
        formatClock(const Duration(hours: 12, minutes: 3, seconds: 2)),
        '12:03:02',
      );
      expect(
        formatStopwatch(const Duration(minutes: 61, seconds: 4)),
        '01:01:04',
      );
    });
  });
}
