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
    await (await _service()).cancelManaged();
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

  /// Rebuilds the platform schedule. Failures in individual notifications are
  /// collected in the report instead of breaking the workspace.
  Future<NotificationSyncReport> syncNow() async {
    final service = await _service();
    final preferences = state.value;
    if (preferences == null) {
      return NotificationSyncReport(
        at: DateTime.now(),
        scheduled: 0,
        failed: 0,
        errors: const [],
        exactUsed: false,
        permissionDenied: false,
      );
    }
    if (!preferences.enabled) {
      await service.cancelManaged();
      return NotificationSyncReport(
        at: DateTime.now(),
        scheduled: 0,
        failed: 0,
        errors: const [],
        exactUsed: false,
        permissionDenied: false,
      );
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

  Future<NotificationStatus> status() async {
    final service = await _service();
    return service.status();
  }

  Future<List<ScheduledReminder>> upcoming() async {
    final service = await _service();
    return service.upcoming();
  }

  Future<void> sendTest({String? title, String? body}) async {
    final service = await _service();
    await service.showTest(title: title, body: body);
  }

  /// Schedules a real test notification through the OS scheduler.
  Future<DateTime?> scheduleTest({
    Duration delay = const Duration(seconds: 10),
    String? title,
    String? body,
  }) async {
    final service = await _service();
    return service.scheduleTest(delay: delay, title: title, body: body);
  }

  Future<DateTime?> scheduleCustom({
    required String title,
    required String body,
    required DateTime when,
    bool repeatDaily = false,
  }) async {
    final service = await _service();
    return service.scheduleCustom(
      title: title,
      body: body,
      when: when,
      repeatDaily: repeatDaily,
    );
  }

  Future<void> cancel(int id) async {
    final service = await _service();
    await service.cancel(id);
  }

  Future<void> cancelAll() async {
    final service = await _service();
    await service.cancelAll();
  }

  Future<bool> requestPermission() async {
    final service = await _service();
    return service.requestPermission();
  }

  Future<bool> requestExactAlarms() async {
    final service = await _service();
    return service.requestExactAlarms();
  }

  Future<bool> openSystemSettings() async {
    final service = await _service();
    return service.openSystemSettings();
  }
}

final reminderControllerProvider =
    AsyncNotifierProvider<ReminderController, ReminderPreferences>(
      ReminderController.new,
    );
