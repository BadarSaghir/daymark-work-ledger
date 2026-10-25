import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/ui/enum_ui.dart';
import '../core/ui/sheets.dart';
import '../core/utils/date_keys.dart';
import '../data/models/task_view.dart';

/// A searchable, paginated task chooser shared by Nearby task sync and any
/// future "send task" entry point.
Future<TaskView?> showTaskPicker(BuildContext context, List<TaskView> views) {
  final candidates = views.where((view) => !view.task.archived).toList()
    ..sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      final plannedA = a.task.plannedDate ?? '9999-99-99';
      final plannedB = b.task.plannedDate ?? '9999-99-99';
      if (plannedA != plannedB) return plannedA.compareTo(plannedB);
      return b.task.updatedAt.compareTo(a.task.updatedAt);
    });
  return showAppSheet<TaskView>(
    context,
    (sheetContext) => AppSheet(
      title: 'Send one task',
      subtitle:
          'The bundle carries notes, steps, tracked time, reminders, and files. '
          'The receiver imports it without replacing their ledger.',
      icon: Icons.task_alt_rounded,
      child: _TaskPickerBody(views: candidates),
    ),
    maxWidth: 620,
  );
}

class _TaskPickerBody extends StatefulWidget {
  const _TaskPickerBody({required this.views});

  final List<TaskView> views;

  @override
  State<_TaskPickerBody> createState() => _TaskPickerBodyState();
}

class _TaskPickerBodyState extends State<_TaskPickerBody> {
  final _search = TextEditingController();
  int _visible = 20;
  bool _openOnly = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final query = _search.text.trim().toLowerCase();
    final filtered = widget.views.where((view) {
      if (_openOnly && view.isDone) return false;
      if (query.isEmpty) return true;
      final haystack = [
        view.task.title,
        view.task.notesMd,
        view.category?.name ?? '',
        view.task.kind.label,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    final shown = filtered.take(_visible).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          autofocus: false,
          onChanged: (_) => setState(() => _visible = 20),
          decoration: InputDecoration(
            hintText: 'Search title, notes, category…',
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      _search.clear();
                      setState(() => _visible = 20);
                    },
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Row(
          children: [
            Text(
              '${filtered.length} ${filtered.length == 1 ? 'task' : 'tasks'}',
              style: AppText.bodySmall.copyWith(
                color: colors.inkFaint,
                fontSize: 10.5,
              ),
            ),
            const Spacer(),
            FilterChip(
              selected: _openOnly,
              onSelected: (value) => setState(() => _openOnly = value),
              label: const Text('Open only'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
            child: Column(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 26,
                  color: colors.inkFaint,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'No task matches that search.',
                  style: AppText.bodySmall.copyWith(color: colors.inkMuted),
                ),
              ],
            ),
          )
        else
          for (final view in shown) ...[
            _TaskPickerRow(
              view: view,
              onTap: () => Navigator.of(context).pop(view),
            ),
            Divider(color: colors.line, height: 1),
          ],
        if (filtered.length > shown.length) ...[
          const SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            onPressed: () => setState(() => _visible += 20),
            icon: const Icon(Icons.expand_more_rounded, size: 17),
            label: Text('Show ${filtered.length - shown.length} more'),
          ),
        ],
      ],
    );
  }
}

class _TaskPickerRow extends StatelessWidget {
  const _TaskPickerRow({required this.view, required this.onTap});

  final TaskView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final planned = view.task.plannedDate;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xs,
          vertical: AppSpace.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (view.category?.colorValue ?? colors.primary).withValues(
                  alpha: 0.11,
                ),
                borderRadius: BorderRadius.circular(AppRadius.badge),
              ),
              child: Icon(
                view.isDone ? Icons.check_rounded : view.task.status.icon,
                size: 16,
                color: view.category?.colorValue ?? colors.primary,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    view.task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyMedium.copyWith(
                      color: view.isDone ? colors.inkMuted : colors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    [
                      view.category?.name ?? 'Unfiled',
                      if (planned != null)
                        relativeDayLabel(parseDateKey(planned)),
                      if (view.totalSteps > 0)
                        '${view.doneSteps}/${view.totalSteps} steps',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkFaint,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Icon(Icons.chevron_right_rounded, size: 18, color: colors.inkFaint),
          ],
        ),
      ),
    );
  }
}
