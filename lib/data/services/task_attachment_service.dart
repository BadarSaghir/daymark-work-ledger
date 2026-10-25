import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/ids.dart';
import '../models/task_attachment.dart';
import '../repositories/task_attachment_repository.dart';

class TaskAttachmentException implements Exception {
  TaskAttachmentException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Copies picked files beside the profile database and keeps their metadata in
/// SQLite. Keeping attachments outside the database avoids bloating every
/// settings write and lets backups/task bundles stream the bytes separately.
class TaskAttachmentService {
  TaskAttachmentService(this._repository, {required this.directory});

  final TaskAttachmentRepository _repository;
  final Directory directory;

  static const maxFileBytes = 50 * 1024 * 1024;
  static const maxTaskBytes = 90 * 1024 * 1024;

  Future<List<TaskAttachment>> listForTask(String taskId) =>
      _repository.listForTask(taskId);

  File fileFor(TaskAttachment attachment) {
    final relative = _safeRelativePath(attachment.relativePath);
    if (relative == null) {
      throw TaskAttachmentException('That attachment path is not valid.');
    }
    return File(p.join(directory.path, relative));
  }

  Future<TaskAttachment> addFile(
    String taskId,
    File source, {
    String? fileName,
  }) async {
    if (!await source.exists()) {
      throw TaskAttachmentException('That file is no longer available.');
    }
    final stat = await source.stat();
    if (stat.size > maxFileBytes) {
      throw TaskAttachmentException('Attachments must be 50 MB or smaller.');
    }
    final existing = await _repository.listForTask(taskId);
    final total = existing.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    if (total + stat.size > maxTaskBytes) {
      throw TaskAttachmentException(
        'This task already holds 90 MB of attachments. Remove a file first.',
      );
    }
    final cleanName = p.basename(
      (fileName ?? p.basename(source.path)).replaceAll(
        RegExp(r'[\r\n\t]'),
        ' ',
      ),
    );
    final id = newId();
    final relative = p.join(taskId, '$id-${_safeFileName(cleanName)}');
    final target = File(p.join(directory.path, relative));
    await target.parent.create(recursive: true);
    await source.copy(target.path);
    final attachment = TaskAttachment(
      id: id,
      taskId: taskId,
      fileName: cleanName,
      mimeType: _mimeFor(cleanName),
      sizeBytes: stat.size,
      relativePath: relative,
      createdAt: DateTime.now(),
    );
    try {
      await _repository.insert(attachment);
    } catch (error) {
      try {
        await target.delete();
      } catch (_) {
        // The metadata error is the useful one.
      }
      rethrow;
    }
    return attachment;
  }

  Future<void> delete(TaskAttachment attachment) async {
    await _repository.delete(attachment);
    try {
      final file = fileFor(attachment);
      if (await file.exists()) await file.delete();
      final parent = file.parent;
      if (await parent.exists() && await parent.list().isEmpty) {
        await parent.delete();
      }
    } catch (_) {
      // A locked/missing file must not resurrect the metadata row.
    }
  }

  /// Removes the whole attachment folder for a deleted task. Metadata rows are
  /// already removed by the task's foreign-key cascade.
  Future<void> deleteTaskFiles(String taskId) async {
    if (taskId.contains('/') ||
        taskId.contains('\\') ||
        taskId == '.' ||
        taskId == '..') {
      return;
    }
    try {
      final folder = Directory(p.join(directory.path, taskId));
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (_) {
      // A locked file should not undo the task deletion.
    }
  }

  /// Clears every attachment file for the active profile. Used by workspace
  /// reset after the database rows have been removed.
  Future<void> deleteAllFiles() async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Best effort; orphaned files cannot break the ledger.
    }
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

  static String _safeFileName(String name) {
    final base = p.basename(name.trim());
    final clean = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (clean.isEmpty || clean == '.' || clean == '..') return 'attachment';
    return clean.length > 140 ? clean.substring(clean.length - 140) : clean;
  }

  static String _mimeFor(String name) {
    return switch (p.extension(name).toLowerCase()) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.pdf' => 'application/pdf',
      '.txt' || '.md' || '.markdown' => 'text/plain',
      '.json' => 'application/json',
      '.csv' => 'text/csv',
      '.zip' => 'application/zip',
      '.mp3' => 'audio/mpeg',
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      _ => 'application/octet-stream',
    };
  }
}
