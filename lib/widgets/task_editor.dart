import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/ui/enum_ui.dart';
import '../core/ui/form.dart';
import '../core/ui/markdown.dart';
import '../core/ui/sheets.dart';
import '../core/utils/date_keys.dart';
import '../core/utils/durations.dart';
import '../data/models/category.dart';
import '../data/models/enums.dart';
import '../data/models/task_view.dart';
import '../state/categories_controller.dart';
import '../state/tasks_controller.dart';
import 'category_picker.dart';

Future<void> showTaskEditor(
  BuildContext context, {
  TaskView? existing,
  DateTime? initialDate,
}) {
  return showAppSheet<void>(
    context,
    (sheetContext) => TaskEditor(existing: existing, initialDate: initialDate),
    maxWidth: 780,
  );
}

class TaskEditor extends ConsumerStatefulWidget {
  const TaskEditor({super.key, this.existing, this.initialDate});

  final TaskView? existing;
  final DateTime? initialDate;

  @override
  ConsumerState<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _steps;
  late final TextEditingController _estimate;
  late final TextEditingController _blocked;
  late final TextEditingController _reminderNote;

  late String? _categoryId;
  late WorkKind _kind;
  late TaskStatus _status;
  late Priority _priority;
  late int _effort;
  late DateTime? _plannedDate;
  late DateTime? _start;
  late DateTime? _end;
  late DateTime? _due;
  late DateTime? _reminderAt;

  bool _saving = false;
  String? _error;

  bool get isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final task = widget.existing?.task;
    _title = TextEditingController(text: task?.title ?? '');
    _notes = TextEditingController(text: task?.notesMd ?? '');
    _steps = TextEditingController();
    _estimate = TextEditingController(
      text: task?.estimateMinutes?.toString() ?? '',
    );
    _blocked = TextEditingController(text: task?.blockedReason ?? '');
    _reminderNote = TextEditingController(text: task?.reminderNote ?? '');
    _categoryId = task?.categoryId;
    if (task == null) {
      final categories = (ref.read(categoriesProvider).value ?? const [])
          .where((category) => !category.archived)
          .toList();
      if (categories.isNotEmpty) _categoryId = categories.first.id;
    }
    _kind = task?.kind ?? WorkKind.official;
    _status = task?.status ?? TaskStatus.inbox;
    _priority = task?.priority ?? Priority.normal;
    _effort = task?.effort ?? 2;
    _plannedDate = task?.plannedDate != null
        ? parseDateKey(task!.plannedDate!)
        : widget.initialDate;
    _start = task?.scheduledStart;
    _end = task?.scheduledEnd;
    _due = task?.dueAt;
    _reminderAt = task?.reminderAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _steps.dispose();
    _estimate.dispose();
    _blocked.dispose();
    _reminderNote.dispose();
    super.dispose();
  }

  Future<void> _pickPlannedDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _plannedDate ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 5),
      helpText: 'Plan this work for…',
    );
    if (picked == null) return;
    setState(() {
      _plannedDate = startOfDay(picked);
      if (_status == TaskStatus.inbox) _status = TaskStatus.planned;
    });
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? _plannedDate ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 5),
      helpText: 'Deadline',
    );
    if (picked == null) return;
    setState(() => _due = DateTime(picked.year, picked.month, picked.day, 17));
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final initial = _reminderAt ?? _start ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Remind me on…',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Remind me at…',
    );
    if (time == null) return;
    setState(() {
      _reminderAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final base = _plannedDate ?? startOfDay(DateTime.now());
    final current = start ? _start : _end;
    final initial = current != null
        ? TimeOfDay(hour: current.hour, minute: current.minute)
        : TimeOfDay(hour: start ? 9 : 10, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: start ? 'Start time' : 'End time',
    );
    if (picked == null) return;
    setState(() {
      _plannedDate ??= base;
      final value = DateTime(
        base.year,
        base.month,
        base.day,
        picked.hour,
        picked.minute,
      );
      if (start) {
        final previousLength = _start != null && _end != null
            ? _end!.difference(_start!)
            : const Duration(minutes: 60);
        _start = value;
        _end = value.add(previousLength);
      } else {
        _end = value;
      }
    });
  }

  int? get _estimateValue {
    final parsed = int.tryParse(_estimate.text.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed.clamp(1, 24 * 60);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'A task needs a title.');
      return;
    }
    if (_start != null && _end != null && _end!.isBefore(_start!)) {
      setState(() => _error = 'The end time is before the start time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final notifier = ref.read(tasksProvider.notifier);
    final dateString = _plannedDate == null ? null : dateKey(_plannedDate!);
    try {
      if (isEditing) {
        final existing = widget.existing!;
        final updated = existing.task.copyWith(
          title: title,
          notesMd: _notes.text,
          categoryId: _categoryId,
          kind: _kind,
          priority: _priority,
          effort: _effort,
          estimateMinutes: _estimateValue,
          plannedDate: dateString,
          scheduledStart: _start,
          scheduledEnd: _end,
          dueAt: _due,
          reminderAt: _reminderAt,
          reminderNote: _reminderAt == null
              ? null
              : (_reminderNote.text.trim().isEmpty
                    ? null
                    : _reminderNote.text.trim()),
          blockedReason: _status == TaskStatus.blocked
              ? _blocked.text.trim()
              : null,
          completedAt: _status == TaskStatus.done
              ? (existing.task.completedAt ?? DateTime.now())
              : null,
        );
        await notifier.updateTask(updated, summary: 'Updated details');
        if (_status != existing.task.status) {
          await notifier.setStatus(
            existing.task.id,
            _status,
            completeSteps: _status == TaskStatus.done,
            blockedReason: _blocked.text,
          );
        }
      } else {
        final stepTitles = _steps.text
            .split('\n')
            .map((line) => line.replaceFirst(RegExp(r'^[-*]\s*'), '').trim())
            .where((line) => line.isNotEmpty)
            .toList();
        await notifier.createNew(
          title: title,
          categoryId: _categoryId,
          kind: _kind,
          status: _status,
          priority: _priority,
          effort: _effort,
          estimateMinutes: _estimateValue,
          plannedDate: dateString,
          scheduledStart: _start,
          scheduledEnd: _end,
          dueAt: _due,
          reminderAt: _reminderAt,
          reminderNote: _reminderAt == null
              ? null
              : (_reminderNote.text.trim().isEmpty
                    ? null
                    : _reminderNote.text.trim()),
          notesMd: _notes.text,
          stepTitles: stepTitles,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, isEditing ? 'Saved changes' : 'Task created');
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;

    return AppSheet(
      title: isEditing ? 'Edit task' : 'New task',
      subtitle: isEditing
          ? 'Shape the work without losing its history.'
          : 'Give the work a shape, a place, and a size.',
      icon: isEditing ? Icons.tune_rounded : Icons.add_task_rounded,
      footer: Row(
        children: [
          if (isEditing) ...[
            Text(
              '${widget.existing!.doneSteps}/${widget.existing!.totalSteps} steps · '
              '${formatPoints(widget.existing!.points)}',
              style: AppText.bodySmall.copyWith(color: colors.inkFaint),
            ),
            const Spacer(),
          ] else
            const Spacer(),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: AppSpace.sm),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(isEditing ? 'Save changes' : 'Create task'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormLabel('Title'),
          TextField(
            controller: _title,
            autofocus: !isEditing,
            textCapitalization: TextCapitalization.sentences,
            style: AppText.titleL.copyWith(color: colors.ink, fontSize: 21),
            decoration: const InputDecoration(hintText: 'What is the work?'),
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
          const SizedBox(height: AppSpace.xl),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _categorySection(categories)),
                const SizedBox(width: AppSpace.xl),
                Expanded(child: _kindSection(colors)),
              ],
            )
          else ...[
            _categorySection(categories),
            const SizedBox(height: AppSpace.lg),
            _kindSection(colors),
          ],
          const SizedBox(height: AppSpace.xl),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _prioritySection(colors)),
                const SizedBox(width: AppSpace.xl),
                Expanded(child: _statusSection(colors)),
              ],
            )
          else ...[
            _prioritySection(colors),
            const SizedBox(height: AppSpace.lg),
            _statusSection(colors),
          ],
          if (_status == TaskStatus.blocked) ...[
            const SizedBox(height: AppSpace.lg),
            const FormLabel('What is blocking it?'),
            TextField(
              controller: _blocked,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Waiting on a review, a decision, a person…',
              ),
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          sectionDivider(context),
          FormLabel('Schedule', hint: 'Dates are local to you'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _DateChip(
                icon: Icons.event_rounded,
                label: _plannedDate == null
                    ? 'No plan date'
                    : _planDateLabel(_plannedDate!),
                active: _plannedDate != null,
                onTap: _pickPlannedDate,
                onClear: _plannedDate == null
                    ? null
                    : () => setState(() => _plannedDate = null),
              ),
              _DateChip(
                icon: Icons.schedule_rounded,
                label: _start == null ? 'Start time' : timeLabel(_start!),
                active: _start != null,
                onTap: () => _pickTime(start: true),
                onClear: _start == null
                    ? null
                    : () => setState(() {
                        _start = null;
                        _end = null;
                      }),
              ),
              _DateChip(
                icon: Icons.timelapse_rounded,
                label: _end == null ? 'End time' : timeLabel(_end!),
                active: _end != null,
                onTap: () => _pickTime(start: false),
                onClear: _end == null
                    ? null
                    : () => setState(() => _end = null),
              ),
              _DateChip(
                icon: Icons.flag_outlined,
                label: _due == null ? 'No deadline' : 'Due ${dateLabel(_due!)}',
                active: _due != null,
                onTap: _pickDueDate,
                onClear: _due == null
                    ? null
                    : () => setState(() => _due = null),
              ),
              _DateChip(
                icon: Icons.notifications_active_outlined,
                label: _reminderAt == null
                    ? 'Custom reminder'
                    : 'Remind ${dateLabel(_reminderAt!)} · '
                          '${timeLabel(_reminderAt!)}',
                active: _reminderAt != null,
                onTap: _pickReminder,
                onClear: _reminderAt == null
                    ? null
                    : () => setState(() {
                        _reminderAt = null;
                        _reminderNote.clear();
                      }),
              ),
            ],
          ),
          if (_reminderAt != null) ...[
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _reminderNote,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reminder note (optional)',
                hintText: 'What should this nudge say?',
                prefixIcon: Icon(Icons.notifications_none_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'A custom reminder fires at this exact local time, in addition to '
              'the start and deadline reminders in Settings.',
              style: AppText.bodySmall.copyWith(
                color: colors.inkFaint,
                fontSize: 10.5,
              ),
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _effortSection(colors)),
                const SizedBox(width: AppSpace.xl),
                Expanded(child: _estimateSection()),
              ],
            )
          else ...[
            _effortSection(colors),
            const SizedBox(height: AppSpace.lg),
            _estimateSection(),
          ],
          const SizedBox(height: AppSpace.xl),
          sectionDivider(context),
          if (isEditing)
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: colors.primarySoft.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.checklist_rounded,
                    size: 17,
                    color: colors.primary,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      'Steps are edited on the task page so their completion '
                      'history stays intact.',
                      style: AppText.bodySmall.copyWith(color: colors.inkMuted),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            const FormLabel('Steps', hint: 'One per line — optional'),
            TextField(
              controller: _steps,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: AppText.body.copyWith(color: colors.ink),
              decoration: const InputDecoration(
                hintText: 'Draft the outline\nAsk for feedback\nSend the final',
              ),
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          const FormLabel('Notes', hint: 'Markdown supported'),
          MarkdownEditor(
            controller: _notes,
            onChanged: (_) {},
            minLines: 4,
            hintText: 'Context, links, decisions, what “done” means…',
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Effort ${_effortLabel(_effort)} × ${_priority.label} priority × '
            '${_kind.label} × category weight sets the points.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _categorySection(List<Category> categories) {
    return CategoryPickerField(
      categories: categories,
      selectedId: _categoryId,
      onChanged: (id) => setState(() => _categoryId = id),
    );
  }

  Widget _kindSection(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FormLabel('Kind'),
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
      ],
    );
  }

  Widget _prioritySection(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FormLabel('Priority'),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final priority in Priority.values)
              ChoicePill(
                label: priority.label,
                icon: priority.icon,
                selected: _priority == priority,
                color: priority.color(colors),
                onTap: () => setState(() => _priority = priority),
              ),
          ],
        ),
      ],
    );
  }

  Widget _statusSection(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FormLabel('Status'),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final status in TaskStatus.values)
              ChoicePill(
                label: status.label,
                icon: status.icon,
                selected: _status == status,
                color: status.color(colors),
                onTap: () => setState(() => _status = status),
              ),
          ],
        ),
      ],
    );
  }

  Widget _effortSection(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel('Effort', hint: _effortLabel(_effort)),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (var value = 1; value <= 5; value++)
              ChoicePill(
                label: _effortShort(value),
                selected: _effort == value,
                onTap: () => setState(() => _effort = value),
              ),
          ],
        ),
      ],
    );
  }

  Widget _estimateSection() {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FormLabel('Estimate', hint: 'Minutes — optional'),
        TextField(
          controller: _estimate,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '45', suffixText: 'min'),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final minutes in [15, 30, 45, 60, 90])
              InkWell(
                onTap: () => setState(() {
                  _estimate.text = '$minutes';
                }),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${minutes}m',
                    style: AppText.monoData.copyWith(
                      color: colors.inkMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _planDateLabel(DateTime date) {
    final base = relativeDayLabel(date);
    if (isToday(date)) return '${weekdayShort(date)} · $base';
    return base;
  }

  String _effortShort(int value) =>
      const ['XS', 'S', 'M', 'L', 'XL'][value.clamp(1, 5) - 1];

  String _effortLabel(int value) {
    return switch (value.clamp(1, 5)) {
      1 => 'XS · a quick touch',
      2 => 'S · under an hour',
      3 => 'M · a solid block',
      4 => 'L · a deep effort',
      _ => 'XL · a project in itself',
    };
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: active
            ? colors.primarySoft.withValues(alpha: 0.55)
            : colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: active ? colors.primary.withValues(alpha: 0.3) : colors.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: active ? colors.primary : colors.inkMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: AppText.bodySmall.copyWith(
                      color: active ? colors.primary : colors.inkMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onClear != null)
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 10, 8),
                child: Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: colors.inkFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
