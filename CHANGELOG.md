# Changelog

All notable changes to Daymark are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
semantic versioning once it reaches a public release.

## [1.4.0] - 2026-10-28

### Added

- Mobile-first app shell for phones: a compact header with the current screen's
  title and subtitle, four-item bottom navigation (Today, Planner, Focus, More),
  a centre-docked capture button, and a floating running-timer pill that opens
  Focus.
- A Focus screen that fits a phone without scrolling: responsive clock dial,
  single-row Pause, Stop, and Discard controls, and a tappable **Today's log**
  summary that opens totals and entries in a sheet. Landscape phones get a
  sideways clock with icon actions for the log, manual entry, and the ritual.
- Phone layouts for Today, Planner, Calendar, Journal, Insights, and Settings
  that keep the primary action on screen and move history, detail, and totals
  into bottom sheets and compact summary rows.
- A grouped settings menu on phones with section sheets for profile, daily
  rhythm, appearance, backup, and data. Each sheet panel owns its state, so
  toggles and fields stay live while the sheet is open.
- Platform capability helpers (`AppPlatform`) so keyboard shortcuts and
  desktop-only copy appear only on desktop.

### Changed

- Bottom sheets on compact screens now size themselves between the notch and
  the open keyboard, scroll inside the remaining space, and keep their last row
  above the home indicator.
- The timer pill is hidden on Focus, where it overlapped the clock, and sits
  above the bottom navigation on the other screens.
- Compact page padding was reduced so content clears the navigation bar and
  capture button without a large dead zone.
- Version is now `1.4.0+5`.

### Fixed

- Bottom sheet menu items could not be reached beneath the home indicator on
  notched phones.
- The Focus screen scrolled on phones and clipped its controls on small and
  landscape screens.
- Keyboard shortcuts were advertised on touch devices where no keyboard exists.

## [1.3.0] - 2026-10-25

### Added

- Single-task bundles (`.daymark-task`) that carry a task's markdown notes,
  steps, tracked time, activity trail, category, reminders, and attachment
  files. Export from task detail, send over Nearby, or import from **Settings →
  Backup & portability**. Re-importing updates the same task instead of making a
  duplicate; time entries are additive and a newer local copy is preserved.
- Per-task file attachments with a searchable task picker. Files are stored
  beside the active profile, shown on task detail with open/share/remove
  actions, and included in backups and task bundles. Limits are 50 MB per file
  and 90 MB per task.
- Custom per-task reminders with an exact local date, time, and optional note,
  in addition to start and deadline reminders.
- Booked-hours occupancy on the calendar: month tiles show busy time, weekly
  rows show a compact total, and a day timeline lists every scheduled window
  with its task, category, and duration. Overlapping work is counted once.
- Learning, admin, and creative work kinds, each with its own weight
  multiplier, icon, and colour.
- Markdown mirrors in backups now list task attachments, and task bundles
  include reminder and deadline metadata in their readable markdown file.

### Changed

- Backups now include attachment metadata and the attachment file tree.
  Restore removes stale files safely and validates every relative path.
- Deleting a task or resetting a workspace removes its attachment files as well
  as its database rows.
- Nearby task sharing uses the existing paired-device flow, adding the bundle
  to the receiver's Inbox for an explicit import.
- Linux reminders now include an in-app 20-second due-reminder pulse because
  the Linux notification plugin cannot schedule; Windows, Android, iOS, and
  macOS continue to use native scheduled notifications.
- Version is now `1.3.0+4`.

### Fixed

- Windows CI builds `permission_handler_windows` with the experimental
  coroutine compatibility define required by current MSVC toolchains.
- Android CI discovers the installed `sdkmanager`, accepts licenses, and
  installs the API 37 platform and build tools without the failing setup
  action.

## [1.2.0] - 2026-10-25

### Added

- Multiple local accounts with separate SQLite ledgers, backups, reminders,
  Nearby history, and Google Drive links. Accounts are remembered, switchable
  from Settings, the sidebar, the More sheet, and the command palette, and
  protected by a sign-out account picker without deleting data.
- Per-local-account Google Drive configuration. Signed-out Google accounts stay
  remembered for one-tap reconnection, with explicit **Sign out** and **Forget
  account** actions.
- Searchable, paginated category management and a shared category picker used by
  quick capture and the task editor, so large category sets stay usable.
- Labelled icon menus across category, task, stopwatch, backup, Nearby, and
  Google account actions.
- Bundle-aware Linux window and menu icon loading, plus a Windows taskbar
  AppUserModelID for consistent Daymark grouping and branding.
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

- Google Drive credentials, tokens, auto-upload settings, and Google account
  choices are now scoped to the active local account.
- The first local account adopts the existing data directory in place, so
  upgrades preserve the current ledger without a migration copy.
- Android CI installs the API 37 platform and build tools explicitly before the
  APK/AAB build.
- macOS packaging now stages with `ditto`, signs and verifies the app, creates
  an HFS+ compressed DMG, and verifies the image.
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
