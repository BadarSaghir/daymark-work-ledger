# Daymark — Product Plan

> **Every effort, marked.**
> A private, offline-first work ledger for people whose real work is scattered across planned tasks, spontaneous requests, and the small things nobody remembers a week later.

---

## 1. The problem

Knowledge workers are asked to account for their time and output, but the tools they use assume work happens in tidy planned blocks.

Reality:

- Work arrives **on the fly** — a Slack request, an unplanned meeting, a production issue, a colleague stopping by.
- People **forget what they did**, especially the ad-hoc work that consumed the day but never produced a ticket.
- Planned tasks are often **too large to start**. They need to be broken into constituent steps, but that breakdown lives in someone's head.
- Timing is approximate. People reconstruct the day from memory and usually get it wrong.
- "How much did I get done?" is answered with a task count, not with **effort, weight, and impact**.
- Daily plans ignore capacity, so every day starts over-committed and ends with a vague sense of failure.
- Journals and notes are separate from tasks, so the record of the day is split across apps.
- Official work, side work, learning, and personal commitments are mixed together with no honest way to see the split.
- Most tools are cloud-first and require an account. Work logs are sensitive; many people want them **local and private**.

### Core problem statement

> A person doing knowledge work needs a **zero-friction, private way to capture, plan, time, and remember work** — including unplanned work — so that effort can be reconstructed accurately, capacity can be respected, and a trustworthy record of the day exists without maintaining it manually.

### Product principles

1. **Capture before structure.** Recording something must take seconds; organising it can happen later.
2. **One active timer.** The system never double-counts attention.
3. **Plan in weight, not just tasks.** Capacity is expressed in effort points and minutes.
4. **The day writes itself.** Completed work, time, and notes are assembled into a reviewable daily record.
5. **Local by default.** SQLite on device. No accounts, no telemetry, no network dependency.
6. **Calm, not gamified.** Progress is informative, never guilt-inducing.
7. **Everything is recoverable.** Exports, pre-migration snapshots, validated restores.

---

## 2. Missing sub-problems (and how Daymark answers them)

| # | Sub-problem | Why it is missed | Daymark answer |
|---|-------------|------------------|----------------|
| 1 | **Ad-hoc invisibility** — unplanned work disappears from records | Trackers only accept planned tickets | `Work kind: Official / Ad-hoc / Personal` on every task; quick capture; retro-log time |
| 2 | **Capture debt** — logging is deferred, then forgotten | Forms are too heavy | One-field quick add, global shortcut, "log now, organise later" inbox status |
| 3 | **Context-switch tax** — multiple timers or overlapping work | Tools allow parallel timers | Single active timer; starting another pauses the first with a confirm |
| 4 | **Timer leakage** — timers left running for hours | No recovery or correction | Running sessions persisted with wall-clock start; recovery prompt; editable time entries |
| 5 | **Estimate drift** — estimates are never compared with reality | No feedback loop | Estimate vs actual on task and in Insights; drift percentage |
| 6 | **Plan–reality gap** — overcommitment every morning | Task count ≠ capacity | Weighted daily load vs configurable target; over-capacity warnings |
| 7 | **Weightage ambiguity** — "points" are arbitrary | No stated formula | Visible formula: effort × priority × kind × category weight; explained in UI |
| 8 | **Task paralysis** — large tasks never start | No breakdown ritual | Subtasks ("break it down"), roll-up progress, completion guard |
| 9 | **Completion integrity** — parent done while steps remain | Status is a single flag | Completing a parent with open steps asks to complete or keep open |
| 10 | **Day-boundary confusion** — late-night work lands on the wrong day | Timestamps vs local dates | UTC instants stored; local `YYYY-MM-DD` keys for planning and journal; configurable week start |
| 11 | **Review amnesia** — weekly reviews start from a blank page | Data is not assembled | Auto daily summary, markdown export, journal history and search |
| 12 | **Proof of work** — no credible record for check-ins | Raw lists lack context | Weighted output, category split, completed-task evidence, markdown report export |
| 13 | **Category entropy** — dozens of abandoned projects | No lifecycle | Archive categories; can't delete categories that own tasks |
| 14 | **Data loss** — reinstall or schema change destroys history | Backups are an afterthought | JSON+markdown ZIP backups, restore validation, automatic pre-migration copy, daily backup |
| 15 | **Privacy** — work logs in someone else's cloud | SaaS default | Offline SQLite; no network permission required; explicit local export |
| 16 | **Offline reminders** — forgetting to start or stop work | Push infrastructure | In-app running-timer pill, recovery on launch, end-of-day journal nudge (local) |
| 17 | **Accessibility & motion** — dense productivity UIs exclude people | Custom charts and tiny targets | 44px targets, semantic labels, scalable text, reduced-motion respect, contrast-checked palette |
| 18 | **Multi-device myth** — sync conflicts corrupt logs | Assume always-online | Explicit non-goal in v1: one device, portable backups. Sync is a later, opt-in design. |

### Explicit non-goals (v1)

- Cloud sync, accounts, teams, shared workspaces.
- Billing/invoicing or payroll export.
- Background notifications that require a server.
- Web target (SQLite persistence semantics differ; use a desktop/mobile build).
- Native mobile home-screen widgets (roadmap).

---

## 3. Personas & jobs

**Maya — product engineer.** Planned sprints plus constant interrupts. Needs to prove where the week went and protect deep-work blocks.
*Job:* "Help me see that the 3 hours of firefighting was real work, not lost time."

**Dan — consultant.** Bills by project, works across categories, needs defensible time records.
*Job:* "Give me an accurate, exportable record of effort by category."

**Priya — lead.** Plans in outcomes, delegates steps. Needs subtask visibility and capacity awareness.
*Job:* "Stop me from planning 14 points into an 8-point day."

**Sam — freelance creative.** Works on the fly, forgets to log, wants a daily journal that is not a second job.
*Job:* "Let me capture a thought in five seconds and make sense of it later."

---

## 4. Success metrics (local, privacy-safe)

- Time to capture a task: **< 8 seconds**.
- Time to start/stop tracking from any screen: **1 tap**.
- Daily log completion after 2 weeks: **> 60% of active days**.
- Percentage of tracked time assigned to a category: **> 90%**.
- Weekly review produced without manual reconstruction: **yes**.
- Backup restore round-trip integrity: **100%** in tests.
- No lost timer on app restart: **100%** of running sessions recovered or surfaced.

---

## 5. Experience map

```
              ┌──────────────────────────────────────────────┐
              │                  TODAY                       │
              │  pulse · capacity · running timer · schedule │
              └───────┬──────────┬──────────┬───────────────┘
                      │          │          │
        ┌─────────────▼──┐  ┌────▼─────┐  ┌─▼──────────────┐
        │   PLANNER     │  │ CALENDAR │  │   JOURNAL      │
        │ board+subtasks│  │ month/day│  │ markdown+auto  │
        └───────┬───────┘  └────┬─────┘  └────┬───────────┘
                │               │             │
        ┌───────▼───────────────▼─────────────▼───────────┐
        │                 TASK DETAIL                     │
        │ notes · checklist · schedule · timer · history   │
        └───────┬───────────────────────────┬─────────────┘
                │                           │
        ┌───────▼────────┐          ┌───────▼────────────┐
        │  TIMER (global)│          │    INSIGHTS        │
        │ focus sessions │          │ weight · drift     │
        └───────┬────────┘          └───────┬────────────┘
                │                           │
        ┌───────▼───────────────────────────▼────────────┐
        │       SETTINGS · BACKUP · MIGRATIONS           │
        └────────────────────────────────────────────────┘
```

### Core loops

**Morning (2 min).** Open Today → see weighted load → adjust plan → pick the first task → start timer.
**During the day (5–15 s each).** Interrupt arrives → quick add as Ad-hoc → optionally schedule → return to work. Or tap the running pill to pause.
**End of day (3 min).** Stop timer → Today's auto summary → write two lines in the journal → review tomorrow's load.
**Weekly (10 min).** Insights → category split, drift, weighted output → export markdown review.

---

## 6. Feature specification (v1)

### 6.1 Dashboard — "Today"

- Time-aware greeting and full date; current focus state.
- **Daily pulse ring:** weighted points earned vs daily weight target, plus focus minutes vs focus target.
- **Running timer banner:** task name, elapsed, pause and stop; survives navigation.
- **Schedule:** today's planned tasks ordered by start time, with weight and state.
- **Due soon:** overdue and due-today tasks not already scheduled.
- **Inbox:** unscheduled quick captures waiting for a decision.
- **Quick journal:** markdown composer with autosave for today's log.
- **Momentum:** 7-day focus bars, completion streak, category split.
- Empty/onboarding state with demo-data option.

### 6.2 Planner

- Status board: **Inbox → Planned → In progress → Blocked → Done**.
- Drag a card between columns (desktop and long-press on touch); menu fallback for accessibility.
- Filters: search, category, kind, priority, scheduled date.
- Capacity header for selected day/week: planned points vs target, estimated minutes vs focus target.
- Task card: category colour, title, kind, priority, weight, schedule, subtask progress, tracked time.
- Create/edit sheet with title, markdown notes, category, kind, priority, effort weight, estimate, schedule start/end, due date, and first steps.
- Completing a task with unfinished steps asks how to resolve them.

### 6.3 Task detail

- Inline title and markdown notes (write/preview).
- Checklist: add, toggle, reorder, delete; rolled-up progress.
- Scheduling: planned date, start/end time, due date, estimate.
- Timer: per-task start/pause/stop, session time, total tracked vs estimate.
- Manual time entry for forgotten work (start/end or minutes + note).
- Time entry list with edit/delete.
- Activity trail: created, status changes, completed steps, timer sessions.
- Archive/restore; archive preserves history.

### 6.4 Calendar

- Month grid with per-day scheduled count, due markers, logged time, completion density.
- Day agenda: scheduled timeline, due tasks, completed tasks, journal status, total focus.
- Week strip: seven day columns with load and tasks.
- Navigation: previous/next/today, jump to date, select a day.
- Quick actions: plan a task on this day, open journal.

### 6.5 Journal (Log)

- One markdown entry per local date, autosaved.
- Auto summary block: completed tasks, focus time, weight points, top category. "Insert into note" action.
- Mood/energy capture (optional).
- History list with search, markdown preview, copy/export.
- Backdating through calendar.
- Streak of journaled days.

### 6.6 Stopwatch

- **Global stopwatch:** label, start/pause/resume/stop, today's unassigned focus total, recovery of a forgotten running session, and convert-to-task time entry.
- **Per-task stopwatch:** same controls attached to a task; total tracked is the sum of all its segments.
- Only one timer runs at a time. Starting a new timer prompts to pause the current one.
- Every run stores wall-clock segments, so crashes lose at most the current un-paused segment; on relaunch the session is recovered.
- Timer pill is available on every screen and shows live elapsed time.

### 6.7 Insights

- Range: this week, last 30 days, this month.
- KPIs: focus time, completed tasks, weighted output, completion rate, estimate drift, official vs ad-hoc split.
- Focus per day bar chart; category distribution donut; kind split; weighted load per day.
- 12-week consistency heatmap.
- Weightage formula explained inline.
- Export the selected range as a markdown report.

### 6.8 Categories

- Name, icon, colour, weight (0.5–2.0), archive.
- Task/time totals per category.
- Default set: Deep Work, Meetings, Admin, Learning, Personal.
- Cannot hard-delete a category with tasks; archive instead.

### 6.9 Quick capture & search

- Global "＋" and `Ctrl/Cmd+N`.
- Command palette `Ctrl/Cmd+K`: find tasks/journal, start timer, new task, toggle theme, create backup.
- Inbox status for captures without a plan.

### 6.10 Settings & data

- Display name, daily weight target, daily focus target, week start, theme.
- Backup now (ZIP with `backup.json` + markdown exports); automatic daily backup; backup list with restore and delete.
- Import with validation, automatic pre-restore snapshot, replace-only semantics with explicit confirmation.
- Markdown export of all journals/tasks.
- Demo workspace loader, clear-data with confirmation.
- About, privacy statement, schema version, app version.
- Migration safety: pre-migration snapshot of the database file.

---

## 7. Weightage model

Effort points are deliberately simple and visible:

```
taskPoints = effortWeight (1–5)
           × priorityMultiplier
           × kindMultiplier
           × categoryWeight

priority: Low 0.8 · Normal 1.0 · High 1.3 · Urgent 1.6
kind:     Official 1.0 · Ad-hoc 0.75 · Personal 0.5
category: 0.5–2.0, default 1.0

progress = subtasks ? doneSteps / totalSteps : (done ? 1 : 0)
earnedPoints = taskPoints × progress
```

- **Daily load** = sum of task points for tasks scheduled on the day (regardless of completion).
- **Weighted output** = sum of earned points in the period.
- **Used category weight** rewards strategic categories without pretending all hours are equal.
- Formula is shown in the planner tooltip and Insights card; no hidden game mechanics.
- Priorities affect load; completing an urgent task earns more. Users can tune category weight and their daily target.

Capacity defaults: **25 points/day**, **300 focus minutes/day**. Editable.

---

## 8. Reliability, privacy, and data ownership

- **Storage:** single SQLite database in the app support directory.
- **Transactions:** every multi-row mutation (subtask cascade, import, session stop) is atomic.
- **Foreign keys:** enabled per connection; explicit `ON DELETE` behaviour.
- **Timestamps:** UTC epoch milliseconds; local date keys (`YYYY-MM-DD`) for grouping.
- **Migrations:** sequential, versioned, tested; `PRAGMA user_version`; pre-migration file snapshot.
- **Backups:** versioned format, app fingerprint, schema version, row counts, SHA-256 of canonical JSON, validation before restore, pre-restore snapshot.
- **Deletion:** archive by default; destructive actions require typed confirmation.
- **Privacy:** no network calls in the app. Export happens on explicit action. No analytics.
- **Crash safety:** running timer state persisted; open journal edits autosaved; DB in WAL mode.
- **Testing:** migration, backup round-trip, timer math, weightage, and widget smoke tests.

---

## 9. UI/UX blueprint

See [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md) for tokens, components, and responsive rules.

- **Personality:** an editorial workbench, not a corporate dashboard. Warm paper, deep ink, a persimmon accent, serif display type, generous white space, quiet borders, one strong focal metric per screen.
- **Density:** comfortable by default with a compact option for the planner on desktop.
- **Navigation:** sidebar on desktop, rail on tablet, five-item bottom bar plus "More" on mobile; timer pill floating above navigation.
- **Adaptive dialogs:** bottom sheets with drag handles on mobile, centred dialogs with max-width on larger screens.
- **Feedback:** optimistic toggles, inline validation, undo for destructive-ish actions where feasible, no blocking spinners for local queries.
- **Empty states:** explain the next action and offer sample data, never a blank void.
- **Accessibility:** semantics on icon-only buttons, 44px minimum targets, visible focus rings, text scaling, reduced motion, no colour-only status (icon/label always present).

---

## 10. Delivery plan

**v1 (this build)**
Core ledger, planner with subtasks, calendar, markdown journal, dual stopwatch, categories, weightage, insights, quick capture, command palette, backups/restore, migrations, demo data, tests, desktop + mobile builds.

**v1.1**
Recurring tasks/templates, idle detection on desktop, timer trim suggestions, markdown attachments, CSV export, custom dashboard cards.

**v1.2**
Optional encrypted backup, folder-based backup rotation, import merge mode, calendar ICS export.

**v2**
Opt-in encrypted device sync with conflict-aware merges; team read-only reports; mobile widgets and quick-tile; natural-language quick capture.

---

## 11. Definition of done (v1)

- App runs offline on Android, iOS, and Linux desktop.
- A user can capture work in under 10 seconds, schedule it, break it down, time it, complete it, and write a markdown log.
- Every task and general focus session appears accurately in time totals and calendar/insights.
- Atomic backup export/import round-trips with checksum validation.
- Automated tests pass; `flutter analyze` is clean; no network dependency at runtime.
- Fresh install and demo workspace both look intentional and complete.
