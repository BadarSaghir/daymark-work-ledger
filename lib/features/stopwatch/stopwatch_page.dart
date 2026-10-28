import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/brand_mark.dart';
import '../../core/ui/enum_ui.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/form.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/menu_action.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../core/utils/durations.dart';
import '../../core/utils/platform.dart';
import '../../data/models/enums.dart';
import '../../data/models/task_view.dart';
import '../../data/models/time_entry.dart';
import '../../state/repository_providers.dart';
import '../../state/stats_providers.dart';
import '../../state/tasks_controller.dart';
import '../../state/timer_controller.dart';
import '../../widgets/timer_dialogs.dart';

class StopwatchPage extends ConsumerStatefulWidget {
  const StopwatchPage({super.key});

  @override
  ConsumerState<StopwatchPage> createState() => _StopwatchPageState();
}

class _StopwatchPageState extends ConsumerState<StopwatchPage> {
  List<TimeEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final today = startOfDay(DateTime.now());
    final entries = await ref
        .read(timerRepositoryProvider)
        .entriesBetween(today, addDays(today, 1));
    if (!mounted) return;
    setState(() {
      _entries = entries.reversed.toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final timer = ref.watch(timerProvider).value;
    final session = timer?.session;
    final active = session != null;
    final today = startOfDay(DateTime.now());
    final focusMs = ref.watch(dayFocusProvider(today)).value ?? 0;
    final views = ref.watch(tasksProvider).value ?? const <TaskView>[];
    final totalToday = _entries.fold<int>(
      0,
      (sum, item) => sum + item.durationMs,
    );
    final generalToday = _entries
        .where((entry) => entry.taskId == null)
        .fold<int>(0, (sum, item) => sum + item.durationMs);
    final taskToday = totalToday - generalToday;
    final isWide = MediaQuery.sizeOf(context).width >= 1060;
    final compact = Layout.isCompact(context);
    final timerLabel = session?.label ?? 'A quiet clock for deep work';
    final timerCategory = session?.taskId == null
        ? null
        : views
                  .where((view) => view.task.id == session!.taskId)
                  .firstOrNull
                  ?.category
                  ?.name ??
              'Task';
    final timerKind = session == null
        ? null
        : session.kind == TimerKind.task
        ? 'TASK TIMER'
        : 'GENERAL TIMER';

    Future<void> toggleTimer() async {
      final current = timer;
      if (current == null) return;
      if (current.isRunning) {
        await ref.read(timerProvider.notifier).pause();
        _load();
      } else {
        await ref.read(timerProvider.notifier).resume();
      }
    }

    void showRitual() {
      showAppSheet<void>(
        context,
        (sheetContext) => AppSheet(
          title: 'Before you start',
          subtitle: 'A small ritual for deliberate attention.',
          icon: Icons.tips_and_updates_outlined,
          onClose: () => Navigator.of(sheetContext).pop(),
          child: const _RitualList(),
        ),
        maxWidth: 520,
      );
    }

    void showTodayLog() {
      showAppSheet<void>(
        context,
        (sheetContext) => AppSheet(
          title: 'Today’s log',
          subtitle:
              '${_entries.length} '
              '${_entries.length == 1 ? 'entry' : 'entries'} · '
              '${formatCompactMs(totalToday)} logged',
          icon: Icons.history_rounded,
          onClose: () => Navigator.of(sheetContext).pop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TodaySummary(
                totalMs: focusMs > totalToday ? focusMs : totalToday,
                generalMs: generalToday,
                taskMs: taskToday,
                onRefresh: _load,
                showRefresh: false,
              ),
              const SizedBox(height: AppSpace.lg),
              if (_loading)
                const LoadingBlock(height: 100)
              else if (_entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
                  child: Text(
                    'No time logged today. Start the clock for one honest '
                    'block — the log can wait.',
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall.copyWith(
                      color: sheetContext.colors.inkMuted,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                  ),
                )
              else
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < _entries.length; index++)
                        _EntryRow(
                          entry: _entries[index],
                          task: _entries[index].taskId == null
                              ? null
                              : views
                                    .where(
                                      (view) =>
                                          view.task.id ==
                                          _entries[index].taskId,
                                    )
                                    .firstOrNull,
                          last: index == _entries.length - 1,
                          onDelete: () {
                            Navigator.of(sheetContext).pop();
                            _deleteEntry(_entries[index]);
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        maxWidth: 560,
      );
    }

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          eyebrow: 'One clock, one intention',
          title: 'Focus',
          subtitle:
              'Start when you begin. Pause when you leave. The ledger keeps '
              'the honest shape of your attention.',
          actions: [
            OutlinedButton.icon(
              onPressed: _showManualEntry,
              icon: const Icon(Icons.edit_calendar_outlined, size: 17),
              label: const Text('Log by hand'),
            ),
            if (!active)
              FilledButton.icon(
                onPressed: () => _startFocus(),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Start focus'),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        _FocusTimerCard(
          active: active,
          running: timer?.isRunning ?? false,
          label: timerLabel,
          category: timerCategory,
          taskType: timerKind,
          elapsed: timer?.elapsed ?? Duration.zero,
          compact: false,
          onStart: _startFocus,
          onToggle: toggleTimer,
          onStop: _stopFlow,
          onDiscard: _discard,
        ),
        const SizedBox(height: AppSpace.xl),
        _TodaySummary(
          totalMs: focusMs > totalToday ? focusMs : totalToday,
          generalMs: generalToday,
          taskMs: taskToday,
          onRefresh: _load,
        ),
        const SizedBox(height: AppSpace.xxl),
        Row(
          children: [
            Text(
              'TODAY’S LOG',
              style: AppText.label.copyWith(color: colors.inkFaint),
            ),
            const Spacer(),
            Text(
              '${_entries.length} ${_entries.length == 1 ? 'entry' : 'entries'}',
              style: AppText.monoData.copyWith(
                color: colors.inkFaint,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        if (_loading)
          const LoadingBlock(height: 120)
        else if (_entries.isEmpty)
          EmptyState(
            compact: true,
            icon: Icons.timer_outlined,
            title: 'No time logged today',
            message:
                'The clock is not a judge. Start it for one honest block and '
                'see what the day actually holds.',
            action: active
                ? null
                : FilledButton.icon(
                    onPressed: () => _startFocus(),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Start focus'),
                  ),
          )
        else
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < _entries.length; index++)
                  _EntryRow(
                    entry: _entries[index],
                    task: _entries[index].taskId == null
                        ? null
                        : views
                              .where(
                                (view) =>
                                    view.task.id == _entries[index].taskId,
                              )
                              .firstOrNull,
                    last: index == _entries.length - 1,
                    onDelete: () => _deleteEntry(_entries[index]),
                  ),
              ],
            ),
          ),
      ],
    );

    final rail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A SMALL RITUAL',
                style: AppText.label.copyWith(color: colors.inkFaint),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Before you start',
                style: AppText.displayS.copyWith(color: colors.ink),
              ),
              const SizedBox(height: AppSpace.sm),
              const _RitualList(),
            ],
          ),
        ),
        if (!Layout.isCompact(context) && AppPlatform.showsKeyboardHints) ...[
          const SizedBox(height: AppSpace.lg),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SHORTCUTS',
                  style: AppText.label.copyWith(color: colors.inkFaint),
                ),
                const SizedBox(height: AppSpace.md),
                _Shortcut(label: 'Command palette', keys: '⌘ K'),
                _Shortcut(label: 'Capture work', keys: '⌘ N'),
                _Shortcut(label: 'Today', keys: '⌘ 1'),
                _Shortcut(label: 'Focus', keys: '⌘ 5'),
                const SizedBox(height: AppSpace.md),
                Text(
                  'On Windows and Linux, use Ctrl instead of ⌘.',
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (compact) {
      final size = MediaQuery.sizeOf(context);
      final landscape = size.width > size.height;
      final todayMs = focusMs > totalToday ? focusMs : totalToday;

      if (landscape) {
        // Landscape phones have very little vertical room once the app bar and
        // bottom nav are accounted for. Lay the clock out sideways and keep the
        // log behind an icon so nothing needs to scroll.
        return PageWidth(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.sm,
            AppSpace.lg,
            AppSpace.x3,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: _FocusTimerCard(
                      active: active,
                      running: timer?.isRunning ?? false,
                      label: timerLabel,
                      category: timerCategory,
                      taskType: timerKind,
                      elapsed: timer?.elapsed ?? Duration.zero,
                      compact: true,
                      landscape: true,
                      dialSize: 168,
                      onStart: _startFocus,
                      onToggle: toggleTimer,
                      onStop: _stopFlow,
                      onDiscard: _discard,
                      onManual: _showManualEntry,
                      onRitual: showRitual,
                      onLog: showTodayLog,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }

      return PageWidth(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.sm,
          AppSpace.lg,
          AppSpace.x4,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CompactFocusTopBar(
                  active: active,
                  running: timer?.isRunning ?? false,
                  onManual: _showManualEntry,
                  onRitual: showRitual,
                ),
                const SizedBox(height: AppSpace.md),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: _FocusTimerCard(
                          active: active,
                          running: timer?.isRunning ?? false,
                          label: timerLabel,
                          category: timerCategory,
                          taskType: timerKind,
                          elapsed: timer?.elapsed ?? Duration.zero,
                          compact: true,
                          dialSize: 240,
                          onStart: _startFocus,
                          onToggle: toggleTimer,
                          onStop: _stopFlow,
                          onDiscard: _discard,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                _CompactTodayRow(
                  totalMs: todayMs,
                  count: _entries.length,
                  onTap: showTodayLog,
                ),
              ],
            );
          },
        ),
      );
    }

    return PageWidth(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: AppSpace.x6),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: main),
                  const SizedBox(width: AppSpace.x3),
                  SizedBox(width: 310, child: rail),
                ],
              )
            : Column(
                children: [
                  main,
                  const SizedBox(height: AppSpace.xl),
                  rail,
                ],
              ),
      ),
    );
  }

  Future<void> _startFocus() async {
    await showStartFocusDialog(context, ref);
    if (!mounted) return;
    await _load();
  }

  Future<void> _stopFlow() async {
    final timer = ref.read(timerProvider).value;
    final session = timer?.session;
    if (session == null || timer == null) return;
    final elapsed = timer.elapsed;
    final views = ref.read(tasksProvider).value ?? const <TaskView>[];
    final request = await showAppSheet<_StopRequest>(
      context,
      (sheetContext) => _StopSheet(
        initialLabel: session.label,
        initialTaskId: session.taskId,
        elapsed: elapsed,
        tasks: views,
      ),
      maxWidth: 540,
    );
    if (request == null) return;
    await ref
        .read(timerProvider.notifier)
        .stop(
          assignTaskId: request.taskId,
          label: request.label,
          note: request.note,
        );
    ref.invalidate(tasksProvider);
    invalidateStatsWidget(ref);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    showToast(context, 'Saved · ${formatCompactMs(elapsed.inMilliseconds)}');
  }

  Future<void> _discard() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Discard this timer?',
      message: 'The time will be removed without being logged. This cannot be undone.',
      confirmLabel: 'Discard',
      danger: true,
      icon: Icons.delete_sweep_outlined,
    );
    if (!confirmed) return;
    await ref.read(timerProvider.notifier).discard();
    if (!mounted) return;
    await _load();
    if (mounted) showToast(context, 'Timer discarded');
  }

  Future<void> _deleteEntry(TimeEntry entry) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this entry?',
      message:
          '${formatCompactMs(entry.durationMs)} on “${entry.label}” will be removed '
          'from the ledger.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!confirmed) return;
    await ref.read(timerRepositoryProvider).deleteEntry(entry.id);
    ref.invalidate(tasksProvider);
    invalidateStatsWidget(ref);
    if (!mounted) return;
    await _load();
  }

  Future<void> _showManualEntry() async {
    final saved = await showAppSheet<bool>(
      context,
      (sheetContext) => const _ManualEntrySheet(),
      maxWidth: 540,
    );
    if (saved == true) {
      ref.invalidate(tasksProvider);
      invalidateStatsWidget(ref);
      await _load();
    }
  }
}

class _FocusTimerCard extends StatelessWidget {
  const _FocusTimerCard({
    required this.active,
    required this.running,
    required this.label,
    required this.elapsed,
    required this.compact,
    required this.onStart,
    required this.onToggle,
    required this.onStop,
    required this.onDiscard,
    this.category,
    this.taskType,
    this.dialSize = 300,
    this.landscape = false,
    this.onManual,
    this.onRitual,
    this.onLog,
  });

  final bool active;
  final bool running;
  final String label;
  final String? category;
  final String? taskType;
  final Duration elapsed;
  final bool compact;

  /// Lays the clock out sideways for short, wide phone screens.
  final bool landscape;
  final double dialSize;
  final VoidCallback onStart;
  final Future<void> Function() onToggle;
  final VoidCallback onStop;
  final VoidCallback onDiscard;
  final VoidCallback? onManual;
  final VoidCallback? onRitual;
  final VoidCallback? onLog;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = active ? colors.canvas : colors.ink;
    final faint = active
        ? colors.canvas.withValues(alpha: 0.55)
        : colors.inkFaint;

    if (landscape) {
      return Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: _cardDecoration(colors),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TimerDial(
              elapsed: elapsed,
              active: active,
              running: running,
              size: dialSize,
            ),
            const SizedBox(width: AppSpace.xl),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statusLine(colors, faint),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.displayS.copyWith(
                      color: foreground,
                      fontSize: 19,
                    ),
                  ),
                  if (active && category != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      category!,
                      style: AppText.label.copyWith(
                        color: colors.accent,
                        fontSize: 8.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpace.md),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onLog != null)
                        IconButton.filledTonal(
                          tooltip: 'Today’s log',
                          onPressed: onLog,
                          icon: const Icon(Icons.history_rounded, size: 18),
                        ),
                      if (onManual != null) ...[
                        const SizedBox(width: AppSpace.sm),
                        IconButton.filledTonal(
                          tooltip: 'Log time by hand',
                          onPressed: onManual,
                          icon: const Icon(
                            Icons.edit_calendar_outlined,
                            size: 18,
                          ),
                        ),
                      ],
                      if (onRitual != null) ...[
                        const SizedBox(width: AppSpace.sm),
                        IconButton.filledTonal(
                          tooltip: 'Before you start',
                          onPressed: onRitual,
                          icon: const Icon(
                            Icons.tips_and_updates_outlined,
                            size: 18,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  SizedBox(width: 292, child: _compactActions(colors)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(compact ? AppSpace.lg : AppSpace.xxl),
      decoration: _cardDecoration(colors),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              LiveDot(
                color: active
                    ? (running ? colors.accent : colors.gold)
                    : colors.inkFaint,
                size: 7,
              ),
              const SizedBox(width: 7),
              Text(
                active ? (running ? 'RUNNING' : 'PAUSED') : 'READY',
                style: AppText.label.copyWith(color: faint, fontSize: 9),
              ),
              const Spacer(),
              if (taskType != null)
                Text(
                  taskType!,
                  style: AppText.label.copyWith(
                    color: active
                        ? colors.canvas.withValues(alpha: 0.45)
                        : colors.inkFaint,
                    fontSize: 8.5,
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? AppSpace.sm : AppSpace.md),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.displayS.copyWith(
              color: foreground,
              fontSize: compact ? 20 : 23,
            ),
          ),
          if (active && category != null) ...[
            const SizedBox(height: 4),
            Text(
              category!,
              style: AppText.label.copyWith(
                color: colors.accent,
                fontSize: 8.5,
              ),
            ),
          ],
          SizedBox(height: compact ? AppSpace.md : AppSpace.xl),
          _TimerDial(
            elapsed: elapsed,
            active: active,
            running: running,
            size: dialSize,
          ),
          SizedBox(height: compact ? AppSpace.md : AppSpace.xl),
          if (compact)
            _compactActions(colors)
          else if (!active)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(160, 50),
              ),
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Start focus'),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: running ? colors.gold : colors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(132, 50),
                  ),
                  onPressed: () => onToggle(),
                  icon: Icon(
                    running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 19,
                  ),
                  label: Text(running ? 'Pause' : 'Resume'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.canvas,
                    side: BorderSide(
                      color: colors.canvas.withValues(alpha: 0.25),
                    ),
                    minimumSize: const Size(150, 50),
                  ),
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_rounded, size: 19),
                  label: const Text('Stop & save'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: colors.canvas.withValues(alpha: 0.55),
                  ),
                  onPressed: onDiscard,
                  child: const Text('Discard'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration(AppColors colors) => BoxDecoration(
    color: active ? colors.ink : colors.surface,
    borderRadius: BorderRadius.circular(AppRadius.sheet),
    border: Border.all(color: active ? colors.ink : colors.line),
  );

  Widget _statusLine(AppColors colors, Color faint) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiveDot(
          color: active
              ? (running ? colors.accent : colors.gold)
              : colors.inkFaint,
          size: 7,
        ),
        const SizedBox(width: 7),
        Text(
          active ? (running ? 'RUNNING' : 'PAUSED') : 'READY',
          style: AppText.label.copyWith(color: faint, fontSize: 9),
        ),
        if (taskType != null) ...[
          const SizedBox(width: AppSpace.sm),
          Text(
            '· $taskType',
            style: AppText.label.copyWith(
              color: faint.withValues(alpha: 0.8),
              fontSize: 8.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _compactActions(AppColors colors) {
    if (!active) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
        ),
        onPressed: onStart,
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: const Text('Start focus'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: running ? colors.gold : colors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () => onToggle(),
            icon: Icon(
              running ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 19,
            ),
            label: Text(running ? 'Pause' : 'Resume'),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.canvas,
              side: BorderSide(color: colors.canvas.withValues(alpha: 0.25)),
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: onStop,
            icon: const Icon(Icons.stop_rounded, size: 19),
            label: const Text('Stop'),
          ),
        ),
        IconButton(
          tooltip: 'Discard',
          onPressed: onDiscard,
          color: colors.canvas.withValues(alpha: 0.55),
          icon: const Icon(Icons.delete_outline_rounded, size: 19),
        ),
      ],
    );
  }
}

class _CompactFocusTopBar extends StatelessWidget {
  const _CompactFocusTopBar({
    required this.active,
    required this.running,
    required this.onManual,
    required this.onRitual,
  });

  final bool active;
  final bool running;
  final VoidCallback onManual;
  final VoidCallback onRitual;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        LiveDot(
          color: active
              ? (running ? colors.accent : colors.gold)
              : colors.inkFaint,
          size: 7,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                active ? (running ? 'IN SESSION' : 'PAUSED') : 'READY TO FOCUS',
                style: AppText.label.copyWith(
                  color: active ? colors.accent : colors.inkFaint,
                  fontSize: 9,
                ),
              ),
              Text(
                active
                    ? 'The clock is keeping this block.'
                    : 'One clock, one intention.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Log time by hand',
          onPressed: onManual,
          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
        ),
        const SizedBox(width: 4),
        IconButton.filledTonal(
          tooltip: 'Before you start',
          onPressed: onRitual,
          icon: const Icon(Icons.tips_and_updates_outlined, size: 18),
        ),
      ],
    );
  }
}

class _CompactTodayRow extends StatelessWidget {
  const _CompactTodayRow({
    required this.totalMs,
    required this.count,
    required this.onTap,
  });

  final int totalMs;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      onTap: onTap,
      semanticLabel: 'Open today’s log',
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history_rounded, size: 18, color: colors.primary),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today’s log',
                  style: AppText.titleM.copyWith(
                    color: colors.ink,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  count == 0
                      ? 'No time logged yet'
                      : '${formatCompactMs(totalMs)} · $count '
                            '${count == 1 ? 'entry' : 'entries'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10.6,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: colors.inkFaint),
        ],
      ),
    );
  }
}

class _TimerDial extends StatelessWidget {
  const _TimerDial({
    required this.elapsed,
    required this.active,
    required this.running,
    this.size = 300,
  });

  final Duration elapsed;
  final bool active;
  final bool running;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DialPainter(
          color: running ? colors.accent : colors.inkFaint,
          track: active
              ? colors.canvas.withValues(alpha: 0.09)
              : colors.surfaceSunken,
          seconds: elapsed.inSeconds,
          active: active,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatStopwatch(elapsed),
                style: AppText.monoHuge.copyWith(
                  fontSize: 42,
                  letterSpacing: -2,
                  color: active ? colors.canvas : colors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                active
                    ? (running ? 'in progress' : 'paused')
                    : 'ready when you are',
                style: AppText.bodySmall.copyWith(
                  color: active
                      ? colors.canvas.withValues(alpha: 0.45)
                      : colors.inkFaint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.color,
    required this.track,
    required this.seconds,
    required this.active,
  });

  final Color color;
  final Color track;
  final int seconds;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 14;
    final tick = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    for (var i = 0; i < 60; i++) {
      final angle = (i / 60) * math.pi * 2 - math.pi / 2;
      final major = i % 5 == 0;
      final inner = radius - (major ? 9 : 5);
      tick.color = i / 60 <= (seconds % 3600) / 3600 ? color : track;
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * inner,
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        tick,
      );
    }
    final ringPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius - 22, ringPaint);
    if (active) {
      final dotPaint = Paint()..color = color;
      final angle = -math.pi / 2 + (seconds % 60) / 60 * math.pi * 2;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * (radius - 14),
        3.2,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) =>
      oldDelegate.seconds != seconds ||
      oldDelegate.active != active ||
      oldDelegate.color != color;
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({
    required this.totalMs,
    required this.generalMs,
    required this.taskMs,
    required this.onRefresh,
    this.showRefresh = true,
  });

  final int totalMs;
  final int generalMs;
  final int taskMs;
  final VoidCallback onRefresh;
  final bool showRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: AppSpace.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryMetric(
              label: 'Total logged',
              value: formatCompactMs(totalMs),
              color: colors.ink,
            ),
          ),
          Container(width: 1, height: 32, color: colors.line),
          const SizedBox(width: AppSpace.xl),
          Expanded(
            child: _SummaryMetric(
              label: 'Task time',
              value: formatCompactMs(taskMs),
              color: colors.primary,
            ),
          ),
          Container(width: 1, height: 32, color: colors.line),
          const SizedBox(width: AppSpace.xl),
          Expanded(
            child: _SummaryMetric(
              label: 'Unassigned',
              value: formatCompactMs(generalMs),
              color: colors.accent,
            ),
          ),
          if (showRefresh)
            IconButton(
              tooltip: 'Refresh log',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppText.label.copyWith(color: colors.inkFaint, fontSize: 8.5),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppText.monoLarge.copyWith(color: color, fontSize: 20),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.task,
    required this.last,
    required this.onDelete,
  });

  final TimeEntry entry;
  final TaskView? task;
  final bool last;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.md,
      ),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: (task?.category?.colorValue ?? colors.accent).withValues(
                alpha: 0.11,
              ),
              borderRadius: BorderRadius.circular(AppRadius.badge),
            ),
            child: Icon(
              task == null ? Icons.bolt_rounded : Icons.task_alt_rounded,
              size: 15,
              color: task?.category?.colorValue ?? colors.accent,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label.isEmpty ? 'Untitled focus' : entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyMedium.copyWith(color: colors.ink),
                ),
                const SizedBox(height: 1),
                Text(
                  '${timeLabel(entry.startedAt)}–${timeLabel(entry.endedAt)}'
                  '${task != null ? ' · ${task!.task.title}' : ' · unassigned'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatCompactMs(entry.durationMs),
            style: AppText.monoData.copyWith(color: colors.ink, fontSize: 12),
          ),
          PopupMenuButton<String>(
            tooltip: 'Entry options',
            icon: Icon(
              Icons.more_horiz_rounded,
              size: 17,
              color: colors.inkFaint,
            ),
            onSelected: (value) {
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'delete',
                child: MenuAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete entry',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StopRequest {
  const _StopRequest({required this.label, required this.note, this.taskId});

  final String label;
  final String note;
  final String? taskId;
}

class _StopSheet extends ConsumerStatefulWidget {
  const _StopSheet({
    required this.initialLabel,
    required this.initialTaskId,
    required this.elapsed,
    required this.tasks,
  });

  final String initialLabel;
  final String? initialTaskId;
  final Duration elapsed;
  final List<TaskView> tasks;

  @override
  ConsumerState<_StopSheet> createState() => _StopSheetState();
}

class _StopSheetState extends ConsumerState<_StopSheet> {
  late final TextEditingController _label = TextEditingController(
    text: widget.initialLabel,
  );
  late final TextEditingController _note = TextEditingController();
  late String? _taskId = widget.initialTaskId;

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final task = widget.tasks
        .where((view) => view.task.id == _taskId)
        .firstOrNull;
    return AppSheet(
      title: 'Stop and save',
      subtitle: formatCompact(widget.elapsed),
      icon: Icons.stop_circle_outlined,
      footer: Row(
        children: [
          Text(
            formatStopwatch(widget.elapsed),
            style: AppText.monoData.copyWith(color: colors.inkMuted),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: AppSpace.sm),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(
              _StopRequest(
                label: _label.text.trim().isEmpty
                    ? 'Focus'
                    : _label.text.trim(),
                note: _note.text.trim(),
                taskId: _taskId,
              ),
            ),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Save time'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormLabel('What was this?'),
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'A name for the time'),
          ),
          const SizedBox(height: AppSpace.lg),
          const FormLabel('Note', hint: 'Optional'),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Where you left off, what shifted…',
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          const FormLabel('Attach to a task', hint: 'Optional'),
          InkWell(
            onTap: () async {
              final result = await showTaskPicker(
                context,
                ref,
                title: 'Attach this time',
                message: 'Choose the task this block belongs to.',
                allowNone: true,
              );
              if (result != null) {
                setState(() => _taskId = result.isEmpty ? null : result);
              }
            },
            borderRadius: BorderRadius.circular(AppRadius.input),
            child: Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(color: colors.line),
              ),
              child: Row(
                children: [
                  Icon(
                    task == null
                        ? Icons.link_off_rounded
                        : Icons.task_alt_rounded,
                    size: 17,
                    color: colors.inkMuted,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      task?.task.title ?? 'Keep as unassigned focus',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodySmall.copyWith(
                        color: task == null ? colors.inkFaint : colors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: colors.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualEntrySheet extends ConsumerStatefulWidget {
  const _ManualEntrySheet();

  @override
  ConsumerState<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends ConsumerState<_ManualEntrySheet> {
  final _label = TextEditingController();
  final _note = TextEditingController();
  DateTime _start = DateTime.now().subtract(const Duration(hours: 1));
  DateTime _end = DateTime.now();
  String? _taskId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_end.isAfter(_start)) {
      setState(() => _error = 'The end must be after the start.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(timerRepositoryProvider)
          .addManualEntry(
            taskId: _taskId,
            label: _label.text,
            note: _note.text,
            startedAt: _start,
            endedAt: _end,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    setState(() {
      final base = startOfDay(DateTime.now());
      final value = DateTime(
        base.year,
        base.month,
        base.day,
        picked.hour,
        picked.minute,
      );
      if (start) {
        _start = value;
      } else {
        _end = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final views = ref.watch(tasksProvider).value ?? const <TaskView>[];
    final task = views.where((view) => view.task.id == _taskId).firstOrNull;
    return AppSheet(
      title: 'Log time by hand',
      subtitle: 'For the work that happened away from the clock.',
      icon: Icons.edit_calendar_outlined,
      footer: Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: AppSpace.sm),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text('Save entry'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormLabel('What did you work on?'),
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'A short label'),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FormLabel('Start'),
                    OutlinedButton(
                      onPressed: () => _pickTime(start: true),
                      child: Text(timeLabel(_start)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FormLabel('End'),
                    OutlinedButton(
                      onPressed: () => _pickTime(start: false),
                      child: Text(timeLabel(_end)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FormLabel('Duration'),
                    Text(
                      formatCompact(_end.difference(_start)),
                      style: AppText.monoData.copyWith(
                        color: colors.ink,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          const FormLabel('Task', hint: 'Optional'),
          InkWell(
            onTap: () async {
              final result = await showTaskPicker(
                context,
                ref,
                title: 'Attach this time',
                message: 'Choose the task this block belongs to.',
                allowNone: true,
              );
              if (result != null) {
                setState(() => _taskId = result.isEmpty ? null : result);
              }
            },
            borderRadius: BorderRadius.circular(AppRadius.input),
            child: Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      task?.task.title ?? 'Unassigned focus',
                      style: AppText.bodySmall.copyWith(
                        color: task == null ? colors.inkFaint : colors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 17),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          const FormLabel('Note', hint: 'Optional'),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'What you did'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              _error!,
              style: AppText.bodySmall.copyWith(color: colors.rose),
            ),
          ],
        ],
      ),
    );
  }
}

class _RitualList extends StatelessWidget {
  const _RitualList();

  static const _items = [
    'Name the one thing you are doing.',
    'Close the tabs that are not part of it.',
    'Decide what “done enough” means.',
    'Start the clock and leave it alone.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkMuted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.label, required this.keys});

  final String label;
  final String keys;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppText.bodySmall.copyWith(color: colors.inkMuted),
            ),
          ),
          KeyHint(keys),
        ],
      ),
    );
  }
}
