import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/task_view.dart';
import '../../core/utils/date_keys.dart';

class ReminderPreferences {
  const ReminderPreferences({
    required this.enabled,
    required this.taskReminders,
    required this.leadMinutes,
    required this.dailyReview,
    required this.reviewHour,
    required this.reviewMinute,
  });

  final bool enabled;
  final bool taskReminders;
  final int leadMinutes;
  final bool dailyReview;
  final int reviewHour;
  final int reviewMinute;

  static const defaults = ReminderPreferences(
    enabled: false,
    taskReminders: true,
    leadMinutes: 10,
    dailyReview: true,
    reviewHour: 18,
    reviewMinute: 30,
  );

  String get reviewLabel {
    final hour = reviewHour % 12 == 0 ? 12 : reviewHour % 12;
    final minute = reviewMinute.toString().padLeft(2, '0');
    final suffix = reviewHour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  ReminderPreferences copyWith({
    bool? enabled,
    bool? taskReminders,
    int? leadMinutes,
    bool? dailyReview,
    int? reviewHour,
    int? reviewMinute,
  }) {
    return ReminderPreferences(
      enabled: enabled ?? this.enabled,
      taskReminders: taskReminders ?? this.taskReminders,
      leadMinutes: leadMinutes ?? this.leadMinutes,
      dailyReview: dailyReview ?? this.dailyReview,
      reviewHour: reviewHour ?? this.reviewHour,
      reviewMinute: reviewMinute ?? this.reviewMinute,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'taskReminders': taskReminders,
    'leadMinutes': leadMinutes,
    'dailyReview': dailyReview,
    'reviewHour': reviewHour,
    'reviewMinute': reviewMinute,
  };

  static ReminderPreferences fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    return ReminderPreferences(
      enabled: raw['enabled'] as bool? ?? defaults.enabled,
      taskReminders: raw['taskReminders'] as bool? ?? defaults.taskReminders,
      leadMinutes: ((raw['leadMinutes'] as num?)?.toInt() ?? 10).clamp(0, 120),
      dailyReview: raw['dailyReview'] as bool? ?? defaults.dailyReview,
      reviewHour: ((raw['reviewHour'] as num?)?.toInt() ?? 18).clamp(0, 23),
      reviewMinute: ((raw['reviewMinute'] as num?)?.toInt() ?? 30).clamp(0, 59),
    );
  }
}

/// Schedules OS-level local notifications. There is no push service: every
/// reminder is computed from the local database and handed to the platform.
class NotificationService {
  NotificationService({required this.configDirectory});

  final Directory configDirectory;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _linuxFallbackCount = 0;
  final Set<String> _firedFallbackReminders = <String>{};

  File get _prefsFile =>
      File(p.join(configDirectory.path, 'notifications.json'));

  static const _channelId = 'daymark_reminders';
  static const _channelName = 'Daymark reminders';
  static const _channelDescription =
      'Task start and due reminders, and the daily closing note.';
  static const _reviewId = 910001;

  Future<ReminderPreferences> loadPreferences() async {
    if (!await _prefsFile.exists()) return ReminderPreferences.defaults;
    try {
      return ReminderPreferences.fromJson(
        jsonDecode(await _prefsFile.readAsString()),
      );
    } catch (_) {
      return ReminderPreferences.defaults;
    }
  }

  Future<void> savePreferences(ReminderPreferences preferences) async {
    await configDirectory.create(recursive: true);
    final temp = File('${_prefsFile.path}.tmp');
    await temp.writeAsString(jsonEncode(preferences.toJson()), flush: true);
    if (await _prefsFile.exists()) await _prefsFile.delete();
    await temp.rename(_prefsFile.path);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Keep the bundled default when a platform cannot report its zone.
    }

    const android = AndroidInitializationSettings('ic_notification');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linux = LinuxInitializationSettings(
      defaultActionName: 'Open Daymark',
    );
    const windows = WindowsInitializationSettings(
      appName: 'Daymark',
      appUserModelId: 'com.daymark.daymark',
      guid: 'a3d9c3f6-6f7b-4be4-9d3b-1f2f7d1a8c42',
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
        linux: linux,
        windows: windows,
      ),
    );
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (Platform.isMacOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    // Linux and Windows use the desktop notification service and do not have a
    // runtime permission prompt.
    return true;
  }

  /// Cancels Daymark reminders and schedules the current set.
  Future<int> sync(
    List<TaskView> tasks,
    ReminderPreferences preferences,
  ) async {
    if (!preferences.enabled) {
      await cancelAll();
      return 0;
    }
    await initialize();
    await _plugin.cancelAll();
    _linuxFallbackCount = 0;
    var scheduled = 0;
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 365));

    if (preferences.taskReminders) {
      final candidates =
          <({int id, DateTime when, String title, String body})>[];
      for (final view in tasks) {
        final task = view.task;
        if (task.isDone || task.archived) continue;
        final category = view.category?.name;
        final start = task.scheduledStart;
        if (start != null) {
          final when = start.subtract(
            Duration(minutes: preferences.leadMinutes),
          );
          if (when.isAfter(now) && when.isBefore(horizon)) {
            candidates.add((
              id: _notificationId('${task.id}:start'),
              when: when,
              title: preferences.leadMinutes == 0
                  ? 'Starting now · ${task.title}'
                  : 'Starts in ${preferences.leadMinutes} min',
              body: [
                task.title,
                ?category,
                'Scheduled ${_timeLabel(start)}',
              ].join(' · '),
            ));
          }
        }
        final due = task.dueAt;
        if (due != null && due.isAfter(now) && due.isBefore(horizon)) {
          candidates.add((
            id: _notificationId('${task.id}:due'),
            when: due,
            title: 'Due ${_timeLabel(due)} · ${task.title}',
            body: category == null
                ? 'This is the deadline you set.'
                : '$category · deadline',
          ));
        }
        final reminderAt = task.reminderAt;
        if (reminderAt != null &&
            reminderAt.isAfter(now) &&
            reminderAt.isBefore(horizon)) {
          final note = task.reminderNote?.trim() ?? '';
          candidates.add((
            id: _notificationId('${task.id}:custom'),
            when: reminderAt,
            title: 'Reminder · ${task.title}',
            body: note.isEmpty
                ? (category == null
                      ? 'You asked to be reminded about this task.'
                      : '$category · custom reminder')
                : note,
          ));
        }
      }

      // Keep the nearest reminders. iOS allows only 64 pending notifications,
      // so a task cap would let distant deadlines crowd out custom reminders.
      candidates.sort((a, b) => a.when.compareTo(b.when));
      for (final reminder in candidates.take(60)) {
        final ok = await _schedule(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          when: reminder.when,
        );
        if (ok) scheduled++;
      }
    }

    if (preferences.dailyReview) {
      final ok = await _scheduleReview(preferences);
      if (ok) scheduled++;
    }
    return scheduled;
  }

  Future<void> cancelAll() async {
    _linuxFallbackCount = 0;
    _firedFallbackReminders.clear();
    try {
      await initialize();
      await _plugin.cancelAll();
    } catch (_) {
      // Notification support can be unavailable in tests or a headless build.
    }
  }

  Future<int> pendingCount() async {
    if (Platform.isLinux) return _linuxFallbackCount;
    try {
      await initialize();
      return (await _plugin.pendingNotificationRequests()).length;
    } catch (_) {
      return 0;
    }
  }

  /// Linux has no scheduled-notification API in the plugin. While Daymark is
  /// open, this pulse raises reminders that have just become due. The OS still
  /// owns rendering; the app only supplies the timing. Returns the number of
  /// notifications raised in this pass.
  Future<int> checkDueReminders(
    List<TaskView> tasks,
    ReminderPreferences preferences, {
    DateTime? at,
  }) async {
    if (!Platform.isLinux || !preferences.enabled) return 0;
    final now = at ?? DateTime.now();
    final due = <({String key, DateTime when, String title, String body})>[];

    if (preferences.taskReminders) {
      for (final view in tasks) {
        final task = view.task;
        if (task.isDone || task.archived) continue;
        final category = view.category?.name;
        final start = task.scheduledStart;
        if (start != null) {
          final when = start.subtract(
            Duration(minutes: preferences.leadMinutes),
          );
          if (_isFresh(when, now)) {
            due.add((
              key: '${task.id}:start:${when.millisecondsSinceEpoch}',
              when: when,
              title: preferences.leadMinutes == 0
                  ? 'Starting now · ${task.title}'
                  : 'Starts in ${preferences.leadMinutes} min',
              body: [
                task.title,
                ?category,
                'Scheduled ${_timeLabel(start)}',
              ].join(' · '),
            ));
          }
        }
        final deadline = task.dueAt;
        if (deadline != null && _isFresh(deadline, now)) {
          due.add((
            key: '${task.id}:due:${deadline.millisecondsSinceEpoch}',
            when: deadline,
            title: 'Due ${_timeLabel(deadline)} · ${task.title}',
            body: category == null
                ? 'This is the deadline you set.'
                : '$category · deadline',
          ));
        }
        final custom = task.reminderAt;
        if (custom != null && _isFresh(custom, now)) {
          final note = task.reminderNote?.trim() ?? '';
          due.add((
            key: '${task.id}:custom:${custom.millisecondsSinceEpoch}',
            when: custom,
            title: 'Reminder · ${task.title}',
            body: note.isEmpty
                ? (category == null
                      ? 'You asked to be reminded about this task.'
                      : '$category · custom reminder')
                : note,
          ));
        }
      }
    }

    if (preferences.dailyReview) {
      var review = DateTime(
        now.year,
        now.month,
        now.day,
        preferences.reviewHour,
        preferences.reviewMinute,
      );
      if (review.isAfter(now)) {
        review = review.subtract(const Duration(days: 1));
      }
      if (_isFresh(review, now, grace: const Duration(hours: 12))) {
        due.add((
          key:
              'review:${review.year}-${review.month}-${review.day}:'
              '${review.millisecondsSinceEpoch}',
          when: review,
          title: 'Close the day',
          body:
              'A few minutes to mark what moved, what stalled, and what '
              'tomorrow needs.',
        ));
      }
    }

    due.sort((a, b) => a.when.compareTo(b.when));
    var raised = 0;
    for (final reminder in due) {
      if (!_firedFallbackReminders.add(reminder.key)) continue;
      await _showNow(
        id: _notificationId(reminder.key),
        title: reminder.title,
        body: reminder.body,
      );
      raised++;
    }
    // Keep the set from growing across a long-running desktop session.
    if (_firedFallbackReminders.length > 500) {
      _firedFallbackReminders.removeAll(
        _firedFallbackReminders.take(200).toSet(),
      );
    }
    return raised;
  }

  static bool _isFresh(
    DateTime when,
    DateTime now, {
    Duration grace = const Duration(minutes: 8),
  }) {
    if (when.isAfter(now)) return false;
    return now.difference(when) <= grace;
  }

  Future<void> showTest() async {
    await initialize();
    await _plugin.show(
      id: 910099,
      title: 'Daymark is listening',
      body:
          'Offline reminders are working. This appears even without an '
          'internet connection.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
    );
  }

  Future<bool> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_notification',
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return true;
    } catch (_) {
      // Linux has no scheduler in flutter_local_notifications. Count it for
      // the settings summary and let AppShell's in-app pulse display it.
      if (Platform.isLinux) {
        _linuxFallbackCount++;
        return true;
      }
      // A platform without scheduling support should not block the rest.
      return false;
    }
  }

  Future<void> _showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await initialize();
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_notification',
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
      );
    } catch (_) {
      // A shell without a notification daemon must not break the app.
    }
  }

  Future<bool> _scheduleReview(ReminderPreferences preferences) async {
    try {
      final now = tz.TZDateTime.now(tz.local);
      final first = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        preferences.reviewHour,
        preferences.reviewMinute,
      );
      final start = first.isAfter(now)
          ? first
          : tz.TZDateTime(
              tz.local,
              now.year,
              now.month,
              now.day + 1,
              preferences.reviewHour,
              preferences.reviewMinute,
            );

      // Windows has no repeating local notifications. Queue a month of closing
      // notes so a long-running workspace keeps its daily cue.
      if (Platform.isWindows) {
        for (var offset = 0; offset < 30; offset++) {
          final when = tz.TZDateTime(
            tz.local,
            start.year,
            start.month,
            start.day + offset,
            preferences.reviewHour,
            preferences.reviewMinute,
          );
          await _scheduleReviewAt(
            id: _reviewId + offset,
            when: when,
            repeatDaily: false,
          );
        }
        return true;
      }

      await _scheduleReviewAt(id: _reviewId, when: start, repeatDaily: true);
      return true;
    } catch (_) {
      if (Platform.isLinux) {
        _linuxFallbackCount++;
        return true;
      }
      return false;
    }
  }

  Future<void> _scheduleReviewAt({
    required int id,
    required tz.TZDateTime when,
    required bool repeatDaily,
  }) {
    return _plugin.zonedSchedule(
      id: id,
      title: 'Close the day',
      body:
          'A few minutes to mark what moved, what stalled, and what '
          'tomorrow needs.',
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: 'ic_notification',
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: repeatDaily ? DateTimeComponents.time : null,
    );
  }

  static int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static String _timeLabel(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  static String dayLabel(DateTime value) => longDateLabel(value);

  static int get maxTaskReminders => math.min(60, 120);
}
