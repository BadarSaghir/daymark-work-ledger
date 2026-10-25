import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/enum_ui.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/form.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/menu_action.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/durations.dart';
import '../../data/models/category.dart';
import '../../data/models/task_view.dart';
import '../../state/categories_controller.dart';
import '../../state/tasks_controller.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  static const _pageSize = 12;
  static const _archivedPageSize = 8;

  final _search = TextEditingController();
  int _page = 0;
  int _archivedVisible = _archivedPageSize;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final categoriesAsync = ref.watch(categoriesProvider);
    final categories = categoriesAsync.value ?? const <Category>[];
    final views = ref.watch(tasksProvider).value ?? const <TaskView>[];
    final query = _search.text.trim().toLowerCase();
    bool matches(Category category) =>
        query.isEmpty || category.name.toLowerCase().contains(query);
    final active = categories
        .where((category) => !category.archived && matches(category))
        .toList();
    final archived = categories
        .where((category) => category.archived && matches(category))
        .toList();
    final pages = active.isEmpty ? 1 : ((active.length - 1) ~/ _pageSize) + 1;
    final page = _page.clamp(0, pages - 1).toInt();
    final start = page * _pageSize;
    final visible = active.skip(start).take(_pageSize).toList();
    final visibleArchived = archived.take(_archivedVisible).toList();
    final tasksByCategory = <String, List<TaskView>>{};
    for (final view in views) {
      final id = view.task.categoryId;
      if (id != null) (tasksByCategory[id] ??= []).add(view);
    }

    return PageWidth(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: AppSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              eyebrow: 'The buckets that carry weight',
              title: 'Categories',
              subtitle:
                  'Categories are not labels. Each one carries a multiplier '
                  'that changes what a piece of work is worth.',
              actions: [
                FilledButton.icon(
                  onPressed: () => showCategoryEditor(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New category'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            if (categoriesAsync.isLoading && categories.isEmpty)
              const LoadingBlock(height: 240)
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: 'Search ${categories.length} categories…',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _page = 0);
                                },
                                icon: const Icon(Icons.close_rounded, size: 17),
                              ),
                      ),
                      onChanged: (_) => setState(() => _page = 0),
                    ),
                  ),
                  if (active.isNotEmpty) ...[
                    const SizedBox(width: AppSpace.md),
                    Text(
                      '${active.length} active',
                      style: AppText.monoData.copyWith(
                        color: colors.inkFaint,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              if (visible.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpace.xl),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: colors.line),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        query.isEmpty
                            ? Icons.category_outlined
                            : Icons.search_off_rounded,
                        size: 26,
                        color: colors.inkFaint,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        query.isEmpty
                            ? 'No categories yet'
                            : 'No categories match “${_search.text.trim()}”',
                        textAlign: TextAlign.center,
                        style: AppText.titleM.copyWith(color: colors.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        query.isEmpty
                            ? 'Create a category to give this work a weight.'
                            : 'Try a shorter search, or clear it to see all '
                                  'categories.',
                        textAlign: TextAlign.center,
                        style: AppText.bodySmall.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = constraints.maxWidth >= 1100
                        ? (constraints.maxWidth - AppSpace.lg * 2) / 3
                        : constraints.maxWidth >= 700
                        ? (constraints.maxWidth - AppSpace.lg) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: AppSpace.lg,
                      runSpacing: AppSpace.lg,
                      children: [
                        for (final category in visible)
                          SizedBox(
                            width: cardWidth,
                            child: _CategoryCard(
                              category: category,
                              tasks: tasksByCategory[category.id] ?? const [],
                              onEdit: () => showCategoryEditor(
                                context,
                                existing: category,
                              ),
                              onArchive: () =>
                                  _archive(context, category, true),
                              onDelete: () => _delete(context, category),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              if (active.length > _pageSize) ...[
                const SizedBox(height: AppSpace.lg),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous page',
                      onPressed: page == 0
                          ? null
                          : () => setState(() => _page = page - 1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '$start–${start + visible.length} of ${active.length} '
                        '· page ${page + 1} of $pages',
                        textAlign: TextAlign.center,
                        style: AppText.monoData.copyWith(
                          color: colors.inkFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next page',
                      onPressed: page >= pages - 1
                          ? null
                          : () => setState(() => _page = page + 1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpace.xl),
              _WeightExplainer(),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xl),
                Row(
                  children: [
                    Text(
                      'ARCHIVED',
                      style: AppText.label.copyWith(color: colors.inkFaint),
                    ),
                    const Spacer(),
                    Text(
                      '${archived.length}',
                      style: AppText.monoData.copyWith(
                        color: colors.inkFaint,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                for (final category in visibleArchived)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpace.sm),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.md,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      border: Border.all(color: colors.line),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          category.iconData,
                          size: 17,
                          color: colors.inkFaint,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(
                            category.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.bodySmall.copyWith(
                              color: colors.inkMuted,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _archive(context, category, false),
                          child: const Text('Restore'),
                        ),
                      ],
                    ),
                  ),
                if (archived.length > _archivedVisible)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _archivedVisible += _archivedPageSize),
                      icon: const Icon(Icons.expand_more_rounded, size: 17),
                      label: Text(
                        'Show ${archived.length - _archivedVisible} more archived',
                      ),
                    ),
                  )
                else if (_archivedVisible > _archivedPageSize)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          setState(() => _archivedVisible = _archivedPageSize),
                      child: const Text('Show fewer'),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _archive(
    BuildContext context,
    Category category,
    bool archived,
  ) async {
    await ref.read(categoriesProvider.notifier).setArchived(category, archived);
    if (context.mounted) {
      showToast(
        context,
        archived
            ? 'Archived “${category.name}”'
            : 'Restored “${category.name}”',
      );
    }
  }

  Future<void> _delete(BuildContext context, Category category) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete “${category.name}”?',
      message:
          'A category can only be deleted when no tasks use it. If it holds '
          'history, archive it instead — archived categories stay visible.',
      confirmLabel: 'Delete',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    try {
      await ref.read(categoriesProvider.notifier).deleteIfEmpty(category);
      if (context.mounted) showToast(context, 'Category deleted');
    } catch (error) {
      if (context.mounted) {
        showToast(
          context,
          'Category still has tasks. Archive it to keep the history intact.',
        );
      }
    }
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.tasks,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
  });

  final Category category;
  final List<TaskView> tasks;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final open = tasks.where((view) => !view.isDone).length;
    final done = tasks.where((view) => view.isDone).length;
    final tracked = tasks.fold<int>(0, (sum, view) => sum + view.trackedMs);
    final points = tasks
        .where((view) => !view.isDone)
        .fold<double>(0, (sum, view) => sum + view.points);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 5,
            decoration: BoxDecoration(
              color: category.colorValue,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.card),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: category.colorValue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.badge),
                      ),
                      child: Icon(
                        category.iconData,
                        size: 19,
                        color: category.colorValue,
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.name,
                            style: AppText.titleM.copyWith(color: colors.ink),
                          ),
                          Text(
                            '×${category.weight.toStringAsFixed(1)} weight',
                            style: AppText.monoData.copyWith(
                              color: category.colorValue,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Category options',
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        size: 18,
                        color: colors.inkFaint,
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            onEdit();
                          case 'archive':
                            onArchive();
                          case 'delete':
                            onDelete();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: MenuAction(
                            icon: Icons.edit_outlined,
                            label: 'Edit',
                          ),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: MenuAction(
                            icon: Icons.archive_outlined,
                            label: 'Archive',
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: MenuAction(
                            icon: Icons.delete_outline_rounded,
                            label: 'Delete',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                Row(
                  children: [
                    Expanded(
                      child: _CardStat(
                        label: 'Open',
                        value: '$open',
                        color: colors.ink,
                      ),
                    ),
                    Expanded(
                      child: _CardStat(
                        label: 'Done',
                        value: '$done',
                        color: colors.green,
                      ),
                    ),
                    Expanded(
                      child: _CardStat(
                        label: 'Time',
                        value: formatCompactMs(tracked),
                        color: colors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Divider(color: colors.line),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    Text(
                      'Open weight',
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      formatPoints(points),
                      style: AppText.monoData.copyWith(
                        color: colors.ink,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  const _CardStat({
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
          style: AppText.label.copyWith(color: colors.inkFaint, fontSize: 8),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppText.monoData.copyWith(color: color, fontSize: 14),
        ),
      ],
    );
  }
}

class _WeightExplainer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      color: colors.primarySoft.withValues(alpha: 0.35),
      borderColor: colors.primary.withValues(alpha: 0.18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.speed_rounded, size: 20, color: colors.primary),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How weightage works',
                  style: AppText.bodyMedium.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'points = effort (1–5) × priority multiplier × kind multiplier '
                  '× category weight. Effort is the size of the work; category '
                  'weight is how much this kind of work matters to you.',
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkMuted,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showCategoryEditor(BuildContext context, {Category? existing}) {
  return showAppSheet<void>(
    context,
    (sheetContext) => _CategoryEditor(existing: existing),
    maxWidth: 560,
  );
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({this.existing});

  final Category? existing;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late int _color =
      widget.existing?.color ?? AppColors.categoryPalette.first.toARGB32();
  late String _icon = widget.existing?.icon ?? 'layers';
  late double _weight = widget.existing?.weight ?? 1.0;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'A category needs a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final notifier = ref.read(categoriesProvider.notifier);
      if (widget.existing == null) {
        await notifier.create(
          name: name,
          color: _color,
          icon: _icon,
          weight: _weight,
        );
      } else {
        await notifier.updateCategory(
          widget.existing!.copyWith(
            name: name,
            color: _color,
            icon: _icon,
            weight: _weight,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(
        context,
        widget.existing == null ? 'Category created' : 'Saved',
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
    final tone = Color(_color);
    return AppSheet(
      title: widget.existing == null ? 'New category' : 'Edit category',
      subtitle: 'A bucket, a colour, and a weight.',
      icon: Icons.category_outlined,
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
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(widget.existing == null ? 'Create' : 'Save'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormLabel('Name'),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Deep work, Admin, Learning…',
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          const FormLabel('Colour'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final color in AppColors.categoryPalette)
                InkWell(
                  onTap: () => setState(() => _color = color.toARGB32()),
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == color.toARGB32()
                            ? colors.ink
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: _color == color.toARGB32()
                        ? const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          const FormLabel('Icon'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final key in CategoryIcons.keys)
                InkWell(
                  onTap: () => setState(() => _icon = key),
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _icon == key
                          ? tone.withValues(alpha: 0.16)
                          : colors.surfaceSunken,
                      borderRadius: BorderRadius.circular(AppRadius.badge),
                      border: Border.all(
                        color: _icon == key ? tone : Colors.transparent,
                      ),
                    ),
                    child: Icon(
                      CategoryIcons.fromKey(key),
                      size: 17,
                      color: _icon == key ? tone : colors.inkMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          Row(
            children: [
              const Expanded(
                child: FormLabel('Weight', hint: 'How much this work matters'),
              ),
              Text(
                '×${_weight.toStringAsFixed(1)}',
                style: AppText.monoLarge.copyWith(color: tone, fontSize: 22),
              ),
            ],
          ),
          Slider(
            value: _weight,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            activeColor: tone,
            onChanged: (value) => setState(() => _weight = value),
          ),
          Row(
            children: [
              Text(
                'Lighter',
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 10.5,
                ),
              ),
              const Spacer(),
              Text(
                'Heavier',
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 10.5,
                ),
              ),
            ],
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
