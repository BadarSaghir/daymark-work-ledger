import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db/app_database.dart';
import '../data/repositories/activity_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/journal_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/task_repository.dart';
import '../data/repositories/timer_repository.dart';
import '../data/services/backup_service.dart';
import '../data/services/demo_service.dart';

/// Overridden in `main()` after the database has opened, and in tests with an
/// in-memory database.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw StateError('databaseProvider must be overridden before use.');
});

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(databaseProvider)),
);

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(databaseProvider)),
);

final timerRepositoryProvider = Provider<TimerRepository>(
  (ref) => TimerRepository(ref.watch(databaseProvider)),
);

final journalRepositoryProvider = Provider<JournalRepository>(
  (ref) => JournalRepository(ref.watch(databaseProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(ref.watch(databaseProvider).db),
);

final demoServiceProvider = Provider<DemoService>(
  (ref) => DemoService(ref.watch(databaseProvider)),
);

final backupDirectoryProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'backups'));
});

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final directory = await ref.watch(backupDirectoryProvider.future);
  return BackupService(ref.watch(databaseProvider), backupDirectory: directory);
});
