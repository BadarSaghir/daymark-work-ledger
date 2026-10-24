import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_settings.dart';
import 'repository_providers.dart';

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    return ref.watch(settingsRepositoryProvider).load();
  }

  Future<void> save(AppSettings settings) async {
    final previous = state.valueOrNull;
    state = AsyncData(settings);
    try {
      await ref.read(settingsRepositoryProvider).save(settings);
    } catch (error, stack) {
      state = previous == null ? AsyncError(error, stack) : AsyncData(previous);
      rethrow;
    }
  }

  Future<void> patch(AppSettings Function(AppSettings current) update) async {
    final current = state.valueOrNull ?? AppSettings.defaults;
    await save(update(current));
  }

  Future<void> setThemeMode(String mode) =>
      patch((settings) => settings.copyWith(themeMode: mode));

  Future<void> completeOnboarding({
    required String displayName,
    required double dailyWeightTarget,
    required int dailyFocusMinutes,
    required String themeMode,
  }) {
    return patch(
      (settings) => settings.copyWith(
        displayName: displayName.trim(),
        dailyWeightTarget: dailyWeightTarget.clamp(4, 100),
        dailyFocusMinutes: dailyFocusMinutes.clamp(30, 900),
        themeMode: themeMode,
        onboarded: true,
      ),
    );
  }

  Future<void> markBackupAt(DateTime at) =>
      patch((settings) => settings.copyWith(lastBackupAt: at));
}

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
