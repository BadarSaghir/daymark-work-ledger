# Daymark

**Every effort, marked.**

Daymark is a private, offline-first work ledger for people whose work is more varied than a task list. Plan the day with honest weight, break large work into steps, time it without ceremony, write in markdown, and keep a record you can actually return to.

No account is required. No telemetry. Your ledger lives in a local SQLite database, and every export is a readable ZIP you own.

[![CI](https://github.com/BadarSaghir/daymark-work-ledger/actions/workflows/ci.yml/badge.svg)](https://github.com/BadarSaghir/daymark-work-ledger/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-335c4a.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.8-54c5f8.svg)](https://flutter.dev)
[![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Linux%20%7C%20macOS%20%7C%20Windows-d48a5f.svg)](#build-and-run)

---

## Why another tracker?

Most tools ask you to choose between a rigid project manager and a blank notes app. Daymark sits between them:

- **Plan by capacity, not by wishful thinking.** Each task carries an effort size and a visible weight. The day has a weight target, so you can see when it is already full.
- **Keep the texture of the work.** Notes, decisions, blockers, and journal entries are markdown, not locked form fields.
- **Measure honestly.** One live timer, paused segments preserved, and time entries that survive a crash.
- **Remember the shape of the week.** The calendar and insights show where attention actually went, not only what was completed.
- **Stay portable.** Backups are ZIP archives with JSON data, a checksum, a manifest, and markdown mirrors. Restore without the original device.
- **Move between your own devices.** Nearby sends a ledger snapshot, a note, or any file directly over the LAN. No relay, no cloud copy.

## Features

| Area | What is there |
| --- | --- |
| **Today** | A calm dashboard with today's plan, inbox, overdue work, focus target, and a quick capture shortcut. |
| **Planner** | Plan by day or week, schedule blocks, and move work without losing its history. |
| **Task detail** | Markdown notes, subtasks with progress, scheduling, estimates, priority, effort, work kind, and a complete activity trail. |
| **Timers** | One live session at a time; start, pause, resume, stop, recover after a crash, and accumulate exact segments. A general stopwatch sits beside per-task timing. |
| **Calendar** | A month view with planned load, completed work, and day drill-down. |
| **Journal** | One markdown entry per day, mood and energy, streaks, search, and date navigation. |
| **Insights** | Trends, focus totals, estimate accuracy, a 12-week focus heatmap, and category distribution. |
| **Categories** | Colour, icon, weight (0.5–2.0), archive, and safe deletion. |
| **Backups** | Manual or daily automatic backups, retention, import validation, pre-restore safety copies, and portable markdown mirrors. |
| **Nearby** | LAN discovery, six-digit transfer codes, snapshot push/pull, note and file transfer, and a local inbox with explicit restore. |
| **Interface** | Warm paper palette, deep green and persimmon accents, adaptive sidebar / rail / bottom navigation, command palette, and compact layouts down to phone width. |

## The weight formula

Weight is deliberately simple and visible everywhere in the UI:

```text
points = effort (1–5)
       × priority multiplier
       × work-kind multiplier
       × category weight (0.5–2.0)
```

- Priority: low `0.8`, normal `1.0`, high `1.3`, urgent `1.6`
- Work kind: official `1.0`, ad-hoc `0.75`, personal `0.5`
- A task is worth full points when done. With steps, progress is the completed-step ratio.

The day target is a capacity signal, not a productivity score.

## Nearby: LAN transfer without a cloud

1. Open **Nearby** on two devices on the same network.
2. Choose **Go online** on both.
3. Read the six-digit code on the receiving device and type it on the sender.
4. Send a full ledger snapshot, pull the other ledger, or send a markdown note or file.

A received snapshot waits in the inbox until you explicitly restore it. Restoring writes a pre-restore safety copy first. Files and notes have their own actions: copy, share through the system sheet, save to the journal, or turn into a task.

**Security model:** traffic is direct device-to-device and is **not encrypted**. The six-digit code guards each transfer and rotates whenever Nearby starts. Only private, loopback, and link-local addresses are accepted. Use Nearby on a network you trust. There is no internet relay, account, or cloud copy.

If UDP discovery is blocked by the network, use **Manual** with the address and port shown on the other device.

## Backups you can read

A Daymark backup is a ZIP archive:

```text
daymark-backup-20261024-183000.zip
├── backup.json        Complete schema-tagged data with canonical SHA-256 checksum
├── manifest.json      Format, schema version, timestamp, contents
├── README.md          Human instructions for the archive
├── markdown/
│   ├── journal/       One markdown file per journal entry
│   └── tasks/         One markdown file per task, including notes
```

Imports are validated before a single row is replaced. Invalid checksums, unsupported schema versions, and oversized archives are rejected. See `docs/ARCHITECTURE.md` for the restore transaction.

## Build and run

### Requirements

- Flutter **3.47.8** (stable) and Dart 3.13+
- Linux desktop: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`
- Android: Android SDK with API 35+, Java 17
- Xcode for iOS/macOS builds

> Do **not** install Flutter with snap for this project. Use the official Flutter archive or a version manager so the desktop toolchain can find the SDK without confinement issues.

```bash
flutter --version
flutter pub get
flutter run -d linux        # or: flutter run -d android
```

### Build artifacts

```bash
make build-linux            # build/linux/x64/release/bundle
make build-apk              # build/app/outputs/flutter-apk/app-release.apk
make build-ios              # unsigned iOS build (macOS host)
```

Or use Flutter directly:

```bash
flutter build linux --release
flutter build apk --release
```

## Development

```bash
make get                    # flutter pub get
make format                 # dart format lib test
make analyze                # flutter analyze
make test                   # flutter test
make check                  # format check + analyze + tests
```

The test suite covers the weight formula, date and duration helpers, backup checksums and restore safety, compact and desktop shell layouts, and overflow regressions. Widget tests use `databaseFactoryFfiNoIsolate` and seed a temporary database outside the widget fake-async zone.

## Project structure

```text
lib/
├── app/                    App shell, navigation, command palette
├── core/
│   ├── theme/              Warm-paper colour system, type, surfaces
│   ├── ui/                 Shared cards, sheets, fields, layout primitives
│   └── utils/              Date keys, duration labels, canonical JSON, weight
├── data/
│   ├── db/                 SQLite open, schema, versioned migrations
│   ├── models/             Immutable domain models
│   ├── repositories/       Typed SQL access and activity events
│   └── services/           Backup archive, demo data, LAN discovery/transfer
├── features/               Today, planner, calendar, journal, focus, insights,
│                           categories, settings, onboarding, nearby, task detail
├── state/                  Riverpod controllers and derived providers
└── widgets/                Task cards, quick capture, timer UI, shared dialogs
docs/                       Product, design, and architecture plans
test/                       Unit and widget tests
```

## Data and privacy

- Local database: `getApplicationSupportDirectory()/data/daymark.db`
- Backups: `getApplicationSupportDirectory()/backups/`
- Pre-migration snapshots: `getApplicationSupportDirectory()/pre_migration/`
- Nearby inbox: `getApplicationSupportDirectory()/nearby/`

The app contains no analytics, ads, crash reporting, or remote API calls. The only network activity is Nearby, and only while you have opened it and chosen **Go online**.

## Continuous integration

GitHub Actions runs on every push and pull request:

- formatting check, `flutter analyze`, and the full test suite;
- release build of the Linux desktop bundle;
- release APK build for Android;
- unsigned iOS build on a macOS runner;
- tagged releases publish downloadable artifacts.

See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Author

**Sardar Badar Saghir**

- GitHub: [@BadarSaghir](https://github.com/BadarSaghir)
- Repository: [BadarSaghir/daymark-work-ledger](https://github.com/BadarSaghir/daymark-work-ledger)

## License

MIT © 2026 Sardar Badar Saghir. See [LICENSE](LICENSE).
