import 'dart:io';

import 'package:daymark/data/services/local_account_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LocalAccountStore', () {
    late Directory temp;
    late LocalAccountStore store;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('daymark_accounts_');
      store = LocalAccountStore(temp);
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test(
      'adopts the existing ledger as the first remembered profile',
      () async {
        final registry = await store.load();

        expect(registry.accounts, hasLength(1));
        expect(registry.accounts.single.name, 'Personal');
        expect(registry.accounts.single.legacy, isTrue);
        expect(registry.signedIn, isTrue);
        expect(
          store.databasePath(registry.accounts.single),
          p.join(temp.path, 'data', 'daymark.db'),
        );
        expect(
          File(p.join(temp.path, 'local_accounts.json')).existsSync(),
          isTrue,
        );
      },
    );

    test('adds isolated profiles and remembers the active one', () async {
      final registry = await store.load();
      final studio = store.newAccount('Studio');
      await store.ensureDirectory(studio);

      expect(
        store.databasePath(studio),
        p.join(temp.path, 'accounts', studio.id, 'data', 'daymark.db'),
      );
      expect(
        Directory(p.join(temp.path, 'accounts', studio.id)).existsSync(),
        isTrue,
      );

      await store.save(
        registry.copyWith(
          accounts: [...registry.accounts, studio],
          activeId: studio.id,
          signedIn: false,
        ),
      );
      final reloaded = await store.load();

      expect(reloaded.accounts, hasLength(2));
      expect(reloaded.activeAccount?.name, 'Studio');
      expect(reloaded.signedIn, isFalse);
      expect(reloaded.accounts.first.legacy, isTrue);
    });

    test('quarantines an unreadable registry and recovers a default', () async {
      await File(p.join(temp.path, 'local_accounts.json'))
          .writeAsString('{not-json');

      final registry = await store.load();
      final corrupt = temp
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('corrupt'))
          .toList();

      expect(registry.accounts, hasLength(1));
      expect(registry.activeAccount?.legacy, isTrue);
      expect(corrupt, isNotEmpty);
    });
  });
}
