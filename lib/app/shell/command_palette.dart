import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/enum_ui.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../data/models/task_view.dart';
import '../../app/routes.dart';
import '../../state/settings_controller.dart';
import '../../state/tasks_controller.dart';
import '../../state/ui_state.dart';
import '../../widgets/quick_capture.dart';
import '../../widgets/task_editor.dart';
import '../../widgets/timer_dialogs.dart';
import '../nav.dart';

class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _query = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final query = _query.text.trim().toLowerCase();
    final tasks = (ref.watch(tasksProvider).value ?? const <TaskView>[])
        .where((view) => !view.task.archived)
        .where(
          (view) =>
              query.isEmpty ||
              view.task.title.toLowerCase().contains(query) ||
              (view.category?.name.toLowerCase().contains(query) ?? false),
        )
        .toList();
    final settings = ref.watch(settingsProvider).value;

    final actions =
        <_PaletteCommand>[
          _PaletteCommand(
            label: 'Capture work',
            hint: 'Quickly add a task',
            icon: Icons.bolt_rounded,
            keys: '⌘N',
            run: () {
              widget.onClose();
              showQuickCapture(context, plannedDate: DateTime.now());
            },
          ),
          _PaletteCommand(
            label: 'New task',
            hint: 'Open the full task editor',
            icon: Icons.add_task_rounded,
            run: () {
              widget.onClose();
              showTaskEditor(context, initialDate: DateTime.now());
            },
          ),
          _PaletteCommand(
            label: 'Start a focus',
            hint: 'Begin the general stopwatch',
            icon: Icons.play_arrow_rounded,
            run: () {
              widget.onClose();
              showStartFocusDialog(context, ref);
            },
          ),
          _PaletteCommand(
            label: 'Write in the journal',
            hint: 'Open today’s markdown page',
            icon: Icons.edit_note_rounded,
            run: () {
              ref.read(selectedDateProvider.notifier).state = DateTime.now();
              _go(NavTarget.journal);
            },
          ),
          _PaletteCommand(
            label: 'Sync with a nearby device',
            hint: 'Pair by QR and exchange ledgers',
            icon: Icons.sync_rounded,
            run: () => _go(NavTarget.nearby),
          ),
          _PaletteCommand(
            label: 'Review insights',
            hint: 'Focus, output, and estimate accuracy',
            icon: Icons.insights_rounded,
            run: () => _go(NavTarget.insights),
          ),
        ].where((command) {
          return query.isEmpty ||
              command.label.toLowerCase().contains(query) ||
              command.hint.toLowerCase().contains(query);
        }).toList();

    final destinations =
        [
              (NavTarget.today, 'Today', Icons.wb_sunny_outlined),
              (NavTarget.planner, 'Planner', Icons.view_week_outlined),
              (NavTarget.calendar, 'Calendar', Icons.calendar_month_outlined),
              (NavTarget.journal, 'Journal', Icons.edit_note_rounded),
              (NavTarget.focus, 'Focus', Icons.timer_outlined),
              (NavTarget.insights, 'Insights', Icons.insights_rounded),
              (NavTarget.categories, 'Categories', Icons.category_outlined),
              (NavTarget.nearby, 'Nearby', Icons.wifi_tethering_rounded),
              (NavTarget.settings, 'Settings', Icons.settings_outlined),
            ]
            .where(
              (item) => query.isEmpty || item.$2.toLowerCase().contains(query),
            )
            .toList();

    final filteredTasks = query.isEmpty
        ? tasks.where((view) => !view.isDone).take(5).toList()
        : tasks.take(8).toList();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(color: Colors.black.withValues(alpha: 0.42)),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.sizeOf(context).height * 0.11,
              left: AppSpace.lg,
              right: AppSpace.lg,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Material(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                clipBehavior: Clip.antiAlias,
                elevation: 24,
                shadowColor: colors.shadow,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: colors.line),
                  ),
                  constraints: const BoxConstraints(maxHeight: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.lg,
                          AppSpace.md,
                          AppSpace.md,
                          AppSpace.md,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: colors.inkFaint,
                            ),
                            const SizedBox(width: AppSpace.sm),
                            Expanded(
                              child: TextField(
                                controller: _query,
                                focusNode: _focus,
                                autofocus: true,
                                style: AppText.titleM.copyWith(
                                  color: colors.ink,
                                  fontSize: 16,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Search tasks, jump somewhere, do a thing…',
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) {
                                  if (actions.isNotEmpty) {
                                    actions.first.run();
                                  } else if (filteredTasks.isNotEmpty) {
                                    _openTask(filteredTasks.first);
                                  }
                                },
                              ),
                            ),
                            const KeyHint('ESC'),
                          ],
                        ),
                      ),
                      Divider(color: colors.line, height: 1),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpace.sm,
                          ),
                          children: [
                            if (actions.isNotEmpty) ...[
                              _Section('ACTIONS'),
                              for (final command in actions)
                                _CommandRow(
                                  label: command.label,
                                  hint: command.hint,
                                  icon: command.icon,
                                  keys: command.keys,
                                  onTap: command.run,
                                ),
                            ],
                            if (destinations.isNotEmpty) ...[
                              _Section('GO TO'),
                              for (final item in destinations)
                                _CommandRow(
                                  label: item.$2,
                                  hint: 'Go to ${item.$2.toLowerCase()}',
                                  icon: item.$3,
                                  onTap: () => _go(item.$1),
                                ),
                            ],
                            if (filteredTasks.isNotEmpty) ...[
                              _Section(query.isEmpty ? 'OPEN TASKS' : 'TASKS'),
                              for (final view in filteredTasks)
                                _TaskRow(
                                  view: view,
                                  onTap: () => _openTask(view),
                                ),
                            ],
                            if (actions.isEmpty &&
                                destinations.isEmpty &&
                                filteredTasks.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(AppSpace.xxl),
                                child: Text(
                                  'Nothing matches “${_query.text.trim()}”.',
                                  textAlign: TextAlign.center,
                                  style: AppText.body.copyWith(
                                    color: colors.inkFaint,
                                  ),
                                ),
                              ),
                            const SizedBox(height: AppSpace.sm),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.xl,
                              ),
                              child: Text(
                                settings?.displayName.trim().isEmpty == false
                                    ? '${settings!.displayName}\'s local ledger · everything stays on this device'
                                    : 'Everything stays on this device',
                                style: AppText.bodySmall.copyWith(
                                  color: colors.inkFaint,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _go(int target) {
    ref.read(navIndexProvider.notifier).state = target;
    widget.onClose();
  }

  void _openTask(TaskView view) {
    widget.onClose();
    openTaskDetail(context, view.task.id);
  }
}

class _PaletteCommand {
  const _PaletteCommand({
    required this.label,
    required this.hint,
    required this.icon,
    required this.run,
    this.keys,
  });

  final String label;
  final String hint;
  final IconData icon;
  final VoidCallback run;
  final String? keys;
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.sm,
        AppSpace.xl,
        AppSpace.xs,
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

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.label,
    required this.hint,
    required this.icon,
    required this.onTap,
    this.keys,
  });

  final String label;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;
  final String? keys;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xl,
          vertical: AppSpace.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadius.badge),
              ),
              child: Icon(icon, size: 15, color: colors.inkMuted),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppText.bodyMedium.copyWith(color: colors.ink),
                  ),
                  Text(
                    hint,
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            if (keys != null) KeyHint(keys!),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.view, required this.onTap});

  final TaskView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xl,
          vertical: 7,
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: view.category?.colorValue ?? colors.inkFaint,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                view.task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyMedium.copyWith(color: colors.ink),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Text(
              view.isDone
                  ? 'Done'
                  : view.task.plannedDate == null
                  ? 'Inbox'
                  : relativeDayLabel(parseDateKey(view.task.plannedDate!)),
              style: AppText.bodySmall.copyWith(
                color: colors.inkFaint,
                fontSize: 10.5,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 15, color: colors.inkFaint),
          ],
        ),
      ),
    );
  }
}
