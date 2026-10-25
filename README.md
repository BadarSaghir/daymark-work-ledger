# Daymark

**Every effort, marked.**

Daymark is a private, offline-first work ledger for people whose work is more varied than a task list. Plan the day with honest weight, break large work into steps, time it without ceremony, write in markdown, and keep a record you can actually return to.

No account is required. No telemetry. Your ledger lives in a local SQLite database, and every export is a readable ZIP you own.

[![Build & Release](https://github.com/BadarSaghir/daymark-work-ledger/actions/workflows/ci.yml/badge.svg)](https://github.com/BadarSaghir/daymark-work-ledger/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/BadarSaghir/daymark-work-ledger?color=d48a5f)](https://github.com/BadarSaghir/daymark-work-ledger/releases/latest)
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
- **Choose your second copy.** Mirror backups into your own Google Drive folder with a user-supplied OAuth client, or skip the cloud entirely.
- **Move between your own devices.** Nearby sends a ledger snapshot, a note, or any file directly over the LAN. No relay, no cloud copy.
- **Remember without a server.** Task starts, deadlines, and a daily closing note are scheduled as offline OS notifications.

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
| **Google Drive** | Optional mirror to a user-owned Drive folder, multiple Google accounts, active-account switching, retention, cloud restore, and automatic uploads at most every 20 hours. |
| **Reminders** | Offline OS notifications for task starts, deadlines, and a daily review, with configurable lead time and review time. |
| **Nearby** | LAN discovery, six-digit transfer codes, snapshot push/pull, note and file transfer, and a local inbox with explicit restore. |
| **Branding** | Adaptive Android icon with themed monochrome layer, iOS/macOS/Windows launcher icons, Linux desktop entry, and a notification icon. |
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

## Optional Google Drive mirror

Daymark does not ship Google credentials and does not run a cloud account. To
use Drive:

1. Open **Settings → Google Drive → Set up Google Drive**.
2. In [Google Cloud Console](https://console.cloud.google.com/apis/credentials),
   enable the **Google Drive API**, then create an OAuth client of type
   **Desktop app**.
3. Paste the client ID and secret into Daymark. They are stored locally in
   `config/google_drive.json` with owner-only permissions on Unix.
4. Connect one or more Google accounts. Choose the active account for uploads.
5. Use **Back up to Drive**, enable automatic mirroring, or restore a cloud
   archive directly.

Daymark requests the narrow `drive.file` scope: it can only see and manage files
it creates. Refresh tokens stay in that separate local config file and are
**never included in ledger backups**. Use the same OAuth client on each device
that should see the same Drive folder.

The loopback sign-in flow is designed for desktop. On Android and iOS it also
uses the device browser against `127.0.0.1`; if a platform or Google policy
blocks that redirect, use the Google Drive backup from desktop or sign in with a
client type supported by that platform.

## Offline reminders

Reminders are computed from the local task list and handed to the operating
system, so they fire without a network connection:

- **Task start** — with a lead time of 0 to 60 minutes.
- **Deadline** — at the task's due time.
- **Daily closing note** — one reminder at your chosen time.

Open **Settings → Offline reminders** to grant notification permission, choose
the lead time, change the daily time, reschedule, or send a test notification.
The schedule refreshes when tasks change, after a restore, and when the app
opens. Android reschedules pending alarms after a reboot through the plugin's
boot receiver. Desktop notification support depends on the system notification
service.

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

### Download a build

Tagged releases publish every platform artifact to
[GitHub Releases](https://github.com/BadarSaghir/daymark-work-ledger/releases):

| Platform | Artifact | Install |
| --- | --- | --- |
| Linux x64 | `.tar.gz`, `.deb` | Extract and run `daymark`, or `sudo apt install ./Daymark-*-linux-amd64.deb`. |
| Windows x64 | `.zip` | Extract and run `daymark.exe`. |
| Android | `.apk`, `.aab` | Sideload the APK or upload the AAB to a store. |
| iOS | unsigned `.ipa` | Sign with your Apple team before installing on a device. |
| macOS | `.dmg`, `.zip` | Open the DMG. Ad-hoc signed builds may need right-click Open. |

`SHA256SUMS.txt` is attached to each release. The release job only runs after
all five platform builds succeed.

### Build artifacts

```bash
make build-linux            # build/linux/x64/release/bundle
make build-windows          # Windows host
make build-apk              # build/app/outputs/flutter-apk/app-release.apk
make build-aab              # build/app/outputs/bundle/release/app-release.aab
make build-ios              # unsigned iOS build (macOS host)
make build-macos            # macOS host
```

Or use Flutter directly:

```bash
flutter build linux --release
flutter build windows --release
flutter build apk --release
flutter build appbundle --release
flutter build ios --release --no-codesign
flutter build macos --release
```

## Development

```bash
make get                    # flutter pub get
make format                 # dart format lib test
make analyze                # flutter analyze
make test                   # flutter test
make check                  # format check + analyze + tests
```

The test suite covers the weight formula, date and duration helpers, backup checksums and restore safety, Google Drive config and multi-account serialization, reminder preference parsing, compact and desktop shell layouts, and overflow regressions. Widget tests use `databaseFactoryFfiNoIsolate` and seed a temporary database outside the widget fake-async zone.

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
│   └── services/           Backup, Google Drive, notifications, LAN transfer
├── features/               Today, planner, calendar, journal, focus, insights,
│                           categories, settings, onboarding, nearby, task detail
├── state/                  Riverpod controllers and derived providers
└── widgets/                Task cards, quick capture, timer UI, shared dialogs
docs/                       Product, design, architecture, and release guides
test/                       Unit and widget tests
```

## Data and privacy

- Local database: `getApplicationSupportDirectory()/data/daymark.db`
- Backups: `getApplicationSupportDirectory()/backups/`
- Pre-migration snapshots: `getApplicationSupportDirectory()/pre_migration/`
- Nearby inbox: `getApplicationSupportDirectory()/nearby/`
- Google OAuth client and refresh tokens: `getApplicationSupportDirectory()/config/google_drive.json`
- Reminder preferences: `getApplicationSupportDirectory()/config/notifications.json`

The app contains no analytics, ads, crash reporting, or telemetry. Network
activity is limited to:

- Nearby, and only while you open it and choose **Go online**;
- Google Drive, and only after you configure your own OAuth client and connect
  an account.

Everything else works offline. The Google Drive config file is separate from
the database and backups so a restored ledger cannot leak or overwrite tokens.

## Continuous integration and releases

The **Build & Release** workflow runs on every push and pull request:

- formatting check, `flutter analyze`, and the full test suite;
- Linux x64 portable tarball and Debian package;
- Windows x64 portable ZIP;
- Android APK and AAB;
- unsigned iOS IPA on a macOS runner;
- macOS DMG and ZIP;
- on `v*` tags, a GitHub Release with all artifacts and `SHA256SUMS.txt`.

No release is published unless every platform build and the quality gate pass.
Android production signing and Apple signing are optional and driven by GitHub
Actions secrets; see [`docs/RELEASING.md`](docs/RELEASING.md) for the exact
secrets, signing commands, macOS notarization notes, and rollback procedure.

See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Author

**Sardar Badar Saghir**

- GitHub: [@BadarSaghir](https://github.com/BadarSaghir)
- Repository: [BadarSaghir/daymark-work-ledger](https://github.com/BadarSaghir/daymark-work-ledger)

## License

MIT © 2026 Sardar Badar Saghir. See [LICENSE](LICENSE).
