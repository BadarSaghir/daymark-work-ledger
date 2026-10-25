import 'dart:io';

import 'package:path/path.dart' as p;

/// A local Daymark profile. Each profile owns a separate SQLite ledger and a
/// separate Google Drive link, so work and cloud choices never leak between
/// people sharing a device.
class LocalAccount {
  const LocalAccount({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.lastUsedAt,
    required this.legacy,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  /// The profile that adopted the pre-multi-account data directory. Keeping
  /// this flag avoids moving an existing ledger during an update.
  final bool legacy;

  String get initial {
    final clean = name.trim();
    if (clean.isEmpty) return 'D';
    return clean.substring(0, 1).toUpperCase();
  }

  LocalAccount copyWith({
    String? name,
    DateTime? lastUsedAt,
    bool? legacy,
  }) {
    return LocalAccount(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      legacy: legacy ?? this.legacy,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
    'lastUsedAt': lastUsedAt.toUtc().millisecondsSinceEpoch,
    'legacy': legacy,
  };

  static LocalAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim();
    final name = raw['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) return null;
    return LocalAccount(
      id: id,
      name: name,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['createdAt'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ).toLocal(),
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['lastUsedAt'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ).toLocal(),
      legacy: raw['legacy'] as bool? ?? false,
    );
  }

  /// The profile's private folder below the platform application-support root.
  Directory directory(Directory support) {
    if (legacy) return support;
    return Directory(p.join(support.path, 'accounts', id));
  }
}

class LocalAccountRegistry {
  const LocalAccountRegistry({
    required this.accounts,
    required this.activeId,
    required this.signedIn,
  });

  final List<LocalAccount> accounts;
  final String? activeId;

  /// Local profiles are not a security boundary. This flag is still useful as
  /// an explicit "sign out" gate so a shared desktop returns to the profile
  /// picker instead of opening the last ledger.
  final bool signedIn;

  static const empty = LocalAccountRegistry(
    accounts: [],
    activeId: null,
    signedIn: false,
  );

  LocalAccount? get activeAccount {
    for (final account in accounts) {
      if (account.id == activeId) return account;
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  LocalAccountRegistry copyWith({
    List<LocalAccount>? accounts,
    String? activeId,
    bool? signedIn,
    bool clearActive = false,
  }) {
    return LocalAccountRegistry(
      accounts: accounts ?? this.accounts,
      activeId: clearActive ? null : (activeId ?? this.activeId),
      signedIn: signedIn ?? this.signedIn,
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'accounts': [for (final account in accounts) account.toJson()],
    'activeId': activeId,
    'signedIn': signedIn,
  };

  static LocalAccountRegistry fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final accounts = <LocalAccount>[];
    final rawAccounts = raw['accounts'];
    if (rawAccounts is List) {
      for (final value in rawAccounts) {
        final account = LocalAccount.fromJson(value);
        if (account != null) accounts.add(account);
      }
    }
    if (accounts.isEmpty) return empty;
    final requested = raw['activeId']?.toString();
    final active = accounts.any((account) => account.id == requested)
        ? requested
        : accounts.first.id;
    return LocalAccountRegistry(
      accounts: accounts,
      activeId: active,
      signedIn: raw['signedIn'] as bool? ?? true,
    );
  }
}
