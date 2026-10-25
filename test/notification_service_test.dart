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
    DateTime? reminderAt,
    String? reminderNote,
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
      scheduledStart: null,
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
}
