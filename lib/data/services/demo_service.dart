import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/date_keys.dart';
import '../db/app_database.dart';
import '../models/enums.dart';
import '../models/journal_entry.dart';
import '../repositories/activity_repository.dart';

/// Loads a realistic, fully-connected workspace so a new user can feel the
/// product before entering their own data. Safe to call only after clearing.
class DemoService {
  DemoService(this._appDb);

  final AppDatabase _appDb;

  Database get _db => _appDb.db;

  static const _categories = <(String, String, int, String, double)>[
    ('cat-deep-work', 'Deep Work', 0xFF1D5B4F, 'target', 1.3),
    ('cat-meetings', 'Meetings', 0xFF3C6E91, 'users', 0.9),
    ('cat-admin', 'Admin', 0xFF8A7A2E, 'inbox', 0.7),
    ('cat-learning', 'Learning', 0xFF7A5CA8, 'book', 1.1),
    ('cat-personal', 'Personal', 0xFFC26A32, 'sun', 0.8),
  ];

  Future<void> load({bool replace = true}) async {
    final now = DateTime.now();
    final today = startOfDay(now);
    final tomorrow = addDays(today, 1);
    final yesterday = addDays(today, -1);
    final random = Random(41);

    final categories = [
      for (var i = 0; i < _categories.length; i++)
        {
          'id': _categories[i].$1,
          'name': _categories[i].$2,
          'color': _categories[i].$3,
          'icon': _categories[i].$4,
          'weight': _categories[i].$5,
          'position': i,
          'archived': 0,
          'created_at': now
              .subtract(const Duration(days: 60))
              .toUtc()
              .millisecondsSinceEpoch,
          'updated_at': now.toUtc().millisecondsSinceEpoch,
        },
    ];

    final tasks = <Map<String, Object?>>[];
    final subtasks = <Map<String, Object?>>[];
    final entries = <Map<String, Object?>>[];
    final journals = <Map<String, Object?>>[];
    final activity = <Map<String, Object?>>[];

    void addTask({
      required String id,
      required String title,
      required String category,
      required WorkKind kind,
      required TaskStatus status,
      required Priority priority,
      required int effort,
      int? estimate,
      DateTime? day,
      int? startHour,
      int? startMinute,
      int durationMinutes = 60,
      DateTime? due,
      String notes = '',
      String? blockedReason,
      DateTime? completedAt,
      List<(String, bool)> steps = const [],
    }) {
      final scheduledStart = day != null && startHour != null
          ? DateTime(day.year, day.month, day.day, startHour, startMinute ?? 0)
          : null;
      final scheduledEnd = scheduledStart?.add(
        Duration(minutes: durationMinutes),
      );
      tasks.add({
        'id': id,
        'title': title,
        'notes_md': notes,
        'category_id': category,
        'kind': kind.db,
        'status': status.db,
        'priority': priority.db,
        'effort': effort,
        'estimate_minutes': estimate,
        'planned_date': day == null ? null : dateKey(day),
        'scheduled_start': scheduledStart?.toUtc().millisecondsSinceEpoch,
        'scheduled_end': scheduledEnd?.toUtc().millisecondsSinceEpoch,
        'due_at': due?.toUtc().millisecondsSinceEpoch,
        'blocked_reason': blockedReason,
        'position': tasks.length,
        'completed_at': completedAt?.toUtc().millisecondsSinceEpoch,
        'archived': 0,
        'created_at': now
            .subtract(Duration(days: 2 + tasks.length % 4))
            .toUtc()
            .millisecondsSinceEpoch,
        'updated_at': now.toUtc().millisecondsSinceEpoch,
      });
      for (var i = 0; i < steps.length; i++) {
        final (title, done) = steps[i];
        subtasks.add({
          'id': 'demo-step-$id-$i',
          'task_id': id,
          'title': title,
          'position': i,
          'is_done': done ? 1 : 0,
          'completed_at': done
              ? now
                    .subtract(Duration(hours: 2 + i))
                    .toUtc()
                    .millisecondsSinceEpoch
              : null,
          'created_at': now
              .subtract(Duration(days: 3))
              .toUtc()
              .millisecondsSinceEpoch,
        });
      }
      activity.add({
        'id': 'demo-activity-task-$id',
        'entity_type': 'task',
        'entity_id': id,
        'action': 'created',
        'summary': 'Created “$title”',
        'metadata': null,
        'created_at': now
            .subtract(Duration(days: 2 + tasks.length % 4))
            .toUtc()
            .millisecondsSinceEpoch,
      });
      if (status == TaskStatus.done && completedAt != null) {
        activity.add({
          'id': 'demo-activity-done-$id',
          'entity_type': 'task',
          'entity_id': id,
          'action': 'completed',
          'summary': 'Moved to Done',
          'metadata': null,
          'created_at': completedAt.toUtc().millisecondsSinceEpoch,
        });
      }
    }

    addTask(
      id: 'demo-onboarding',
      title: 'Ship the onboarding refresh',
      category: 'cat-deep-work',
      kind: WorkKind.official,
      status: TaskStatus.inProgress,
      priority: Priority.high,
      effort: 4,
      estimate: 240,
      day: today,
      startHour: 9,
      durationMinutes: 150,
      notes: '''
## The goal

Make the first five minutes feel like the product already understands your work.

- [x] Audit the current welcome flow
- [x] Write the empty states
- [x] Decide on a single-screen setup
- [ ] Build the responsive layout
- [ ] QA at 390 px and 1440 px

> Keep the tone quiet. One promise, one action, no tour.

**Copy direction:** “Two lines are enough.”
''',
      steps: const [
        ('Audit the current welcome flow', true),
        ('Write the empty states', true),
        ('Decide on a single-screen setup', true),
        ('Build the responsive layout', false),
        ('QA at 390 px and 1440 px', false),
      ],
    );
    addTask(
      id: 'demo-auth',
      title: 'Refactor the auth middleware',
      category: 'cat-deep-work',
      kind: WorkKind.official,
      status: TaskStatus.inProgress,
      priority: Priority.high,
      effort: 3,
      estimate: 180,
      day: today,
      startHour: 13,
      durationMinutes: 120,
      notes: '''
The current middleware reads the session twice and hides the failure mode.

1. Extract token verification
2. Return a typed failure
3. Add regression tests for expired sessions
''',
      steps: const [
        ('Extract token verification', true),
        ('Return a typed failure', false),
        ('Add regression tests', false),
      ],
    );
    addTask(
      id: 'demo-design-review',
      title: 'Design review: dashboard density',
      category: 'cat-meetings',
      kind: WorkKind.official,
      status: TaskStatus.planned,
      priority: Priority.normal,
      effort: 2,
      estimate: 45,
      day: today,
      startHour: 15,
      startMinute: 30,
      durationMinutes: 45,
      notes: 'Bring two versions: comfortable and compact. Decide with real data, not a mood board.',
    );
    addTask(
      id: 'demo-vendor',
      title: 'Reply to the vendor security questionnaire',
      category: 'cat-admin',
      kind: WorkKind.adhoc,
      status: TaskStatus.planned,
      priority: Priority.normal,
      effort: 2,
      estimate: 40,
      day: today,
      notes: 'Arrived this morning. Twenty-two questions; most answers are in the trust page.',
    );
    addTask(
      id: 'demo-deploy',
      title: 'Fix the staging deploy script',
      category: 'cat-deep-work',
      kind: WorkKind.adhoc,
      status: TaskStatus.done,
      priority: Priority.high,
      effort: 2,
      estimate: 45,
      day: today,
      startHour: 11,
      startMinute: 20,
      durationMinutes: 55,
      completedAt: now.subtract(const Duration(hours: 3)),
      notes: 'The build cache path was wrong after the runner upgrade. Patched and added a smoke check.',
    );
    addTask(
      id: 'demo-priya',
      title: '1:1 with Priya',
      category: 'cat-meetings',
      kind: WorkKind.official,
      status: TaskStatus.done,
      priority: Priority.normal,
      effort: 1,
      estimate: 30,
      day: yesterday,
      startHour: 11,
      durationMinutes: 30,
      completedAt: addDays(
        today,
        -1,
      ).add(const Duration(hours: 11, minutes: 40)),
      notes: 'Talked through the Q4 scope. She wants the capacity model before the next planning round.',
    );
    addTask(
      id: 'demo-read',
      title: 'Read Shape Up — chapter 4',
      category: 'cat-learning',
      kind: WorkKind.personal,
      status: TaskStatus.done,
      priority: Priority.low,
      effort: 2,
      estimate: 40,
      day: yesterday,
      completedAt: addDays(today, -1).add(const Duration(hours: 20)),
      notes: 'Appetite is a constraint, not an estimate. Useful framing for the weekly planning flow.',
    );
    addTask(
      id: 'demo-report',
      title: 'Send the Q3 usage report',
      category: 'cat-admin',
      kind: WorkKind.official,
      status: TaskStatus.planned,
      priority: Priority.urgent,
      effort: 3,
      estimate: 60,
      day: yesterday,
      due: addDays(today, -1).add(const Duration(hours: 17)),
      notes: 'Waiting on the final retention numbers from the warehouse.',
    );
    addTask(
      id: 'demo-weekly',
      title: 'Write the weekly update',
      category: 'cat-admin',
      kind: WorkKind.official,
      status: TaskStatus.planned,
      priority: Priority.normal,
      effort: 2,
      estimate: 35,
      day: tomorrow,
      startHour: 9,
      startMinute: 30,
      durationMinutes: 35,
      notes: '''
## Structure

- What moved
- What changed shape
- What I need

Keep it under 300 words. Link the evidence, not the activity.
''',
    );
    addTask(
      id: 'demo-capture',
      title: 'Explore keyboard-first capture',
      category: 'cat-deep-work',
      kind: WorkKind.official,
      status: TaskStatus.inbox,
      priority: Priority.normal,
      effort: 3,
      notes: 'Could a single chord capture a thought without leaving the current task? Prototype with a command palette overlay.',
    );
    addTask(
      id: 'demo-dentist',
      title: 'Book the dentist',
      category: 'cat-personal',
      kind: WorkKind.personal,
      status: TaskStatus.inbox,
      priority: Priority.low,
      effort: 1,
      estimate: 10,
      notes: 'Before the end of the month.',
    );
    addTask(
      id: 'demo-runbook',
      title: 'Update the incident runbook',
      category: 'cat-deep-work',
      kind: WorkKind.official,
      status: TaskStatus.blocked,
      priority: Priority.normal,
      effort: 2,
      estimate: 50,
      blockedReason: 'Waiting on access to the new dashboard',
      notes: 'Merge the two escalation paths. Remove the old pager rotation.',
    );

    // ---- Time entries -------------------------------------------------------
    final taskIds = [
      'demo-onboarding',
      'demo-auth',
      'demo-design-review',
      'demo-vendor',
      'demo-deploy',
      'demo-priya',
      'demo-read',
      'demo-report',
      'demo-runbook',
    ];
    const taskLabels = {
      'demo-onboarding': 'Ship the onboarding refresh',
      'demo-auth': 'Refactor the auth middleware',
      'demo-design-review': 'Design review: dashboard density',
      'demo-vendor': 'Reply to the vendor security questionnaire',
      'demo-deploy': 'Fix the staging deploy script',
      'demo-priya': '1:1 with Priya',
      'demo-read': 'Read Shape Up — chapter 4',
      'demo-report': 'Send the Q3 usage report',
      'demo-runbook': 'Update the incident runbook',
    };
    var entryIndex = 0;
    for (var daysAgo = 13; daysAgo >= 0; daysAgo--) {
      final day = addDays(today, -daysAgo);
      if (day.weekday == DateTime.sunday) continue;
      final count = 2 + random.nextInt(3);
      var cursor = DateTime(day.year, day.month, day.day, 9, 10);
      for (var i = 0; i < count; i++) {
        final minutes = const [25, 35, 45, 55, 70, 90][random.nextInt(6)];
        final taskId = taskIds[random.nextInt(taskIds.length)];
        final start = cursor.add(Duration(minutes: random.nextInt(40)));
        final end = start.add(Duration(minutes: minutes));
        final general = daysAgo == 4 && i == 0;
        entries.add({
          'id': 'demo-entry-${entryIndex++}',
          'session_id': null,
          'task_id': general ? null : taskId,
          'label': general ? 'Admin sweep' : taskLabels[taskId],
          'note': '',
          'source': EntrySource.timer.db,
          'started_at': start.toUtc().millisecondsSinceEpoch,
          'ended_at': end.toUtc().millisecondsSinceEpoch,
          'duration_ms': minutes * 60 * 1000,
          'created_at': end.toUtc().millisecondsSinceEpoch,
        });
        cursor = end.add(Duration(minutes: 20 + random.nextInt(60)));
      }
    }

    // ---- Journals -----------------------------------------------------------
    final journalBodies = <int, String>{
      0: '''
Two good hours on onboarding before the first interruption. The single-screen setup is the right call.

- Shipped the empty-state copy
- Patched staging
- Protected 9–11 tomorrow for the layout

Tomorrow: finish the responsive pass, then the auth tests.
''',
      1: '''
The 1:1 was shorter than expected but sharper. Capacity, not velocity.

> “If the plan needs fourteen points, the plan is the problem.”

Read a chapter on appetites. Good language for the weekly review.
''',
      2: '''
Firefighting morning. The runner upgrade broke the cache path; fixed it and added a smoke check.

Ad-hoc work is still work. Logging it made the afternoon feel less stolen.
''',
      4: '''
A quieter day. Design review moved to Thursday. Spent the gap on the runbook until access blocked me.

Energy: 3/5. Focus: good until 15:00.
''',
      6: '''
Weekly reset. Cleared the inbox, moved two things to next week, wrote the update early.

The weight target is working: 23 planned points felt honest.
''',
    };
    journalBodies.forEach((daysAgo, body) {
      final day = addDays(today, -daysAgo);
      journals.add({
        'id': 'demo-journal-${dateKey(day)}',
        'date_key': dateKey(day),
        'body_md': body.trim(),
        'mood': daysAgo == 2 ? 3 : 4,
        'energy': daysAgo == 2 ? 2 : 4,
        'created_at': day.toUtc().millisecondsSinceEpoch,
        'updated_at': day
            .add(const Duration(hours: 21))
            .toUtc()
            .millisecondsSinceEpoch,
      });
    });

    await _db.transaction((txn) async {
      if (replace) {
        await txn.delete('time_entries');
        await txn.delete('timer_sessions');
        await txn.delete('subtasks');
        await txn.delete('tasks');
        await txn.delete('journal_entries');
        await txn.delete('activity_events');
        await txn.delete('categories');
        await txn.delete('settings');
      }
      for (final category in categories) {
        await txn.insert('categories', category);
      }
      for (final task in tasks) {
        await txn.insert('tasks', task);
      }
      for (final step in subtasks) {
        await txn.insert('subtasks', step);
      }
      for (final entry in entries) {
        await txn.insert('time_entries', entry);
      }
      for (final journal in journals) {
        await txn.insert('journal_entries', journal);
      }
      for (final event in activity) {
        await txn.insert('activity_events', event);
      }
      final settings = <String, String>{
        'display_name': 'Maya',
        'daily_weight_target': '25',
        'daily_focus_minutes': '300',
        'week_starts_monday': '1',
        'theme_mode': 'system',
        'onboarded': '1',
        'auto_backup': '1',
        'last_backup_at': '',
        'backup_retention': '7',
      };
      for (final entry in settings.entries) {
        await txn.insert('settings', {'key': entry.key, 'value': entry.value});
      }
      await writeActivity(
        txn,
        entityType: 'system',
        action: 'demo_loaded',
        summary: 'Loaded the demo workspace',
      );
    });
  }

  static JournalEntry? findJournal(Iterable<JournalEntry> entries, String key) {
    for (final entry in entries) {
      if (entry.dateKey == key) return entry;
    }
    return null;
  }
}
