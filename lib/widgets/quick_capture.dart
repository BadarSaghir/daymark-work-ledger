import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/ui/enum_ui.dart';
import '../core/ui/form.dart';
import '../core/ui/sheets.dart';
import '../core/utils/date_keys.dart';
import '../data/models/enums.dart';
import '../state/categories_controller.dart';
import '../state/tasks_controller.dart';
import 'category_picker.dart';

/// A fast path into the ledger. Title first; everything else is optional.
Future<void> showQuickCapture(
  BuildContext context, {
  DateTime? plannedDate,
  TaskStatus? initialStatus,
  String initialTitle = '',
  String? initialNotes,
}) {
  return showAppSheet<void>(
    context,
    (sheetContext) => QuickCapture(
      plannedDate: plannedDate,
      initialStatus: initialStatus,
      initialTitle: initialTitle,
      initialNotes: initialNotes,
    ),
    maxWidth: 620,
  );
}

class QuickCapture extends ConsumerStatefulWidget {
  const QuickCapture({
    super.key,
    this.plannedDate,
    this.initialStatus,
    this.initialTitle = '',
    this.initialNotes,
  });

  final DateTime? plannedDate;
  final TaskStatus? initialStatus;
  final String initialTitle;
  final String? initialNotes;

  @override
  ConsumerState<QuickCapture> createState() => _QuickCaptureState();
}

class _QuickCaptureState extends ConsumerState<QuickCapture> {
  final _title = TextEditingController();
  final _focus = FocusNode();
  String? _categoryId;
  WorkKind _kind = WorkKind.official;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialTitle.isNotEmpty) _title.text = widget.initialTitle;
    final categories = (ref.read(categoriesProvider).value ?? const [])
        .where((category) => !category.archived)
        .toList();
    if (categories.isNotEmpty) _categoryId = categories.first.id;
  }

  @override
  void dispose() {
    _title.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save({required bool planToday}) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give this piece of work a name first.');
      _focus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final date = widget.plannedDate ?? DateTime.now();
      final planned = planToday || widget.initialStatus == TaskStatus.planned;
      await ref
          .read(tasksProvider.notifier)
          .createNew(
            title: title,
            categoryId: _categoryId,
            kind: _kind,
            status: planned ? TaskStatus.planned : TaskStatus.inbox,
            plannedDate: planned ? dateKey(date) : null,
            notesMd: widget.initialNotes?.trim() ?? '',
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(
        context,
        planned
            ? 'Planned for ${relativeDayLabel(date, lowercaseToday: true)}'
            : 'Captured in your inbox',
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final categories = ref.watch(categoriesProvider).value ?? const [];

    return AppSheet(
      title: 'Capture work',
      subtitle: 'One clear line now. Add structure when it matters.',
      icon: Icons.add_task_rounded,
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _saving ? null : () => _save(planToday: false),
              icon: const Icon(Icons.inbox_outlined, size: 17),
              label: const Text('Add to inbox'),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: FilledButton.icon(
              onPressed: _saving ? null : () => _save(planToday: true),
              icon: _saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_rounded, size: 18),
              label: Text(
                widget.plannedDate == null ? 'Plan today' : 'Add to day',
              ),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            focusNode: _focus,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            maxLines: 3,
            minLines: 1,
            style: AppText.titleL.copyWith(color: colors.ink, fontSize: 22),
            decoration: const InputDecoration(
              hintText: 'What needs doing?',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => _save(planToday: true),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              _error!,
              style: AppText.bodySmall.copyWith(color: colors.rose),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          sectionDivider(context),
          const FormLabel('Kind of work'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final kind in WorkKind.values)
                ChoicePill(
                  label: kind.label,
                  icon: kind.icon,
                  selected: _kind == kind,
                  color: kind.color(colors),
                  onTap: () => setState(() => _kind = kind),
                ),
            ],
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xl),
            CategoryPickerField(
              categories: categories,
              selectedId: _categoryId,
              onChanged: (id) => setState(() => _categoryId = id),
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          Row(
            children: [
              Icon(
                Icons.keyboard_return_rounded,
                size: 14,
                color: colors.inkFaint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Enter plans it for today · every capture is a real task, '
                  'not a scratchpad line.',
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
