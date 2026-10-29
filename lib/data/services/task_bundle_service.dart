import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/ids.dart';
import '../db/app_database.dart';
import '../db/migrations.dart';

class TaskBundleException implements Exception {
  TaskBundleException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TaskBundleExport {
  const TaskBundleExport({
    required this.bytes,
    required this.fileName,
    required this.title,
    required this.attachmentCount,
  });

  final Uint8List bytes;
  final String fileName;
  final String title;
  final int attachmentCount;
}

enum TaskBundleImportStatus { created, updated, keptLocal }

class TaskBundleImportResult {
  const TaskBundleImportResult({
    required this.status,
    required this.taskId,
    required this.title,
    required this.attachmentCount,
  });

  final TaskBundleImportStatus status;
  final String taskId;
  final String title;
  final int attachmentCount;

  bool get keptLocal => status == TaskBundleImportStatus.keptLocal;
  bool get isNew => status == TaskBundleImportStatus.created;
}

/// Exports and imports one task with everything attached to it: category,
/// steps, tracked time, activity, notes, reminders, and files. Re-importing the
/// same task id updates it instead of making a duplicate, which is what makes
/// this useful as an ongoing sync between two devices.
class TaskBundleService {
  TaskBundleService(this._appDb, {required this.attachmentDirectory});

  final AppDatabase _appDb;
  final Directory attachmentDirectory;

  static const format = 'daymark.task';
  static const formatVersion = 1;
  static const appVersion = '1.5.0';
  static const maxBytes = 100 * 1024 * 1024;
  static const maxAttachmentBytes = 90 * 1024 * 1024;

  Database get _db => _appDb.db;

  static const _taskColumns = <String>{
    'id',
    'title',
    'notes_md',
    'category_id',
    'kind',
    'status',
    'priority',
    'effort',
    'estimate_minutes',
    'planned_date',
    'scheduled_start',
    'scheduled_end',
    'due_at',
    'blocked_reason',
    'position',
    'completed_at',
    'archived',
    'created_at',
    'updated_at',
    'reminder_at',
    'reminder_note',
    'reminder_daily',
  };

  static const _categoryColumns = <String>{
    'id',
    'name',
    'color',
    'icon',
    'weight',
    'position',
    'archived',
    'created_at',
    'updated_at',
  };

  static const _subtaskColumns = <String>{
    'id',
    'task_id',
    'title',
    'position',
    'is_done',
    'completed_at',
    'created_at',
  };

  static const _timeEntryColumns = <String>{
    'id',
    'session_id',
    'task_id',
    'label',
    'note',
    'source',
    'started_at',
    'ended_at',
    'duration_ms',
    'created_at',
  };

  static const _activityColumns = <String>{
    'id',
    'entity_type',
    'entity_id',
    'action',
    'summary',
    'metadata',
    'created_at',
  };

  static const _attachmentColumns = <String>{
    'id',
    'task_id',
    'file_name',
    'mime_type',
    'size_bytes',
    'relative_path',
    'created_at',
  };

  Future<TaskBundleExport> exportTask(String taskId, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    final taskRows = await _db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (taskRows.isEmpty) {
      throw TaskBundleException('That task no longer exists.');
    }
    final task = _map(taskRows.first);
    final title = (task['title']?.toString().trim().isNotEmpty ?? false)
        ? task['title']!.toString()
        : 'Untitled task';

    Map<String, Object?>? category;
    final categoryId = task['category_id'] as String?;
    if (categoryId != null) {
      final rows = await _db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [categoryId],
        limit: 1,
      );
      if (rows.isNotEmpty) category = _map(rows.first);
    }

    final subtasks = (await _db.query(
      'subtasks',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'position ASC, created_at ASC',
    )).map(_map).toList();
    final entries = (await _db.query(
      'time_entries',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'started_at ASC',
    )).map(_map).toList();
    final activity = (await _db.query(
      'activity_events',
      where: "entity_type = 'task' AND entity_id = ?",
      whereArgs: [taskId],
      orderBy: 'created_at ASC',
    )).map(_map).toList();
    final attachmentRows = (await _db.query(
      'task_attachments',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'created_at ASC',
    )).map(_map).toList();

    final pendingFiles = <({String path, Uint8List bytes})>[];
    final attachmentMeta = <Map<String, Object?>>[];
    var attachmentBytes = 0;
    for (final row in attachmentRows) {
      final meta = Map<String, Object?>.from(row);
      final relative = _safeRelativePath(
        (row['relative_path'] as String? ?? '').trim(),
      );
      if (relative == null) continue;
      final file = File(p.join(attachmentDirectory.path, relative));
      if (await file.exists()) {
        final size = await file.length();
        attachmentBytes += size;
        if (attachmentBytes > maxAttachmentBytes) {
          throw TaskBundleException(
            'This task has more than 90 MB of files. Share a smaller set.',
          );
        }
        final archivePath = _archivePath(relative);
        pendingFiles.add((path: archivePath, bytes: await file.readAsBytes()));
        meta['archive_path'] = archivePath;
        meta['included'] = true;
      } else {
        meta['included'] = false;
      }
      attachmentMeta.add(meta);
    }

    final envelope = <String, Object?>{
      'format': format,
      'formatVersion': formatVersion,
      'schemaVersion': Migrations.latestVersion,
      'appVersion': appVersion,
      'exportedAt': now.toUtc().millisecondsSinceEpoch,
      'task': task,
      'category': category,
      'subtasks': subtasks,
      'time_entries': entries,
      'activity_events': activity,
      'task_attachments': attachmentMeta,
    };
    final taskJson = const JsonEncoder.withIndent('  ').convert(envelope);
    final manifest = const JsonEncoder.withIndent('  ').convert({
      'app': 'Daymark',
      'format': format,
      'formatVersion': formatVersion,
      'schemaVersion': Migrations.latestVersion,
      'exportedAt': now.toIso8601String(),
      'taskId': taskId,
      'title': title,
      'attachments': pendingFiles.length,
      'contents': ['task.json', 'manifest.json', 'task.md', 'attachments/*'],
    });
    final archive = Archive();
    _addText(archive, 'task.json', taskJson);
    _addText(archive, 'manifest.json', manifest);
    _addText(
      archive,
      'task.md',
      _taskMarkdown(task, category, subtasks, entries, attachmentMeta),
    );
    for (final file in pendingFiles) {
      archive.addFile(ArchiveFile(file.path, file.bytes.length, file.bytes));
    }
    final encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) {
      throw TaskBundleException('Could not encode the task bundle.');
    }
    if (encoded.length > maxBytes) {
      throw TaskBundleException('The task bundle is larger than 100 MB.');
    }
    return TaskBundleExport(
      bytes: Uint8List.fromList(encoded),
      fileName: _fileName(title, now),
      title: title,
      attachmentCount: pendingFiles.length,
    );
  }

  Future<TaskBundleImportResult> importFile(
    File file, {
    bool keepNewerLocal = true,
  }) async {
    if (!await file.exists()) {
      throw TaskBundleException('That task bundle is no longer available.');
    }
    return importBytes(
      await file.readAsBytes(),
      sourceName: p.basename(file.path),
      keepNewerLocal: keepNewerLocal,
    );
  }

  Future<TaskBundleImportResult> importBytes(
    Uint8List bytes, {
    String sourceName = 'shared task',
    bool keepNewerLocal = true,
  }) async {
    if (bytes.length > maxBytes) {
      throw TaskBundleException('That task bundle is larger than 100 MB.');
    }

    final Map<String, Object?> envelope;
    final files = <String, Uint8List>{};
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes, verify: true);
      } catch (_) {
        throw TaskBundleException('The task ZIP is damaged or incomplete.');
      }
      ArchiveFile? jsonEntry;
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final name = file.name.replaceAll('\\', '/');
        if (name == 'task.json') {
          jsonEntry = file;
        } else if (name.startsWith('attachments/')) {
          final content = file.readBytes();
          if (content != null) files[name] = Uint8List.fromList(content);
        }
      }
      if (jsonEntry == null) {
        throw TaskBundleException('No task.json found inside the bundle.');
      }
      final raw = jsonEntry.readBytes();
      if (raw == null) {
        throw TaskBundleException('The task.json entry could not be read.');
      }
      envelope = _decodeEnvelope(utf8.decode(raw, allowMalformed: false));
    } else {
      envelope = _decodeEnvelope(utf8.decode(bytes, allowMalformed: false));
    }

    if (envelope['format'] != format) {
      throw TaskBundleException('This is not a Daymark task bundle.');
    }
    final version = (envelope['formatVersion'] as num?)?.toInt() ?? 0;
    if (version < 1 || version > formatVersion) {
      throw TaskBundleException(
        'Unsupported task bundle v$version. This app supports v$formatVersion.',
      );
    }
    final schema = (envelope['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schema > Migrations.latestVersion) {
      throw TaskBundleException(
        'This bundle comes from a newer Daymark schema (v$schema). Update first.',
      );
    }

    final taskRaw = envelope['task'];
    if (taskRaw is! Map) {
      throw TaskBundleException('The bundle is missing its task.');
    }
    final incomingTask = _cleanRow(_map(taskRaw), _taskColumns);
    final taskId = incomingTask['id']?.toString() ?? '';
    final title = incomingTask['title']?.toString().trim() ?? '';
    if (taskId.isEmpty || title.isEmpty) {
      throw TaskBundleException('The shared task has no id or title.');
    }
    if (!_isSafeId(taskId)) {
      throw TaskBundleException('The shared task has an invalid id.');
    }

    final categoryRaw = envelope['category'];
    final incomingCategory = categoryRaw is Map
        ? _cleanRow(_map(categoryRaw), _categoryColumns)
        : null;
    final subtasks = _asMaps(envelope['subtasks']);
    final entries = _asMaps(envelope['time_entries']);
    final activity = _asMaps(envelope['activity_events']);
    final attachments = _asMaps(envelope['task_attachments']);

    var status = TaskBundleImportStatus.created;
    var importedAttachments = 0;
    final db = _db;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      final existing = existingRows.isEmpty ? null : existingRows.first;
      final localUpdated = (existing?['updated_at'] as num?)?.toInt() ?? 0;
      final incomingUpdated =
          (incomingTask['updated_at'] as num?)?.toInt() ?? 0;
      if (existing != null &&
          keepNewerLocal &&
          localUpdated > incomingUpdated) {
        status = TaskBundleImportStatus.keptLocal;
        return;
      }

      final resolvedCategory = await _resolveCategory(
        txn,
        incomingCategory,
        taskId: taskId,
      );
      final cleanTask = _cleanRow(incomingTask, _taskColumns)
        ..['category_id'] = resolvedCategory;
      if (existing != null) {
        cleanTask['position'] = existing['position'];
        status = TaskBundleImportStatus.updated;
        await txn.update(
          'tasks',
          cleanTask,
          where: 'id = ?',
          whereArgs: [taskId],
        );
      } else {
        final next = await _nextPosition(txn, 'tasks');
        cleanTask['position'] = next;
        await txn.insert('tasks', cleanTask);
      }

      // The accepted side is authoritative for steps.
      await txn.delete('subtasks', where: 'task_id = ?', whereArgs: [taskId]);
      for (var index = 0; index < subtasks.length; index++) {
        final row = _cleanRow(subtasks[index], _subtaskColumns)
          ..['task_id'] = taskId
          ..['position'] = index;
        var id = row['id']?.toString() ?? '';
        if (id.isEmpty || !await _idIsFree(txn, 'subtasks', id, taskId)) {
          id = newId();
        }
        row['id'] = id;
        if (row['title'] == null || row['title'].toString().trim().isEmpty) {
          continue;
        }
        row['created_at'] ??= DateTime.now().toUtc().millisecondsSinceEpoch;
        await txn.insert('subtasks', row);
      }

      // Time history is additive: keep time that was already tracked locally.
      for (final raw in entries) {
        final row = _cleanRow(raw, _timeEntryColumns)..['task_id'] = taskId;
        var id = row['id']?.toString() ?? '';
        if (id.isEmpty) id = newId();
        row['id'] = id;
        if ((await txn.query(
          'time_entries',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        )).isNotEmpty) {
          await txn.update(
            'time_entries',
            row,
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          await txn.insert('time_entries', row);
        }
      }

      for (final raw in activity) {
        final row = _cleanRow(raw, _activityColumns)
          ..['entity_type'] = 'task'
          ..['entity_id'] = taskId;
        var id = row['id']?.toString() ?? '';
        if (id.isEmpty) id = newId();
        row['id'] = id;
        await txn.insert(
          'activity_events',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      for (final raw in attachments) {
        final meta = _cleanRow(raw, _attachmentColumns);
        final name = meta['file_name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final archivePath = raw['archive_path']?.toString() ?? '';
        final bytes = files[archivePath];
        if (bytes == null) continue;
        var id = meta['id']?.toString() ?? '';
        if (id.isEmpty ||
            !_isSafeId(id) ||
            !await _attachmentIdIsFree(txn, id, taskId)) {
          id = newId();
        }
        final relative = p.join(taskId, '$id-${_safeFileName(name)}');
        final target = File(p.join(attachmentDirectory.path, relative));
        await target.parent.create(recursive: true);
        if (!await target.exists()) {
          await target.writeAsBytes(bytes, flush: true);
        }
        final row = <String, Object?>{
          'id': id,
          'task_id': taskId,
          'file_name': name,
          'mime_type': meta['mime_type']?.toString() ?? '',
          'size_bytes': bytes.length,
          'relative_path': relative,
          'created_at':
              (meta['created_at'] as num?)?.toInt() ??
              DateTime.now().toUtc().millisecondsSinceEpoch,
        };
        final present = await txn.query(
          'task_attachments',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (present.isEmpty) {
          await txn.insert('task_attachments', row);
        } else {
          await txn.update(
            'task_attachments',
            row,
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        importedAttachments++;
      }

      await txn.insert('activity_events', {
        'id': newId(),
        'entity_type': 'task',
        'entity_id': taskId,
        'action': 'imported',
        'summary': 'Received task bundle from $sourceName',
        'metadata': null,
        'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
    });

    return TaskBundleImportResult(
      status: status,
      taskId: taskId,
      title: title,
      attachmentCount: importedAttachments,
    );
  }

  Future<String?> _resolveCategory(
    Transaction txn,
    Map<String, Object?>? incoming, {
    required String taskId,
  }) async {
    if (incoming == null) return null;
    final sourceId = incoming['id']?.toString() ?? '';
    if (sourceId.isNotEmpty) {
      final existing = await txn.query(
        'categories',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [sourceId],
        limit: 1,
      );
      if (existing.isNotEmpty) return sourceId;
    }
    final name = incoming['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) {
      final byName = await txn.query(
        'categories',
        columns: ['id'],
        where: 'name = ? COLLATE NOCASE',
        whereArgs: [name],
        limit: 1,
      );
      if (byName.isNotEmpty) return byName.first['id'] as String;
    }
    if (name.isEmpty) return null;
    final next = await _nextPosition(txn, 'categories');
    final id =
        sourceId.isNotEmpty && await _idIsFreeAny(txn, 'categories', sourceId)
        ? sourceId
        : newId();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await txn.insert('categories', {
      'id': id,
      'name': name,
      'color': (incoming['color'] as num?)?.toInt() ?? 0xFF1D5B4F,
      'icon': incoming['icon']?.toString() ?? 'layers',
      'weight': ((incoming['weight'] as num?)?.toDouble() ?? 1.0).clamp(
        0.5,
        2.0,
      ),
      'position': next,
      'archived': 0,
      'created_at': (incoming['created_at'] as num?)?.toInt() ?? now,
      'updated_at': now,
    });
    return id;
  }

  Future<int> _nextPosition(Transaction txn, String table) async {
    final rows = await txn.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next FROM $table',
    );
    return (rows.first['next'] as num?)?.toInt() ?? 0;
  }

  Future<bool> _idIsFree(
    Transaction txn,
    String table,
    String id,
    String taskId,
  ) async {
    final rows = await txn.query(
      table,
      columns: ['task_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty || rows.first['task_id'] == taskId;
  }

  Future<bool> _attachmentIdIsFree(
    Transaction txn,
    String id,
    String taskId,
  ) async {
    final rows = await txn.query(
      'task_attachments',
      columns: ['task_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty || rows.first['task_id'] == taskId;
  }

  Future<bool> _idIsFreeAny(Transaction txn, String table, String id) async {
    final rows = await txn.query(
      table,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty;
  }

  static Map<String, Object?> _decodeEnvelope(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw TaskBundleException('The task bundle is not valid JSON.');
    }
    if (decoded is! Map) {
      throw TaskBundleException('The task bundle has an unexpected shape.');
    }
    return _map(decoded);
  }

  static Map<String, Object?> _map(Map<dynamic, dynamic> raw) => {
    for (final entry in raw.entries) entry.key.toString(): entry.value,
  };

  static List<Map<String, Object?>> _asMaps(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map) _map(row),
    ];
  }

  static Map<String, Object?> _cleanRow(
    Map<String, Object?> row,
    Set<String> allowed,
  ) => {
    for (final entry in row.entries)
      if (allowed.contains(entry.key)) entry.key: entry.value,
  };

  static void _addText(Archive archive, String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  static bool _isSafeId(String id) {
    if (id.isEmpty || id.length > 160 || id != id.trim()) return false;
    if (id == '.' || id == '..') return false;
    return !id.contains('/') &&
        !id.contains('\\') &&
        !id.contains('\u0000') &&
        !id.contains(':');
  }

  static String? _safeRelativePath(String raw) {
    final normalized = raw.trim().replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        p.isAbsolute(normalized) ||
        p.windows.isAbsolute(normalized)) {
      return null;
    }
    final parts = normalized.split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      return null;
    }
    return p.joinAll(parts);
  }

  static String _archivePath(String relative) {
    final parts = p
        .split(relative)
        .map((part) => part.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_'))
        .toList();
    return p.posix.joinAll(['attachments', ...parts]);
  }

  static String _isoFromMs(Object? value) {
    final ms = (value as num?)?.toInt();
    if (ms == null || ms <= 0) return '';
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal().toIso8601String();
  }

  static String _safeFileName(String name) {
    final base = p.basename(name.trim());
    final clean = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (clean.isEmpty || clean == '.' || clean == '..') return 'attachment';
    return clean.length > 140 ? clean.substring(clean.length - 140) : clean;
  }

  static String _fileName(String title, DateTime at) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final safe = slug.isEmpty
        ? 'task'
        : slug.substring(0, math.min(48, slug.length));
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${at.year}${two(at.month)}${two(at.day)}-${two(at.hour)}${two(at.minute)}';
    return 'daymark-task-$safe-$stamp.daymark-task';
  }

  static String _taskMarkdown(
    Map<String, Object?> task,
    Map<String, Object?>? category,
    List<Map<String, Object?>> subtasks,
    List<Map<String, Object?>> entries,
    List<Map<String, Object?>> attachments,
  ) {
    final title = task['title']?.toString() ?? 'Untitled task';
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('title: "${title.replaceAll('"', '\\"')}"')
      ..writeln(
        'category: "${(category?['name']?.toString() ?? 'Unfiled').replaceAll('"', '\\"')}"',
      )
      ..writeln('status: ${task['status']}')
      ..writeln('kind: ${task['kind']}')
      ..writeln('priority: ${task['priority']}')
      ..writeln('effort: ${task['effort']}')
      ..writeln('planned: ${task['planned_date'] ?? ''}')
      ..writeln('due: ${_isoFromMs(task['due_at'])}')
      ..writeln('reminder: ${_isoFromMs(task['reminder_at'])}')
      ..writeln('reminder repeats daily: ${task['reminder_daily'] == 1}')
      ..writeln('---')
      ..writeln()
      ..writeln('# $title')
      ..writeln();
    final notes = task['notes_md']?.toString().trim() ?? '';
    if (notes.isNotEmpty) {
      buffer
        ..writeln(notes)
        ..writeln();
    }
    final reminderNote = task['reminder_note']?.toString().trim() ?? '';
    if (reminderNote.isNotEmpty) {
      buffer
        ..writeln('## Reminder')
        ..writeln(reminderNote)
        ..writeln();
    }
    if (subtasks.isNotEmpty) {
      buffer.writeln('## Steps');
      for (final step in subtasks) {
        final done = (step['is_done'] as num?)?.toInt() == 1;
        buffer.writeln('- [${done ? 'x' : ' '}] ${step['title']}');
      }
      buffer.writeln();
    }
    if (entries.isNotEmpty) {
      buffer.writeln('## Tracked time');
      final total = entries.fold<int>(
        0,
        (sum, entry) => sum + ((entry['duration_ms'] as num?)?.toInt() ?? 0),
      );
      buffer.writeln(
        '- ${(total / 60000).round()} minutes across ${entries.length} segments',
      );
      buffer.writeln();
    }
    if (attachments.isNotEmpty) {
      buffer.writeln('## Attachments');
      for (final attachment in attachments) {
        buffer.writeln('- ${attachment['file_name']}');
      }
    }
    return buffer.toString();
  }
}
