# Changelog

All notable changes to Daymark are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
semantic versioning once it reaches a public release.

## [1.2.0] - 2026-10-25

### Added

- One-tap Google Drive sign-in for official builds with build-time OAuth
  credentials. Builds without credentials retain the guided self-hosted setup.
- Build-time OAuth injection through `GOOGLE_OAUTH_CLIENT_ID` and
  `GOOGLE_OAUTH_CLIENT_SECRET`, the `assets/config/google_oauth.json` asset, and
  `tool/configure_google_oauth.dart`.
- QR pairing, pairing links, and scan support in Nearby, plus a one-tap
  **Sync now** action that exchanges ledgers in both directions.
- Separate Nearby **Sync**, **Send**, **Inbox**, and **History** tabs.
- A persistent 500-entry transfer history recording sent, received, restored,
  journaled, and removed items, with direction filters and session-scoped code
  memory.
- Global sync entry points in the desktop sidebar, phone bottom bar, More sheet,
  and command palette.
- Runtime handling and platform guidance for camera, Android Nearby devices,
  Android 17 local network access, iOS local network, and desktop firewall
  permissions.
- Android camera and local-network permissions, iOS/macOS camera usage strings,
  and macOS camera entitlements.

### Changed

- Upgraded to Riverpod 3.4.3, with legacy `StateProvider` imports isolated to the
  controllers that still use them.
- Replaced `flutter_markdown` with `flutter_markdown_plus`.
- Refreshed dependencies, including `qr_flutter`, `mobile_scanner`, and
  `permission_handler`.
- Google Drive setup copy now leads with **Continue with Google** when the build
  has an embedded OAuth client.
- Version is now `1.2.0+3`.

### Fixed

- macOS launches after the `AppDelegate` override fix.
- Nearby permission failures now surface actionable guidance instead of a
  generic connection error.
- Google Drive credentials and tokens remain outside ledger backups.

## [1.1.0] - 2026-10-24

### Added

- Offline-first SQLite work ledger with versioned migrations and pre-migration
  snapshots.
- Today dashboard, planner, calendar, journal, focus stopwatch, insights,
  categories, task detail, and onboarding.
- Weighted planning with effort, priority, work kind, and category weight.
- Per-task and general timers with pause/resume, crash recovery, and accumulated
  segments.
- Markdown notes and daily journal entries with mood, energy, streaks, and
  search.
- Portable ZIP backups with canonical checksums, manifests, markdown mirrors,
  validation, retention, and pre-restore safety copies.
- Google Drive mirroring with a user-supplied OAuth desktop client, multiple
  Google accounts, active-account selection, retention, download, restore, and
  optional automatic uploads every 20 hours.
- Offline OS notifications for task starts, deadlines, and a daily closing
  note, with configurable lead time and review time.
- Nearby LAN transfer: discovery, six-digit codes, snapshot push/pull, note and
  file transfer, and a persistent received inbox.
- Responsive shell with adaptive sidebar, rail, and phone navigation, command
  palette, and compact layouts.
- Branded launcher icons for Android (including adaptive and themed
  monochrome), iOS, macOS, and Windows; a Linux desktop entry and icon; and a
  monochrome Android notification icon.
- GitHub Actions pipeline that formats, analyzes, tests, and publishes Linux,
  Windows, Android, iOS, and macOS artifacts, checksums, and a tagged GitHub
  Release.

### Fixed

- Today and desktop sidebar overflows on narrow windows.
- Mobile bottom navigation now exposes Nearby and Settings through More.
- Backup restore now refreshes the task, journal, timer, and statistics state.

### Security

- Google OAuth client configuration and refresh tokens are stored in a
  separate local file with owner-only permissions. They are never written into
  ledger backups.
- Release signing material is supplied only through GitHub Actions secrets;
  no keystore or client secret is committed.

## [1.0.0] - 2026-10-24

Initial repository publication.
