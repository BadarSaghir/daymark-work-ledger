import 'package:sqflite_common/sqlite_api.dart';

import '../db/app_database.dart';
import '../models/task_attachment.dart';
import 'activity_repository.dart';

class TaskAttachmentRepository {
  TaskAttachmentRepository(this._appDb);

  final AppDatabase _appDb;

  Database get _db => _appDb.db;

  Future<List<TaskAttachment>> listForTask(String taskId) async {
    final rows = await _db.query(
      'task_attachments',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'created_at ASC',
    );
    return rows.map(TaskAttachment.fromMap).toList();
  }

  Future<TaskAttachment?> byId(String id) async {
    final rows = await _db.query(
      'task_attachments',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return TaskAttachment.fromMap(rows.first);
  }

  Future<void> insert(TaskAttachment attachment) async {
    final now = DateTime.now();
    await _db.transaction((txn) async {
      await txn.insert(
        'task_attachments',
        attachment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        'tasks',
        {'updated_at': now.toUtc().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [attachment.taskId],
      );
      await writeActivity(
        txn,
        entityType: 'task',
        entityId: attachment.taskId,
        action: 'attachment_added',
        summary: 'Attached “${attachment.fileName}”',
      );
    });
  }

  Future<void> delete(TaskAttachment attachment) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'task_attachments',
        where: 'id = ?',
        whereArgs: [attachment.id],
      );
      await txn.update(
        'tasks',
        {'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [attachment.taskId],
      );
      await writeActivity(
        txn,
        entityType: 'task',
        entityId: attachment.taskId,
        action: 'attachment_removed',
        summary: 'Removed attachment “${attachment.fileName}”',
      );
    });
  }
}
