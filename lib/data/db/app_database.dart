import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

/// Owns the SQLite connection, pragmas, and migration safety net.
class AppDatabase {
  AppDatabase({required this.path, DatabaseFactory? factory})
    : _factory = factory ?? databaseFactory;

  final String path;
  final DatabaseFactory _factory;
  Database? _db;
  String? _lastMigrationSnapshot;

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('AppDatabase.open() must be called before use.');
    }
    return database;
  }

  bool get isOpen => _db != null;

  /// Path of the snapshot created during the most recent upgrade, if any.
  String? get lastMigrationSnapshot => _lastMigrationSnapshot;

  Future<Database> open() async {
    if (_db != null) return _db!;
    _db = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: Migrations.latestVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
          await database.execute('PRAGMA busy_timeout = 5000');
          try {
            await database.execute('PRAGMA journal_mode = WAL');
          } catch (_) {
            // In-memory databases do not support WAL; harmless.
          }
        },
        onCreate: (database, version) async {
          await Migrations.create(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          await _snapshotBeforeMigration(database, oldVersion, newVersion);
          await Migrations.upgrade(database, oldVersion, newVersion);
        },
        onDowngrade: (database, oldVersion, newVersion) async {
          throw StateError(
            'This database is from a newer version of Daymark '
            '(schema v$oldVersion). Update the app instead of downgrading.',
          );
        },
      ),
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Copies the database files before a schema upgrade. SQLite's WAL means the
  /// main file alone may be incomplete, so `-wal`/`-shm` are copied too.
  Future<void> _snapshotBeforeMigration(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (path == ':memory:' || path == inMemoryDatabasePath) return;
    try {
      final source = File(path);
      if (!await source.exists()) return;
      final directory = Directory(p.join(p.dirname(path), 'pre_migration'));
      await directory.create(recursive: true);
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '');
      final base = 'pre-migration-v$oldVersion-to-v$newVersion-$stamp.db';
      for (final suffix in const ['', '-wal', '-shm']) {
        final file = File('$path$suffix');
        if (await file.exists()) {
          final target = File(p.join(directory.path, '$base$suffix'));
          await file.copy(target.path);
          if (suffix.isEmpty) _lastMigrationSnapshot = target.path;
        }
      }
    } catch (_) {
      // A failed safety copy must never block the migration itself.
    }
  }
}
