import 'package:sqflite_common/sqlite_api.dart';

import '../db/app_database.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._appDb);

  final AppDatabase _appDb;

  Database get _db => _appDb.db;

  Future<AppSettings> load() async {
    final rows = await _db.query('settings');
    final map = <String, String>{
      for (final row in rows)
        row['key'] as String: row['value'] as String? ?? '',
    };
    return AppSettings.fromMap(map);
  }

  Future<void> save(AppSettings settings) async {
    final batch = _db.batch();
    for (final entry in settings.toMap().entries) {
      batch.insert('settings', {
        'key': entry.key,
        'value': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> put(String key, String value) async {
    await _db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
