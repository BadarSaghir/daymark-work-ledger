import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/ui/enum_ui.dart';
import '../core/ui/form.dart';
import '../core/ui/sheets.dart';
import '../data/models/category.dart';

const int _pageSize = 12;

/// A searchable, paginated category chooser. The task editor never builds a
/// pill for every category, so hundreds of categories stay fast on phones.
Future<String?> showCategoryPicker(
  BuildContext context, {
  required List<Category> categories,
  String? selectedId,
  bool allowUnfiled = true,
}) {
  return showAppSheet<String>(
    context,
    (sheetContext) => _CategoryPickerSheet(
      categories: categories.where((category) => !category.archived).toList(),
      selectedId: selectedId,
      allowUnfiled: allowUnfiled,
    ),
    maxWidth: 560,
  );
}

class CategoryPickerField extends StatelessWidget {
  const CategoryPickerField({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onChanged,
    this.label = 'Category',
  });

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Category? selected;
    for (final category in categories) {
      if (category.id == selectedId) selected = category;
    }
    final tone = selected?.colorValue ?? colors.inkFaint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel(
          label,
          hint: '${categories.where((c) => !c.archived).length} available',
        ),
        InkWell(
          onTap: () async {
            final choice = await showCategoryPicker(
              context,
              categories: categories,
              selectedId: selectedId,
            );
            if (choice == null) return;
            onChanged(choice.isEmpty ? null : choice);
          },
          borderRadius: BorderRadius.circular(AppRadius.input),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: colors.line),
            ),
            child: Row(
              children: [
                Icon(
                  selected?.iconData ?? Icons.inbox_outlined,
                  size: 17,
                  color: tone,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected?.name ?? 'Unfiled',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodySmall.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        selected == null
                            ? 'No category · still counts as work'
                            : 'Weight ×${selected.weight.toStringAsFixed(1)} · tap to change',
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
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: colors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.selectedId,
    required this.allowUnfiled,
  });

  final List<Category> categories;
  final String? selectedId;
  final bool allowUnfiled;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final _query = TextEditingController();
  int _page = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Category> get _filtered {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return widget.categories;
    return widget.categories
        .where((category) => category.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filtered = _filtered;
    final pages = math.max(1, (filtered.length / _pageSize).ceil());
    final page = _page.clamp(0, pages - 1).toInt();
    final start = page * _pageSize;
    final visible = filtered.skip(start).take(_pageSize).toList();
    return AppSheet(
      title: 'Choose category',
      subtitle: 'Search and page through the ledger’s categories.',
      icon: Icons.category_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search categories…',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _query.clear();
                        setState(() => _page = 0);
                      },
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
            ),
            onChanged: (_) => setState(() => _page = 0),
          ),
          const SizedBox(height: AppSpace.md),
          if (widget.allowUnfiled)
            _CategoryChoice(
              icon: Icons.inbox_outlined,
              color: colors.inkFaint,
              name: 'Unfiled',
              detail: 'No multiplier · keep it for later',
              selected: widget.selectedId == null,
              onTap: () => Navigator.of(context).pop(''),
            ),
          for (final category in visible)
            _CategoryChoice(
              icon: category.iconData,
              color: category.colorValue,
              name: category.name,
              detail:
                  'Weight ×${category.weight.toStringAsFixed(1)} · '
                  '${category.position + 1} in the ledger',
              selected: widget.selectedId == category.id,
              onTap: () => Navigator.of(context).pop(category.id),
            ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
              child: Text(
                'No category matches “${_query.text.trim()}”.',
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          if (filtered.length > _pageSize) ...[
            const SizedBox(height: AppSpace.md),
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
                    '${start + 1}–${math.min(start + _pageSize, filtered.length)} '
                    'of ${filtered.length} · page ${page + 1} of $pages',
                    textAlign: TextAlign.center,
                    style: AppText.monoData.copyWith(
                      color: colors.inkFaint,
                      fontSize: 10,
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
        ],
      ),
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    required this.icon,
    required this.color,
    required this.name,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String name;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected
            ? colors.primarySoft.withValues(alpha: 0.55)
            : colors.surfaceSunken.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(
          color: selected
              ? colors.primary.withValues(alpha: 0.35)
              : colors.line,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        onTap: onTap,
        leading: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.badge),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.bodySmall.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.bodySmall.copyWith(
            color: colors.inkFaint,
            fontSize: 10,
          ),
        ),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, size: 18, color: colors.primary)
            : null,
      ),
    );
  }
}
