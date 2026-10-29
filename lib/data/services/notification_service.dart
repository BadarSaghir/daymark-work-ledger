import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/utils/date_keys.dart';
import '../models/task_view.dart';

/// Everything Daymark remembers about reminders. Stored as JSON beside the
/// profile database so it survives restarts and account switches.
class ReminderPreferences {
  const ReminderPreferences({
    required this.enabled,
    required this.taskReminders,
    required this.leadMinutes,
    required this.dailyReview,
    required this.reviewHour,
    required this.reviewMinute,
    this.startReminders = true,
    this.deadlineReminders = true,
    this.customReminders = true,
    this.dailyTaskReminders = true,
  });

  final bool enabled;

  /// Master switch for every task-based reminder.
  final bool taskReminders;
  final int leadMinutes;
  final bool dailyReview;
  final int reviewHour;
  final int reviewMinute;

  /// Individual task reminder types. Keeping them separate lets a person mute
  /// deadline nudges without losing the reminder attached to a task.
  final bool startReminders;
  final bool deadlineReminders;
  final bool customReminders;
  final bool dailyTaskReminders;

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
    bool? startReminders,
    bool? deadlineReminders,
    bool? customReminders,
    bool? dailyTaskReminders,
  }) {
    return ReminderPreferences(
      enabled: enabled ?? this.enabled,
      taskReminders: taskReminders ?? this.taskReminders,
      leadMinutes: leadMinutes ?? this.leadMinutes,
      dailyReview: dailyReview ?? this.dailyReview,
      reviewHour: reviewHour ?? this.reviewHour,
      reviewMinute: reviewMinute ?? this.reviewMinute,
      startReminders: startReminders ?? this.startReminders,
      deadlineReminders: deadlineReminders ?? this.deadlineReminders,
      customReminders: customReminders ?? this.customReminders,
      dailyTaskReminders: dailyTaskReminders ?? this.dailyTaskReminders,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'taskReminders': taskReminders,
    'leadMinutes': leadMinutes,
    'dailyReview': dailyReview,
    'reviewHour': reviewHour,
    'reviewMinute': reviewMinute,
    'startReminders': startReminders,
    'deadlineReminders': deadlineReminders,
    'customReminders': customReminders,
    'dailyTaskReminders': dailyTaskReminders,
  };

  static ReminderPreferences fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    final legacyTasks = raw['taskReminders'] as bool? ?? defaults.taskReminders;
    return ReminderPreferences(
      enabled: raw['enabled'] as bool? ?? defaults.enabled,
      taskReminders: legacyTasks,
      leadMinutes: ((raw['leadMinutes'] as num?)?.toInt() ?? 10).clamp(0, 120),
      dailyReview: raw['dailyReview'] as bool? ?? defaults.dailyReview,
      reviewHour: ((raw['reviewHour'] as num?)?.toInt() ?? 18).clamp(0, 23),
      reviewMinute: ((raw['reviewMinute'] as num?)?.toInt() ?? 30).clamp(0, 59),
      startReminders:
          raw['startReminders'] as bool? ?? legacyTasks,
      deadlineReminders:
          raw['deadlineReminders'] as bool? ?? legacyTasks,
      customReminders: raw['customReminders'] as bool? ?? legacyTasks,
      dailyTaskReminders:
          raw['dailyTaskReminders'] as bool? ?? legacyTasks,
    );
  }
}

/// The kinds of notification Daymark can schedule. Each kind gets its own
/// Android channel so device settings can be tuned individually.
enum NotificationKind {
  taskStart,
  taskDeadline,
  taskCustom,
  taskDaily,
  dailyReview,
  custom,
  test,
}

/// A notification that should exist on the operating system schedule. Pure
/// data so it can be planned and tested without touching a platform plugin.
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.when,
    required this.repeatDaily,
    this.taskId,
  });

  final int id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime when;
  final bool repeatDaily;
  final String? taskId;

  PlannedNotification copyWith({
    int? id,
    DateTime? when,
    bool? repeatDaily,
  }) {
    return PlannedNotification(
      id: id ?? this.id,
      kind: kind,
      title: title,
      body: body,
      when: when ?? this.when,
      repeatDaily: repeatDaily ?? this.repeatDaily,
      taskId: taskId,
    );
  }
}

/// A pending request as exposed by the OS, enriched with the metadata Daymark
/// stores in the notification payload.
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.repeatDaily,
    this.when,
    this.taskId,
  });

  final int id;
  final String title;
  final String body;
  final NotificationKind kind;
  final bool repeatDaily;
  final DateTime? when;
  final String? taskId;
}

class NotificationSyncReport {
  const NotificationSyncReport({
    required this.at,
    required this.scheduled,
    required this.failed,
    required this.errors,
    required this.exactUsed,
    required this.permissionDenied,
  });

  final DateTime at;
  final int scheduled;
  final int failed;
  final List<String> errors;
  final bool exactUsed;
  final bool permissionDenied;

  bool get ok => failed == 0 && errors.isEmpty;

  String get summary {
    if (permissionDenied) {
      return 'Notifications are blocked for Daymark in system settings.';
    }
    if (scheduled == 0 && failed == 0) {
      return 'No future reminders to schedule.';
    }
    if (failed > 0) {
      return '$scheduled scheduled · $failed could not be scheduled';
    }
    return '$scheduled reminders scheduled';
  }
}

class NotificationStatus {
  const NotificationStatus({
    required this.supported,
    required this.permissionGranted,
    required this.exactSupported,
    required this.exactAllowed,
    required this.pending,
    required this.initError,
    required this.lastReport,
    required this.platformNote,
  });

  final bool supported;
  final bool permissionGranted;
  final bool exactSupported;
  final bool exactAllowed;
  final int pending;
  final String? initError;
  final NotificationSyncReport? lastReport;
  final String platformNote;
}

/// Schedules OS-level local notifications. There is no push service: every
/// reminder is computed from the local database and handed to the platform.
///
/// The service is deliberately defensive. A missing plugin, a denied
/// permission, or an OEM battery restriction must never surface as a raw
/// PlatformException in the UI. Every call records a human-readable failure
/// instead, and the notification screen can show exactly what happened.
class NotificationService {
  NotificationService({required this.configDirectory});

  final Directory configDirectory;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void>? _initFuture;
  bool _initialized = false;
  String? _initError;
  bool _exactAllowed = false;
  int _linuxFallbackCount = 0;
  final Set<String> _firedFallbackReminders = <String>{};
  NotificationSyncReport? _lastReport;

  File get _prefsFile =>
      File(p.join(configDirectory.path, 'notifications.json'));

  static const taskChannelId = 'daymark_task_reminders';
  static const deadlineChannelId = 'daymark_deadlines';
  static const customChannelId = 'daymark_custom_reminders';
  static const dailyChannelId = 'daymark_daily_task_reminders';
  static const reviewChannelId = 'daymark_daily_review';
  static const testChannelId = 'daymark_test';

  static const _reviewId = 910001;
  static const _testId = 910099;
  static const _payloadSource = 'daymark';
  static const _kindsCancelledOnSync = {
    NotificationKind.taskStart,
    NotificationKind.taskDeadline,
    NotificationKind.taskCustom,
    NotificationKind.taskDaily,
    NotificationKind.dailyReview,
  };

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

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initFuture ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    try {
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
      if (Platform.isAndroid) {
        await _createAndroidChannels();
        try {
          final androidPlugin = _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
          _exactAllowed =
              await androidPlugin?.canScheduleExactNotifications() ?? false;
        } catch (_) {
          _exactAllowed = false;
        }
      }
      _initialized = true;
      _initError = null;
    } catch (error) {
      _initialized = false;
      _initError = _humanize(error);
      // Allow a later retry after the platform is ready (for example after the
      // first frame or after the user grants permission in system settings).
      _initFuture = null;
    }
  }

  Future<void> _createAndroidChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    for (final channel in const [
      AndroidNotificationChannel(
        taskChannelId,
        'Task reminders',
        description: 'Task start and custom task reminders.',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        deadlineChannelId,
        'Deadlines',
        description: 'A nudge when a task reaches its deadline.',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        customChannelId,
        'Custom reminders',
        description: 'Reminders you schedule yourself, including daily ones.',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        dailyChannelId,
        'Daily task reminders',
        description: 'Task reminders that repeat at the same time every day.',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        reviewChannelId,
        'Daily closing note',
        description: 'One quiet nudge to close the day.',
        importance: Importance.defaultImportance,
      ),
      AndroidNotificationChannel(
        testChannelId,
        'Test notifications',
        description: 'Confirmation notes used to verify reminders work.',
        importance: Importance.high,
      ),
    ]) {
      await android.createNotificationChannel(channel);
    }
  }

  Future<bool> requestPermission() async {
    await initialize();
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (android == null) return false;
        var enabled = await android.areNotificationsEnabled() ?? false;
        if (!enabled) {
          await android.requestNotificationsPermission();
          enabled = await android.areNotificationsEnabled() ?? false;
        }
        _exactAllowed = await android.canScheduleExactNotifications() ?? false;
        return enabled;
      }
      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        if (ios == null) return false;
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? (await ios.checkPermissions())?.isEnabled ?? false;
      }
      if (Platform.isMacOS) {
        final macos = _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        if (macos == null) return false;
        final granted = await macos.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? (await macos.checkPermissions())?.isEnabled ?? false;
      }
      // Linux and Windows use the desktop notification service and do not
      // have a runtime permission prompt.
      return true;
    } catch (error) {
      _initError = _humanize(error);
      return false;
    }
  }

  /// Android 12+ only guarantees exact delivery when the user allows exact
  /// alarms. Daymark asks for it explicitly from the notification screen and
  /// silently falls back to an inexact alarm when it is unavailable.
  Future<bool> requestExactAlarms() async {
    if (!Platform.isAndroid) return true;
    await initialize();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return false;
      final granted = await android.requestExactAlarmsPermission() ?? false;
      _exactAllowed =
          granted || (await android.canScheduleExactNotifications() ?? false);
      return _exactAllowed;
    } catch (error) {
      _initError = _humanize(error);
      return false;
    }
  }

  Future<bool> openSystemSettings() async {
    try {
      await initialize();
      return await _plugin.openAppNotificationSettings() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Plans the OS schedule from local state. Pure and deterministic so the
  /// reminder behaviour is covered by unit tests on every host platform.
  static List<PlannedNotification> plan(
    List<TaskView> tasks,
    ReminderPreferences preferences, {
    DateTime? at,
    int limit = 60,
  }) {
    if (!preferences.enabled) return const [];
    final now = at ?? DateTime.now();
    final horizon = now.add(const Duration(days: 365));
    final recurring = <PlannedNotification>[];
    final oneOff = <PlannedNotification>[];

    if (preferences.taskReminders) {
      for (final view in tasks) {
        final task = view.task;
        if (task.isDone || task.archived) continue;
        final category = view.category?.name;

        final start = task.scheduledStart;
        if (preferences.startReminders && start != null) {
          final when = start.subtract(
            Duration(minutes: preferences.leadMinutes),
          );
          if (when.isAfter(now) && when.isBefore(horizon)) {
            oneOff.add(
              PlannedNotification(
                id: notificationId('${task.id}:start'),
                kind: NotificationKind.taskStart,
                when: when,
                repeatDaily: false,
                taskId: task.id,
                title: preferences.leadMinutes == 0
                    ? 'Starting now · ${task.title}'
                    : 'Starts in ${preferences.leadMinutes} min',
                body: [
                  task.title,
                  ?category,
                  'Scheduled ${timeLabel(start)}',
                ].join(' · '),
              ),
            );
          }
        }

        final due = task.dueAt;
        if (preferences.deadlineReminders &&
            due != null &&
            due.isAfter(now) &&
            due.isBefore(horizon)) {
          oneOff.add(
            PlannedNotification(
              id: notificationId('${task.id}:due'),
              kind: NotificationKind.taskDeadline,
              when: due,
              repeatDaily: false,
              taskId: task.id,
              title: 'Due ${timeLabel(due)} · ${task.title}',
              body: category == null
                  ? 'This is the deadline you set.'
                  : '$category · deadline',
            ),
          );
        }

        final reminderAt = task.reminderAt;
        if (reminderAt != null) {
          final note = task.reminderNote?.trim() ?? '';
          if (task.reminderDaily && preferences.dailyTaskReminders) {
            final next = _nextDaily(reminderAt, now);
            if (next.isBefore(horizon)) {
              recurring.add(
                PlannedNotification(
                  id: notificationId('${task.id}:daily'),
                  kind: NotificationKind.taskDaily,
                  when: next,
                  repeatDaily: true,
                  taskId: task.id,
                  title: 'Daily reminder · ${task.title}',
                  body: note.isEmpty
                      ? (category == null
                            ? 'Your daily reminder for this task.'
                            : '$category · daily reminder')
                      : note,
                ),
              );
            }
          } else if (!task.reminderDaily &&
              preferences.customReminders &&
              reminderAt.isAfter(now) &&
              reminderAt.isBefore(horizon)) {
            oneOff.add(
              PlannedNotification(
                id: notificationId('${task.id}:custom'),
                kind: NotificationKind.taskCustom,
                when: reminderAt,
                repeatDaily: false,
                taskId: task.id,
                title: 'Reminder · ${task.title}',
                body: note.isEmpty
                    ? (category == null
                          ? 'You asked to be reminded about this task.'
                          : '$category · custom reminder')
                    : note,
              ),
            );
          }
        }
      }
    }

    if (preferences.dailyReview) {
      final first = _nextReview(preferences, now);
      if (Platform.isWindows) {
        // Windows cannot repeat a scheduled notification, so queue a month of
        // closing notes. The next app launch refreshes the window.
        for (var offset = 0; offset < 30; offset++) {
          oneOff.add(
            PlannedNotification(
              id: _reviewId + offset,
              kind: NotificationKind.dailyReview,
              when: DateTime(
                first.year,
                first.month,
                first.day + offset,
                preferences.reviewHour,
                preferences.reviewMinute,
              ),
              repeatDaily: false,
              title: 'Close the day',
              body:
                  'A few minutes to mark what moved, what stalled, and what '
                  'tomorrow needs.',
            ),
          );
        }
      } else {
        recurring.add(
          PlannedNotification(
            id: _reviewId,
            kind: NotificationKind.dailyReview,
            when: first,
            repeatDaily: true,
            title: 'Close the day',
            body:
                'A few minutes to mark what moved, what stalled, and what '
                'tomorrow needs.',
          ),
        );
      }
    }

    // Recurring reminders are the cheapest and most valuable, so they always
    // fit inside the iOS 64-notification budget. Remaining slots go to the
    // nearest one-off reminders.
    oneOff.sort((a, b) => a.when.compareTo(b.when));
    final result = <PlannedNotification>[
      ...recurring.take(limit),
      ...oneOff.take(math.max(0, limit - recurring.length)),
    ];
    return result;
  }

  /// Cancels managed Daymark reminders and schedules the current set. Custom
  /// and test notifications scheduled from the notification screen are left
  /// alone.
  Future<NotificationSyncReport> sync(
    List<TaskView> tasks,
    ReminderPreferences preferences,
  ) async {
    // Serialise syncs. Enabling, resuming, and task changes can request a
    // rebuild at the same moment; overlapping rebuilds would cancel each
    // other's notifications.
    final previous = _syncTail;
    final gate = Completer<void>();
    _syncTail = gate.future;
    try {
      await previous;
      return await _syncNow(tasks, preferences);
    } finally {
      gate.complete();
    }
  }

  Future<void> _syncTail = Future<void>.value();

  Future<NotificationSyncReport> _syncNow(
    List<TaskView> tasks,
    ReminderPreferences preferences,
  ) async {
    final now = DateTime.now();
    if (!preferences.enabled) {
      await cancelManaged();
      return _report(now, scheduled: 0, errors: const [], permissionDenied: false);
    }
    await initialize();
    if (!_initialized) {
      return _report(
        now,
        scheduled: 0,
        errors: [_initError ?? 'Notification support is unavailable.'],
        permissionDenied: true,
      );
    }

    await cancelManaged();
    if (!await _hasPermission()) {
      final report = _report(
        now,
        scheduled: 0,
        errors: const [],
        permissionDenied: true,
      );
      _lastReport = report;
      return report;
    }
    _linuxFallbackCount = 0;
    final planned = plan(tasks, preferences, at: now, limit: _platformLimit);
    final ordered = [...planned]
      ..sort((a, b) => b.when.compareTo(a.when));

    var scheduled = 0;
    final errors = <String>[];
    for (final reminder in ordered) {
      if (await _schedulePlanned(reminder)) {
        scheduled++;
      } else if (_lastScheduleError != null) {
        errors.add(_lastScheduleError!);
      }
    }
    final report = _report(
      now,
      scheduled: scheduled,
      errors: errors.toSet().toList(),
      permissionDenied: false,
    );
    _lastReport = report;
    return report;
  }

  String? _lastScheduleError;

  Future<bool> _hasPermission() async {
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.areNotificationsEnabled() ?? false;
      }
      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final options = await ios?.checkPermissions();
        return options == null
            ? false
            : options.isEnabled ||
                  options.isProvisionalEnabled ||
                  options.isAlertEnabled;
      }
      if (Platform.isMacOS) {
        final macos = _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        final options = await macos?.checkPermissions();
        return options == null
            ? false
            : options.isEnabled ||
                  options.isProvisionalEnabled ||
                  options.isAlertEnabled;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  int get _platformLimit {
    if (Platform.isIOS || Platform.isMacOS) return 60;
    if (Platform.isAndroid) return 120;
    return 240;
  }

  Future<bool> _schedulePlanned(PlannedNotification reminder) async {
    _lastScheduleError = null;
    try {
      await _plugin.zonedSchedule(
        id: reminder.id,
        title: reminder.title,
        body: reminder.body,
        scheduledDate: tz.TZDateTime.from(reminder.when, tz.local),
        notificationDetails: _detailsFor(reminder.kind, reminder.body),
        androidScheduleMode: _scheduleMode,
        matchDateTimeComponents: reminder.repeatDaily
            ? DateTimeComponents.time
            : null,
        payload: _encodePayload(reminder),
      );
      return true;
    } on PlatformException catch (error) {
      // Android 12+ may reject an exact alarm even though the app declared the
      // permission. Retry as an inexact alarm rather than losing the reminder.
      if (error.code == 'exact_alarms_not_permitted' && _exactAllowed) {
        _exactAllowed = false;
        try {
          await _plugin.zonedSchedule(
            id: reminder.id,
            title: reminder.title,
            body: reminder.body,
            scheduledDate: tz.TZDateTime.from(reminder.when, tz.local),
            notificationDetails: _detailsFor(reminder.kind, reminder.body),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: reminder.repeatDaily
                ? DateTimeComponents.time
                : null,
            payload: _encodePayload(reminder),
          );
          return true;
        } on PlatformException catch (retryError) {
          _lastScheduleError = _humanize(retryError);
          return false;
        }
      }
      if (Platform.isLinux) {
        // Linux has no scheduler in the plugin. Count it for the settings
        // summary and let the in-app pulse display it while Daymark is open.
        _linuxFallbackCount++;
        return true;
      }
      _lastScheduleError = _humanize(error);
      return false;
    } catch (error) {
      if (Platform.isLinux) {
        _linuxFallbackCount++;
        return true;
      }
      _lastScheduleError = _humanize(error);
      return false;
    }
  }

  AndroidScheduleMode get _scheduleMode {
    if (Platform.isAndroid && _exactAllowed) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  NotificationDetails _detailsFor(NotificationKind kind, String body) {
    final channel = switch (kind) {
      NotificationKind.taskStart => taskChannelId,
      NotificationKind.taskDeadline => deadlineChannelId,
      NotificationKind.taskCustom => customChannelId,
      NotificationKind.taskDaily => dailyChannelId,
      NotificationKind.custom => customChannelId,
      NotificationKind.dailyReview => reviewChannelId,
      NotificationKind.test => testChannelId,
    };
    final name = switch (kind) {
      NotificationKind.taskStart => 'Task reminders',
      NotificationKind.taskDeadline => 'Deadlines',
      NotificationKind.taskCustom => 'Custom reminders',
      NotificationKind.taskDaily => 'Daily task reminders',
      NotificationKind.custom => 'Custom reminders',
      NotificationKind.dailyReview => 'Daily closing note',
      NotificationKind.test => 'Test notifications',
    };
    final high =
        kind != NotificationKind.dailyReview; // the closing note stays quiet

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel,
        name,
        channelDescription: 'Daymark reminders. Scheduled on this device.',
        importance: high ? Importance.high : Importance.defaultImportance,
        priority: high ? Priority.high : Priority.defaultPriority,
        icon: 'ic_notification',
        category: AndroidNotificationCategory.reminder,
        autoCancel: true,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: channel,
        interruptionLevel: high
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: channel,
      ),
      linux: const LinuxNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    );
  }

  String _encodePayload(PlannedNotification reminder) {
    return jsonEncode({
      'source': _payloadSource,
      'kind': reminder.kind.name,
      'taskId': reminder.taskId,
      'when': reminder.when.toIso8601String(),
      'time': _clock(reminder.when),
      'repeat': reminder.repeatDaily ? 'daily' : 'once',
    });
  }

  Map<String, Object?>? _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map && decoded['source'] == _payloadSource) {
        return {for (final entry in decoded.entries) '${entry.key}': entry.value};
      }
    } catch (_) {
      // A notification from another plugin or an older version.
    }
    return null;
  }

  /// Cancels only the reminders Daymark rebuilds on every sync. User-scheduled
  /// custom and test notifications survive.
  Future<void> cancelManaged() async {
    _linuxFallbackCount = 0;
    try {
      await initialize();
      if (!_initialized) return;
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        final meta = _decodePayload(request.payload);
        final kind = _kindFromName(meta?['kind']?.toString());
        if (kind != null && _kindsCancelledOnSync.contains(kind)) {
          await _plugin.cancel(id: request.id);
        }
      }
    } catch (_) {
      // Notification support can be unavailable in tests or a headless build.
    }
  }

  Future<void> cancelAll() async {
    _linuxFallbackCount = 0;
    _firedFallbackReminders.clear();
    try {
      await initialize();
      if (!_initialized) return;
      await _plugin.cancelAll();
    } catch (_) {
      // Notification support can be unavailable in tests or a headless build.
    }
  }

  Future<void> cancel(int id) async {
    try {
      await initialize();
      if (!_initialized) return;
      await _plugin.cancel(id: id);
    } catch (_) {
      // Nothing to cancel.
    }
  }

  Future<int> pendingCount() async {
    if (Platform.isLinux) return _linuxFallbackCount;
    try {
      await initialize();
      if (!_initialized) return 0;
      return (await _plugin.pendingNotificationRequests()).length;
    } catch (_) {
      return 0;
    }
  }

  /// The upcoming reminders as the OS knows them, sorted by time. Daily
  /// reminders are re-projected to their next occurrence so the list never
  /// shows a stale date.
  Future<List<ScheduledReminder>> upcoming({int limit = 40}) async {
    try {
      await initialize();
      if (!_initialized) return const [];
      final pending = await _plugin.pendingNotificationRequests();
      final now = DateTime.now();
      final result = <ScheduledReminder>[];
      for (final request in pending) {
        final meta = _decodePayload(request.payload);
        final kind = _kindFromName(meta?['kind']?.toString()) ??
            NotificationKind.custom;
        final repeat = meta?['repeat'] == 'daily';
        var when = DateTime.tryParse(meta?['when']?.toString() ?? '');
        if (repeat && when != null) {
          when = _nextDaily(when, now);
        }
        result.add(
          ScheduledReminder(
            id: request.id,
            title: request.title ?? 'Daymark reminder',
            body: request.body ?? '',
            kind: kind,
            repeatDaily: repeat,
            when: when,
            taskId: meta?['taskId']?.toString(),
          ),
        );
      }
      result.sort((a, b) {
        final aTime = a.when;
        final bTime = b.when;
        if (aTime == null && bTime == null) return a.id.compareTo(b.id);
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return aTime.compareTo(bTime);
      });
      return result.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<NotificationStatus> status() async {
    await initialize();
    var pending = 0;
    var granted = false;
    var exactSupported = false;
    var exactAllowed = false;
    try {
      if (_initialized) {
        pending = (await _plugin.pendingNotificationRequests()).length;
      }
      if (Platform.isAndroid) {
        exactSupported = true;
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        granted = await android?.areNotificationsEnabled() ?? false;
        exactAllowed =
            await android?.canScheduleExactNotifications() ?? false;
        _exactAllowed = exactAllowed;
      } else if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        granted = (await ios?.checkPermissions())?.isEnabled ?? false;
      } else if (Platform.isMacOS) {
        final macos = _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        granted = (await macos?.checkPermissions())?.isEnabled ?? false;
      } else {
        granted = true;
      }
    } catch (error) {
      _initError = _humanize(error);
    }

    return NotificationStatus(
      supported: !Platform.isLinux,
      permissionGranted: granted,
      exactSupported: exactSupported,
      exactAllowed: exactAllowed,
      pending: pending,
      initError: _initError,
      lastReport: _lastReport,
      platformNote: switch (Platform.operatingSystem) {
        'android' =>
          'Scheduled by Android. Exact timing needs the exact-alarm permission; '
              'without it Android may delay a reminder by a few minutes.',
        'ios' =>
          'Scheduled by iOS. Keep permission on, and allow notifications in '
              'Focus modes if you want them while a Focus is active.',
        'macos' => 'Scheduled by macOS. Focus modes can hold notifications.',
        'windows' => 'Scheduled by Windows. Keep Daymark installed and signed in.',
        _ =>
          'Linux has no background scheduler in the notification plugin. '
              'Daymark rings reminders while the app is open.',
      },
    );
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
        if (preferences.startReminders && start != null) {
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
                'Scheduled ${timeLabel(start)}',
              ].join(' · '),
            ));
          }
        }
        final deadline = task.dueAt;
        if (preferences.deadlineReminders &&
            deadline != null &&
            _isFresh(deadline, now)) {
          due.add((
            key: '${task.id}:due:${deadline.millisecondsSinceEpoch}',
            when: deadline,
            title: 'Due ${timeLabel(deadline)} · ${task.title}',
            body: category == null
                ? 'This is the deadline you set.'
                : '$category · deadline',
          ));
        }
        final custom = task.reminderAt;
        if (custom != null) {
          final note = task.reminderNote?.trim() ?? '';
          final effective = task.reminderDaily
              ? _todayDaily(custom, now)
              : custom;
          final allowed = task.reminderDaily
              ? preferences.dailyTaskReminders
              : preferences.customReminders;
          if (allowed && _isFresh(effective, now)) {
            due.add((
              key:
                  '${task.id}:custom:${effective.millisecondsSinceEpoch}:'
                  '${task.reminderDaily}',
              when: effective,
              title: task.reminderDaily
                  ? 'Daily reminder · ${task.title}'
                  : 'Reminder · ${task.title}',
              body: note.isEmpty
                  ? (category == null
                        ? 'You asked to be reminded about this task.'
                        : '$category · custom reminder')
                  : note,
            ));
          }
        }
      }
    }

    if (preferences.dailyReview) {
      final review = _previousReview(preferences, now);
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
        id: notificationId(reminder.key),
        title: reminder.title,
        body: reminder.body,
        kind: NotificationKind.taskCustom,
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

  Future<void> showTest({String? title, String? body}) async {
    await _showNow(
      id: _testId,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : 'Daymark is listening',
      body: body?.trim().isNotEmpty == true
          ? body!.trim()
          : 'Offline reminders are working. This appears even without an '
                'internet connection.',
      kind: NotificationKind.test,
    );
  }

  /// Schedules a test notification a few seconds from now. This exercises the
  /// real OS scheduler instead of only the immediate `show` path.
  Future<DateTime?> scheduleTest({
    Duration delay = const Duration(seconds: 10),
    String? title,
    String? body,
  }) async {
    final when = DateTime.now().add(delay);
    final ok = await _scheduleCustom(
      id: notificationId('test:${when.microsecondsSinceEpoch}'),
      kind: NotificationKind.test,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : 'Scheduled test',
      body: body?.trim().isNotEmpty == true
          ? body!.trim()
          : 'If this arrived at the expected time, scheduling works on this device.',
      when: when,
      repeatDaily: false,
    );
    return ok ? when : null;
  }

  /// A user-authored reminder that is not tied to a task. It survives ledger
  /// changes because sync only cancels the reminders it owns.
  Future<DateTime?> scheduleCustom({
    required String title,
    required String body,
    required DateTime when,
    bool repeatDaily = false,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return null;
    final at = repeatDaily ? _nextDaily(when, DateTime.now()) : when;
    if (!at.isAfter(DateTime.now())) return null;
    final ok = await _scheduleCustom(
      id: notificationId(
        'custom:$cleanTitle:${at.toIso8601String()}:'
        '${DateTime.now().microsecondsSinceEpoch}',
      ),
      kind: NotificationKind.custom,
      title: cleanTitle,
      body: body.trim().isEmpty ? 'A reminder from your Daymark ledger.' : body.trim(),
      when: at,
      repeatDaily: repeatDaily,
    );
    return ok ? at : null;
  }

  Future<bool> _scheduleCustom({
    required int id,
    required NotificationKind kind,
    required String title,
    required String body,
    required DateTime when,
    required bool repeatDaily,
  }) async {
    await initialize();
    if (!_initialized) return false;
    final planned = PlannedNotification(
      id: id,
      kind: kind,
      title: title,
      body: body,
      when: when,
      repeatDaily: repeatDaily,
    );
    return _schedulePlanned(planned);
  }

  Future<void> _showNow({
    required int id,
    required String title,
    required String body,
    required NotificationKind kind,
  }) async {
    try {
      await initialize();
      if (!_initialized) return;
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _detailsFor(kind, body),
        payload: jsonEncode({
          'source': _payloadSource,
          'kind': kind.name,
          'when': DateTime.now().toIso8601String(),
          'repeat': 'once',
        }),
      );
    } catch (error) {
      _initError = _humanize(error);
    }
  }

  NotificationSyncReport _report(
    DateTime at, {
    required int scheduled,
    required List<String> errors,
    required bool permissionDenied,
  }) {
    return NotificationSyncReport(
      at: at,
      scheduled: scheduled,
      failed: errors.length,
      errors: errors,
      exactUsed: _exactAllowed,
      permissionDenied: permissionDenied,
    );
  }

  static NotificationKind? _kindFromName(String? name) {
    if (name == null) return null;
    for (final kind in NotificationKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  static DateTime _nextDaily(DateTime timeOfDay, DateTime now) {
    var next = DateTime(
      now.year,
      now.month,
      now.day,
      timeOfDay.hour,
      timeOfDay.minute,
    );
    if (!next.isAfter(now)) {
      // Build tomorrow from calendar parts rather than adding 24 hours so the
      // reminder keeps its wall-clock time across daylight-saving changes.
      next = DateTime(
        now.year,
        now.month,
        now.day + 1,
        timeOfDay.hour,
        timeOfDay.minute,
      );
    }
    return next;
  }

  static DateTime _todayDaily(DateTime timeOfDay, DateTime now) {
    return DateTime(
      now.year,
      now.month,
      now.day,
      timeOfDay.hour,
      timeOfDay.minute,
    );
  }

  static DateTime _nextReview(ReminderPreferences prefs, DateTime now) {
    final today = DateTime(
      now.year,
      now.month,
      now.day,
      prefs.reviewHour,
      prefs.reviewMinute,
    );
    if (today.isAfter(now)) return today;
    return DateTime(
      now.year,
      now.month,
      now.day + 1,
      prefs.reviewHour,
      prefs.reviewMinute,
    );
  }

  static DateTime _previousReview(ReminderPreferences prefs, DateTime now) {
    final today = DateTime(
      now.year,
      now.month,
      now.day,
      prefs.reviewHour,
      prefs.reviewMinute,
    );
    if (today.isAfter(now)) {
      return DateTime(
        now.year,
        now.month,
        now.day - 1,
        prefs.reviewHour,
        prefs.reviewMinute,
      );
    }
    return today;
  }

  static int notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static String _clock(DateTime value) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  static String _humanize(Object error) {
    final text = error.toString();
    if (text.contains('exact_alarms_not_permitted')) {
      return 'Android blocked exact alarms. Daymark will use an inexact '
          'reminder instead; allow exact alarms for precise timing.';
    }
    if (text.contains('notifications_not_enabled')) {
      return 'Notifications are switched off for Daymark in system settings.';
    }
    if (text.contains('MissingPluginException')) {
      return 'Notifications are not available on this build of Daymark.';
    }
    return text.replaceFirst('PlatformException(', '').split(',').first.trim();
  }

  // Kept for the existing settings/test surface.
  static String dayLabel(DateTime value) => longDateLabel(value);

  static int get maxTaskReminders => math.min(60, 120);
}
