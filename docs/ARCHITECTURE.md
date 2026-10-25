# Daymark — Architecture & Engineering Notes

## 1. Overview

Daymark is a Flutter application with a local SQLite source of truth. It has no backend, no authentication, and no runtime network calls.

```
┌────────────────────────────────────────────────────────────┐
│ Presentation                                               │
│  app/ shell/ theme/ reusable widgets/ feature pages        │
└──────────────────────────┬─────────────────────────────────┘
                           │ watches / invokes
┌──────────────────────────▼─────────────────────────────────┐
│ Application state (Riverpod)                               │
│  repositories as providers, AsyncNotifiers, derived data   │
└──────────────────────────┬─────────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────────┐
│ Domain services                                            │
│  weightage · duration format · markdown · timer engine     │
│  backup · export · demo seed · date keys                   │
└──────────────────────────┬─────────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────────┐
│ Data                                                       │
│  repositories (SQL only here) · migrations · models        │
│  SQLite (sqflite / sqflite_common_ffi on desktop)          │
└────────────────────────────────────────────────────────────┘
```

**Dependency rule:** `core → data → features`. Features never import another feature's widgets; shared widgets live in `lib/widgets` or `lib/core/ui`. Repositories are the only classes that touch `Database`.

---

## 2. Project layout

```
lib/
  main.dart                     bootstrap, DB init, desktop FFI
  app.dart                      MaterialApp, theme controller, shell
  core/
    theme/app_theme.dart        tokens → ThemeData + ThemeExtension
    theme/app_colors.dart       palette
    theme/app_typography.dart   font families/styles
    ui/                         SurfaceCard, badges, buttons, empty state…
    utils/date_keys.dart        local YYYY-MM-DD helpers, ranges
    utils/durations.dart        HH:MM:SS / compact human format
    utils/weightage.dart        pure scoring functions
    utils/result.dart           typed success/failure for import
  data/
    db/app_database.dart        open, PRAGMAs, migrations, snapshots
    db/migrations.dart          versioned DDL
    models/*.dart               immutable models + fromMap/toMap
    repositories/*.dart         categories, tasks, subtasks, time,
                                journal, activity, settings, stats
    services/backup_service.dart
    services/export_service.dart
    services/demo_service.dart
  state/
    providers.dart              DB/repository providers
    settings_controller.dart
    tasks_controller.dart
    categories_controller.dart
    timer_controller.dart
    journal_controller.dart
    selected_date_controller.dart
    search_controller.dart
  widgets/                      cross-feature components
  features/
    onboarding/  shell/  today/  planner/  task_detail/
    calendar/  journal/  insights/  categories/  settings/
    stopwatch/  search/
test/
  database_test.dart
  migrations_test.dart
  backup_test.dart
  timer_test.dart
  weightage_test.dart
  duration_test.dart
  widget_smoke_test.dart
```

---

## 3. Platform support

| Platform | SQLite | Notes |
|---|---|---|
| Android | `sqflite` | `path_provider` app support dir |
| iOS | `sqflite` | Same |
| Linux | `sqflite_common_ffi` + system sqlite3 | `sqfliteFfiInit()` before `runApp` |
| Windows | `sqflite_common_ffi` | Bundled sqlite3 via package |
| macOS | `sqflite_common_ffi` | Desktop |
| Web | **not supported** | Offline requirement + SQLite semantics; excluded from project |

### 3.1 Local accounts

`local_accounts.json` at the application-support root remembers profiles,
the active id, and whether the workspace is signed in. The first profile adopts
the original root layout in place (`data/`, `backups/`, `cloud/`, `nearby/`,
`config/`). Every additional profile gets `accounts/<uuid>/` with the same
internal layout. Switching opens the next SQLite database before closing the
previous one, then lets Riverpod rebuild repositories from the new
`databaseProvider`. Google credentials and auto-upload settings are therefore
per local account, and signing out only flips the picker gate; it never deletes
an account or its data.

---

## 4. Data model (schema v1)

All timestamps are **UTC epoch milliseconds** (`INTEGER`). Planning keys are **local dates** (`TEXT`, `YYYY-MM-DD`) so a day means the user's day. IDs are UUID v4 strings. Booleans are `INTEGER` 0/1.

```sql
CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  color INTEGER NOT NULL,           -- ARGB
  icon TEXT NOT NULL,               -- stable semantic key, e.g. 'briefcase'
  weight REAL NOT NULL DEFAULT 1.0, -- 0.5..2.0
  position INTEGER NOT NULL DEFAULT 0,
  archived INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE tasks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  notes_md TEXT NOT NULL DEFAULT '',
  category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
  kind TEXT NOT NULL DEFAULT 'official',      -- official | adhoc | personal
  status TEXT NOT NULL DEFAULT 'inbox',       -- inbox|planned|in_progress|blocked|done
  priority TEXT NOT NULL DEFAULT 'normal',    -- low|normal|high|urgent
  effort INTEGER NOT NULL DEFAULT 2,          -- 1..5
  estimate_minutes INTEGER,
  planned_date TEXT,                          -- YYYY-MM-DD
  scheduled_start INTEGER,                    -- epoch ms, optional
  scheduled_end INTEGER,
  due_at INTEGER,
  blocked_reason TEXT,
  position INTEGER NOT NULL DEFAULT 0,
  completed_at INTEGER,
  archived INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_tasks_planned_date ON tasks(planned_date);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_category ON tasks(category_id);

CREATE TABLE subtasks (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  is_done INTEGER NOT NULL DEFAULT 0,
  completed_at INTEGER,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_subtasks_task ON subtasks(task_id);

CREATE TABLE timer_sessions (
  id TEXT PRIMARY KEY,
  task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
  label TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL DEFAULT 'general',   -- general | task
  status TEXT NOT NULL DEFAULT 'running', -- running | paused
  started_at INTEGER NOT NULL,
  segment_started_at INTEGER,             -- null when paused
  accumulated_ms INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
-- Enforce at most one live session in the repository layer + unique partial index:
CREATE UNIQUE INDEX idx_one_live_timer
  ON timer_sessions((status IS NOT NULL)) WHERE status IN ('running','paused');

CREATE TABLE time_entries (
  id TEXT PRIMARY KEY,
  session_id TEXT,                        -- group id; nullable for manual entries
  task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
  label TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT 'timer',   -- timer | manual
  started_at INTEGER NOT NULL,
  ended_at INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_time_task ON time_entries(task_id);
CREATE INDEX idx_time_started ON time_entries(started_at);

CREATE TABLE journal_entries (
  id TEXT PRIMARY KEY,
  date_key TEXT NOT NULL UNIQUE,          -- local YYYY-MM-DD
  body_md TEXT NOT NULL DEFAULT '',
  mood INTEGER,                           -- 1..5
  energy INTEGER,                         -- 1..5
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE activity_events (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,              -- task|category|journal|system
  entity_id TEXT,
  action TEXT NOT NULL,                   -- created|status|completed|timer…
  summary TEXT NOT NULL,
  metadata TEXT,                          -- JSON string, optional
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_activity_created ON activity_events(created_at);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

### Repository invariants

- Enabling `PRAGMA foreign_keys = ON` for every connection.
- Journal dates are unique; upsert on `date_key`.
- At most one live timer session (repository transaction; partial unique index as backstop).
- Deleting a task is only hard-delete via explicit purge; normal flow archives. Time entries keep `task_id` null if a task is purged.
- Subtasks cascade with their parent.
- Activity events are append-only and survive task archival.
- Every mutation that spans tables runs in a transaction.

---

## 5. Weightage & derived data

`lib/core/utils/weightage.dart` contains pure functions:

```dart
double taskPoints({required int effort, required Priority priority,
                   required WorkKind kind, required double categoryWeight});
double taskProgress({required List<Subtask> subtasks, required TaskStatus status});
double earnedPoints(Task task, Category? category, List<Subtask> subtasks);
DailyLoad dailyLoad(List<Task> dayTasks, Map<String, Category> categories);
```

Multipliers:

| Dimension | Value |
|---|---|
| Effort | 1, 2, 3, 4, 5 |
| Priority low / normal / high / urgent | 0.8 / 1.0 / 1.3 / 1.6 |
| Kind official / adhoc / personal | 1.0 / 0.75 / 0.5 |
| Category weight | 0.5–2.0 |

`progress` = subtasks present ? done/total : (done ? 1 : manual status progress). Completed always 1.

Derived view models (`TaskView`) are built in controllers/repositories and passed to widgets: task + category + subtasks + tracked ms + points + progress.

---

## 6. Timer engine

### Persistence

`timer_sessions` stores the live session. `time_entries` stores finished contiguous segments.

Start:

1. In a transaction, pause/finish any live session (per UI policy, the controller confirms first).
2. Insert session `{status: running, started_at: now, segment_started_at: now, accumulated_ms: 0}`.
3. Store `activeTimerSessionId` in the settings table (crash breadcrumb; optional).

Pause:

1. `elapsed = now - segment_started_at`.
2. Insert `time_entries` segment `{started_at, ended_at: now, duration_ms: elapsed, task_id, session_id}`.
3. Update session `accumulated_ms += elapsed`, `segment_started_at = null`, `status = paused`.

Resume: set `segment_started_at = now`, `status = running`.
Stop: perform pause, then delete the session row (entries remain). Optional trim edits the final entry duration before delete.
Recovery on launch: any live session is loaded; if `running`, elapsed includes the still-open wall-clock segment. The UI shows a banner: _Timer recovered — keep or trim_. Starting work with a stale session > 8 h asks for confirmation.

### Display

- Per-task **total** = `SUM(time_entries.duration_ms WHERE task_id = ?)` + active uncommitted segment for that task.
- **Session** = `accumulated_ms` + (`now - segment_started_at` if running).
- Task detail shows both session and all-time totals.
- Global stopwatch shows the unassigned session; on stop it can be labeled and optionally assigned to a task (updates all its entries).

### Invariant

Starting any timer first stops the current one. The controller exposes `startForTask`, `startGeneral`, `pause`, `resume`, `stop`, and a `tick` provider updated once per second only while running.

---

## 7. Markdown

- Stored raw in `tasks.notes_md` and `journal_entries.body_md`.
- Editor: plain `TextField` with toolbar insertion helpers; no rich-text conversion, so round-trips are lossless.
- Preview: `flutter_markdown_plus` with a custom `MarkdownStyleSheet`; HTML is not enabled.
- Autosave: 700 ms debounce on typing + flush on blur/route pop.
- Export: raw markdown, with front-matter in file exports (`title`, `date`, `category`, `kind`, `points`).
- Insert summary builds a checklist from completed tasks and a time table.

---

## 8. Backup format

ZIP (`daymark-backup-YYYYMMDD-HHMMSS.zip`) containing:

```
manifest.json
backup.json
markdown/
  journal/2026-10-24.md
  tasks/<slug>-<id8>.md
```

`backup.json`:

```json
{
  "format": "daymark.backup",
  "formatVersion": 1,
  "schemaVersion": 1,
  "appVersion": "1.2.0",
  "exportedAt": 1761300000000,
  "checksum": "sha256(canonical backup payload)",
  "counts": {"tasks": 42, "timeEntries": 310},
  "data": {
    "categories": [], "tasks": [], "subtasks": [],
    "timerSessions": [], "timeEntries": [], "journalEntries": [],
    "activityEvents": [], "settings": []
  }
}
```

Rules:

- **Export** is read-only and runs in a transaction/consistent read. Writes to the backups directory via `path_provider`; desktop may use a save dialog.
- **Validate before import:** format string, formatVersion supported, schemaVersion ≤ current, checksum matches canonical JSON, referenced task/category IDs resolve or are nulled, no live timers restored as running.
- **Restore:** always create `pre-restore-…zip` first. Delete children before parents; insert parents before children; all in one transaction. Replace-only (merge is roadmap).
- **Automatic pre-migration snapshot:** in `onUpgrade`, before executing migrations, copy `app.db`, `app.db-wal`, `app.db-shm` to `backups/pre-migration-v{old}-to-v{new}-{ts}.db*`.
- **Daily backup:** once per 24 h on app launch if enabled, retaining the last 7.

---

## 9. Migrations

- `PRAGMA user_version` is the version. `AppDatabase.schemaVersion = 1`.
- `Migrations.create(db)` creates the latest schema for fresh installs.
- `Migrations.upgrade(db, from, to)` applies ordered SQL statements (and Dart callbacks when data backfills are needed) one version at a time.
- Fresh installs always create the latest schema; they do not replay migrations.
- `onUpgrade` runs inside sqflite's transaction; SQLite DDL is transactional, so a failure rolls back.
- Tests:
  - fresh create → expected tables/indexes/version;
  - simulate v0 → latest upgrade;
  - idempotent `open()` → no duplicate tables;
  - pre-migration snapshot file exists.
- Never edit a shipped migration. Add a new version with a compensating change.

---

## 10. State management

Riverpod 3.4.3. Key providers:

| Provider | Type | Responsibility |
|---|---|---|
| `databaseProvider` | `Provider<AppDatabase>` | overridden in tests |
| `settingsProvider` | `AsyncNotifier<AppSettings>` | preferences, targets, onboarding |
| `categoriesProvider` | `AsyncNotifier<List<Category>>` | CRUD + archive |
| `tasksProvider` | `AsyncNotifier<List<TaskView>>` | all active tasks, derived views |
| `journalListProvider` | `AsyncNotifier<List<JournalEntry>>` | history + search |
| `journalForDateProvider` | `FutureProvider.family<Journal?>` | editor |
| `timerProvider` | `AsyncNotifier<TimerState>` | active session, ticker, stopwatch ops |
| `statsProvider` | `FutureProvider.family<StatsRange, DateRange>` | insights |
| `selectedDateProvider` | `StateProvider<DateTime>` (legacy) | calendar + planner |
| `navIndexProvider` | `StateProvider<int>` (legacy) | shell destination |

Mutations call repositories, then invalidate affected providers. Local queries are fast enough that explicit invalidation is simpler and safer than streams. Optimistic checkbox toggles are allowed, with rollback on error.

---

## 11. Testing strategy

**Unit (pure):** weightage, duration formatting, date keys/ranges, timer math, markdown insertion helpers, backup validation/canonical JSON, Google OAuth defaults, LAN pairing payloads, and transfer-history serialization.

**Database (ffi in-memory / temp file):** CRUD, FK cascade, unique journal upsert, one-live-timer constraint, migration from empty and from v1 fixture, snapshot creation logic.

**Backup:** export → file → import into a fresh DB → equality of row counts and key rows; tampered checksum rejected; unsupported version rejected; pre-restore snapshot created.

**Widget:** app boots with demo data at 390×844, 820×1180, 1440×900; navigation across the full shell; open task detail; toggle checklist; start/stop timer; open quick add; no exceptions/overflow.

**Manual smoke:** Linux desktop on `:0` with screenshots in light and dark; Android emulator if available.

**CI suggestion:** `dart format --set-exit-if-changed lib test && flutter analyze && flutter test`.

---

## 12. Developer experience

```bash
flutter pub get
flutter run -d linux            # desktop dev loop
flutter run -d <android-device> # mobile
flutter test
flutter analyze
dart format lib test
flutter build linux --release
flutter build apk --release
```

Makefile targets mirror these. Seed/demo data is available from Settings and empty states. A debug-only menu (long-press brand mark) opens the database directory for inspection.

**Conventions**

- Immutable models with `copyWith`; equality by id.
- `AsyncValue` rendered through a shared `AsyncView` widget.
- No business logic in widgets; no SQL outside repositories.
- All user-visible strings in code (no l10n yet, but no concatenated sentences in dialogs).
- Activity events are written by repositories, not widgets.
- Keep files under ~400 lines where practical; extract widgets.

---

## 13. Security & privacy

- The ledger, backups, and journal never require an online account or telemetry. Local accounts separate data and cloud links but are profiles, not a password boundary; the sign-out gate is a convenience on shared devices.
- Google OAuth client values, refresh tokens, and notification preferences live in separate local files, never in ledger backups. Token files are written with owner-only permissions on Unix.
- Nearby is opt-in per session, binds only to private/loopback/link-local addresses, and is guarded by a rotating six-digit code. **LAN payloads are not encrypted.**
- The pairing QR contains the session code. The UI tells the user to show it only to their own device.
- Backups are plain-text ZIPs (by design, portable and inspectable). The UI states this clearly.
- Sensitive note content is never logged to console in release builds.
- File paths come from `path_provider`, never from user text.
- Import validates structure and caps array sizes/accepted file size to avoid memory abuse.
- No server-side secret or shared cloud account is embedded. Google sign-in uses a Desktop-app OAuth client and the narrow `drive.file` scope.

---

## 14. Nearby LAN protocol

- **Discovery:** UDP broadcast on port `45913`; peers exchange an id, display name, platform, and HTTP port. Discovery never leaves the local network.
- **Transport:** a short-lived `HttpServer` on a random port. Private, loopback, and link-local targets only. No TLS.
- **Pairing:** six random digits generated with `Random.secure()` on each Nearby session. A QR or paste link encodes `daymark://pair?host=…&port=…&pin=…&name=…&id=…`. Pairing remembers the code in memory until the page goes offline; it is not persisted.
- **Endpoints:** `GET /v1/info`, `GET /v1/snapshot`, `POST /v1/snapshot`, `POST /v1/text`, and `POST /v1/file`, all PIN-guarded and capped at 100 MB.
- **Inbox:** received notes, files, and snapshots are written under the active local account's `nearby/` folder. A snapshot is never applied automatically; restore validates the archive and writes a pre-restore safety copy first.
- **History:** `history.json` keeps the newest 500 events with direction, kind, title, peer, timestamp, status, item id, and size. Statuses move from `received` to `restored`, `journaled`, or `removed`.
- **Sync now:** sends the local snapshot, then pulls the peer snapshot in one user action. Each side sees the other side's backup in its inbox.
