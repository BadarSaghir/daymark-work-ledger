import 'dart:io';

import 'package:daymark/data/models/enums.dart';
import 'package:daymark/data/models/task.dart';
import 'package:daymark/data/models/task_view.dart';
import 'package:daymark/data/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Task task({
    String id = 'task-1',
    String title = 'Prepare the brief',
    TaskStatus status = TaskStatus.planned,
    DateTime? dueAt,
    DateTime? scheduledStart,
    DateTime? reminderAt,
    String? reminderNote,
    bool reminderDaily = false,
  }) {
    return Task(
      id: id,
      title: title,
      notesMd: '',
      categoryId: null,
      kind: WorkKind.official,
      status: status,
      priority: Priority.normal,
      effort: 2,
      estimateMinutes: 60,
      plannedDate: '2026-10-25',
      scheduledStart: scheduledStart,
      scheduledEnd: null,
      dueAt: dueAt,
      blockedReason: null,
      position: 0,
      completedAt: null,
      archived: false,
      createdAt: DateTime(2026, 10, 20),
      updatedAt: DateTime(2026, 10, 20),
      reminderAt: reminderAt,
      reminderNote: reminderNote,
      reminderDaily: reminderDaily,
    );
  }

  TaskView view(Task task) =>
      TaskView(task: task, category: null, subtasks: const [], trackedMs: 0);

  test('reminder preferences survive a JSON round trip', () {
    const preferences = ReminderPreferences(
      enabled: true,
      taskReminders: false,
      leadMinutes: 35,
      dailyReview: true,
      reviewHour: 21,
      reviewMinute: 5,
    );
    final restored = ReminderPreferences.fromJson(preferences.toJson());
    expect(restored.enabled, isTrue);
    expect(restored.taskReminders, isFalse);
    expect(restored.leadMinutes, 35);
    expect(restored.reviewLabel, '9:05 PM');
  });

  test(
    'custom reminders, deadlines, and the daily review fire once while open',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'daymark_reminders_test',
      );
      addTearDown(() => temp.delete(recursive: true));
      final service = NotificationService(configDirectory: temp);
      const preferences = ReminderPreferences(
        enabled: true,
        taskReminders: true,
        leadMinutes: 0,
        dailyReview: true,
        reviewHour: 18,
        reviewMinute: 30,
      );
      final custom = view(
        task(
          reminderAt: DateTime(2026, 10, 25, 9, 30),
          reminderNote: 'Bring the two charts.',
        ),
      );
      expect(
        await service.checkDueReminders(
          [custom],
          preferences,
          at: DateTime(2026, 10, 25, 9, 32),
        ),
        1,
      );
      expect(
        await service.checkDueReminders(
          [custom],
          preferences,
          at: DateTime(2026, 10, 25, 9, 34),
        ),
        0,
      );

      final deadline = view(task(dueAt: DateTime(2026, 10, 25, 10)));
      expect(
        await service.checkDueReminders(
          [deadline],
          preferences,
          at: DateTime(2026, 10, 25, 10, 2),
        ),
        1,
      );

      expect(
        await service.checkDueReminders(
          const [],
          preferences,
          at: DateTime(2026, 10, 25, 18, 35),
        ),
        1,
      );
      expect(
        await service.checkDueReminders(
          const [],
          preferences,
          at: DateTime(2026, 10, 25, 18, 40),
        ),
        0,
      );
    },
    skip: Platform.isLinux ? false : 'Linux in-app fallback only',
  );

  test('completed and archived tasks do not raise reminders', () async {
    final temp = await Directory.systemTemp.createTemp(
      'daymark_reminders_test',
    );
    addTearDown(() => temp.delete(recursive: true));
    final service = NotificationService(configDirectory: temp);
    const preferences = ReminderPreferences(
      enabled: true,
      taskReminders: true,
      leadMinutes: 0,
      dailyReview: false,
      reviewHour: 18,
      reviewMinute: 30,
    );
    final done = view(
      task(status: TaskStatus.done, reminderAt: DateTime(2026, 10, 25, 9, 30)),
    );
    final archived = view(
      task(
        id: 'task-2',
        reminderAt: DateTime(2026, 10, 25, 9, 30),
      ).copyWith(archived: true),
    );
    expect(
      await service.checkDueReminders(
        [done, archived],
        preferences,
        at: DateTime(2026, 10, 25, 9, 31),
      ),
      0,
    );
  }, skip: Platform.isLinux ? false : 'Linux in-app fallback only');

  group('plan', () {
    const offReview = ReminderPreferences(
      enabled: true,
      taskReminders: true,
      leadMinutes: 10,
      dailyReview: false,
      reviewHour: 18,
      reviewMinute: 30,
    );
    final now = DateTime(2026, 10, 25, 8);

    test('schedules start and deadline reminders with the lead time', () {
      final planned = NotificationService.plan(
        [
          view(
            task(
              scheduledStart: DateTime(2026, 10, 25, 10),
              dueAt: DateTime(2026, 10, 25, 17),
            ),
          ),
        ],
        offReview,
        at: now,
      );
      final start = planned.singleWhere(
        (item) => item.kind == NotificationKind.taskStart,
      );
      final deadline = planned.singleWhere(
        (item) => item.kind == NotificationKind.taskDeadline,
      );
      expect(start.when, DateTime(2026, 10, 25, 9, 50));
      expect(start.repeatDaily, isFalse);
      expect(deadline.when, DateTime(2026, 10, 25, 17));
    });

    test('projects a daily task reminder to its next occurrence', () {
      final planned = NotificationService.plan(
        [
          view(
            task(
              reminderAt: DateTime(2026, 10, 25, 9, 30),
              reminderDaily: true,
              reminderNote: 'Water the plants',
            ),
          ),
        ],
        offReview,
        at: now,
      );
      final daily = planned.singleWhere(
        (item) => item.kind == NotificationKind.taskDaily,
      );
      expect(daily.when, DateTime(2026, 10, 25, 9, 30));
      expect(daily.repeatDaily, isTrue);
      expect(daily.body, 'Water the plants');
    });

    test('rolls a daily reminder to tomorrow once its time has passed', () {
      final planned = NotificationService.plan(
        [
          view(
            task(
              reminderAt: DateTime(2026, 10, 24, 7, 15),
              reminderDaily: true,
            ),
          ),
        ],
        offReview,
        at: now,
      );
      final daily = planned.singleWhere(
        (item) => item.kind == NotificationKind.taskDaily,
      );
      expect(daily.when, DateTime(2026, 10, 26, 7, 15));
      expect(daily.title, contains('Daily reminder'));
    });

    test('honours the granular toggles and the master switch', () {
      final views = [
        view(
          task(
            scheduledStart: DateTime(2026, 10, 25, 10),
            dueAt: DateTime(2026, 10, 25, 17),
            reminderAt: DateTime(2026, 10, 25, 9, 30),
          ),
        ),
        view(
          task(
            id: 'task-daily',
            reminderAt: DateTime(2026, 10, 25, 7, 0),
            reminderDaily: true,
          ),
        ),
      ];

      expect(
        NotificationService.plan(
          views,
          offReview.copyWith(
            startReminders: false,
            deadlineReminders: false,
            customReminders: false,
            dailyTaskReminders: false,
          ),
          at: now,
        ),
        isEmpty,
      );

      final onlyDaily = NotificationService.plan(
        views,
        offReview.copyWith(dailyTaskReminders: true),
        at: now,
      );
      expect(
        onlyDaily.where((item) => item.kind == NotificationKind.taskDaily),
        hasLength(1),
      );
      expect(
        NotificationService.plan(views, offReview.copyWith(enabled: false)),
        isEmpty,
      );
    });

    test('keeps one-off reminders inside the supplied limit', () {
      final views = [
        for (var i = 0; i < 12; i++)
          view(
            task(
              id: 'task-$i',
              dueAt: DateTime(2026, 10, 25, 9).add(Duration(minutes: i)),
            ),
          ),
      ];
      final planned = NotificationService.plan(views, offReview, at: now, limit: 5);
      expect(planned, hasLength(5));
      expect(
        planned.map((item) => item.when).toList(),
        orderedEquals(
          [
            for (var i = 0; i < 5; i++) DateTime(2026, 10, 25, 9, i),
          ],
        ),
      );
    });
  });
}
