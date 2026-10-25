import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/notification_service.dart';
import 'repository_providers.dart';
import 'tasks_controller.dart';

/// Reads and writes reminder preferences, then keeps the OS-level schedule in
/// step with the local task list.
class ReminderController extends AsyncNotifier<ReminderPreferences> {
  @override
  Future<ReminderPreferences> build() async {
    final service = await ref.watch(notificationServiceProvider.future);
    return service.loadPreferences();
  }

  Future<NotificationService> _service() =>
      ref.read(notificationServiceProvider.future);

  /// Asks the platform for permission. Returns false when the user declines or
  /// the platform has notifications switched off for Daymark.
  Future<bool> enable() async {
    final service = await _service();
    final granted = await service.requestPermission();
    if (!granted) return false;
    final current = state.value ?? ReminderPreferences.defaults;
    await _persist(current.copyWith(enabled: true));
    return true;
  }

  Future<void> disable() async {
    final current = state.value ?? ReminderPreferences.defaults;
    await _persist(current.copyWith(enabled: false));
    await (await _service()).cancelAll();
  }

  Future<void> savePreferences(ReminderPreferences preferences) async {
    await _persist(preferences);
  }

  Future<void> _persist(ReminderPreferences preferences) async {
    final service = await _service();
    await service.savePreferences(preferences);
    state = AsyncData(preferences);
    await syncNow();
  }

  /// Rebuilds the platform schedule. Returns the number of reminders accepted,
  /// or zero when reminders are off. Failures in individual notifications are
  /// ignored by the service; a missing platform returns zero.
  Future<int> syncNow() async {
    final preferences = state.value;
    final service = await _service();
    if (preferences == null) {
      return 0;
    }
    if (!preferences.enabled) {
      await service.cancelAll();
      return 0;
    }
    final tasks = await ref.read(tasksProvider.future);
    return service.sync(tasks, preferences);
  }

  /// Linux fallback pulse. It is a no-op on platforms with native scheduling.
  Future<int> pumpDueReminders() async {
    final preferences = state.value;
    if (preferences == null || !preferences.enabled) return 0;
    final service = await _service();
    final tasks = await ref.read(tasksProvider.future);
    return service.checkDueReminders(tasks, preferences);
  }

  Future<int> pendingCount() async {
    final service = await _service();
    return service.pendingCount();
  }

  Future<void> sendTest() async {
    final service = await _service();
    await service.showTest();
  }

  Future<bool> requestPermission() async {
    final service = await _service();
    return service.requestPermission();
  }
}

final reminderControllerProvider =
    AsyncNotifierProvider<ReminderController, ReminderPreferences>(
      ReminderController.new,
    );
