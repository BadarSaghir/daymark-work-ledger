import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:daymark/data/db/app_database.dart';
import 'package:daymark/data/models/app_settings.dart';
import 'package:daymark/data/repositories/category_repository.dart';
import 'package:daymark/data/repositories/settings_repository.dart';
import 'package:daymark/data/repositories/task_repository.dart';
import 'package:daymark/data/models/enums.dart';
import 'package:daymark/data/services/backup_service.dart';
import 'package:daymark/core/utils/canonical_json.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory temp;
  late AppDatabase db;
  late BackupService backups;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('daymark_backup_test');
    db = AppDatabase(
      path: p.join(temp.path, 'test.db'),
      factory: databaseFactoryFfi,
    );
    await db.open();
    await SettingsRepository(
      db,
    ).save(AppSettings.defaults.copyWith(onboarded: true, autoBackup: false));
    backups = BackupService(
      db,
      backupDirectory: Directory(p.join(temp.path, 'backups')),
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test(
    'creates a portable, checksummed archive with markdown mirrors',
    () async {
      final categories = CategoryRepository(db);
      final tasks = TaskRepository(db);
      final category = await categories.create(
        name: 'Client work',
        color: 0xFF335C4A,
        icon: 'briefcase',
      );
      await tasks.createNew(
        title: 'Draft the brief',
        categoryId: category.id,
        status: TaskStatus.planned,
        plannedDate: '2026-10-24',
        notesMd: 'Keep **the promise** small.',
      );
      await tasks.createNew(title: 'Inbox thought', notesMd: 'One line.');

      final result = await backups.createBackup();
      expect(result.file, isNotNull);
      expect(result.counts['tasks'], 2);
      expect(result.counts['categories'], greaterThanOrEqualTo(1));

      final archive = ZipDecoder().decodeBytes(
        await result.file!.readAsBytes(),
      );
      final names = archive.files.map((file) => file.name).toList();
      expect(names, contains('backup.json'));
      expect(names, contains('manifest.json'));
      expect(names, contains('README.md'));
      expect(names.any((name) => name.startsWith('markdown/tasks/')), isTrue);

      final backupJson = jsonDecode(
        utf8.decode(archive.findFile('backup.json')!.content as List<int>),
      ) as Map<String, dynamic>;
      final checksum = backupJson['checksum'];
      expect(checksum, isNotNull);
      backupJson.remove('checksum');
      expect(BackupService.checksumFor(backupJson), checksum);
    },
  );

  test('restoring replaces rows and keeps a pre-restore copy', () async {
    final tasks = TaskRepository(db);
    final original = await tasks.createNew(
      title: 'Original title',
      notesMd: 'Original notes',
    );
    final result = await backups.createBackup();
    await db.db.update(
      'tasks',
      {'title': 'Changed after backup'},
      where: 'id = ?',
      whereArgs: [original.id],
    );

    final restored = await backups.importFile(result.file!);
    expect(restored.counts['tasks'], 1);
    expect((await tasks.byId(original.id))!.title, 'Original title');

    final files = Directory(p.join(temp.path, 'backups')).listSync();
    expect(
      files.where((file) => p.basename(file.path).startsWith('pre-restore-')),
      isNotEmpty,
    );
  });

  test('rejects an archive whose checksum no longer matches', () async {
    final tasks = TaskRepository(db);
    await tasks.createNew(title: 'Untampered');
    final result = await backups.createBackup();
    final bytes = await result.file!.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final backupFile = archive.findFile('backup.json')!;
    final map = jsonDecode(
      utf8.decode(backupFile.content as List<int>),
    ) as Map<String, dynamic>;
    map['exportedAt'] = 0;
    final tampered = utf8.encode(jsonEncode(map));
    archive.addFile(ArchiveFile('backup.json', tampered.length, tampered));
    final encoded = ZipEncoder().encode(archive);

    expect(
      () => backups.importBytes(
        Uint8List.fromList(encoded),
        sourceName: 'tampered.zip',
      ),
      throwsA(isA<BackupException>()),
    );
  });
}
