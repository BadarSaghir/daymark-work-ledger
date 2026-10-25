import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/local_account.dart';

/// Persists the list of local profiles and owns their directory layout.
///
/// The original single-account ledger lives directly under the application
/// support directory and is adopted as the `legacy` profile. New profiles live
/// under `accounts/<id>/`, giving each one its own database, backups, Google
/// credentials, reminders, and Nearby history.
class LocalAccountStore {
  LocalAccountStore(this.supportDirectory);

  final Directory supportDirectory;

  File get _registryFile =>
      File(p.join(supportDirectory.path, 'local_accounts.json'));

  Future<LocalAccountRegistry> load() async {
    LocalAccountRegistry registry = LocalAccountRegistry.empty;
    if (await _registryFile.exists()) {
      try {
        registry = LocalAccountRegistry.fromJson(
          jsonDecode(await _registryFile.readAsString()),
        );
      } catch (_) {
        await _quarantineCorruptRegistry();
      }
    }
    if (registry.accounts.isEmpty) {
      final now = DateTime.now();
      registry = LocalAccountRegistry(
        accounts: [
          LocalAccount(
            id: 'local-default',
            name: 'Personal',
            createdAt: now,
            lastUsedAt: now,
            legacy: true,
          ),
        ],
        activeId: 'local-default',
        signedIn: true,
      );
      await save(registry);
    }
    return registry;
  }

  Future<void> save(LocalAccountRegistry registry) async {
    await supportDirectory.create(recursive: true);
    final temp = File('${_registryFile.path}.tmp');
    await temp.writeAsString(jsonEncode(registry.toJson()), flush: true);
    if (await _registryFile.exists()) await _registryFile.delete();
    await temp.rename(_registryFile.path);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', _registryFile.path]);
      } catch (_) {
        // Unusual sandboxes may not expose chmod. The registry is not secret.
      }
    }
  }

  LocalAccount newAccount(String name) {
    final now = DateTime.now();
    return LocalAccount(
      id: const Uuid().v4(),
      name: name.trim(),
      createdAt: now,
      lastUsedAt: now,
      legacy: false,
    );
  }

  Future<Directory> ensureDirectory(LocalAccount account) async {
    final directory = account.directory(supportDirectory);
    await directory.create(recursive: true);
    await Directory(p.join(directory.path, 'data')).create(recursive: true);
    return directory;
  }

  String databasePath(LocalAccount account) {
    return p.join(
      account.directory(supportDirectory).path,
      'data',
      'daymark.db',
    );
  }

  Future<void> _quarantineCorruptRegistry() async {
    try {
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '');
      await _registryFile.rename(
        '${_registryFile.path}.corrupt-$stamp',
      );
    } catch (_) {
      // A read-only support directory will fail later with a clearer error.
    }
  }
}
