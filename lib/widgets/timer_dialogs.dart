import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/ui/enum_ui.dart';
import '../core/ui/sheets.dart';
import '../data/models/task_view.dart';
import '../state/tasks_controller.dart';
import '../state/timer_controller.dart';

/// Ask for an intention, then start the one general stopwatch.
Future<bool> showStartFocusDialog(
  BuildContext context,
  WidgetRef ref, {
  String initialLabel = '',
}) async {
  final label = TextEditingController(text: initialLabel);
  final started = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppSpace.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: colors.line),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: colors.accentSoft,
                            borderRadius: BorderRadius.circular(
                              AppRadius.badge,
                            ),
                          ),
                          child: Icon(
                            Icons.timer_outlined,
                            color: colors.accent,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Text(
                            'Start a focus',
                            style: Theme.of(dialogContext).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xl),
                    TextField(
                      controller: label,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'What are you giving your attention to?',
                      ),
                      onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
                    ),
                    const SizedBox(height: AppSpace.md),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final suggestion in const [
                          'Deep work',
                          'Writing',
                          'Reading',
                          'Admin',
                          'Planning',
                        ])
                          InkWell(
                            borderRadius: BorderRadius.circular(99),
                            onTap: () => label.text = suggestion,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceSunken,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                suggestion,
                                style: AppText.bodySmall.copyWith(
                                  color: colors.inkMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xxl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        FilledButton.icon(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('Start'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  final text = label.text;
  label.dispose();
  if (started != true) return false;

  if (!context.mounted) return false;
  final existing = ref.read(timerProvider).value?.session;
  if (existing != null) {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Switch focus?',
      message:
          '“${existing.label}” is still live. Starting a new timer will stop and save it.',
      confirmLabel: 'Switch',
      icon: Icons.swap_horiz_rounded,
    );
    if (!confirmed) return false;
  }
  await ref.read(timerProvider.notifier).startGeneral(text);
  return true;
}

/// Returns a task id, `''` for "no task", or null when cancelled.
Future<String?> showTaskPicker(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Choose a task',
  String message = '',
  bool allowNone = false,
}) {
  return showAppSheet<String>(
    context,
    (sheetContext) =>
        _TaskPickerSheet(title: title, message: message, allowNone: allowNone),
    maxWidth: 520,
  );
}

class _TaskPickerSheet extends ConsumerStatefulWidget {
  const _TaskPickerSheet({
    required this.title,
    required this.message,
    required this.allowNone,
  });

  final String title;
  final String message;
  final bool allowNone;

  @override
  ConsumerState<_TaskPickerSheet> createState() => _TaskPickerSheetState();
}

class _TaskPickerSheetState extends ConsumerState<_TaskPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tasks =
        (ref.watch(tasksProvider).value ?? const <TaskView>[])
            .where((view) => !view.task.archived)
            .where(
              (view) =>
                  _query.isEmpty ||
                  view.task.title.toLowerCase().contains(_query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) {
            if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
            return b.task.updatedAt.compareTo(a.task.updatedAt);
          });
    return AppSheet(
      title: widget.title,
      subtitle: widget.message.isEmpty ? null : widget.message,
      icon: Icons.playlist_add_check_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search tasks…',
              prefixIcon: Icon(Icons.search_rounded, size: 19),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: AppSpace.md),
          if (widget.allowNone)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.remove_circle_outline_rounded,
                color: colors.inkMuted,
              ),
              title: Text(
                'No task — keep it as general focus',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              onTap: () => Navigator.of(context).pop(''),
            ),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
              child: Text(
                'No matching tasks.',
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: colors.inkFaint),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: tasks.length,
                separatorBuilder: (_, _) => Divider(color: colors.line),
                itemBuilder: (context, index) {
                  final view = tasks[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: view.category?.colorValue ?? colors.inkFaint,
                      ),
                    ),
                    title: Text(
                      view.task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      [
                        view.task.kind.label,
                        if (view.task.plannedDate != null)
                          view.task.plannedDate!,
                        if (view.isDone) 'Done',
                      ].join(' · '),
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 11.5,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                    onTap: () => Navigator.of(context).pop(view.task.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
