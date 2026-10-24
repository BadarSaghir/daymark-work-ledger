import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/ids.dart';
import '../models/activity_event.dart';

/// Write-only audit helper. Accepts a [DatabaseExecutor] so it can participate
/// in the caller's transaction.
Future<void> writeActivity(
  DatabaseExecutor executor, {
  required String entityType,
  String? entityId,
  required String action,
  required String summary,
  String? metadata,
  DateTime? at,
}) async {
  await executor.insert('activity_events', {
    'id': newId(),
    'entity_type': entityType,
    'entity_id': entityId,
    'action': action,
    'summary': summary,
    'metadata': metadata,
    'created_at': (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
  });
}

class ActivityRepository {
  ActivityRepository(this._db);

  final Database _db;

  Future<List<ActivityEvent>> forEntity(
    String entityId, {
    int limit = 40,
  }) async {
    final rows = await _db.query(
      'activity_events',
      where: 'entity_id = ?',
      whereArgs: [entityId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ActivityEvent.fromMap).toList();
  }

  Future<List<ActivityEvent>> recent({int limit = 30}) async {
    final rows = await _db.query(
      'activity_events',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ActivityEvent.fromMap).toList();
  }
}
