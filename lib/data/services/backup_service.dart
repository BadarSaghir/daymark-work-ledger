import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/canonical_json.dart';
import '../db/app_database.dart';
import '../db/migrations.dart';
import '../models/app_settings.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BackupResult {
  const BackupResult({
    required this.file,
    required this.counts,
    required this.createdAt,
    this.automatic = false,
    this.warning,
  });

  final File? file;
  final Map<String, int> counts;
  final DateTime createdAt;
  final bool automatic;
  final String? warning;
}

class BackupInfo {
  const BackupInfo({
    required this.file,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.isAutomatic,
    required this.isPreRestore,
  });

  final File file;
  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;
  final bool isAutomatic;
  final bool isPreRestore;

  String get sizeLabel {
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(sizeBytes / 1024).round()} KB';
  }
}

/// Portable, validated, human-inspectable backups: a ZIP with `backup.json`,
/// a manifest, and markdown mirrors of journals and task notes.
class BackupService {
  BackupService(
    this._appDb, {
    required this.backupDirectory,
    this.attachmentDirectory,
  });

  final AppDatabase _appDb;
  final Directory backupDirectory;

  /// Optional attachment root for the active profile. Backups restore the
  /// file tree alongside `task_attachments` metadata.
  final Directory? attachmentDirectory;

  static const format = 'daymark.backup';
  static const formatVersion = 1;
  static const appVersion = '1.3.0';
  static const maxImportBytes = 100 * 1024 * 1024;

  static const _tables = <String>[
    'categories',
    'tasks',
    'subtasks',
    'time_entries',
    'task_attachments',
    'journal_entries',
    'activity_events',
    'settings',
  ];

  static const _columns = <String, Set<String>>{
    'categories': {
      'id',
      'name',
      'color',
      'icon',
      'weight',
      'position',
      'archived',
      'created_at',
      'updated_at',
    },
    'tasks': {
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
    },
    'subtasks': {
      'id',
      'task_id',
      'title',
      'position',
      'is_done',
      'completed_at',
      'created_at',
    },
    'time_entries': {
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
    },
    'task_attachments': {
      'id',
      'task_id',
      'file_name',
      'mime_type',
      'size_bytes',
      'relative_path',
      'created_at',
    },
    'journal_entries': {
      'id',
      'date_key',
      'body_md',
      'mood',
      'energy',
      'created_at',
      'updated_at',
    },
    'activity_events': {
      'id',
      'entity_type',
      'entity_id',
      'action',
      'summary',
      'metadata',
      'created_at',
    },
    'settings': {'key', 'value'},
  };

  Database get _db => _appDb.db;

  Future<BackupResult> createBackup({
    String prefix = 'daymark-backup',
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final encoded = await createBackupBytes(at: now);
    await backupDirectory.create(recursive: true);
    final file = await _uniqueFile('$prefix-${_stamp(now)}.zip');
    await file.writeAsBytes(encoded, flush: true);
    final counts = await _tableCounts();
    return BackupResult(
      file: file,
      counts: counts,
      createdAt: now,
      automatic: prefix.contains('auto'),
    );
  }

  /// Build a complete archive in memory. LAN transfer uses this so the file
  /// never has to be written to disk before it is sent.
  Future<Uint8List> createBackupBytes({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final data = <String, List<Map<String, Object?>>>{};
    for (final table in _tables) {
      final rows = await _db.query(table);
      data[table] = rows
          .map(
            (row) => <String, Object?>{
              for (final entry in row.entries) entry.key: entry.value,
            },
          )
          .toList();
    }

    final envelope = <String, Object?>{
      'format': format,
      'formatVersion': formatVersion,
      'schemaVersion': Migrations.latestVersion,
      'appVersion': appVersion,
      'exportedAt': now.toUtc().millisecondsSinceEpoch,
      'counts': {for (final table in _tables) table: data[table]!.length},
      'data': data,
    };
    envelope['checksum'] = checksumFor(envelope);

    final files = <String, String>{
      'backup.json': const JsonEncoder.withIndent('  ').convert(envelope),
      'manifest.json': const JsonEncoder.withIndent('  ').convert({
        'app': 'Daymark',
        'format': format,
        'formatVersion': formatVersion,
        'schemaVersion': Migrations.latestVersion,
        'exportedAt': now.toIso8601String(),
        'contents': [
          'backup.json',
          'manifest.json',
          'markdown/journal/*.md',
          'markdown/tasks/*.md',
          'attachments/*',
        ],
      }),
      'README.md': _backupReadme(now),
      ...await _markdownFiles(),
    };

    final archive = Archive();
    for (final entry in files.entries) {
      final bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    final attachmentFiles = await _attachmentArchiveFiles();
    for (final entry in attachmentFiles.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) {
      throw BackupException('Could not encode the backup archive.');
    }
    return Uint8List.fromList(encoded);
  }

  Future<Map<String, Uint8List>> _attachmentArchiveFiles() async {
    final root = attachmentDirectory;
    if (root == null) return const {};
    final rows = await _db.query('task_attachments');
    final files = <String, Uint8List>{};
    var total = 0;
    for (final row in rows) {
      final relative = row['relative_path'] as String? ?? '';
      final safe = _safeRelativePath(relative);
      if (safe == null) continue;
      final file = File(p.join(root.path, safe));
      if (!await file.exists()) continue;
      final length = await file.length();
      total += length;
      if (total > maxImportBytes) {
        throw BackupException(
          'Attachments make this backup larger than 100 MB. Remove a large '
          'file from a task and try again.',
        );
      }
      files[_attachmentArchivePath(safe)] = await file.readAsBytes();
    }
    return files;
  }

  Future<Map<String, int>> _tableCounts() async {
    final counts = <String, int>{};
    for (final table in _tables) {
      final result = await _db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      counts[table] = (result.first['c'] as num?)?.toInt() ?? 0;
    }
    return counts;
  }

  /// Once-per-24-hours automatic backup. The caller is responsible for saving
  /// the new `lastBackupAt` to settings.
  Future<BackupResult?> maybeCreateDailyBackup(
    AppSettings settings, {
    DateTime? now,
  }) async {
    if (!settings.autoBackup || !settings.onboarded) return null;
    final reference = now ?? DateTime.now();
    final last = settings.lastBackupAt;
    if (last != null &&
        reference.difference(last) < const Duration(hours: 24)) {
      return null;
    }
    final result = await createBackup(prefix: 'daymark-auto', at: reference);
    await pruneAutomatic(settings.backupRetention);
    return result;
  }

  Future<void> pruneAutomatic(int retention) async {
    final backups = await listBackups();
    final automatic = backups.where((backup) => backup.isAutomatic).toList();
    for (var i = retention; i < automatic.length; i++) {
      try {
        await automatic[i].file.delete();
      } catch (_) {
        // A locked or missing file should not break the backup flow.
      }
    }
  }

  Future<List<BackupInfo>> listBackups() async {
    if (!await backupDirectory.exists()) return const [];
    final files = await backupDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.zip'))
        .cast<File>()
        .toList();
    final infos = <BackupInfo>[];
    for (final file in files) {
      final stat = await file.stat();
      final name = p.basename(file.path);
      infos.add(
        BackupInfo(
          file: file,
          name: name,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
          isAutomatic: name.startsWith('daymark-auto-'),
          isPreRestore: name.startsWith('pre-restore-'),
        ),
      );
    }
    infos.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return infos;
  }

  Future<void> deleteBackup(BackupInfo backup) async {
    if (await backup.file.exists()) {
      await backup.file.delete();
    }
  }

  Future<BackupResult> importFile(File file) async {
    final bytes = await file.readAsBytes();
    return importBytes(bytes, sourceName: p.basename(file.path));
  }

  Future<BackupResult> importBytes(
    Uint8List bytes, {
    String sourceName = 'backup',
  }) async {
    if (bytes.length > maxImportBytes) {
      throw BackupException('That backup is larger than 100 MB.');
    }
    final String jsonText;
    final attachmentFiles = <String, Uint8List>{};
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes, verify: true);
      } catch (_) {
        throw BackupException('The ZIP file is damaged or incomplete.');
      }
      ArchiveFile? entry;
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final name = file.name.replaceAll('\\', '/');
        if (name == 'backup.json') {
          entry = file;
          continue;
        }
        if (!name.startsWith('attachments/')) continue;
        final content = file.readBytes();
        if (content != null) {
          attachmentFiles[name] = Uint8List.fromList(content);
        }
      }
      if (entry == null) {
        throw BackupException('No backup.json found inside the ZIP.');
      }
      final data = entry.readBytes();
      if (data == null) {
        throw BackupException('The backup.json entry could not be read.');
      }
      jsonText = utf8.decode(data, allowMalformed: false);
    } else {
      jsonText = utf8.decode(bytes, allowMalformed: false);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      throw BackupException('The backup is not valid JSON.');
    }
    if (decoded is! Map) {
      throw BackupException('The backup has an unexpected structure.');
    }
    final envelope = <String, Object?>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    };
    if (envelope['format'] != format) {
      throw BackupException('This is not a Daymark backup.');
    }
    final version = (envelope['formatVersion'] as num?)?.toInt() ?? 0;
    if (version < 1 || version > formatVersion) {
      throw BackupException(
        'Unsupported backup format v$version. This app supports v$formatVersion.',
      );
    }
    final schemaVersion = (envelope['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schemaVersion > Migrations.latestVersion) {
      throw BackupException(
        'This backup comes from a newer schema (v$schemaVersion). Update Daymark first.',
      );
    }
    final expectedChecksum = envelope['checksum'];
    if (expectedChecksum is! String || expectedChecksum.isEmpty) {
      throw BackupException('The backup has no integrity checksum.');
    }
    final actualChecksum = checksumFor(envelope);
    if (actualChecksum != expectedChecksum) {
      throw BackupException(
        'The backup checksum does not match. The file may have been edited or damaged.',
      );
    }

    final data = _decodeData(envelope['data']);
    String? warning;
    try {
      final preRestore = await createBackup(prefix: 'pre-restore');
      if (preRestore.file == null) {
        warning = 'Restored, but no pre-restore snapshot could be written.';
      }
    } catch (_) {
      warning = 'Restored. A pre-restore safety copy could not be written (storage may be full).';
    }

    await _restore(data, attachmentFiles);
    return BackupResult(
      file: null,
      counts: {for (final table in _tables) table: data[table]!.length},
      createdAt: DateTime.now(),
      warning: warning,
    );
  }

  Future<void> _restore(
    Map<String, List<Map<String, Object?>>> data,
    Map<String, Uint8List> attachmentFiles,
  ) async {
    final categoryIds = <String>{
      for (final row in data['categories']!) row['id'] as String? ?? '',
    }..remove('');
    final taskIds = <String>{
      for (final row in data['tasks']!) row['id'] as String? ?? '',
    }..remove('');

    final attachmentRoot = attachmentDirectory;
    if (attachmentRoot != null) {
      await attachmentRoot.create(recursive: true);
      await for (final entity in attachmentRoot.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // A locked file should not prevent the database restore.
        }
      }
    }

    await _db.transaction((txn) async {
      for (final table in const [
        'task_attachments',
        'time_entries',
        'subtasks',
        'tasks',
        'categories',
        'journal_entries',
        'activity_events',
        'settings',
      ]) {
        await txn.delete(table);
      }

      for (final row in data['settings']!) {
        final clean = _cleanRow('settings', row);
        await txn.insert(
          'settings',
          clean,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      // Always fill anything the backup did not know about.
      for (final entry in AppSettings.defaults.toMap().entries) {
        await txn.insert('settings', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      for (final row in data['categories']!) {
        await txn.insert(
          'categories',
          _cleanRow('categories', row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in data['tasks']!) {
        final clean = _cleanRow('tasks', row);
        final category = clean['category_id'] as String?;
        if (category != null && !categoryIds.contains(category)) {
          clean['category_id'] = null;
        }
        await txn.insert(
          'tasks',
          clean,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in data['subtasks']!) {
        final clean = _cleanRow('subtasks', row);
        final task = clean['task_id'] as String?;
        if (task == null || !taskIds.contains(task)) continue;
        await txn.insert(
          'subtasks',
          clean,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in data['time_entries']!) {
        final clean = _cleanRow('time_entries', row);
        final task = clean['task_id'] as String?;
        if (task != null && !taskIds.contains(task)) clean['task_id'] = null;
        await txn.insert(
          'time_entries',
          clean,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (attachmentRoot != null) {
        for (final row in data['task_attachments']!) {
          final clean = _cleanRow('task_attachments', row);
          final task = clean['task_id'] as String?;
          if (task == null || !taskIds.contains(task)) continue;
          final relative = _safeRelativePath(
            clean['relative_path'] as String? ?? '',
          );
          if (relative == null) continue;
          final archived = attachmentFiles[_attachmentArchivePath(relative)];
          if (archived == null) continue;
          final target = File(p.join(attachmentRoot.path, relative));
          await target.parent.create(recursive: true);
          await target.writeAsBytes(archived, flush: true);
          clean['relative_path'] = relative;
          clean['size_bytes'] = archived.length;
          await txn.insert(
            'task_attachments',
            clean,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      for (final row in data['journal_entries']!) {
        await txn.insert(
          'journal_entries',
          _cleanRow('journal_entries', row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in data['activity_events']!) {
        await txn.insert(
          'activity_events',
          _cleanRow('activity_events', row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      // A live timer is device state, never history.
      await txn.delete('timer_sessions');
    });
  }

  Map<String, List<Map<String, Object?>>> _decodeData(Object? raw) {
    if (raw is! Map) {
      throw BackupException('The backup is missing its data payload.');
    }
    final result = <String, List<Map<String, Object?>>>{};
    for (final table in _tables) {
      final list = raw[table] ?? const <Object?>[];
      if (list is! List) {
        throw BackupException('Backup table “$table” is not a list.');
      }
      result[table] = [
        for (final row in list)
          if (row is Map)
            {for (final entry in row.entries) entry.key.toString(): entry.value}
          else
            throw BackupException('Backup table “$table” has an invalid row.'),
      ];
    }
    return result;
  }

  Map<String, Object?> _cleanRow(String table, Map<String, Object?> row) {
    final allowed = _columns[table];
    if (allowed == null) {
      throw BackupException('Unknown backup table “$table”.');
    }
    return {
      for (final entry in row.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
  }

  Future<Map<String, String>> _markdownFiles() async {
    final files = <String, String>{};
    final journals = await _db.query(
      'journal_entries',
      orderBy: 'date_key ASC',
    );
    for (final row in journals) {
      final date = row['date_key'] as String? ?? 'undated';
      final body = (row['body_md'] as String? ?? '').trim();
      if (body.isEmpty) continue;
      files['markdown/journal/$date.md'] = '# $date\n\n$body\n';
    }

    final attachmentRows = await _db.query(
      'task_attachments',
      orderBy: 'created_at ASC',
    );
    final attachmentsByTask = <String, List<String>>{};
    for (final row in attachmentRows) {
      final taskId = row['task_id'] as String?;
      final name = row['file_name'] as String?;
      if (taskId == null || name == null) continue;
      attachmentsByTask.putIfAbsent(taskId, () => []).add(name);
    }

    final categoryRows = await _db.query('categories');
    final categoryNames = {
      for (final row in categoryRows)
        row['id'] as String: row['name'] as String? ?? '',
    };
    final tasks = await _db.query('tasks', orderBy: 'created_at ASC');
    final ids = <String>{};
    for (final row in tasks) {
      final id = row['id'] as String;
      final title = row['title'] as String? ?? 'Untitled';
      var name = _slug(title);
      if (ids.contains(name)) {
        name =
            '${name.substring(0, math.min(name.length, 40))}-${id.substring(0, 8)}';
      }
      ids.add(name);
      final notes = (row['notes_md'] as String? ?? '').trim();
      final category = categoryNames[row['category_id']] ?? 'Uncategorised';
      final buffer = StringBuffer()
        ..writeln('---')
        ..writeln('title: "${title.replaceAll('"', '\\"')}"')
        ..writeln('category: "${category.replaceAll('"', '\\"')}"')
        ..writeln('kind: ${row['kind']}')
        ..writeln('status: ${row['status']}')
        ..writeln('priority: ${row['priority']}')
        ..writeln('effort: ${row['effort']}')
        ..writeln('planned: ${row['planned_date'] ?? ''}')
        ..writeln('---')
        ..writeln()
        ..writeln('# $title')
        ..writeln();
      if (notes.isNotEmpty) buffer.writeln(notes);
      final attachments = attachmentsByTask[id] ?? const <String>[];
      if (attachments.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('## Attachments');
        for (final attachment in attachments) {
          buffer.writeln('- $attachment');
        }
      }
      files['markdown/tasks/$name.md'] = buffer.toString();
    }
    return files;
  }

  Future<Directory> exportMarkdown() async {
    final now = DateTime.now();
    final directory = Directory(
      p.join(backupDirectory.path, 'daymark-export-${_stamp(now)}'),
    );
    await directory.create(recursive: true);
    final files = await _markdownFiles();
    for (final entry in files.entries) {
      final file = File(p.join(directory.path, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
    await File(p.join(directory.path, 'README.md')).writeAsString(
      '# Daymark export\n\n'
      'Exported ${now.toIso8601String()}.\n\n'
      'This folder contains your journal and task notes as plain markdown. '
      'Task attachment files are not copied here. For a complete, restorable '
      'snapshot use “Create backup” instead.\n',
    );
    return directory;
  }

  Future<File> _uniqueFile(String name) async {
    var file = File(p.join(backupDirectory.path, name));
    var index = 1;
    while (await file.exists()) {
      final base = p.basenameWithoutExtension(name);
      file = File(p.join(backupDirectory.path, '$base-$index.zip'));
      index++;
    }
    return file;
  }

  static String checksumFor(Map<String, Object?> envelope) {
    final payload = <String, Object?>{
      'formatVersion': envelope['formatVersion'],
      'schemaVersion': envelope['schemaVersion'],
      'exportedAt': envelope['exportedAt'],
      'data': envelope['data'],
    };
    return sha256.convert(utf8.encode(canonicalJson(payload))).toString();
  }

  static String _stamp(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}${two(local.month)}${two(local.day)}'
        '-${two(local.hour)}${two(local.minute)}${two(local.second)}';
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

  static String _attachmentArchivePath(String relative) {
    final parts = relative.replaceAll('\\', '/').split('/');
    return p.posix.joinAll(['attachments', ...parts]);
  }

  static String _slug(String input) {
    final slug = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) return 'untitled';
    return slug.length > 56 ? slug.substring(0, 56) : slug;
  }

  static String _backupReadme(DateTime now) =>
      '''
# Daymark backup

Created ${now.toLocal().toIso8601String()}

- `backup.json` is the complete data snapshot. It has a SHA-256 checksum.
- `manifest.json` records format and schema versions.
- `markdown/` contains readable mirrors of journals and task notes.
- `attachments/` contains the files attached to tasks.

Restore from Daymark → Settings → Backup & portability. Backups are plain files
and are not encrypted; store them somewhere you trust. A live stopwatch is not
included.
''';
}
