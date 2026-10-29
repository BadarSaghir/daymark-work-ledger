import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/form.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../data/services/notification_service.dart';
import '../../state/notification_controller.dart';

/// The notification centre. Everything about reminders lives here: what is
/// enabled, what the OS currently has queued, a custom scheduler, and device
/// tests. The page is tabbed so it never becomes one long web-style scroll.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final _customTitle = TextEditingController();
  final _customBody = TextEditingController();
  final _testTitle = TextEditingController();
  final _testBody = TextEditingController();

  NotificationStatus? _status;
  List<ScheduledReminder> _upcoming = const [];
  DateTime? _customDate;
  TimeOfDay? _customTime;
  bool _customDaily = false;
  bool _busy = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _customTitle.dispose();
    _customBody.dispose();
    _testTitle.dispose();
    _testBody.dispose();
    super.dispose();
  }

  Future<T?> _guard<T>(Future<T> Function() action, {String? success}) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      final result = await action();
      await _refresh();
      if (success != null && mounted) showToast(context, success);
      return result;
    } catch (error) {
      if (mounted) {
        showToast(context, '$error', duration: const Duration(seconds: 5));
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final controller = ref.read(reminderControllerProvider.notifier);
      final results = await Future.wait([
        controller.status(),
        controller.upcoming(),
      ]);
      if (!mounted) return;
      setState(() {
        _status = results[0] as NotificationStatus;
        _upcoming = results[1] as List<ScheduledReminder>;
      });
    } catch (error) {
      if (mounted) showToast(context, 'Could not read notifications: $error');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      final granted = await ref
          .read(reminderControllerProvider.notifier)
          .enable();
      await _refresh();
      if (!mounted) return;
      if (!granted) {
        showToast(
          context,
          _status?.initError ??
              'Notifications are blocked. Allow them for Daymark in system '
                  'settings, then try again.',
          duration: const Duration(seconds: 6),
        );
      } else {
        showToast(context, 'Notifications are on');
      }
    } catch (error) {
      if (mounted) showToast(context, 'Could not enable notifications: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(ReminderPreferences next, {String? message}) async {
    await _guard(
      () => ref.read(reminderControllerProvider.notifier).savePreferences(next),
      success: message,
    );
  }

  Future<void> _pickReviewTime(ReminderPreferences prefs) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: prefs.reviewHour,
        minute: prefs.reviewMinute,
      ),
      helpText: 'Daily closing note',
    );
    if (picked == null) return;
    await _save(
      prefs.copyWith(reviewHour: picked.hour, reviewMinute: picked.minute),
    );
  }

  Future<void> _pickCustomWhen() async {
    final now = DateTime.now();
    final initial = _customDate ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Notification date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _customTime ?? TimeOfDay.fromDateTime(now),
      helpText: 'Notification time',
    );
    if (time == null) return;
    setState(() {
      _customDate = date;
      _customTime = time;
    });
  }

  DateTime? get _customWhen {
    final date = _customDate;
    final time = _customTime;
    if (date == null || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _scheduleCustom() async {
    final when = _customWhen;
    if (_customTitle.text.trim().isEmpty) {
      showToast(context, 'Give the notification a title first.');
      return;
    }
    if (when == null) {
      showToast(context, 'Choose a date and time for the notification.');
      return;
    }
    final at = await _guard(
      () => ref
          .read(reminderControllerProvider.notifier)
          .scheduleCustom(
            title: _customTitle.text,
            body: _customBody.text,
            when: when,
            repeatDaily: _customDaily,
          ),
    );
    if (at == null || !mounted) return;
    showToast(
      context,
      _customDaily
          ? 'Scheduled every day at ${timeLabel(at)}'
          : 'Scheduled for ${dateLabel(at)} · ${timeLabel(at)}',
      duration: const Duration(seconds: 4),
    );
    _customTitle.clear();
    _customBody.clear();
    setState(() {
      _customDate = null;
      _customTime = null;
      _customDaily = false;
    });
  }

  Future<void> _scheduleTest(Duration delay) async {
    final at = await _guard(
      () => ref
          .read(reminderControllerProvider.notifier)
          .scheduleTest(
            delay: delay,
            title: _testTitle.text,
            body: _testBody.text,
          ),
    );
    if (at == null || !mounted) return;
    showToast(
      context,
      'Test scheduled for ${timeLabel(at)}. Lock the screen to check it.',
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _sendTestNow() async {
    await _guard(
      () => ref
          .read(reminderControllerProvider.notifier)
          .sendTest(title: _testTitle.text, body: _testBody.text),
      success: 'Test notification sent',
    );
  }

  Future<void> _remove(ScheduledReminder reminder) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove this reminder?',
      message: '“${reminder.title}” will be removed from the device schedule.',
      confirmLabel: 'Remove',
      danger: true,
      icon: Icons.notifications_off_outlined,
    );
    if (!confirmed) return;
    await _guard(
      () => ref.read(reminderControllerProvider.notifier).cancel(reminder.id),
      success: 'Reminder removed',
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear every scheduled notification?',
      message:
          'Task reminders, the daily closing note, custom reminders, and tests '
          'will all be removed. Turning on reminders again rebuilds them.',
      confirmLabel: 'Clear all',
      danger: true,
      icon: Icons.delete_sweep_outlined,
    );
    if (!confirmed) return;
    await _guard(
      () => ref.read(reminderControllerProvider.notifier).cancelAll(),
      success: 'Scheduled notifications cleared',
    );
  }

  Future<void> _openSystemSettings() async {
    final opened = await ref
        .read(reminderControllerProvider.notifier)
        .openSystemSettings();
    if (!opened && mounted) {
      showToast(context, 'Open your device settings and find Daymark.');
    }
  }

  Future<void> _requestExact() async {
    final granted = await _guard(
      () => ref.read(reminderControllerProvider.notifier).requestExactAlarms(),
    );
    if (granted != null && mounted) {
      showToast(
        context,
        granted
            ? 'Exact timing is allowed'
            : 'Exact timing is still off. Android will deliver reminders '
                  'within a few minutes instead.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final prefsAsync = ref.watch(reminderControllerProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: colors.canvas,
        appBar: AppBar(
          backgroundColor: colors.canvas,
          surfaceTintColor: Colors.transparent,
          title: const Text('Notifications'),
          bottom: TabBar(
            isScrollable: Layout.isCompact(context),
            labelColor: colors.primary,
            unselectedLabelColor: colors.inkFaint,
            indicatorColor: colors.primary,
            tabs: const [
              Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'Settings'),
              Tab(
                icon: Icon(Icons.schedule_rounded, size: 18),
                text: 'Upcoming',
              ),
              Tab(
                icon: Icon(Icons.edit_notifications_rounded, size: 18),
                text: 'Custom',
              ),
              Tab(icon: Icon(Icons.science_outlined, size: 18), text: 'Test'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: prefsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: InlineError(message: 'Could not read reminders: $error'),
            ),
          ),
          data: (prefs) => TabBarView(
            children: [
              _settingsTab(prefs),
              _upcomingTab(),
              _customTab(),
              _testTab(prefs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsTab(ReminderPreferences prefs) {
    final colors = context.colors;
    final status = _status;
    return _tabScroll(
      children: [
        _StatusCard(
          prefs: prefs,
          status: status,
          busy: _busy,
          onEnable: _enable,
          onOpenSettings: _openSystemSettings,
          onRequestExact: _requestExact,
        ),
        const SizedBox(height: AppSpace.lg),
        if (!prefs.enabled)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'What Daymark will send',
                  style: AppText.titleM.copyWith(color: colors.ink),
                ),
                const SizedBox(height: AppSpace.sm),
                for (final (icon, title, body) in const [
                  (
                    Icons.timer_outlined,
                    'Task starts',
                    'A lead-time nudge before the work begins.',
                  ),
                  (
                    Icons.flag_outlined,
                    'Deadlines',
                    'A note at the exact deadline you chose.',
                  ),
                  (
                    Icons.edit_notifications_outlined,
                    'Custom task reminders',
                    'One-off or every-day reminders attached to a task.',
                  ),
                  (
                    Icons.nightlight_outlined,
                    'Daily closing note',
                    'One quiet cue to close the day.',
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 17, color: colors.inkMuted),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: AppText.bodySmall.copyWith(
                                  color: colors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                body,
                                style: AppText.bodySmall.copyWith(
                                  color: colors.inkFaint,
                                  fontSize: 10.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpace.sm),
              ],
            ),
          )
        else ...[
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionTitle(
                  icon: Icons.task_alt_rounded,
                  title: 'Task reminders',
                  subtitle:
                      'Each type has its own switch so you can keep the useful '
                      'ones and mute the rest.',
                ),
                const SizedBox(height: AppSpace.md),
                ToggleRow(
                  label: 'All task reminders',
                  subtitle: 'Master switch for the options below.',
                  icon: Icons.notifications_none_rounded,
                  value: prefs.taskReminders,
                  onChanged: _busy
                      ? null
                      : (value) => _save(
                          prefs.copyWith(taskReminders: value),
                          message: value
                              ? 'Task reminders on'
                              : 'Task reminders off',
                        ),
                ),
                const Divider(),
                ToggleRow(
                  label: 'Start times',
                  subtitle: 'Uses the lead time below.',
                  icon: Icons.timer_outlined,
                  value: prefs.startReminders,
                  onChanged: _busy || !prefs.taskReminders
                      ? null
                      : (value) => _save(prefs.copyWith(startReminders: value)),
                ),
                ToggleRow(
                  label: 'Deadlines',
                  subtitle: 'Fires at the deadline, not before it.',
                  icon: Icons.flag_outlined,
                  value: prefs.deadlineReminders,
                  onChanged: _busy || !prefs.taskReminders
                      ? null
                      : (value) =>
                            _save(prefs.copyWith(deadlineReminders: value)),
                ),
                ToggleRow(
                  label: 'Custom task reminders',
                  subtitle: 'One-off reminders set in the task editor.',
                  icon: Icons.edit_notifications_outlined,
                  value: prefs.customReminders,
                  onChanged: _busy || !prefs.taskReminders
                      ? null
                      : (value) =>
                            _save(prefs.copyWith(customReminders: value)),
                ),
                ToggleRow(
                  label: 'Daily task reminders',
                  subtitle: 'Reminders marked “every day” in the task editor.',
                  icon: Icons.repeat_rounded,
                  value: prefs.dailyTaskReminders,
                  onChanged: _busy || !prefs.taskReminders
                      ? null
                      : (value) =>
                            _save(prefs.copyWith(dailyTaskReminders: value)),
                ),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    Text(
                      'Lead time',
                      style: AppText.bodySmall.copyWith(color: colors.inkMuted),
                    ),
                    const Spacer(),
                    DropdownButton<int>(
                      value: prefs.leadMinutes,
                      underline: const SizedBox.shrink(),
                      style: AppText.monoData.copyWith(
                        color: colors.ink,
                        fontSize: 12,
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('At start')),
                        DropdownMenuItem(value: 5, child: Text('5 min before')),
                        DropdownMenuItem(
                          value: 10,
                          child: Text('10 min before'),
                        ),
                        DropdownMenuItem(
                          value: 15,
                          child: Text('15 min before'),
                        ),
                        DropdownMenuItem(
                          value: 30,
                          child: Text('30 min before'),
                        ),
                        DropdownMenuItem(
                          value: 60,
                          child: Text('1 hour before'),
                        ),
                      ],
                      onChanged: _busy || !prefs.taskReminders
                          ? null
                          : (next) {
                              if (next != null) {
                                _save(prefs.copyWith(leadMinutes: next));
                              }
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionTitle(
                  icon: Icons.nightlight_outlined,
                  title: 'Daily closing note',
                  subtitle:
                      'One quiet nudge to review the day and set tomorrow.',
                ),
                const SizedBox(height: AppSpace.sm),
                ToggleRow(
                  label: 'Send the closing note',
                  subtitle: 'Repeats every day at the time below.',
                  icon: Icons.repeat_rounded,
                  value: prefs.dailyReview,
                  onChanged: _busy
                      ? null
                      : (value) => _save(prefs.copyWith(dailyReview: value)),
                ),
                if (prefs.dailyReview)
                  Row(
                    children: [
                      Text(
                        'Remind me at',
                        style: AppText.bodySmall.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _pickReviewTime(prefs),
                        icon: const Icon(Icons.schedule_rounded, size: 15),
                        label: Text(prefs.reviewLabel),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionTitle(
                  icon: Icons.health_and_safety_outlined,
                  title: 'Device health',
                  subtitle:
                      status?.platformNote ??
                      'Checking how this device handles reminders.',
                ),
                const SizedBox(height: AppSpace.md),
                _HealthRow(
                  icon: Icons.notifications_active_outlined,
                  label: 'Permission',
                  value: status?.permissionGranted == true
                      ? 'Allowed'
                      : 'Blocked',
                  ok: status?.permissionGranted == true,
                ),
                _HealthRow(
                  icon: Icons.schedule_rounded,
                  label: 'Scheduled',
                  value: '${status?.pending ?? _upcoming.length} queued',
                  ok: true,
                ),
                if (status?.exactSupported == true)
                  _HealthRow(
                    icon: Icons.alarm_rounded,
                    label: 'Exact timing',
                    value: status?.exactAllowed == true ? 'On' : 'Inexact',
                    ok: status?.exactAllowed == true,
                  ),
                if (status?.initError != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  InlineError(message: status!.initError!),
                ],
                const SizedBox(height: AppSpace.md),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _openSystemSettings,
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: const Text('System settings'),
                    ),
                    if (status?.exactSupported == true &&
                        status?.exactAllowed != true)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _requestExact,
                        icon: const Icon(Icons.alarm_on_rounded, size: 16),
                        label: const Text('Allow exact timing'),
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _save(
                              prefs.copyWith(enabled: false),
                              message: 'Notifications turned off',
                            ),
                      child: const Text('Turn off'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _upcomingTab() {
    final colors = context.colors;
    return _tabScroll(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What the OS will show',
                    style: AppText.titleL.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _upcoming.isEmpty
                        ? 'Nothing is queued yet.'
                        : '${_upcoming.length} pending notification'
                              '${_upcoming.length == 1 ? '' : 's'} on this device.',
                    style: AppText.bodySmall.copyWith(color: colors.inkFaint),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _busy || _upcoming.isEmpty ? null : _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: const Text('Clear all'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (_upcoming.isEmpty)
          SurfaceCard(
            child: Column(
              children: [
                Icon(
                  Icons.notifications_paused_outlined,
                  size: 34,
                  color: colors.inkFaint,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'No scheduled reminders',
                  style: AppText.titleM.copyWith(color: colors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  'Add a start time, deadline, custom reminder, or daily '
                  'reminder to a task. The schedule refreshes automatically.',
                  textAlign: TextAlign.center,
                  style: AppText.bodySmall.copyWith(color: colors.inkMuted),
                ),
              ],
            ),
          )
        else
          for (final reminder in _upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: _UpcomingRow(
                reminder: reminder,
                busy: _busy,
                onRemove: () => _remove(reminder),
              ),
            ),
      ],
    );
  }

  Widget _customTab() {
    final colors = context.colors;
    final when = _customWhen;
    return _tabScroll(
      children: [
        Text(
          'Schedule anything',
          style: AppText.titleL.copyWith(color: colors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          'A standalone reminder that is not tied to a task. It keeps ringing '
          'even if the task list changes, and it can repeat every day.',
          style: AppText.bodySmall.copyWith(
            color: colors.inkFaint,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FormLabel('Title'),
              TextField(
                controller: _customTitle,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Call the dentist',
                  prefixIcon: Icon(Icons.notifications_none_rounded, size: 18),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              const FormLabel('Message', hint: 'Optional'),
              TextField(
                controller: _customBody,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Bring the insurance card.',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickCustomWhen,
                      icon: const Icon(Icons.event_rounded, size: 17),
                      label: Text(
                        when == null
                            ? 'Choose date & time'
                            : '${dateLabel(when)} · ${timeLabel(when)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              ToggleRow(
                label: 'Repeat every day',
                subtitle: 'Uses the time above and rings daily.',
                icon: Icons.repeat_rounded,
                value: _customDaily,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _customDaily = value),
              ),
              const SizedBox(height: AppSpace.md),
              FilledButton.icon(
                onPressed: _busy ? null : _scheduleCustom,
                icon: const Icon(Icons.add_alert_outlined, size: 18),
                label: const Text('Schedule notification'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Text(
          'Custom notifications are stored by the operating system, so they '
          'arrive even when Daymark is closed. They survive ledger changes and '
          'are only removed from the Upcoming tab.',
          style: AppText.bodySmall.copyWith(
            color: colors.inkFaint,
            fontSize: 10.8,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _testTab(ReminderPreferences prefs) {
    final colors = context.colors;
    return _tabScroll(
      children: [
        Text(
          'Test this device',
          style: AppText.titleL.copyWith(color: colors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          'Send a notification right now, or schedule one through the real OS '
          'scheduler and lock the screen to confirm it arrives.',
          style: AppText.bodySmall.copyWith(
            color: colors.inkFaint,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FormLabel('Test title', hint: 'Optional'),
              TextField(
                controller: _testTitle,
                decoration: const InputDecoration(
                  hintText: 'Daymark is listening',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              const FormLabel('Test message', hint: 'Optional'),
              TextField(
                controller: _testBody,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Offline reminders are working.',
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              FilledButton.icon(
                onPressed: _busy ? null : _sendTestNow,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send test now'),
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _scheduleTest(const Duration(seconds: 10)),
                    icon: const Icon(Icons.timer_rounded, size: 17),
                    label: const Text('In 10 seconds'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _scheduleTest(const Duration(minutes: 1)),
                    icon: const Icon(Icons.timelapse_rounded, size: 17),
                    label: const Text('In 1 minute'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(
                icon: Icons.checklist_rounded,
                title: 'If a test does not arrive',
                subtitle:
                    'Work through these in order. Nothing leaves your device.',
              ),
              const SizedBox(height: AppSpace.md),
              for (final line in const [
                'Allow notifications for Daymark in system settings.',
                'Turn off battery optimisation for Daymark on Android.',
                'On iPhone, allow notifications for Daymark and check Focus modes.',
                'Turn notifications off and on again here to rebuild the schedule.',
                'Use “In 1 minute”, then lock the phone and wait.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: colors.inkFaint,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          line,
                          style: AppText.bodySmall.copyWith(
                            color: colors.inkMuted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (prefs.enabled) ...[
                const Divider(),
                Text(
                  'Current schedule: ${_status?.pending ?? _upcoming.length} '
                  'queued notification'
                  '${(_status?.pending ?? _upcoming.length) == 1 ? '' : 's'}.',
                  style: AppText.bodySmall.copyWith(color: colors.inkFaint),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabScroll({required List<Widget> children}) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.x6,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.prefs,
    required this.status,
    required this.busy,
    required this.onEnable,
    required this.onOpenSettings,
    required this.onRequestExact,
  });

  final ReminderPreferences prefs;
  final NotificationStatus? status;
  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onOpenSettings;
  final VoidCallback onRequestExact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final on = prefs.enabled;
    final pending = status?.pending ?? 0;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: on
              ? [colors.primary, colors.primary.withValues(alpha: 0.82)]
              : [colors.ink, colors.ink.withValues(alpha: 0.86)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                on
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_outlined,
                size: 22,
                color: colors.onPrimary,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  on ? 'Notifications are on' : 'Notifications are off',
                  style: AppText.titleM.copyWith(
                    color: colors.onPrimary,
                    fontSize: 18,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            on
                ? pending == 0
                      ? 'No reminders are queued right now.'
                      : '$pending reminders queued on this device.'
                : 'Turn them on to get start, deadline, custom, and daily '
                      'reminders without a connection.',
            style: AppText.bodySmall.copyWith(
              color: colors.onPrimary.withValues(alpha: 0.78),
              height: 1.5,
            ),
          ),
          if (on && status != null) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  icon: status!.permissionGranted
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  label: status!.permissionGranted
                      ? 'Permission allowed'
                      : 'Permission blocked',
                ),
                if (status!.exactSupported)
                  _StatusChip(
                    icon: Icons.alarm_rounded,
                    label: status!.exactAllowed
                        ? 'Exact timing'
                        : 'Inexact timing',
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              if (!on)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: busy ? null : onEnable,
                  icon: const Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                  ),
                  label: const Text('Turn on notifications'),
                )
              else ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.onPrimary,
                    side: BorderSide(
                      color: colors.onPrimary.withValues(alpha: 0.4),
                    ),
                  ),
                  onPressed: busy ? null : onOpenSettings,
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('System settings'),
                ),
                if (status?.exactSupported == true &&
                    status?.exactAllowed != true)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.onPrimary,
                      side: BorderSide(
                        color: colors.onPrimary.withValues(alpha: 0.4),
                      ),
                    ),
                    onPressed: busy ? null : onRequestExact,
                    icon: const Icon(Icons.alarm_on_rounded, size: 16),
                    label: const Text('Allow exact timing'),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colors.onPrimary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.onPrimary),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.bodySmall.copyWith(
              color: colors.onPrimary,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.badge),
          ),
          child: Icon(icon, size: 17, color: colors.primary),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.titleM.copyWith(color: colors.ink)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppText.bodySmall.copyWith(
                  color: colors.inkFaint,
                  fontSize: 10.8,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.ok,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 15, color: colors.inkFaint),
          const SizedBox(width: 7),
          Text(
            label,
            style: AppText.bodySmall.copyWith(color: colors.inkMuted),
          ),
          const Spacer(),
          Icon(
            ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 14,
            color: ok ? colors.green : colors.gold,
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: AppText.bodySmall.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({
    required this.reminder,
    required this.busy,
    required this.onRemove,
  });

  final ScheduledReminder reminder;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (icon, label) = _kindUi(reminder.kind);
    final when = reminder.when;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.badge),
            ),
            child: Icon(icon, size: 17, color: colors.primary),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  [
                    label,
                    if (when != null)
                      reminder.repeatDaily
                          ? 'Every day · ${timeLabel(when)}'
                          : '${dateLabel(when)} · ${timeLabel(when)}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.monoData.copyWith(
                    color: colors.inkFaint,
                    fontSize: 9.8,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove reminder',
            onPressed: busy ? null : onRemove,
            icon: const Icon(Icons.close_rounded, size: 17),
          ),
        ],
      ),
    );
  }

  static (IconData, String) _kindUi(NotificationKind kind) {
    return switch (kind) {
      NotificationKind.taskStart => (Icons.timer_outlined, 'Task start'),
      NotificationKind.taskDeadline => (Icons.flag_outlined, 'Deadline'),
      NotificationKind.taskCustom => (
        Icons.edit_notifications_outlined,
        'Task',
      ),
      NotificationKind.taskDaily => (Icons.repeat_rounded, 'Daily task'),
      NotificationKind.dailyReview => (
        Icons.nightlight_outlined,
        'Closing note',
      ),
      NotificationKind.custom => (Icons.notifications_none_rounded, 'Custom'),
      NotificationKind.test => (Icons.science_outlined, 'Test'),
    };
  }
}
