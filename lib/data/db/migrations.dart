import 'package:sqflite_common/sqlite_api.dart';

import '../models/app_settings.dart';

/// Versioned schema. Rules:
/// * Never edit a shipped version's statements; add a new version.
/// * Fresh installs call [create] (latest schema, no replay).
/// * Upgrades call [upgrade] one version at a time.
class Migrations {
  Migrations._();

  static const int latestVersion = 3;

  static Future<void> create(Database db) async {
    final batch = db.batch();
    for (final statement in [..._v1, ..._v2, ..._v3]) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
    await _seed(db);
  }

  static Future<void> upgrade(Database db, int from, int to) async {
    for (var version = from + 1; version <= to; version++) {
      switch (version) {
        case 1:
          for (final statement in _v1) {
            await db.execute(statement);
          }
          await _seed(db);
        case 2:
          for (final statement in _v2) {
            await db.execute(statement);
          }
        case 3:
          for (final statement in _v3) {
            await db.execute(statement);
          }
        default:
          throw StateError('No migration registered for schema v$version');
      }
    }
  }

  static Future<void> _seed(Database db) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final categories = <(String, String, int, String, double)>[
      ('cat-deep-work', 'Deep Work', 0xFF1D5B4F, 'target', 1.3),
      ('cat-meetings', 'Meetings', 0xFF3C6E91, 'users', 0.9),
      ('cat-admin', 'Admin', 0xFF8A7A2E, 'inbox', 0.7),
      ('cat-learning', 'Learning', 0xFF7A5CA8, 'book', 1.1),
      ('cat-personal', 'Personal', 0xFFC26A32, 'sun', 0.8),
    ];
    final batch = db.batch();
    for (var i = 0; i < categories.length; i++) {
      final c = categories[i];
      batch.insert('categories', {
        'id': c.$1,
        'name': c.$2,
        'color': c.$3,
        'icon': c.$4,
        'weight': c.$5,
        'position': i,
        'archived': 0,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final entry in AppSettings.defaults.toMap().entries) {
      batch.insert('settings', {
        'key': entry.key,
        'value': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  static const List<String> _v1 = [
    '''
    CREATE TABLE IF NOT EXISTS categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      color INTEGER NOT NULL,
      icon TEXT NOT NULL,
      weight REAL NOT NULL DEFAULT 1.0,
      position INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS tasks (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      notes_md TEXT NOT NULL DEFAULT '',
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      kind TEXT NOT NULL DEFAULT 'official',
      status TEXT NOT NULL DEFAULT 'inbox',
      priority TEXT NOT NULL DEFAULT 'normal',
      effort INTEGER NOT NULL DEFAULT 2,
      estimate_minutes INTEGER,
      planned_date TEXT,
      scheduled_start INTEGER,
      scheduled_end INTEGER,
      due_at INTEGER,
      blocked_reason TEXT,
      position INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER,
      archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_tasks_planned_date ON tasks(planned_date)',
    'CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)',
    'CREATE INDEX IF NOT EXISTS idx_tasks_category ON tasks(category_id)',
    '''
    CREATE TABLE IF NOT EXISTS subtasks (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0,
      is_done INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_subtasks_task ON subtasks(task_id)',
    '''
    CREATE TABLE IF NOT EXISTS timer_sessions (
      id TEXT PRIMARY KEY,
      task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
      label TEXT NOT NULL DEFAULT '',
      kind TEXT NOT NULL DEFAULT 'general',
      status TEXT NOT NULL DEFAULT 'running',
      started_at INTEGER NOT NULL,
      segment_started_at INTEGER,
      accumulated_ms INTEGER NOT NULL DEFAULT 0,
      singleton INTEGER NOT NULL DEFAULT 1 UNIQUE,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS time_entries (
      id TEXT PRIMARY KEY,
      session_id TEXT,
      task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
      label TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      source TEXT NOT NULL DEFAULT 'timer',
      started_at INTEGER NOT NULL,
      ended_at INTEGER NOT NULL,
      duration_ms INTEGER NOT NULL,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_time_task ON time_entries(task_id)',
    'CREATE INDEX IF NOT EXISTS idx_time_started ON time_entries(started_at)',
    'CREATE INDEX IF NOT EXISTS idx_time_session ON time_entries(session_id)',
    '''
    CREATE TABLE IF NOT EXISTS journal_entries (
      id TEXT PRIMARY KEY,
      date_key TEXT NOT NULL UNIQUE,
      body_md TEXT NOT NULL DEFAULT '',
      mood INTEGER,
      energy INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_journal_date ON journal_entries(date_key)',
    '''
    CREATE TABLE IF NOT EXISTS activity_events (
      id TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL,
      entity_id TEXT,
      action TEXT NOT NULL,
      summary TEXT NOT NULL,
      metadata TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_activity_created ON activity_events(created_at)',
    '''
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
  ];

  /// v2 adds per-task reminders and task attachments. The attachment rows are
  /// metadata; the bytes live beside the profile database and are bundled into
  /// backups and single-task shares.
  static const List<String> _v2 = [
    'ALTER TABLE tasks ADD COLUMN reminder_at INTEGER',
    'ALTER TABLE tasks ADD COLUMN reminder_note TEXT',
    '''
    CREATE TABLE IF NOT EXISTS task_attachments (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
      file_name TEXT NOT NULL,
      mime_type TEXT NOT NULL DEFAULT '',
      size_bytes INTEGER NOT NULL DEFAULT 0,
      relative_path TEXT NOT NULL UNIQUE,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_task_attachments_task ON task_attachments(task_id)',
  ];

  /// v3 turns a task reminder into an optional daily repeating reminder that
  /// fires at the same local time every day.
  static const List<String> _v3 = [
    'ALTER TABLE tasks ADD COLUMN reminder_daily INTEGER NOT NULL DEFAULT 0',
  ];
}
