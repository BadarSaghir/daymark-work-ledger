import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/date_keys.dart';
import '../../core/utils/ids.dart';
import '../db/app_database.dart';
import '../models/journal_entry.dart';

class JournalRepository {
  JournalRepository(this._appDb);

  final AppDatabase _appDb;

  Database get _db => _appDb.db;

  Future<List<JournalEntry>> list({int? limit, String? search}) async {
    final query = (search ?? '').trim();
    final rows = await _db.query(
      'journal_entries',
      where: query.isEmpty ? null : 'body_md LIKE ?',
      whereArgs: query.isEmpty ? null : ['%$query%'],
      orderBy: 'date_key DESC',
      limit: limit,
    );
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<JournalEntry?> byDate(String key) async {
    final rows = await _db.query(
      'journal_entries',
      where: 'date_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return JournalEntry.fromMap(rows.first);
  }

  Future<JournalEntry> save({
    required String dateKey,
    required String bodyMd,
    int? mood,
    int? energy,
  }) async {
    final existing = await byDate(dateKey);
    final now = DateTime.now();
    if (existing == null) {
      final entry = JournalEntry(
        id: newId(),
        dateKey: dateKey,
        bodyMd: bodyMd,
        mood: mood,
        energy: energy,
        createdAt: now,
        updatedAt: now,
      );
      await _db.insert('journal_entries', entry.toMap());
      return entry;
    }
    final updated = existing.copyWith(
      bodyMd: bodyMd,
      mood: mood,
      energy: energy,
      updatedAt: now,
    );
    await _db.update(
      'journal_entries',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [existing.id],
    );
    return updated;
  }

  Future<void> delete(String dateKey) async {
    await _db.delete(
      'journal_entries',
      where: 'date_key = ?',
      whereArgs: [dateKey],
    );
  }

  Future<Map<String, String>> bodiesBetween(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _db.query(
      'journal_entries',
      where: 'date_key >= ? AND date_key <= ?',
      whereArgs: [dateKey(start), dateKey(end)],
      orderBy: 'date_key ASC',
    );
    return {
      for (final row in rows)
        row['date_key'] as String: row['body_md'] as String? ?? '',
    };
  }

  /// Consecutive days with a non-empty entry. If today is still blank, the
  /// streak is counted up to yesterday (it is not "lost" before bedtime).
  Future<int> currentStreak({DateTime? now}) async {
    final entries = await list();
    final filled = <String>{
      for (final entry in entries)
        if (entry.bodyMd.trim().isNotEmpty) entry.dateKey,
    };
    if (filled.isEmpty) return 0;
    final today = startOfDay(now ?? DateTime.now());
    var cursor = today;
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
  }

  Future<Set<String>> journaledDays(DateTime start, DateTime end) async {
    final rows = await _db.query(
      'journal_entries',
      columns: ['date_key'],
      where: 'date_key >= ? AND date_key <= ?',
      whereArgs: [dateKey(start), dateKey(end)],
    );
    return {for (final row in rows) row['date_key'] as String};
  }
}
