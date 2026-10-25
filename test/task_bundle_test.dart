import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:daymark/data/db/app_database.dart';
import 'package:daymark/data/models/app_settings.dart';
import 'package:daymark/data/models/enums.dart';
import 'package:daymark/data/repositories/category_repository.dart';
import 'package:daymark/data/repositories/settings_repository.dart';
import 'package:daymark/data/repositories/task_attachment_repository.dart';
import 'package:daymark/data/repositories/task_repository.dart';
import 'package:daymark/data/services/backup_service.dart';
import 'package:daymark/data/services/task_attachment_service.dart';
import 'package:daymark/data/services/task_bundle_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory temp;
  late AppDatabase source;
  late AppDatabase target;
  late Directory sourceFiles;
  late Directory targetFiles;
  late TaskBundleService sourceBundles;
  late TaskBundleService targetBundles;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('daymark_task_bundle_test');
    sourceFiles = Directory(p.join(temp.path, 'source_files'));
    targetFiles = Directory(p.join(temp.path, 'target_files'));
    source = AppDatabase(
      path: p.join(temp.path, 'source.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
    target = AppDatabase(
      path: p.join(temp.path, 'target.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
    await source.open();
    await target.open();
    await SettingsRepository(
      source,
    ).save(AppSettings.defaults.copyWith(onboarded: true, autoBackup: false));
    await SettingsRepository(
      target,
    ).save(AppSettings.defaults.copyWith(onboarded: true, autoBackup: false));
    sourceBundles = TaskBundleService(source, attachmentDirectory: sourceFiles);
    targetBundles = TaskBundleService(target, attachmentDirectory: targetFiles);
  });

  tearDown(() async {
    await source.close();
    await target.close();
    await temp.delete(recursive: true);
  });

  test(
    'round-trips one task with notes, steps, time, reminders, and files',
    () async {
      final categories = CategoryRepository(source);
      final category = await categories.create(
        name: 'Client work',
        color: 0xFF335C4A,
        icon: 'briefcase',
        weight: 1.4,
      );
      final tasks = TaskRepository(source);
      final task = await tasks.createNew(
        title: 'Draft the launch brief',
        categoryId: category.id,
        kind: WorkKind.creative,
        status: TaskStatus.planned,
        priority: Priority.high,
        effort: 4,
        estimateMinutes: 90,
        plannedDate: '2026-10-25',
        dueAt: DateTime(2026, 10, 26, 17),
        reminderAt: DateTime(2026, 10, 25, 9, 30),
        reminderNote: 'Bring the outline and the two charts.',
        notesMd: 'Keep **the promise** small.',
        stepTitles: const ['Outline', 'Find references'],
      );
      await source.db.insert('time_entries', {
        'id': 'entry-1',
        'session_id': null,
        'task_id': task.id,
        'label': 'Writing',
        'note': 'Morning block',
        'source': 'manual',
        'started_at': DateTime(2026, 10, 25, 8).millisecondsSinceEpoch,
        'ended_at': DateTime(2026, 10, 25, 8, 45).millisecondsSinceEpoch,
        'duration_ms': 45 * 60 * 1000,
        'created_at': DateTime(2026, 10, 25, 8, 45).millisecondsSinceEpoch,
      });
      final sourceNote = File(p.join(temp.path, 'brief.txt'));
      await sourceNote.writeAsString('The attached brief.');
      final attachments = TaskAttachmentService(
        TaskAttachmentRepository(source),
        directory: sourceFiles,
      );
      await attachments.addFile(task.id, sourceNote, fileName: 'brief.txt');

      final export = await sourceBundles.exportTask(task.id);
      expect(export.bytes, isNotEmpty);
      expect(export.attachmentCount, 1);

      final archive = ZipDecoder().decodeBytes(export.bytes);
      final names = archive.files.map((file) => file.name).toList();
      expect(names, contains('task.json'));
      expect(names, contains('manifest.json'));
      expect(names, contains('task.md'));
      expect(names.any((name) => name.startsWith('attachments/')), isTrue);
      final envelope = jsonDecode(
        utf8.decode(archive.findFile('task.json')!.content as List<int>),
      ) as Map<String, dynamic>;
      expect(envelope['format'], TaskBundleService.format);
      expect((envelope['task'] as Map)['id'], task.id);
      expect(envelope['subtasks'], hasLength(2));
      expect(envelope['time_entries'], hasLength(1));
      expect(envelope['task_attachments'], hasLength(1));

      final result = await targetBundles.importBytes(export.bytes);
      expect(result.status, TaskBundleImportStatus.created);
      expect(result.taskId, task.id);
      expect(result.attachmentCount, 1);

      final imported = await TaskRepository(target).byId(task.id);
      expect(imported, isNotNull);
      expect(imported!.title, 'Draft the launch brief');
      expect(imported.reminderAt, DateTime(2026, 10, 25, 9, 30));
      expect(imported.reminderNote, 'Bring the outline and the two charts.');
      expect(imported.notesMd, 'Keep **the promise** small.');
      expect(imported.kind, WorkKind.creative);
      expect(imported.priority, Priority.high);
      final importedCategory = await CategoryRepository(target)
          .byId(imported.categoryId!);
      expect(importedCategory!.name, 'Client work');
      expect(importedCategory.weight, closeTo(1.4, 0.001));
      expect(await TaskRepository(target).subtasksFor(task.id), hasLength(2));
      expect(
        await TaskRepository(target).entriesForTask(task.id),
        hasLength(1),
      );
      final importedFiles = await TaskAttachmentRepository(target)
          .listForTask(task.id);
      expect(importedFiles, hasLength(1));
      expect(importedFiles.first.fileName, 'brief.txt');
      expect(
        await File(p.join(targetFiles.path, importedFiles.first.relativePath))
            .readAsString(),
        'The attached brief.',
      );

      // A later export updates the same task instead of creating a duplicate.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final updated = imported.copyWith(
        title: 'Draft the launch brief (v2)',
        updatedAt: DateTime.now().add(const Duration(seconds: 1)),
      );
      await source.db.update(
        'tasks',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [task.id],
      );
      final second = await sourceBundles.exportTask(task.id);
      final updatedResult = await targetBundles.importBytes(second.bytes);
      expect(updatedResult.status, TaskBundleImportStatus.updated);
      expect(
        (await TaskRepository(target).byId(task.id))!.title,
        'Draft the launch brief (v2)',
      );
      expect((await TaskRepository(target).list()), hasLength(1));

      // A newer local copy wins unless the caller explicitly forces the import.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await target.db.update(
        'tasks',
        {
          'title': 'Local copy is newer',
          'updated_at': DateTime.now()
              .add(const Duration(minutes: 1))
              .toUtc()
              .millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [task.id],
      );
      final kept = await targetBundles.importBytes(second.bytes);
      expect(kept.keptLocal, isTrue);
      expect(
        (await TaskRepository(target).byId(task.id))!.title,
        'Local copy is newer',
      );
    },
  );

  test('rejects an unsafe task id before writing any attachment', () async {
    final envelope = {
      'format': TaskBundleService.format,
      'formatVersion': TaskBundleService.formatVersion,
      'schemaVersion': 2,
      'appVersion': 'test',
      'task': {
        'id': '../escape',
        'title': 'Unsafe',
        'notes_md': '',
        'created_at': 1,
        'updated_at': 1,
      },
      'category': null,
      'subtasks': <Object?>[],
      'time_entries': <Object?>[],
      'activity_events': <Object?>[],
      'task_attachments': <Object?>[],
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    await expectLater(
      targetBundles.importBytes(bytes),
      throwsA(isA<TaskBundleException>()),
    );
    expect(await Directory(p.join(temp.path, 'escape')).exists(), isFalse);
  });

  test('backups include task attachments and restore their bytes', () async {
    final tasks = TaskRepository(source);
    final task = await tasks.createNew(title: 'With a file');
    final note = File(p.join(temp.path, 'reference.md'));
    await note.writeAsString('# Reference\n\nKeep this.');
    final attachments = TaskAttachmentService(
      TaskAttachmentRepository(source),
      directory: sourceFiles,
    );
    await attachments.addFile(task.id, note, fileName: 'reference.md');

    final backups = BackupService(
      source,
      backupDirectory: Directory(p.join(temp.path, 'backups')),
      attachmentDirectory: sourceFiles,
    );
    final bytes = await backups.createBackupBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(
      archive.files.any((file) => file.name.startsWith('attachments/')),
      isTrue,
    );

    final restoreBundles = BackupService(
      target,
      backupDirectory: Directory(p.join(temp.path, 'target_backups')),
      attachmentDirectory: targetFiles,
    );
    final restored = await restoreBundles.importBytes(bytes);
    expect(restored.counts['task_attachments'], 1);
    final restoredFiles = await TaskAttachmentRepository(target)
        .listForTask(task.id);
    expect(restoredFiles, hasLength(1));
    expect(restoredFiles.first.fileName, 'reference.md');
    expect(
      await File(p.join(targetFiles.path, restoredFiles.first.relativePath))
          .readAsString(),
      '# Reference\n\nKeep this.',
    );
  });
}
