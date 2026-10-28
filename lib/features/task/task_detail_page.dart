import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/brand_mark.dart';
import '../../core/ui/enum_ui.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/form.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/markdown.dart';
import '../../core/ui/menu_action.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../core/utils/durations.dart';
import '../../data/models/activity_event.dart';
import '../../data/models/enums.dart';
import '../../data/models/subtask.dart';
import '../../data/models/task_attachment.dart';
import '../../data/models/task_view.dart';
import '../../data/models/time_entry.dart';
import '../../data/services/task_attachment_service.dart';
import '../../state/repository_providers.dart';
import '../../state/tasks_controller.dart';
import '../../state/timer_controller.dart';
import '../../widgets/task_actions.dart';
import '../../widgets/task_editor.dart';

class TaskDetailPage extends ConsumerStatefulWidget {
  const TaskDetailPage({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage> {
  final _notes = TextEditingController();
  final _step = TextEditingController();
  final _stepFocus = FocusNode();
  Timer? _saveTimer;
  bool _hydrated = false;
  bool _notesDirty = false;
  bool _savingNotes = false;
  DateTime? _notesSavedAt;
  List<TimeEntry> _entries = const [];
  List<ActivityEvent> _activity = const [];
  List<TaskAttachment> _attachments = const [];
  bool _historyLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_notesDirty) {
      ref.read(tasksProvider.notifier).saveNotes(widget.taskId, _notes.text);
    }
    _notes.dispose();
    _step.dispose();
    _stepFocus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final repo = ref.read(taskRepositoryProvider);
    final entries = await repo.entriesForTask(widget.taskId);
    final activity = await repo.activityFor(widget.taskId);
    final attachments = await ref
        .read(taskAttachmentRepositoryProvider)
        .listForTask(widget.taskId);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _activity = activity;
      _attachments = attachments;
      _historyLoading = false;
    });
  }

  Future<void> _addAttachments() async {
    List<XFile> picked;
    try {
      picked = await openFiles();
    } catch (error) {
      if (mounted) showToast(context, 'Could not open the file picker: $error');
      return;
    }
    if (picked.isEmpty) return;
    late final TaskAttachmentService service;
    try {
      service = await ref.read(taskAttachmentServiceProvider.future);
    } catch (error) {
      if (mounted) showToast(context, 'Could not attach that file: $error');
      return;
    }
    var added = 0;
    Object? failure;
    for (final file in picked) {
      try {
        await service.addFile(widget.taskId, File(file.path));
        added++;
      } catch (error) {
        failure ??= error;
      }
    }
    await _loadHistory();
    if (!mounted) return;
    if (failure == null) {
      showToast(
        context,
        picked.length == 1
            ? 'File attached.'
            : '${picked.length} files attached.',
      );
    } else if (added == 0) {
      showToast(context, 'Could not attach that file: $failure');
    } else {
      showToast(context, '$added of ${picked.length} files attached: $failure');
    }
  }

  Future<void> _openAttachment(TaskAttachment attachment) async {
    try {
      final service = await ref.read(taskAttachmentServiceProvider.future);
      final file = service.fileFor(attachment);
      if (!await file.exists()) {
        if (mounted) showToast(context, 'That file is missing from disk.');
        return;
      }
      final opened = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        showToast(context, 'No app is registered to open this file type.');
      }
    } catch (error) {
      if (mounted) showToast(context, 'Could not open the file: $error');
    }
  }

  Future<void> _shareAttachment(TaskAttachment attachment) async {
    try {
      final service = await ref.read(taskAttachmentServiceProvider.future);
      final file = service.fileFor(attachment);
      if (!await file.exists()) {
        if (mounted) showToast(context, 'That file is missing from disk.');
        return;
      }
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: attachment.fileName,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      if (mounted) showToast(context, 'Could not share the file: $error');
    }
  }

  Future<void> _deleteAttachment(TaskAttachment attachment) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove this attachment?',
      message: '“${attachment.fileName}” will be deleted from this device.',
      confirmLabel: 'Remove',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    try {
      final service = await ref.read(taskAttachmentServiceProvider.future);
      await service.delete(attachment);
      await _loadHistory();
    } catch (error) {
      if (mounted) showToast(context, 'Could not remove the file: $error');
    }
  }

  Future<void> _shareTask(TaskView view) async {
    try {
      final service = await ref.read(taskBundleServiceProvider.future);
      final export = await service.exportTask(widget.taskId);
      final temp = await getTemporaryDirectory();
      final file = File(p.join(temp.path, export.fileName));
      await file.writeAsBytes(export.bytes, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/zip')],
          subject: 'Daymark task · ${export.title}',
          text:
              'Daymark task bundle with notes, steps, tracked time, reminders, '
              'and ${export.attachmentCount} file(s). Import it from Settings → '
              'Backup & portability → Import task bundle.',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (mounted) {
        showToast(
          context,
          'Task bundle ready. The other device can import it from Settings → '
          'Backup & portability.',
          duration: const Duration(seconds: 4),
        );
      }
    } catch (error) {
      if (mounted) showToast(context, 'Could not share the task: $error');
    }
  }

  void _hydrate(TaskView view) {
    if (_hydrated) return;
    _hydrated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notes.text = view.task.notesMd;
      _notesSavedAt = view.task.updatedAt;
      setState(() {});
    });
  }

  void _onNotesChanged(String value) {
    setState(() => _notesDirty = true);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted) return;
      setState(() => _savingNotes = true);
      await ref.read(tasksProvider.notifier).saveNotes(widget.taskId, value);
      if (!mounted) return;
      setState(() {
        _savingNotes = false;
        _notesDirty = false;
        _notesSavedAt = DateTime.now();
      });
    });
  }

  Future<void> _flushNotes() async {
    _saveTimer?.cancel();
    if (!_notesDirty) return;
    setState(() => _savingNotes = true);
    await ref
        .read(tasksProvider.notifier)
        .saveNotes(widget.taskId, _notes.text);
    if (!mounted) return;
    setState(() {
      _savingNotes = false;
      _notesDirty = false;
      _notesSavedAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final views = ref.watch(tasksProvider);
    var view = views.value
        ?.where((item) => item.task.id == widget.taskId)
        .firstOrNull;
    final timer = ref.watch(timerProvider).value;
    final session = timer?.session;
    final active = session?.taskId == widget.taskId;
    final liveMs = active ? timer!.elapsed.inMilliseconds : 0;

    if (view == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: views.isLoading
                ? const CircularProgressIndicator()
                : EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'This task is gone',
                    message: 'It may have been deleted or archived on another screen.',
                    action: OutlinedButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Go back'),
                    ),
                  ),
          ),
        ),
      );
    }
    _hydrate(view);

    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final notes = _NotesCard(
      controller: _notes,
      onChanged: _onNotesChanged,
      saving: _savingNotes,
      dirty: _notesDirty,
      savedAt: _notesSavedAt,
      onFlush: _flushNotes,
    );
    final steps = _StepsCard(
      view: view,
      controller: _step,
      focusNode: _stepFocus,
      onAdd: _addStep,
    );
    final attachments = _AttachmentsCard(
      attachments: _attachments,
      onAdd: _addAttachments,
      onOpen: _openAttachment,
      onShare: _shareAttachment,
      onDelete: _deleteAttachment,
    );
    final history = _HistoryCard(
      view: view,
      entries: _entries,
      activity: _activity,
      loading: _historyLoading,
      liveMs: liveMs,
      timerActive: active,
    );
    final rail = _DetailRail(
      view: view,
      liveMs: liveMs,
      timerActive: active,
      onEdit: () => showTaskEditor(context, existing: view),
      onTimer: () => _toggleTimer(view),
      onStatus: (status) => _changeStatus(view, status),
    );

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _DetailTopBar(
              view: view,
              onBack: () => Navigator.of(context).maybePop(),
              onEdit: () => showTaskEditor(context, existing: view),
              onTimer: () => _toggleTimer(view),
              timerActive: active,
              timerRunning: active && (timer?.isRunning ?? false),
              onShare: () => _shareTask(view),
              onArchive: () => _archive(view),
              onDelete: () => _delete(view),
            ),
            Expanded(
              child: PageWidth(
                maxWidth: 1180,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: AppSpace.x6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DetailHeader(
                        view: view,
                        onEdit: () => showTaskEditor(context, existing: view),
                      ),
                      const SizedBox(height: AppSpace.xxl),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: Column(
                                children: [
                                  notes,
                                  const SizedBox(height: AppSpace.lg),
                                  steps,
                                  const SizedBox(height: AppSpace.lg),
                                  attachments,
                                  const SizedBox(height: AppSpace.lg),
                                  history,
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpace.x3),
                            SizedBox(width: 320, child: rail),
                          ],
                        )
                      else ...[
                        notes,
                        const SizedBox(height: AppSpace.lg),
                        steps,
                        const SizedBox(height: AppSpace.lg),
                        attachments,
                        const SizedBox(height: AppSpace.lg),
                        rail,
                        const SizedBox(height: AppSpace.lg),
                        history,
                      ],
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

  Future<void> _addStep() async {
    final title = _step.text.trim();
    if (title.isEmpty) return;
    _step.clear();
    _stepFocus.requestFocus();
    await ref.read(tasksProvider.notifier).addStep(widget.taskId, title);
  }

  Future<void> _toggleTimer(TaskView view) async {
    await toggleTaskTimer(context, ref, view);
    _loadHistory();
  }

  Future<void> _changeStatus(TaskView view, TaskStatus status) async {
    if (status == TaskStatus.done) {
      await toggleTaskDone(context, ref, view);
      _loadHistory();
      return;
    }
    String? reason;
    if (status == TaskStatus.blocked) {
      reason = await _askBlockedReason();
      if (reason == null) return;
    }
    await ref
        .read(tasksProvider.notifier)
        .setStatus(widget.taskId, status, blockedReason: reason);
    _loadHistory();
  }

  Future<String?> _askBlockedReason() async {
    final controller = TextEditingController(text: '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('What is in the way?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Waiting on review, a decision, someone else…',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Mark blocked'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _archive(TaskView view) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Archive this task?',
      message:
          '“${view.task.title}” will leave the active lists but its history and '
          'tracked time stay in the ledger.',
      confirmLabel: 'Archive',
      icon: Icons.archive_outlined,
    );
    if (!confirmed) return;
    await ref.read(tasksProvider.notifier).setArchived(view, true);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _delete(TaskView view) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this task?',
      message:
          'This removes the task, its steps, attached files, and its activity '
          'trail. Tracked time is kept but becomes unassigned. This cannot be '
          'undone.',
      confirmLabel: 'Delete',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await ref.read(tasksProvider.notifier).deleteTask(view);
    if (mounted) Navigator.of(context).maybePop();
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.view,
    required this.onBack,
    required this.onEdit,
    required this.onTimer,
    required this.timerActive,
    required this.timerRunning,
    required this.onShare,
    required this.onArchive,
    required this.onDelete,
  });

  final TaskView view;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onTimer;
  final bool timerActive;
  final bool timerRunning;
  final VoidCallback onShare;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = Layout.isCompact(context);
    final menu = PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (value) {
        if (value == 'share') onShare();
        if (value == 'archive') onArchive();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'share',
          child: MenuAction(
            icon: Icons.ios_share_rounded,
            label: 'Share task bundle',
          ),
        ),
        PopupMenuItem(
          value: 'archive',
          child: MenuAction(icon: Icons.archive_outlined, label: 'Archive'),
        ),
        PopupMenuItem(
          value: 'delete',
          child: MenuAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
          ),
        ),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpace.sm : AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              'Task',
              style: AppText.label.copyWith(color: colors.inkFaint),
            ),
          ),
          if (compact) ...[
            IconButton(
              tooltip: timerActive
                  ? (timerRunning ? 'Pause timer' : 'Resume timer')
                  : 'Track time',
              onPressed: onTimer,
              icon: Icon(
                timerRunning
                    ? Icons.pause_circle_rounded
                    : Icons.play_circle_rounded,
                color: timerActive ? colors.accent : colors.primary,
                size: 27,
              ),
            ),
            IconButton(
              tooltip: 'Edit task',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 22),
            ),
            menu,
          ] else ...[
            OutlinedButton.icon(
              onPressed: onTimer,
              icon: Icon(
                timerRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 17,
              ),
              label: Text(
                timerActive
                    ? (timerRunning ? 'Pause' : 'Resume')
                    : 'Track time',
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
            ),
            menu,
          ],
        ],
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.view, required this.onEdit});

  final TaskView view;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final task = view.task;
    final compact = Layout.isCompact(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (view.category != null) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: view.category!.colorValue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  view.category!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(color: colors.inkMuted),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              'CREATED ${dateLabel(task.createdAt).toUpperCase()}',
              style: AppText.label.copyWith(
                color: colors.inkFaint,
                fontSize: 9,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        SelectableText(
          task.title,
          style: (compact ? AppText.displayM : AppText.displayL).copyWith(
            color: task.isDone ? colors.inkMuted : colors.ink,
            decoration: task.isDone ? TextDecoration.lineThrough : null,
            decorationColor: colors.inkFaint,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BadgePill(
              label: task.status.label,
              icon: task.status.icon,
              color: task.status.color(colors),
            ),
            BadgePill(
              label: task.kind.label,
              icon: task.kind.icon,
              color: task.kind.color(colors),
            ),
            BadgePill(
              label: '${task.priority.label} priority',
              icon: task.priority.icon,
              color: task.priority.color(colors),
            ),
            if (view.isOverdue)
              BadgePill(
                label: 'Overdue',
                icon: Icons.warning_amber_rounded,
                color: colors.rose,
              ),
            if (view.hasSteps)
              BadgePill(
                label: '${view.doneSteps} of ${view.totalSteps} steps',
                icon: Icons.checklist_rounded,
                color: colors.primary,
              ),
          ],
        ),
        if (task.blockedReason != null && task.blockedReason!.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: colors.rose.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: colors.rose.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.block_rounded, size: 16, color: colors.rose),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    task.blockedReason!,
                    style: AppText.bodySmall.copyWith(color: colors.ink),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({
    required this.controller,
    required this.onChanged,
    required this.saving,
    required this.dirty,
    required this.savedAt,
    required this.onFlush,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool saving;
  final bool dirty;
  final DateTime? savedAt;
  final VoidCallback onFlush;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.notes_rounded, size: 17, color: colors.inkMuted),
              const SizedBox(width: 6),
              Text(
                'NOTES',
                style: AppText.label.copyWith(color: colors.inkFaint),
              ),
              const Spacer(),
              Text(
                saving
                    ? 'Saving…'
                    : dirty
                    ? 'Unsaved'
                    : savedLabel(savedAt, DateTime.now()),
                style: AppText.bodySmall.copyWith(
                  color: dirty ? colors.accent : colors.inkFaint,
                  fontSize: 11,
                ),
              ),
              if (dirty && !saving) ...[
                const SizedBox(width: 6),
                TextButton(onPressed: onFlush, child: const Text('Save now')),
              ],
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          MarkdownEditor(
            controller: controller,
            onChanged: onChanged,
            minLines: 10,
            hintText: 'Context, links, decisions, what “done” means. Markdown works here.',
          ),
        ],
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({
    required this.view,
    required this.controller,
    required this.focusNode,
    required this.onAdd,
  });

  final TaskView view;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded, size: 17, color: colors.inkMuted),
              const SizedBox(width: 6),
              Text(
                'STEPS',
                style: AppText.label.copyWith(color: colors.inkFaint),
              ),
              const Spacer(),
              Text(
                view.hasSteps
                    ? '${(view.progress * 100).round()}% complete'
                    : 'Break the work down',
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (view.hasSteps) ...[
            const SizedBox(height: AppSpace.md),
            ProgressHairline(
              value: view.progress,
              color: view.category?.colorValue ?? colors.primary,
            ),
            const SizedBox(height: AppSpace.sm),
            for (var index = 0; index < view.subtasks.length; index++)
              _StepRow(
                step: view.subtasks[index],
                index: index,
                last: index == view.subtasks.length - 1,
              ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
              child: Text(
                'A task with steps is easier to start. Add the next physical action.',
                style: AppText.body.copyWith(
                  color: colors.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: controller,
            focusNode: focusNode,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Add a step…',
              suffixIcon: IconButton(
                tooltip: 'Add step',
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 19),
              ),
            ),
            onSubmitted: (_) => onAdd(),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends ConsumerWidget {
  const _StepRow({required this.step, required this.index, required this.last});

  final Subtask step;
  final int index;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final done = step.isDone;
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(color: colors.line.withValues(alpha: 0.6)),
              ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => ref.read(tasksProvider.notifier).toggleStep(step),
            borderRadius: BorderRadius.circular(99),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: AnimatedContainer(
                duration: AppDurations.fast,
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: done ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: done ? colors.primary : colors.lineStrong,
                    width: 1.4,
                  ),
                ),
                child: done
                    ? Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: colors.onPrimary,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              step.title,
              style: AppText.body.copyWith(
                color: done ? colors.inkMuted : colors.ink,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: colors.inkFaint,
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Step options',
            icon: Icon(
              Icons.more_horiz_rounded,
              size: 17,
              color: colors.inkFaint,
            ),
            onSelected: (value) {
              final notifier = ref.read(tasksProvider.notifier);
              switch (value) {
                case 'up':
                  notifier.moveStep(step, -1);
                  break;
                case 'down':
                  notifier.moveStep(step, 1);
                  break;
                case 'delete':
                  notifier.deleteStep(step);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'up',
                child: MenuAction(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Move up',
                ),
              ),
              PopupMenuItem(
                value: 'down',
                child: MenuAction(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Move down',
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: MenuAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete step',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRail extends ConsumerWidget {
  const _DetailRail({
    required this.view,
    required this.liveMs,
    required this.timerActive,
    required this.onEdit,
    required this.onTimer,
    required this.onStatus,
  });

  final TaskView view;
  final int liveMs;
  final bool timerActive;
  final VoidCallback onEdit;
  final VoidCallback onTimer;
  final ValueChanged<TaskStatus> onStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final timer = ref.watch(timerProvider).value;
    final elapsed = timerActive ? timer!.elapsed : Duration.zero;
    final totalMs = view.trackedMs + liveMs;
    final activeRunning = timerActive && (timer?.isRunning ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: timerActive ? colors.ink : colors.primary,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LiveDot(
                    color: timerActive ? colors.accent : colors.onPrimary,
                    size: 7,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    timerActive ? 'TRACKING THIS TASK' : 'TIME ON THIS TASK',
                    style: AppText.label.copyWith(
                      color: colors.onPrimary.withValues(alpha: 0.65),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                timerActive
                    ? formatStopwatch(elapsed)
                    : formatCompactMs(totalMs),
                style: AppText.monoLarge.copyWith(
                  color: colors.onPrimary,
                  fontSize: 30,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                totalMs == 0
                    ? 'No time tracked yet'
                    : '${formatCompactMs(totalMs)} all time',
                style: AppText.bodySmall.copyWith(
                  color: colors.onPrimary.withValues(alpha: 0.6),
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: onTimer,
                      icon: Icon(
                        timerActive
                            ? (activeRunning
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded)
                            : Icons.play_arrow_rounded,
                        size: 18,
                      ),
                      label: Text(
                        timerActive
                            ? (activeRunning ? 'Pause' : 'Resume')
                            : 'Start timer',
                      ),
                    ),
                  ),
                  if (timerActive) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Stop and save',
                      onPressed: () => confirmStopTimer(context, ref),
                      icon: Icon(
                        Icons.stop_rounded,
                        color: colors.onPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'STATUS',
                    style: AppText.label.copyWith(color: colors.inkFaint),
                  ),
                  const Spacer(),
                  TextButton(onPressed: onEdit, child: const Text('Edit')),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final status in TaskStatus.values)
                    ChoicePill(
                      label: status.label,
                      icon: status.icon,
                      selected: view.task.status == status,
                      color: status.color(colors),
                      onTap: () => onStatus(status),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.xl),
              _DetailRow(
                icon: Icons.category_outlined,
                label: 'Category',
                value: view.category?.name ?? 'Unfiled',
                color: view.category?.colorValue,
              ),
              _DetailRow(
                icon: Icons.work_outline_rounded,
                label: 'Kind',
                value: view.task.kind.label,
              ),
              _DetailRow(
                icon: Icons.flag_outlined,
                label: 'Priority',
                value: view.task.priority.label,
              ),
              _DetailRow(
                icon: Icons.fitness_center_rounded,
                label: 'Effort',
                value: '${view.task.effort} / 5',
              ),
              _DetailRow(
                icon: Icons.timer_outlined,
                label: 'Estimate',
                value: formatMinutes(view.task.estimateMinutes),
              ),
              _DetailRow(
                icon: Icons.event_rounded,
                label: 'Planned',
                value: view.task.plannedDate == null
                    ? 'Inbox'
                    : relativeDayLabel(parseDateKey(view.task.plannedDate!)),
              ),
              if (view.task.scheduledStart != null)
                _DetailRow(
                  icon: Icons.schedule_rounded,
                  label: 'Window',
                  value: timeRangeLabel(
                    view.task.scheduledStart,
                    view.task.scheduledEnd,
                  ),
                ),
              if (view.task.dueAt != null)
                _DetailRow(
                  icon: Icons.flag_circle_outlined,
                  label: 'Due',
                  value:
                      '${dateLabel(view.task.dueAt!)} · ${timeLabel(view.task.dueAt!)}',
                  color: view.isOverdue ? colors.rose : null,
                ),
              if (view.task.reminderAt != null)
                _DetailRow(
                  icon: Icons.notifications_active_outlined,
                  label: 'Reminder',
                  value:
                      '${dateLabel(view.task.reminderAt!)} · '
                      '${timeLabel(view.task.reminderAt!)}',
                  color: colors.accent,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WEIGHTAGE',
                style: AppText.label.copyWith(color: colors.inkFaint),
              ),
              const SizedBox(height: AppSpace.md),
              _WeightRow(label: 'Effort', value: '× ${view.task.effort}'),
              _WeightRow(
                label: 'Priority',
                value: '× ${view.task.priority.multiplier}',
              ),
              _WeightRow(
                label: 'Kind',
                value: '× ${_kindMultiplier(view.task.kind)}',
              ),
              _WeightRow(
                label: 'Category',
                value: '× ${(view.category?.weight ?? 1).toStringAsFixed(1)}',
              ),
              Divider(color: colors.line, height: AppSpace.xl),
              Row(
                children: [
                  Text(
                    'Worth',
                    style: AppText.bodyMedium.copyWith(color: colors.inkMuted),
                  ),
                  const Spacer(),
                  Text(
                    formatPoints(view.points),
                    style: AppText.monoLarge.copyWith(
                      color: colors.primary,
                      fontSize: 19,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                view.hasSteps
                    ? '${formatPoints(view.earnedPoints)} earned at current progress'
                    : 'Earned when complete',
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _kindMultiplier(WorkKind kind) => switch (kind) {
    WorkKind.official => 1.0,
    WorkKind.adhoc => 0.75,
    WorkKind.personal => 0.5,
    WorkKind.learning => 0.9,
    WorkKind.admin => 0.6,
    WorkKind.creative => 0.85,
  };
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.inkFaint),
          const SizedBox(width: 7),
          Text(
            label,
            style: AppText.bodySmall.copyWith(color: colors.inkFaint),
          ),
          const Spacer(),
          if (color != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodySmall.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightRow extends StatelessWidget {
  const _WeightRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: AppText.bodySmall.copyWith(color: colors.inkMuted),
          ),
          const Spacer(),
          Text(
            value,
            style: AppText.monoData.copyWith(
              color: colors.inkFaint,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentsCard extends StatelessWidget {
  const _AttachmentsCard({
    required this.attachments,
    required this.onAdd,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final List<TaskAttachment> attachments;
  final Future<void> Function() onAdd;
  final Future<void> Function(TaskAttachment) onOpen;
  final Future<void> Function(TaskAttachment) onShare;
  final Future<void> Function(TaskAttachment) onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file_rounded, size: 16, color: colors.primary),
              const SizedBox(width: 7),
              Text(
                'FILES & REFERENCES',
                style: AppText.label.copyWith(color: colors.inkFaint),
              ),
              if (attachments.isNotEmpty) ...[
                const SizedBox(width: 7),
                Text(
                  '${attachments.length}',
                  style: AppText.monoData.copyWith(
                    color: colors.inkFaint,
                    fontSize: 10,
                  ),
                ),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: () => onAdd(),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add files'),
              ),
            ],
          ),
          if (attachments.isEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              'Attach briefs, screenshots, references, or working files. They '
              'travel with this task when you share it or create a backup.',
              style: AppText.bodySmall.copyWith(
                color: colors.inkFaint,
                fontSize: 11.5,
              ),
            ),
          ] else
            for (final attachment in attachments) ...[
              Divider(color: colors.line, height: AppSpace.lg),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.surfaceSunken,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      border: Border.all(color: colors.line),
                    ),
                    child: Icon(
                      _attachmentIcon(attachment.mimeType),
                      size: 15,
                      color: colors.inkMuted,
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySmall.copyWith(
                            color: colors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          attachment.sizeLabel,
                          style: AppText.monoData.copyWith(
                            color: colors.inkFaint,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open',
                    onPressed: () => onOpen(attachment),
                    icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'File actions',
                    onSelected: (value) {
                      if (value == 'share') onShare(attachment);
                      if (value == 'delete') onDelete(attachment);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'share',
                        child: MenuAction(
                          icon: Icons.ios_share_rounded,
                          label: 'Share file',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: MenuAction(
                          icon: Icons.delete_outline_rounded,
                          label: 'Remove',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  static IconData _attachmentIcon(String mime) {
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('video/')) return Icons.movie_outlined;
    if (mime.startsWith('audio/')) return Icons.audio_file_outlined;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mime.startsWith('text/')) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.view,
    required this.entries,
    required this.activity,
    required this.loading,
    required this.liveMs,
    required this.timerActive,
  });

  final TaskView view;
  final List<TimeEntry> entries;
  final List<ActivityEvent> activity;
  final bool loading;
  final int liveMs;
  final bool timerActive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 17, color: colors.inkMuted),
              const SizedBox(width: 6),
              Text(
                'HISTORY',
                style: AppText.label.copyWith(color: colors.inkFaint),
              ),
              const Spacer(),
              Text(
                '${formatCompactMs(view.trackedMs + liveMs)} tracked',
                style: AppText.monoData.copyWith(
                  color: colors.inkMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            const SizedBox(height: AppSpace.md),
            if (entries.isEmpty)
              Text(
                'No time logged. Start the timer when you begin, not when you remember.',
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              for (final entry in entries) _TimeEntryRow(entry: entry),
            if (activity.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xl),
              Text(
                'ACTIVITY',
                style: AppText.label.copyWith(
                  color: colors.inkFaint,
                  fontSize: 9,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              for (final event in activity)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: colors.lineStrong,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.summary,
                          style: AppText.bodySmall.copyWith(
                            color: colors.inkMuted,
                            fontSize: 11.8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${dateLabel(event.createdAt)} ${timeLabel(event.createdAt)}',
                        style: AppText.monoData.copyWith(
                          color: colors.inkFaint,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TimeEntryRow extends StatelessWidget {
  const _TimeEntryRow({required this.entry});

  final TimeEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            entry.source == EntrySource.timer
                ? Icons.timer_outlined
                : Icons.edit_calendar_outlined,
            size: 14,
            color: colors.inkFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${dateLabel(entry.startedAt)} · '
              '${timeLabel(entry.startedAt)}–${timeLabel(entry.endedAt)}',
              style: AppText.bodySmall.copyWith(color: colors.inkMuted),
            ),
          ),
          if (entry.note.isNotEmpty) ...[
            Flexible(
              child: Text(
                entry.note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            formatCompactMs(entry.durationMs),
            style: AppText.monoData.copyWith(color: colors.ink, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
