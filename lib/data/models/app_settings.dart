/// User preferences persisted as key/value rows in SQLite.
class AppSettings {
  const AppSettings({
    required this.displayName,
    required this.dailyWeightTarget,
    required this.dailyFocusMinutes,
    required this.weekStartsMonday,
    required this.themeMode,
    required this.onboarded,
    required this.autoBackup,
    required this.lastBackupAt,
    required this.backupRetention,
  });

  final String displayName;
  final double dailyWeightTarget;
  final int dailyFocusMinutes;
  final bool weekStartsMonday;

  /// `system`, `light`, or `dark`.
  final String themeMode;
  final bool onboarded;
  final bool autoBackup;
  final DateTime? lastBackupAt;
  final int backupRetention;

  static const defaults = AppSettings(
    displayName: '',
    dailyWeightTarget: 25,
    dailyFocusMinutes: 300,
    weekStartsMonday: true,
    themeMode: 'system',
    onboarded: false,
    autoBackup: true,
    lastBackupAt: null,
    backupRetention: 7,
  );

  AppSettings copyWith({
    String? displayName,
    double? dailyWeightTarget,
    int? dailyFocusMinutes,
    bool? weekStartsMonday,
    String? themeMode,
    bool? onboarded,
    bool? autoBackup,
    DateTime? lastBackupAt,
    int? backupRetention,
  }) {
    return AppSettings(
      displayName: displayName ?? this.displayName,
      dailyWeightTarget: dailyWeightTarget ?? this.dailyWeightTarget,
      dailyFocusMinutes: dailyFocusMinutes ?? this.dailyFocusMinutes,
      weekStartsMonday: weekStartsMonday ?? this.weekStartsMonday,
      themeMode: themeMode ?? this.themeMode,
      onboarded: onboarded ?? this.onboarded,
      autoBackup: autoBackup ?? this.autoBackup,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      backupRetention: backupRetention ?? this.backupRetention,
    );
  }

  factory AppSettings.fromMap(Map<String, String> map) {
    String raw(String key, String fallback) => map[key] ?? fallback;
    double asDouble(String key, double fallback) =>
        double.tryParse(map[key] ?? '') ?? fallback;
    int asInt(String key, int fallback) =>
        int.tryParse(map[key] ?? '') ?? fallback;
    bool asBool(String key, bool fallback) {
      final value = map[key];
      if (value == null) return fallback;
      return value == '1' || value.toLowerCase() == 'true';
    }

    final lastBackupMs = int.tryParse(map['last_backup_at'] ?? '');
    return AppSettings(
      displayName: raw('display_name', ''),
      dailyWeightTarget: asDouble('daily_weight_target', 25),
      dailyFocusMinutes: asInt('daily_focus_minutes', 300),
      weekStartsMonday: asBool('week_starts_monday', true),
      themeMode: raw('theme_mode', 'system'),
      onboarded: asBool('onboarded', false),
      autoBackup: asBool('auto_backup', true),
      lastBackupAt: lastBackupMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              lastBackupMs,
              isUtc: true,
            ).toLocal(),
      backupRetention: asInt('backup_retention', 7),
    );
  }

  Map<String, String> toMap() {
    return {
      'display_name': displayName,
      'daily_weight_target': dailyWeightTarget.toString(),
      'daily_focus_minutes': dailyFocusMinutes.toString(),
      'week_starts_monday': weekStartsMonday ? '1' : '0',
      'theme_mode': themeMode,
      'onboarded': onboarded ? '1' : '0',
      'auto_backup': autoBackup ? '1' : '0',
      'last_backup_at':
          lastBackupAt?.toUtc().millisecondsSinceEpoch.toString() ?? '',
      'backup_retention': backupRetention.toString(),
    };
  }
}
