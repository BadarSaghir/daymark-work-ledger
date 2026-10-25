import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/models/app_settings.dart';
import '../data/models/local_account.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/local_account_store.dart';

/// Created by `main()` after the active local ledger has opened. Tests leave
/// this empty and override `databaseProvider` directly.
class LocalAccountBoot {
  const LocalAccountBoot({
    required this.store,
    required this.registry,
    required this.account,
    required this.database,
  });

  final LocalAccountStore store;
  final LocalAccountRegistry registry;
  final LocalAccount account;
  final AppDatabase database;
}

final localAccountBootProvider = Provider<LocalAccountBoot?>((ref) => null);

class LocalAccountState {
  const LocalAccountState({
    required this.store,
    required this.accounts,
    required this.active,
    required this.signedIn,
    required this.database,
  });

  final LocalAccountStore store;
  final List<LocalAccount> accounts;
  final LocalAccount active;
  final bool signedIn;
  final AppDatabase database;

  LocalAccountState copyWith({
    List<LocalAccount>? accounts,
    LocalAccount? active,
    bool? signedIn,
    AppDatabase? database,
  }) {
    return LocalAccountState(
      store: store,
      accounts: accounts ?? this.accounts,
      active: active ?? this.active,
      signedIn: signedIn ?? this.signedIn,
      database: database ?? this.database,
    );
  }
}

class LocalAccountController extends Notifier<LocalAccountState?> {
  @override
  LocalAccountState? build() {
    final boot = ref.watch(localAccountBootProvider);
    if (boot == null) return null;
    return LocalAccountState(
      store: boot.store,
      accounts: boot.registry.accounts,
      active: boot.account,
      signedIn: boot.registry.signedIn,
      database: boot.database,
    );
  }

  /// Opens another local ledger and makes it current. The previous database is
  /// closed after a short grace period so in-flight queries can finish.
  Future<void> switchTo(String id) async {
    final current = state;
    if (current == null) return;
    final account = current.accounts.where((item) => item.id == id).firstOrNull;
    if (account == null) {
      throw StateError('That local account no longer exists.');
    }
    if (current.active.id == account.id && current.signedIn) return;

    AppDatabase? nextDatabase;
    if (current.active.id == account.id) {
      nextDatabase = current.database;
    } else {
      final candidate = AppDatabase(path: current.store.databasePath(account));
      await current.store.ensureDirectory(account);
      await candidate.open();
      nextDatabase = candidate;
    }

    final now = DateTime.now();
    final accounts = [
      for (final item in current.accounts)
        item.id == account.id ? item.copyWith(lastUsedAt: now) : item,
    ];
    final active = accounts.firstWhere((item) => item.id == account.id);
    await current.store.save(
      LocalAccountRegistry(
        accounts: accounts,
        activeId: active.id,
        signedIn: true,
      ),
    );

    state = current.copyWith(
      accounts: accounts,
      active: active,
      signedIn: true,
      database: nextDatabase,
    );
    if (current.database != nextDatabase) {
      unawaited(
        Future<void>.delayed(
          const Duration(seconds: 3),
          current.database.close,
        ),
      );
    }
  }

  /// Creates a fresh ledger, seeds its identity, and switches to it.
  Future<LocalAccount> createAccount(String name) async {
    final current = state;
    if (current == null) throw StateError('Local accounts are not available.');
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Give this account a name.');

    final account = current.store.newAccount(clean);
    await current.store.ensureDirectory(account);
    final database = AppDatabase(path: current.store.databasePath(account));
    await database.open();
    await SettingsRepository(
      database,
    ).save(AppSettings.defaults.copyWith(displayName: clean, onboarded: true));

    final accounts = [...current.accounts, account];
    await current.store.save(
      LocalAccountRegistry(
        accounts: accounts,
        activeId: account.id,
        signedIn: true,
      ),
    );
    state = current.copyWith(
      accounts: accounts,
      active: account,
      signedIn: true,
      database: database,
    );
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3), current.database.close),
    );
    return account;
  }

  Future<void> renameAccount(String id, String name) async {
    final current = state;
    if (current == null) return;
    final clean = name.trim();
    if (clean.isEmpty) return;
    final accounts = [
      for (final item in current.accounts)
        item.id == id ? item.copyWith(name: clean) : item,
    ];
    await current.store.save(
      LocalAccountRegistry(
        accounts: accounts,
        activeId: current.active.id,
        signedIn: current.signedIn,
      ),
    );
    state = current.copyWith(
      accounts: accounts,
      active: accounts.firstWhere((item) => item.id == current.active.id),
    );
  }

  /// Hides the workspace behind the profile picker without deleting anything.
  Future<void> signOut() async {
    final current = state;
    if (current == null || !current.signedIn) return;
    await current.store.save(
      LocalAccountRegistry(
        accounts: current.accounts,
        activeId: current.active.id,
        signedIn: false,
      ),
    );
    state = current.copyWith(signedIn: false);
  }

  Future<void> signIn() async {
    final current = state;
    if (current == null || current.signedIn) return;
    await current.store.save(
      LocalAccountRegistry(
        accounts: current.accounts,
        activeId: current.active.id,
        signedIn: true,
      ),
    );
    state = current.copyWith(signedIn: true);
  }
}

final localAccountProvider =
    NotifierProvider<LocalAccountController, LocalAccountState?>(
      LocalAccountController.new,
    );

final activeLocalAccountProvider = Provider<LocalAccount?>((ref) {
  return ref.watch(localAccountProvider)?.active;
});
