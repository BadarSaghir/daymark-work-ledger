import 'dart:io';

import 'package:daymark/data/db/app_database.dart';
import 'package:daymark/data/models/app_settings.dart';
import 'package:daymark/data/repositories/settings_repository.dart';
import 'package:daymark/data/services/local_account_store.dart';
import 'package:daymark/state/local_account_controller.dart';
import 'package:daymark/state/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  test('switching local accounts swaps the database and settings', () async {
    final support = await Directory.systemTemp.createTemp('daymark_profiles_');
    final store = LocalAccountStore(support);
    final registry = await store.load();
    final personal = registry.activeAccount!;
    await store.ensureDirectory(personal);
    final personalDatabase = AppDatabase(path: store.databasePath(personal));
    await personalDatabase.open();
    await SettingsRepository(personalDatabase).save(
      AppSettings.defaults.copyWith(
        displayName: 'Personal',
        onboarded: true,
        autoBackup: false,
      ),
    );

    final container = ProviderContainer(
      overrides: [
        localAccountBootProvider.overrideWithValue(
          LocalAccountBoot(
            store: store,
            registry: registry,
            account: personal,
            database: personalDatabase,
          ),
        ),
      ],
    );

    try {
      final initial = await container.read(settingsProvider.future);
      expect(initial.displayName, 'Personal');
      expect(container.read(activeLocalAccountProvider)?.id, personal.id);

      final studio = await container
          .read(localAccountProvider.notifier)
          .createAccount('Studio');
      expect(container.read(activeLocalAccountProvider)?.id, studio.id);
      expect(
        container.read(localAccountProvider)!.database,
        isNot(same(personalDatabase)),
      );
      final studioSettings = await container.read(settingsProvider.future);
      expect(studioSettings.displayName, 'Studio');
      expect(studioSettings.onboarded, isTrue);

      await container.read(localAccountProvider.notifier).signOut();
      expect(container.read(localAccountProvider)!.signedIn, isFalse);

      await container.read(localAccountProvider.notifier).switchTo(personal.id);
      expect(container.read(localAccountProvider)!.signedIn, isTrue);
      expect(container.read(activeLocalAccountProvider)?.id, personal.id);
      final restored = await container.read(settingsProvider.future);
      expect(restored.displayName, 'Personal');

      final restarted = await LocalAccountStore(support).load();
      expect(restarted.accounts, hasLength(2));
      expect(restarted.activeAccount?.id, personal.id);
      expect(restarted.signedIn, isTrue);
    } finally {
      await container.read(localAccountProvider)?.database.close();
      await personalDatabase.close();
      container.dispose();
      await support.delete(recursive: true);
    }
  });
}
