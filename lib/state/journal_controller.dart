import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/utils/date_keys.dart';
import '../data/models/journal_entry.dart';
import 'repository_providers.dart';

class JournalController extends AsyncNotifier<List<JournalEntry>> {
  @override
  Future<List<JournalEntry>> build() {
    return ref.watch(journalRepositoryProvider).list();
  }

  Future<JournalEntry> save({
    required String dateKey,
    required String bodyMd,
    int? mood,
    int? energy,
  }) async {
    final entry = await ref
        .read(journalRepositoryProvider)
        .save(dateKey: dateKey, bodyMd: bodyMd, mood: mood, energy: energy);
    final current = [...(state.value ?? const <JournalEntry>[])];
    final index = current.indexWhere((item) => item.dateKey == dateKey);
    if (index >= 0) {
      current[index] = entry;
    } else {
      current.add(entry);
      current.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    }
    state = AsyncData(current);
    return entry;
  }

  Future<void> delete(String dateKey) async {
    await ref.read(journalRepositoryProvider).delete(dateKey);
    final current = [...(state.value ?? const <JournalEntry>[])]
      ..removeWhere((entry) => entry.dateKey == dateKey);
    state = AsyncData(current);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(journalRepositoryProvider).list(),
    );
  }
}

final journalProvider =
    AsyncNotifierProvider<JournalController, List<JournalEntry>>(
      JournalController.new,
    );

final journalForDateProvider = Provider.family<JournalEntry?, String>((
  ref,
  dateKey,
) {
  final entries = ref.watch(journalProvider).value ?? const [];
  for (final entry in entries) {
    if (entry.dateKey == dateKey) return entry;
  }
  return null;
});

final journalSearchProvider = StateProvider<String>((ref) => '');

/// Consecutive journaled days ending today (or yesterday, if today is still
/// unwritten).
final journalStreakProvider = Provider<int>((ref) {
  final entries = ref.watch(journalProvider).value ?? const [];
  final filled = <String>{
    for (final entry in entries)
      if (entry.bodyMd.trim().isNotEmpty) entry.dateKey,
  };
  if (filled.isEmpty) return 0;
  var cursor = startOfDay(DateTime.now());
  if (!filled.contains(dateKey(cursor))) {
    cursor = addDays(cursor, -1);
    if (!filled.contains(dateKey(cursor))) return 0;
  }
  var streak = 0;
  while (filled.contains(dateKey(cursor))) {
    streak++;
    cursor = addDays(cursor, -1);
  }
  return streak;
});
