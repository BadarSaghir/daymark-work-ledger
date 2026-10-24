import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/ids.dart';
import '../db/app_database.dart';
import '../models/category.dart';
import 'activity_repository.dart';

class CategoryRepository {
  CategoryRepository(this._appDb);

  final AppDatabase _appDb;

  Database get _db => _appDb.db;

  Future<List<Category>> list({bool includeArchived = false}) async {
    final rows = await _db.query(
      'categories',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'position ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<Category?> byId(String id) async {
    final rows = await _db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Category.fromMap(rows.first);
  }

  Future<Map<String, int>> taskCounts() async {
    final rows = await _db.rawQuery(
      'SELECT category_id, COUNT(*) AS total FROM tasks '
      'WHERE archived = 0 GROUP BY category_id',
    );
    final result = <String, int>{};
    for (final row in rows) {
      final id = row['category_id'] as String?;
      if (id != null) result[id] = (row['total'] as num).toInt();
    }
    return result;
  }

  Future<Category> create({
    required String name,
    required int color,
    required String icon,
    double weight = 1.0,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next FROM categories',
    );
    final position = (rows.first['next'] as num).toInt();
    final now = DateTime.now();
    final category = Category(
      id: newId(),
      name: name.trim(),
      color: color,
      icon: icon,
      weight: weight.clamp(0.5, 2.0),
      position: position,
      archived: false,
      createdAt: now,
      updatedAt: now,
    );
    await _db.transaction((txn) async {
      await txn.insert('categories', category.toMap());
      await writeActivity(
        txn,
        entityType: 'category',
        entityId: category.id,
        action: 'created',
        summary: 'Created category “${category.name}”',
      );
    });
    return category;
  }

  Future<void> update(Category category) async {
    final updated = category.copyWith(updatedAt: DateTime.now());
    await _db.transaction((txn) async {
      await txn.update(
        'categories',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      await writeActivity(
        txn,
        entityType: 'category',
        entityId: updated.id,
        action: 'updated',
        summary: 'Updated category “${updated.name}”',
      );
    });
  }

  Future<void> setArchived(String id, bool archived) async {
    final category = await byId(id);
    if (category == null) return;
    await _db.transaction((txn) async {
      await txn.update(
        'categories',
        {
          'archived': archived ? 1 : 0,
          'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await writeActivity(
        txn,
        entityType: 'category',
        entityId: id,
        action: archived ? 'archived' : 'restored',
        summary:
            '${archived ? 'Archived' : 'Restored'} category “${category.name}”',
      );
    });
  }

  Future<void> deleteIfEmpty(String id) async {
    final count = await _db.rawQuery(
      'SELECT COUNT(*) AS total FROM tasks WHERE category_id = ?',
      [id],
    );
    if ((count.first['total'] as num).toInt() > 0) {
      throw StateError('Category still has tasks. Archive it instead.');
    }
    await _db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }
}
