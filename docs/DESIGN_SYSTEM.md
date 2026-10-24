# Daymark — UI/UX & Design System

## 1. Design direction

**Editorial workbench.** Think a well-made paper planner crossed with a precise instrument panel.

- Warm paper surfaces, deep ink text, fine rules.
- A serif display face for moments of reflection; a geometric sans for controls; mono for time.
- One accent (persimmon) reserved for _live_ and _attention_: running timer, overdue, primary action.
- Deep green as the "steady" brand colour: completion, capacity, calm progress.
- Data is shown as quiet bars/rings, never neon dashboards.
- The interface should feel good at 9am and honest at 9pm.

Non-goals: glassmorphism, gradient soup, confetti, cartoon mascots, red-alarm productivity guilt.

---

## 2. Design tokens

### 2.1 Colour

| Token | Light | Dark | Use |
|---|---|---|---|
| `canvas` | `#F4F0E8` | `#121310` | App background |
| `surface` | `#FFFCF6` | `#1A1B17` | Cards, sheets |
| `surfaceRaised` | `#FFFFFF` | `#20211C` | Popovers, focused cards |
| `surfaceSunken` | `#EDE7DB` | `#0D0E0C` | Wells, tracks, code |
| `ink` | `#171712` | `#F2EDE3` | Primary text |
| `inkMuted` | `#6F6A5F` | `#A6A093` | Secondary text |
| `inkFaint` | `#928B7C` | `#7C776B` | Metadata |
| `line` | `#E5DCCB` | `#2D2F28` | Hairlines |
| `lineStrong` | `#D3C7B2` | `#3B3E34` | Emphasised borders |
| `primary` | `#1D5B4F` | `#8FD0BC` | Brand, active nav, progress |
| `primarySoft` | `#DCEBE4` | `#1F3A32` | Selected fills |
| `accent` | `#E2673C` | `#FF986F` | Live timer, attention |
| `accentSoft` | `#FBE4DA` | `#3A241C` | Accent fills |
| `gold` | `#C98A2E` | `#E6B35E` | Personal, warnings |
| `blue` | `#3C6E91` | `#8CB6D2` | Planned, meetings |
| `rose` | `#B4556C` | `#E19AAE` | Blocked, destructive |
| `green` | `#2F7D5B` | `#7FCBAA` | Done, positive delta |

Category palette (12 choices, all contrast-checked on light/dark surfaces):
`#1D5B4F` `#3C6E91` `#7A5CA8` `#B4556C` `#C26A32` `#8A7A2E` `#2F7D5B` `#8E5A3A` `#4F6B78` `#9A4F8C` `#5E6B3A` `#6B5E52`.

Kind semantics:

- **Official** — primary/green, briefcase icon.
- **Ad-hoc** — accent/persimmon, bolt icon.
- **Personal** — gold, sun icon.

Status semantics (always paired with a label/icon):

- Inbox — outline circle, muted.
- Planned — calendar icon, blue.
- In progress — play icon, accent.
- Blocked — slash icon, rose.
- Done — check, green.
- Archived — box, faint.

### 2.2 Typography

Bundled open-source fonts:

- **Newsreader** (variable, 200–800) — display.
- **Manrope** (variable, 200–800) — UI/body.
- **JetBrains Mono** (variable) — timers, durations, numerals, code.

| Style | Font | Size / line | Weight | Notes |
|---|---|---|---|---|
| Display XL | Newsreader | 44 / 48 | 400 | Today hero, onboarding |
| Display L | Newsreader | 34 / 40 | 400 | Page titles |
| Display M | Newsreader | 26 / 32 | 500 | Section heroes |
| Title L | Manrope | 20 / 26 | 700 | Card titles |
| Title M | Manrope | 17 / 24 | 700 | List titles |
| Body | Manrope | 15 / 23 | 450 | Notes, paragraphs |
| Body S | Manrope | 13 / 20 | 450 | Metadata |
| Label | Manrope | 11.5 / 14 | 700 | Uppercase, `.08em` tracking |
| Mono Timer | JetBrains Mono | 40 / 44 | 500 | Stopwatch |
| Mono Data | JetBrains Mono | 13 / 18 | 500 | Tabular numbers |

- Numbers use `FontFeature.tabularFigures()`.
- Minimum body size 13; user text scaling respected. No text inside fixed-height boxes.
- Measure: 68 characters max for prose; journal preview max 720 px.

### 2.3 Spacing, radii, elevation

- Space scale: 2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64.
- Screen padding: 20 compact, 28 medium, 36 expanded. Content max width 1280.
- Radii: 8 (badges), 12 (inputs), 16 (buttons), 20 (cards), 28 (sheets), 999 (pills).
- Borders: 1 px `line`; focused: 1.5 px `primary`.
- Elevation: sheets/popovers only. Shadow `0 18px 50px rgba(23,23,18,.14)` light, `rgba(0,0,0,.5)` dark. Cards rely on border, not shadow.
- Hover: background shifts to `surfaceRaised` + border `lineStrong`; no scale above 1.01.

### 2.4 Motion

- Durations: `fast 120ms`, `base 200ms`, `slow 320ms`.
- Curve: `easeOutCubic` for entrances, `easeInOut` for state changes.
- Timer digits update every second without layout shift (tabular figures).
- Page changes: 180 ms fade/slide 8 px. No bouncing.
- Respect `MediaQuery.disableAnimations`; provide instant fallbacks.
- Reduced motion: charts render final values, sheets fade only.

---

## 3. Responsive behaviour

| Breakpoint | Width | Navigation | Layout |
|---|---|---|---|
| Compact | `< 720` | Bottom bar (5 items) + More sheet; timer pill above | Single column; sheets; full-screen detail |
| Medium | `720–1079` | Navigation rail (icons + tooltips) | 1–2 columns; dialogs max 560; side-by-side list/detail only for journal |
| Expanded | `≥ 1080` | 252 px sidebar with labels + shortcuts + timer card | Max 1280 content; Today 2-col (2:1); Task detail 2-col; Calendar month + agenda |

Rules:

- Never stretch text beyond 720 px.
- Planner board: horizontal scroll with 300 px columns; on compact, default to grouped list with a Board toggle.
- Month grid: cell min 96 px on desktop, 44 px on mobile, weekday initials only when narrow.
- Bottom nav includes safe-area padding; timer pill sits above it and respects inset.
- Dialog adaptive helper: compact → `showModalBottomSheet(isScrollControlled)`, else `showDialog`.

---

## 4. Component library

**`AppScaffold`** — background wash (subtle radial tint top-left), max-width content, optional side rail/panel.

**`BrandMark`** — hand-drawn arc + dot (persimmon) beside "Daymark" wordmark; compact uses symbol only.

**`SurfaceCard`** — 20 radius, 1 px line, surface background, padding 20; variants `sunken`, `accent`, `flat`; optional header with eyebrow/title/action.

**`SectionHeader`** — uppercase tracked label + serif heading + optional action link.

**`StatTile`** — label, large tabular value, unit, delta chip, optional sparkline. One primary stat per row gets accent treatment.

**`PulseRing`** — 180–220 px ring: weighted earned points / target; inner serif percentage; secondary arc for focus minutes; caption "of 25 pts".

**`CapacityBar`** — segmented bar of planned points; over-capacity turns accent with a short explanation, not an error.

**`TaskCard`** — category dot + title + kind icon + priority flag; second row schedule/time/weight; subtask progress hairline; quick play button; supports compact/comfortable, selected, dragging.

**`StatusBadge`, `KindBadge`, `PriorityBadge`, `CategoryChip`** — pill with icon + label; no colour-only meaning.

**`MarkdownEditor`** — Write/Preview segmented control; toolbar (bold, italic, H2, list, checklist, quote, code, link); autosave status ("Saved 2s ago"); character count; focus mode; mobile keyboard-safe toolbar above keyboard.

**`MarkdownView`** — themed `flutter_markdown`: serif H1/H2, sans body, sunken code blocks, persimmon links, task-list checkboxes, blockquote rule, tables horizontally scrollable. No raw HTML.

**`TimerDisplay`** — mono digits `HH:MM:SS`; label; live dot; optional compact variant for the pill.

**`TimerPill`** — floating rounded bar with pulsing dot, elapsed, task/label, pause/stop; contrast against both themes.

**`ChecklistRow`** — custom animated checkbox, strikethrough on complete, drag handle, inline actions.

**`EmptyState`** — geometric line illustration, serif headline, one-sentence explanation, primary + secondary actions.

**`ConfirmSheet`** — danger variant with typed confirmation for destructive data actions.

**`AppTooltip`** — explains weightage, streak, capacity and drift in human language.

**`KeyHint`** — small bordered shortcut glyphs (⌘K).

---

## 5. Screen blueprints

### 5.1 Today (expanded)

```
┌ sidebar ─┐┌───────────────────────────────────────────────────────────┐
│ brand    ││ Saturday, 24 October            [search] [⌘K]      [＋]  │
│ Today ●  ││ Good afternoon, Maya.                                     │
│ Planner  ││ ┌───────────── 2fr ────────────┐ ┌────── 1fr ────────┐  │
│ Calendar ││ │ TODAY'S PULSE                │ │ LIVE              │  │
│ Journal  ││ │  ○ ring 12.4/25 pts          │ │ running timer     │  │
│ Insights ││ │  2h 40m focused · 4 done     │ │ [pause] [stop]    │  │
│ Categories│ │ capacity bar                 │ ├───────────────────┤  │
│ Settings ││ ├──────────────────────────────┤ │ SCHEDULE          │  │
│          ││ │ UP NEXT (3 tasks)            │ │ 09:00 Deep work   │  │
│ [timer]  ││ │ task cards with play         │ │ 11:00 Standup     │  │
│          ││ ├──────────────────────────────┤ │ ...               │  │
│          ││ │ QUICK LOG (markdown)         │ ├───────────────────┤  │
│          ││ └──────────────────────────────┘ │ MOMENTUM / bars   │  │
│          │└───────────────────────────────────┴───────────────────┘  │
└──────────┘
```

Order on compact: greeting → pulse (compact) → running timer → up next → schedule → quick log → momentum.

### 5.2 Planner

- Header: "Planner" serif, date scroller (Mon–Sun), capacity summary.
- Filter row: search pill, category menu, kind chips, priority menu, "Board/List" toggle.
- Board columns each with count + point total; drag states show a dashed target.
- Add card at column bottom.
- Task create/edit sheet: sectioned ("What", "When", "Weight", "Notes"), sticky footer with Cancel / Save.

### 5.3 Task detail

```
← All tasks      [Official] [High]        [⋯]
Title (inline, serif-ish large sans)
┌ notes (markdown, 2fr) ──────────┐ ┌ checklist ──┐
│ Write | Preview                 │ │ 3/7 steps  │
│ ...                             │ │ □ ...      │
│                                 │ ├─ timer ────┤
│                                 │ │ 01:12:44   │
│                                 │ ├─ schedule ─┤
│                                 │ │ Today 9–11 │
└─────────────────────────────────┘ └ time log ───┘
```
Compact: status strip → timer → checklist → notes → schedule → time log → activity.

### 5.4 Calendar

- Expanded: left month grid (flex 3), right selected-day panel (flex 2) with date, focus total, scheduled timeline, due, completed, journal CTA.
- Compact: month grid, selected day sheet/agenda below; segmented Month / Week.
- Today: filled circle in primary; selected: soft primary fill + border; dots capped at 4 with "+N".

### 5.5 Journal

- Expanded: history list 300 px + editor; summary card; mood/energy chips.
- Mobile: timeline list with excerpts → full-screen editor.
- Editor header: date serif, "Saved" state, insert summary, copy markdown.
- Empty state: "The page is blank. Two lines are enough."

### 5.6 Insights

- Range chips + export report.
- KPI row (4 tiles) → focus bar chart → donut + legend → estimation drift → heatmap → formula explainer.
- Charts animate in 320 ms unless reduced motion.

### 5.7 Stopwatch

- Focus-state full page (or desktop panel): huge mono timer on a sunken well, label field, task picker, start/pause/stop, today's sessions, recovery banner.
- Global sessions are unassigned by default; assign to a task when stopping (optional).

---

## 6. Content & tone

- Direct, warm, never scolding.
- Prefer "Nothing planned yet — add the next small step." over "No tasks."
- Over capacity: "That's 32 points for a 25-point day. Move something, or accept a heavier day."
- Timer recovery: "This timer was still running. Keep the 3h 12m, or trim it?"
- Weight: "Size is 1–5. Points also reflect priority, kind, and category."
- Confirmation: "Delete this backup? The file will be removed from this device."
- Empty journal: "Two lines are enough. What moved today?"

---

## 7. Accessibility checklist

- [x] All interactive controls ≥ 44×44 logical px.
- [x] Semantics labels on icon-only buttons; live region for timer.
- [x] Focus order follows visual order; visible 2 px focus ring.
- [x] Status conveyed by icon + text, never colour alone.
- [x] Text scaling to 200% without clipping primary actions.
- [x] Contrast ≥ 4.5:1 for body text in both themes.
- [x] Keyboard shortcuts for capture, search, timer, navigation; Escape closes overlays.
- [x] Reduced-motion respected.
- [x] Charts have adjacent textual summaries.

---

## 8. DX standards

- Feature-first folders with a one-way dependency flow: `features → providers/data/services/core`.
- Design tokens only through `ThemeExtension`/`AppColors`/`AppSpacing`; no hex codes in widgets.
- Reusable primitives before one-off widgets.
- `flutter analyze` clean; formatting enforced.
- Every page has a loading, empty, and error state.
- No `setState` for shared state; Riverpod only.
- Database access only through repositories; no SQL in widgets.
- Every mutation records an activity event where meaningful.
- `Makefile` targets for run/test/analyze/format/build.
- Screenshot checklist for compact/expanded and light/dark before shipping a UI change.
