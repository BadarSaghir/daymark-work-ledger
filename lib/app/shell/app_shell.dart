import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/brand_mark.dart';
import '../../core/ui/surface_card.dart';
import '../../core/ui/layout.dart';
import '../../features/calendar/calendar_page.dart';
import '../../features/categories/categories_page.dart';
import '../../features/accounts/local_account_ui.dart';
import '../../features/insights/insights_page.dart';
import '../../features/journal/journal_page.dart';
import '../../features/nearby/nearby_page.dart';
import '../../features/planner/planner_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/stopwatch/stopwatch_page.dart';
import '../../data/models/task_view.dart';
import '../../data/services/backup_service.dart';
import '../../features/today/today_page.dart';
import '../../state/backup_controller.dart';
import '../../state/local_account_controller.dart';
import '../../state/repository_providers.dart';
import '../../state/settings_controller.dart';
import '../../state/tasks_controller.dart';
import '../../state/timer_controller.dart';
import '../../state/notification_controller.dart';
import '../../state/ui_state.dart';
import '../../widgets/quick_capture.dart';
import '../../widgets/task_editor.dart';
import '../../widgets/timer_pill.dart';
import '../nav.dart';
import 'command_palette.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Timer? _reminderDebounce;
  ProviderSubscription<AsyncValue<List<TaskView>>>? _taskSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoBackup();
      _syncReminders();
    });
    _taskSubscription = ref.listenManual(tasksProvider, (previous, next) {
      if (next.hasValue) _queueReminderSync();
    });
  }

  @override
  void dispose() {
    _reminderDebounce?.cancel();
    _taskSubscription?.close();
    super.dispose();
  }

  void _queueReminderSync() {
    if (!ref.read(remindersEnabledProvider)) return;
    final preferences = ref.read(reminderControllerProvider).value;
    if (preferences?.enabled != true) return;
    _reminderDebounce?.cancel();
    _reminderDebounce = Timer(const Duration(seconds: 2), _syncReminders);
  }

  Future<void> _syncReminders() async {
    if (!ref.read(remindersEnabledProvider)) return;
    try {
      final preferences = await ref.read(reminderControllerProvider.future);
      if (!preferences.enabled) return;
      await ref.read(reminderControllerProvider.notifier).syncNow();
    } catch (_) {
      // Reminder support is optional and must never break the workspace.
    }
  }

  Future<void> _autoBackup() async {
    try {
      final settings = await ref.read(settingsProvider.future);
      if (!settings.onboarded) return;

      BackupResult? localBackup;
      if (settings.autoBackup) {
        final service = await ref.read(backupServiceProvider.future);
        localBackup = await service.maybeCreateDailyBackup(settings);
        if (localBackup?.file != null) {
          await ref
              .read(settingsProvider.notifier)
              .markBackupAt(DateTime.now());
          ref.invalidate(backupListProvider);
        }
      }

      // Drive mirroring is independent of the local daily-backup switch.
      final drive = await ref.read(googleDriveServiceProvider.future);
      final config = await drive.loadConfig();
      if (!config.autoUpload || !config.hasAccount) return;
      final file = localBackup?.file;
      if (file != null) {
        await drive.uploadBackup(file, accountId: config.activeAccountId);
      } else {
        await drive.autoUploadIfDue();
      }
    } catch (_) {
      // A failed automatic backup must never interrupt the workspace.
    }
  }

  void _go(int index) {
    ref.read(navIndexProvider.notifier).state = index;
  }

  void _openPalette() {
    ref.read(commandPaletteOpenProvider.notifier).state = true;
  }

  void _closePalette() {
    ref.read(commandPaletteOpenProvider.notifier).state = false;
  }

  void _openTaskEditor() {
    showTaskEditor(context, initialDate: DateTime.now());
  }

  void _capture() {
    showQuickCapture(context, plannedDate: DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppBreakpoints.compact;
    final expanded = width >= AppBreakpoints.expanded;
    final index = ref.watch(navIndexProvider);
    final paletteOpen = ref.watch(commandPaletteOpenProvider);
    final settings = ref.watch(settingsProvider).value;
    final taskViews = ref.watch(tasksProvider).value ?? const <TaskView>[];
    final openToday = taskViews
        .forDate(DateTime.now())
        .where((view) => !view.isDone)
        .length;
    final timerActive = ref.watch(timerProvider).value?.hasSession ?? false;

    final pages = const [
      TodayPage(),
      PlannerPage(),
      CalendarPage(),
      JournalPage(),
      StopwatchPage(),
      InsightsPage(),
      CategoriesPage(),
      SettingsPage(),
      NearbyPage(),
    ];
    final page = IndexedStack(index: index, children: pages);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _capture,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _capture,
        const SingleActivator(LogicalKeyboardKey.escape): _closePalette,
        for (var i = 0; i < NavLabels.titles.length; i++)
          SingleActivator(
            LogicalKeyboardKey(0x00000031 + i),
            control: true,
          ): () =>
              _go(i),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: context.colors.canvas,
          body: Row(
            children: [
              if (expanded)
                _Sidebar(
                  index: index,
                  openToday: openToday,
                  displayName: settings?.displayName ?? '',
                  onGo: _go,
                  onCapture: _capture,
                  onNewTask: _openTaskEditor,
                  onPalette: _openPalette,
                  onAccount: () => showLocalAccountSwitcher(context),
                )
              else if (!compact)
                _Rail(
                  index: index,
                  openToday: openToday,
                  onGo: _go,
                  onPalette: _openPalette,
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: CanvasWash(child: page)),
                    Positioned(
                      right: compact ? AppSpace.lg : AppSpace.xxl,
                      bottom: AppSpace.xxl,
                      child: TimerPill(
                        onOpen: () => _go(NavTarget.focus),
                        compact: compact,
                      ),
                    ),
                    if (paletteOpen)
                      Positioned.fill(
                        child: CommandPalette(onClose: _closePalette),
                      ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: compact
              ? _BottomBar(
                  index: index,
                  openToday: openToday,
                  timerActive: timerActive,
                  onGo: _go,
                  onMore: () => _showMore(context),
                )
              : null,
        ),
      ),
    );
  }

  void _showMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (sheetContext) {
        final colors = sheetContext.colors;
        final local = ref.read(localAccountProvider);
        final items = const [
          (NavTarget.calendar, Icons.calendar_month_outlined, 'Calendar'),
          (NavTarget.journal, Icons.edit_note_rounded, 'Journal'),
          (NavTarget.insights, Icons.insights_rounded, 'Insights'),
          (NavTarget.categories, Icons.category_outlined, 'Categories'),
          (NavTarget.nearby, Icons.sync_rounded, 'Nearby & sync'),
          (NavTarget.settings, Icons.settings_outlined, 'Settings'),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            AppSpace.md,
            AppSpace.xl,
            AppSpace.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpace.lg),
                  decoration: BoxDecoration(
                    color: colors.lineStrong,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text(
                'More of Daymark',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpace.md),
              if (local != null) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.switch_account_rounded,
                    size: 20,
                    color: colors.primary,
                  ),
                  title: Text('Local account · ${local.active.name}'),
                  subtitle: Text(
                    '${local.accounts.length} remembered on this device',
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkFaint,
                      fontSize: 10.5,
                    ),
                  ),
                  trailing: const Icon(Icons.unfold_more_rounded, size: 18),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showLocalAccountSwitcher(context);
                  },
                ),
                Divider(color: colors.line),
                const SizedBox(height: AppSpace.sm),
              ],
              for (final (target, icon, label) in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon, size: 20),
                  title: Text(label),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _go(target);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.openToday,
    required this.displayName,
    required this.onGo,
    required this.onCapture,
    required this.onNewTask,
    required this.onPalette,
    required this.onAccount,
  });

  final int index;
  final int openToday;
  final String displayName;
  final ValueChanged<int> onGo;
  final VoidCallback onCapture;
  final VoidCallback onNewTask;
  final VoidCallback onPalette;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final initial = displayName.trim().isEmpty
        ? 'D'
        : displayName.trim().characters.first.toUpperCase();
    return Container(
      width: 242,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.72),
        border: Border(right: BorderSide(color: colors.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.xl,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: BrandMark(
                size: 30,
                showWordmark: true,
                onTap: () => onGo(NavTarget.today),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: FilledButton.icon(
                onPressed: onNewTask,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New task'),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: OutlinedButton.icon(
                onPressed: () => onGo(NavTarget.nearby),
                icon: const Icon(Icons.sync_rounded, size: 17),
                label: const Text('Sync nearby'),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: InkWell(
                onTap: onPalette,
                borderRadius: BorderRadius.circular(AppRadius.input),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.sm,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    border: Border.all(color: colors.line),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 15,
                        color: colors.inkFaint,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Search or jump',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySmall.copyWith(
                            color: colors.inkFaint,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const KeyHint('⌘K'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                children: [
                  _GroupLabel('WORK'),
                  _SidebarItem(
                    label: 'Today',
                    icon: Icons.wb_sunny_outlined,
                    selected: index == NavTarget.today,
                    badge: openToday,
                    onTap: () => onGo(NavTarget.today),
                  ),
                  _SidebarItem(
                    label: 'Planner',
                    icon: Icons.view_week_outlined,
                    selected: index == NavTarget.planner,
                    onTap: () => onGo(NavTarget.planner),
                  ),
                  _SidebarItem(
                    label: 'Calendar',
                    icon: Icons.calendar_month_outlined,
                    selected: index == NavTarget.calendar,
                    onTap: () => onGo(NavTarget.calendar),
                  ),
                  const SizedBox(height: AppSpace.md),
                  _GroupLabel('PRACTICE'),
                  _SidebarItem(
                    label: 'Journal',
                    icon: Icons.edit_note_rounded,
                    selected: index == NavTarget.journal,
                    onTap: () => onGo(NavTarget.journal),
                  ),
                  _SidebarItem(
                    label: 'Focus',
                    icon: Icons.timer_outlined,
                    selected: index == NavTarget.focus,
                    onTap: () => onGo(NavTarget.focus),
                  ),
                  _SidebarItem(
                    label: 'Insights',
                    icon: Icons.insights_rounded,
                    selected: index == NavTarget.insights,
                    onTap: () => onGo(NavTarget.insights),
                  ),
                  const SizedBox(height: AppSpace.md),
                  _GroupLabel('LEDGER'),
                  _SidebarItem(
                    label: 'Categories',
                    icon: Icons.category_outlined,
                    selected: index == NavTarget.categories,
                    onTap: () => onGo(NavTarget.categories),
                  ),
                  _SidebarItem(
                    label: 'Settings',
                    icon: Icons.settings_outlined,
                    selected: index == NavTarget.settings,
                    onTap: () => onGo(NavTarget.settings),
                  ),
                  const SizedBox(height: AppSpace.md),
                  _GroupLabel('TRANSFER'),
                  _SidebarItem(
                    label: 'Nearby & sync',
                    icon: Icons.sync_rounded,
                    selected: index == NavTarget.nearby,
                    onTap: () => onGo(NavTarget.nearby),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: InkWell(
                onTap: onAccount,
                borderRadius: BorderRadius.circular(AppRadius.input),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: colors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: AppText.bodyMedium.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName.trim().isEmpty
                                  ? 'Daymark'
                                  : displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.bodySmall.copyWith(
                                color: colors.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Local account · switch',
                              style: AppText.bodySmall.copyWith(
                                color: colors.inkFaint,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quick capture',
                        onPressed: onCapture,
                        icon: const Icon(Icons.bolt_rounded, size: 17),
                      ),
                      Icon(
                        Icons.unfold_more_rounded,
                        size: 15,
                        color: colors.inkFaint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.index,
    required this.openToday,
    required this.onGo,
    required this.onPalette,
  });

  final int index;
  final int openToday;
  final ValueChanged<int> onGo;
  final VoidCallback onPalette;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.72),
        border: Border(right: BorderSide(color: colors.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: AppSpace.lg),
            BrandMark(size: 26, onTap: () => onGo(NavTarget.today)),
            const SizedBox(height: AppSpace.lg),
            _RailButton(
              icon: Icons.search_rounded,
              tooltip: 'Search',
              onTap: onPalette,
            ),
            const SizedBox(height: AppSpace.sm),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _RailButton(
                      icon: Icons.wb_sunny_outlined,
                      tooltip: 'Today',
                      selected: index == NavTarget.today,
                      badge: openToday,
                      onTap: () => onGo(NavTarget.today),
                    ),
                    _RailButton(
                      icon: Icons.view_week_outlined,
                      tooltip: 'Planner',
                      selected: index == NavTarget.planner,
                      onTap: () => onGo(NavTarget.planner),
                    ),
                    _RailButton(
                      icon: Icons.calendar_month_outlined,
                      tooltip: 'Calendar',
                      selected: index == NavTarget.calendar,
                      onTap: () => onGo(NavTarget.calendar),
                    ),
                    _RailButton(
                      icon: Icons.edit_note_rounded,
                      tooltip: 'Journal',
                      selected: index == NavTarget.journal,
                      onTap: () => onGo(NavTarget.journal),
                    ),
                    _RailButton(
                      icon: Icons.timer_outlined,
                      tooltip: 'Focus',
                      selected: index == NavTarget.focus,
                      onTap: () => onGo(NavTarget.focus),
                    ),
                    _RailButton(
                      icon: Icons.insights_rounded,
                      tooltip: 'Insights',
                      selected: index == NavTarget.insights,
                      onTap: () => onGo(NavTarget.insights),
                    ),
                  ],
                ),
              ),
            ),
            _RailButton(
              icon: Icons.category_outlined,
              tooltip: 'Categories',
              selected: index == NavTarget.categories,
              onTap: () => onGo(NavTarget.categories),
            ),
            _RailButton(
              icon: Icons.sync_rounded,
              tooltip: 'Nearby & sync',
              selected: index == NavTarget.nearby,
              onTap: () => onGo(NavTarget.nearby),
            ),
            _RailButton(
              icon: Icons.settings_outlined,
              tooltip: 'Settings',
              selected: index == NavTarget.settings,
              onTap: () => onGo(NavTarget.settings),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.badge = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.input),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? colors.primarySoft : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? colors.primary : colors.inkMuted,
                ),
                if (badge > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$badge',
                        style: AppText.bodySmall.copyWith(
                          color: Colors.white,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? colors.primary : colors.inkMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: AppText.bodySmall.copyWith(
                    color: selected ? colors.primary : colors.ink,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primary.withValues(alpha: 0.12)
                        : colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$badge',
                    style: AppText.monoData.copyWith(
                      color: selected ? colors.primary : colors.inkFaint,
                      fontSize: 9,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.md,
        AppSpace.sm,
      ),
      child: Text(
        label,
        style: AppText.label.copyWith(
          color: context.colors.inkFaint,
          fontSize: 8.5,
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.openToday,
    required this.timerActive,
    required this.onGo,
    required this.onMore,
  });

  final int index;
  final int openToday;
  final bool timerActive;
  final ValueChanged<int> onGo;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: 6,
          ),
          child: Row(
            children: [
              _BottomItem(
                label: 'Today',
                icon: Icons.wb_sunny_outlined,
                selected: index == NavTarget.today,
                badge: openToday,
                onTap: () => onGo(NavTarget.today),
              ),
              _BottomItem(
                label: 'Planner',
                icon: Icons.view_week_outlined,
                selected: index == NavTarget.planner,
                onTap: () => onGo(NavTarget.planner),
              ),
              _BottomItem(
                label: 'Focus',
                icon: Icons.timer_outlined,
                selected: index == NavTarget.focus,
                live: timerActive,
                onTap: () => onGo(NavTarget.focus),
              ),
              _BottomItem(
                label: 'Sync',
                icon: Icons.sync_rounded,
                selected: index == NavTarget.nearby,
                onTap: () => onGo(NavTarget.nearby),
              ),
              _BottomItem(
                label: 'More',
                icon: Icons.grid_view_rounded,
                selected:
                    index >= NavTarget.calendar &&
                    index != NavTarget.focus &&
                    index != NavTarget.nearby,
                onTap: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
    this.live = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 21,
                    color: selected ? colors.primary : colors.inkMuted,
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -3,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '$badge',
                          style: AppText.bodySmall.copyWith(
                            color: Colors.white,
                            fontSize: 7.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  if (live)
                    Positioned(
                      top: -1,
                      right: -3,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppText.bodySmall.copyWith(
                  color: selected ? colors.primary : colors.inkMuted,
                  fontSize: 9.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
