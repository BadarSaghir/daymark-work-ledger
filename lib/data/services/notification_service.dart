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
      appUserModelId: 'SardarBadar.Daymark.WorkLedger',
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
    var scheduled = 0;
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 60));

    if (preferences.taskReminders) {
      final upcoming = <TaskView>[];
      for (final view in tasks) {
        final task = view.task;
        if (task.isDone || task.archived) continue;
        final start = task.scheduledStart;
        final due = task.dueAt;
        if ((start != null && start.isAfter(now)) ||
            (due != null && due.isAfter(now))) {
          upcoming.add(view);
        }
      }
      upcoming.sort((a, b) {
        final aTime = a.task.scheduledStart ?? a.task.dueAt ?? DateTime(2100);
        final bTime = b.task.scheduledStart ?? b.task.dueAt ?? DateTime(2100);
        return aTime.compareTo(bTime);
      });

      for (final view in upcoming.take(60)) {
        final task = view.task;
        final category = view.category?.name;
        final start = task.scheduledStart;
        if (start != null) {
          final when = start.subtract(
            Duration(minutes: preferences.leadMinutes),
          );
          if (when.isAfter(now) && when.isBefore(horizon)) {
            final ok = await _schedule(
              id: _notificationId('${task.id}:start'),
              title: preferences.leadMinutes == 0
                  ? 'Starting now · ${task.title}'
                  : 'Starts in ${preferences.leadMinutes} min',
              body: [
                task.title,
                ?category,
                'Scheduled ${_timeLabel(start)}',
              ].join(' · '),
              when: when,
            );
            if (ok) scheduled++;
          }
        }
        final due = task.dueAt;
        if (due != null && due.isAfter(now) && due.isBefore(horizon)) {
          final ok = await _schedule(
            id: _notificationId('${task.id}:due'),
            title: 'Due ${_timeLabel(due)} · ${task.title}',
            body: category == null
                ? 'This is the deadline you set.'
                : '$category · deadline',
            when: due,
          );
          if (ok) scheduled++;
        }
      }
    }

    if (preferences.dailyReview) {
      final ok = await _scheduleReview(preferences);
      if (ok) scheduled++;
    }
    return scheduled;
  }

  Future<void> cancelAll() async {
    try {
      await initialize();
      await _plugin.cancelAll();
    } catch (_) {
      // Notification support can be unavailable in tests or a headless build.
    }
  }

  Future<int> pendingCount() async {
    try {
      await initialize();
      return (await _plugin.pendingNotificationRequests()).length;
    } catch (_) {
      return 0;
    }
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
      // A platform without scheduling support should not block the rest.
      return false;
    }
  }

  Future<bool> _scheduleReview(ReminderPreferences preferences) async {
    try {
      final now = tz.TZDateTime.now(tz.local);
      var when = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        preferences.reviewHour,
        preferences.reviewMinute,
      );
      if (!when.isAfter(now)) {
        when = when.add(const Duration(days: 1));
      }
      await _plugin.zonedSchedule(
        id: _reviewId,
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
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } catch (_) {
      return false;
    }
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
