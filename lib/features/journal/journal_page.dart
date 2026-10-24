import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/markdown.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../core/utils/durations.dart';
import '../../data/models/journal_entry.dart';
import '../../state/journal_controller.dart';
import '../../state/ui_state.dart';

class JournalPage extends ConsumerStatefulWidget {
  const JournalPage({super.key});

  @override
  ConsumerState<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends ConsumerState<JournalPage> {
  final _body = TextEditingController();
  final _search = TextEditingController();
  Timer? _saveTimer;
  String _loadedKey = '';
  bool _dirty = false;
  bool _saving = false;
  DateTime? _savedAt;
  int? _mood;
  int? _energy;

  static const _prompts = [
    'What moved forward today?',
    'What resisted, and why?',
    'What did I learn?',
    'What deserves tomorrow’s attention?',
  ];

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty && _loadedKey.isNotEmpty) {
      final key = _loadedKey;
      final body = _body.text;
      final mood = _mood;
      final energy = _energy;
      // Fire-and-forget on teardown; the controller updates optimistically.
      ref
          .read(journalProvider.notifier)
          .save(dateKey: key, bodyMd: body, mood: mood, energy: energy);
    }
    _body.dispose();
    _search.dispose();
    super.dispose();
  }

  void _sync(String key, JournalEntry? entry) {
    if (_loadedKey == key) return;
    _loadedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _body.text = entry?.bodyMd ?? '';
        _mood = entry?.mood;
        _energy = entry?.energy;
        _dirty = false;
        _savedAt = entry?.updatedAt;
      });
    });
  }

  void _scheduleSave() {
    setState(() => _dirty = true);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), _save);
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    if (_loadedKey.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(journalProvider.notifier)
          .save(
            dateKey: _loadedKey,
            bodyMd: _body.text,
            mood: _mood,
            energy: _energy,
          );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _savedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, 'Could not save the entry: $error');
    }
  }

  Future<void> _goDate(DateTime date) async {
    if (_dirty) await _save();
    ref.read(selectedDateProvider.notifier).state = startOfDay(date);
  }

  void _insertPrompt(String prompt) {
    final current = _body.text;
    final prefix = current.trim().isEmpty ? '' : '\n\n';
    _body.text = '$current$prefix**$prompt**\n';
    _body.selection = TextSelection.collapsed(offset: _body.text.length);
    _scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedDateProvider);
    final key = dateKey(selected);
    final entriesAsync = ref.watch(journalProvider);
    final entries = entriesAsync.valueOrNull;
    final entry = ref.watch(journalForDateProvider(key));
    final streak = ref.watch(journalStreakProvider);
    final query = ref.watch(journalSearchProvider);
    if (entries != null) _sync(key, entry);
    final colors = context.colors;
    final wordCount = _wordCount(_body.text);
    final filtered = (entries ?? const <JournalEntry>[])
        .where(
          (item) =>
              query.trim().isEmpty ||
              item.bodyMd.toLowerCase().contains(query.toLowerCase()) ||
              item.dateKey.contains(query),
        )
        .toList();
    final wide = MediaQuery.sizeOf(context).width >= 1040;

    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous day',
                          onPressed: () => _goDate(addDays(selected, -1)),
                          icon: const Icon(
                            Icons.chevron_left_rounded,
                            size: 20,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              relativeDayLabel(selected).toUpperCase(),
                              style: AppText.label.copyWith(
                                color: colors.inkFaint,
                                fontSize: 9,
                              ),
                            ),
                            Text(
                              longDateLabel(selected),
                              style: AppText.displayS.copyWith(
                                color: colors.ink,
                                fontSize: 19,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          tooltip: 'Next day',
                          onPressed: () => _goDate(addDays(selected, 1)),
                          icon: const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isToday(selected))
                    TextButton(
                      onPressed: () => _goDate(DateTime.now()),
                      child: const Text('Today'),
                    ),
                  TextButton.icon(
                    onPressed: _dirty ? _save : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_done_outlined, size: 16),
                    label: Text(
                      _saving
                          ? 'Saving'
                          : _dirty
                          ? 'Save now'
                          : savedLabel(_savedAt, DateTime.now()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              Divider(color: colors.line),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  _ScalePicker(
                    label: 'Mood',
                    value: _mood,
                    color: colors.gold,
                    onChange: (value) {
                      setState(() => _mood = value);
                      _scheduleSave();
                    },
                  ),
                  const SizedBox(width: AppSpace.xxl),
                  _ScalePicker(
                    label: 'Energy',
                    value: _energy,
                    color: colors.accent,
                    onChange: (value) {
                      setState(() => _energy = value);
                      _scheduleSave();
                    },
                  ),
                  const Spacer(),
                  Text(
                    '$wordCount ${wordCount == 1 ? 'word' : 'words'}',
                    style: AppText.monoData.copyWith(
                      color: colors.inkFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              MarkdownEditor(
                controller: _body,
                onChanged: (_) => _scheduleSave(),
                minLines: wide ? 18 : 12,
                hintText: 'Start anywhere. What happened, what it cost, what it taught you…',
              ),
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Text(
                    'PROMPTS',
                    style: AppText.label.copyWith(
                      color: colors.inkFaint,
                      fontSize: 8.5,
                    ),
                  ),
                  for (final prompt in _prompts)
                    InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => _insertPrompt(prompt),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceSunken,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          prompt,
                          style: AppText.bodySmall.copyWith(
                            color: colors.inkMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (entry != null && !entry.isEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: colors.rose),
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 15),
              label: const Text('Delete this entry'),
            ),
          ),
        ],
      ],
    );

    final rail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department_outlined,
                    size: 17,
                    color: colors.gold,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'STREAK',
                    style: AppText.label.copyWith(color: colors.inkFaint),
                  ),
                  const Spacer(),
                  Text(
                    '$streak ${streak == 1 ? 'day' : 'days'}',
                    style: AppText.monoData.copyWith(color: colors.gold),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                streak == 0
                    ? 'One honest note is enough to begin.'
                    : 'Keep the thread. Even three lines count.',
                style: AppText.bodySmall.copyWith(
                  color: colors.inkMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SurfaceCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'Search the journal…',
                  prefixIcon: Icon(Icons.search_rounded, size: 17),
                  isDense: true,
                ),
                onChanged: (value) =>
                    ref.read(journalSearchProvider.notifier).state = value,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'RECENT ENTRIES',
                style: AppText.label.copyWith(
                  color: colors.inkFaint,
                  fontSize: 8.5,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              if (entriesAsync.isLoading && entries == null)
                const Padding(
                  padding: EdgeInsets.all(AppSpace.lg),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Text(
                    query.isEmpty ? 'No entries yet.' : 'No entries match.',
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkFaint,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                for (final item in filtered.take(14))
                  _HistoryRow(
                    item: item,
                    selected: item.dateKey == key,
                    onTap: () => _goDate(parseDateKey(item.dateKey)),
                  ),
            ],
          ),
        ),
      ],
    );

    return PageWidth(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              eyebrow: 'The private record',
              title: 'Journal',
              subtitle:
                  'A markdown page per day. No audience, no performance — '
                  'just what the work felt like while it was yours.',
              actions: [
                if (streak > 0)
                  BadgePill(
                    label: '$streak-day streak',
                    icon: Icons.local_fire_department_outlined,
                    color: colors.gold,
                  ),
                OutlinedButton.icon(
                  onPressed: () => _goDate(DateTime.now()),
                  icon: const Icon(Icons.edit_note_rounded, size: 17),
                  label: const Text('Write today'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: editor),
                  const SizedBox(width: AppSpace.x3),
                  SizedBox(width: 320, child: rail),
                ],
              )
            else ...[
              editor,
              const SizedBox(height: AppSpace.lg),
              rail,
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this entry?',
      message:
          'The journal entry for ${dateLabel(parseDateKey(_loadedKey))} will be '
          'removed. This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await ref.read(journalProvider.notifier).delete(_loadedKey);
    if (!mounted) return;
    setState(() {
      _body.clear();
      _dirty = false;
      _mood = null;
      _energy = null;
      _savedAt = null;
    });
    showToast(context, 'Journal entry deleted');
  }

  int _wordCount(String text) {
    final matches = RegExp(r"[\w’'-]+").allMatches(text);
    return matches.length;
  }
}

class _ScalePicker extends StatelessWidget {
  const _ScalePicker({
    required this.label,
    required this.value,
    required this.color,
    required this.onChange,
  });

  final String label;
  final int? value;
  final Color color;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: AppText.label.copyWith(color: colors.inkFaint, fontSize: 8.5),
        ),
        const SizedBox(width: 6),
        for (var i = 1; i <= 5; i++)
          InkWell(
            onTap: () => onChange(i),
            borderRadius: BorderRadius.circular(99),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: AnimatedContainer(
                duration: AppDurations.fast,
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value != null && i <= value!
                      ? color
                      : colors.surfaceSunken,
                  border: Border.all(
                    color: value != null && i <= value!
                        ? color
                        : colors.lineStrong,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final JournalEntry item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final excerpt = item.bodyMd
        .replaceAll(RegExp(r'[#>*_`\-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.sm,
        ),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: selected
              ? colors.primarySoft.withValues(alpha: 0.55)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel(parseDateKey(item.dateKey)).split(' ').first,
                    style: AppText.monoData.copyWith(
                      color: selected ? colors.primary : colors.ink,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    monthShort(parseDateKey(item.dateKey)),
                    style: AppText.label.copyWith(
                      color: colors.inkFaint,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                excerpt.isEmpty ? 'Blank page' : excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySmall.copyWith(
                  color: excerpt.isEmpty ? colors.inkFaint : colors.inkMuted,
                  fontStyle: excerpt.isEmpty ? FontStyle.italic : null,
                  fontSize: 11.3,
                  height: 1.4,
                ),
              ),
            ),
            if (item.mood != null) ...[
              const SizedBox(width: 4),
              Text(
                '${item.mood}/5',
                style: AppText.monoData.copyWith(
                  color: colors.gold,
                  fontSize: 9,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
