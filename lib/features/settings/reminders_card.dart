import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../data/services/notification_service.dart';
import '../../state/notification_controller.dart';

/// A compact reminder status card for Settings. The full control surface lives
/// in the dedicated [NotificationsPage], reachable from here and the app bar.
class RemindersCard extends ConsumerStatefulWidget {
  const RemindersCard({super.key});

  @override
  ConsumerState<RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends ConsumerState<RemindersCard> {
  bool _busy = false;
  int? _pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPending());
  }

  Future<T?> _run<T>(String label, Future<T> Function() action) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      await _refreshPending();
      return result;
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          '$label failed: $error',
          duration: const Duration(seconds: 5),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reschedule() async {
    final report = await _run<NotificationSyncReport>(
      'Rescheduling',
      () => ref.read(reminderControllerProvider.notifier).syncNow(),
    );
    if (report == null || !mounted) return;
    showToast(
      context,
      report.summary,
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _refreshPending() async {
    if (!mounted) return;
    try {
      final count = await ref
          .read(reminderControllerProvider.notifier)
          .pendingCount();
      if (mounted) setState(() => _pending = count);
    } catch (_) {
      if (mounted) setState(() => _pending = 0);
    }
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      final controller = ref.read(reminderControllerProvider.notifier);
      final granted = await controller.enable();
      if (!granted && mounted) {
        showToast(
          context,
          'Notifications are blocked. Allow them for Daymark in your system '
          'settings, then try again.',
          duration: const Duration(seconds: 6),
        );
      } else if (mounted) {
        showToast(context, 'Notifications are on');
      }
      await _refreshPending();
    } catch (error) {
      if (mounted) {
        showToast(context, 'Could not enable notifications: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(ReminderPreferences next, {String? message}) async {
    await _run(
      'Updating reminders',
      () =>
          ref.read(reminderControllerProvider.notifier).savePreferences(next),
    );
    if (message != null && mounted) showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final async = ref.watch(reminderControllerProvider);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Icon(
                  Icons.notifications_none_rounded,
                  size: 18,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications',
                      style: AppText.titleM.copyWith(
                        color: colors.ink,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scheduled on this device. Start, deadline, custom, and '
                      'daily task reminders arrive without a network.',
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 10.8,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (async.value?.enabled == true && _pending != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$_pending queued',
                    style: AppText.monoData.copyWith(
                      color: colors.primary,
                      fontSize: 8.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          async.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (error, stack) => InlineError(
              message: 'Could not read notification settings: $error',
              onRetry: () {
                ref.invalidate(reminderControllerProvider);
                _refreshPending();
              },
            ),
            data: (prefs) => !prefs.enabled
                ? _DisabledPrompt(busy: _busy, onEnable: _enable)
                : _EnabledSummary(
                    prefs: prefs,
                    pending: _pending,
                    busy: _busy,
                    onOpen: () => openNotifications(context),
                    onReschedule: _reschedule,
                    onTest: () => _run<void>(
                      'Test notification',
                      () => ref
                          .read(reminderControllerProvider.notifier)
                          .sendTest(),
                    ),
                    onTaskReminders: (value) => _save(
                      prefs.copyWith(taskReminders: value),
                      message: value
                          ? 'Task reminders on'
                          : 'Task reminders off',
                    ),
                    onDailyReview: (value) => _save(
                      prefs.copyWith(dailyReview: value),
                      message: value
                          ? 'Daily closing note on'
                          : 'Daily closing note off',
                    ),
                    onLead: (value) => _save(
                      prefs.copyWith(leadMinutes: value),
                      message: 'Lead time updated',
                    ),
                    onDisable: () => _save(
                      prefs.copyWith(enabled: false),
                      message: 'Notifications turned off',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DisabledPrompt extends StatelessWidget {
  const _DisabledPrompt({required this.busy, required this.onEnable});

  final bool busy;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviewNote(
          title: 'Starts in 10 min · Draft the launch note',
          body: 'Writing · scheduled 9:30 AM',
          icon: Icons.timer_outlined,
        ),
        const SizedBox(height: AppSpace.sm),
        _PreviewNote(
          title: 'Daily reminder · Water the plants',
          body: 'Repeats every day at 8:00 AM',
          icon: Icons.repeat_rounded,
        ),
        const SizedBox(height: AppSpace.sm),
        _PreviewNote(
          title: 'Close the day',
          body: 'A few minutes to mark what moved and what stalled.',
          icon: Icons.nightlight_outlined,
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'Start, deadline, custom, and daily task reminders plus a daily '
          'closing note are all computed from your ledger. Nothing leaves the '
          'device.',
          style: AppText.bodySmall.copyWith(
            color: colors.inkMuted,
            fontSize: 10.8,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onEnable,
              icon: const Icon(Icons.notifications_active_outlined, size: 17),
              label: const Text('Turn on notifications'),
            ),
            TextButton.icon(
              onPressed: () => openNotifications(context),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Open notification centre'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviewNote extends StatelessWidget {
  const _PreviewNote({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.inkMuted),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(
                    color: colors.ink,
                    fontSize: 10.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall.copyWith(
                    color: colors.inkFaint,
                    fontSize: 9.8,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'now',
            style: AppText.monoData.copyWith(
              color: colors.inkFaint,
              fontSize: 8.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EnabledSummary extends StatelessWidget {
  const _EnabledSummary({
    required this.prefs,
    required this.pending,
    required this.busy,
    required this.onOpen,
    required this.onReschedule,
    required this.onTest,
    required this.onTaskReminders,
    required this.onDailyReview,
    required this.onLead,
    required this.onDisable,
  });

  final ReminderPreferences prefs;
  final int? pending;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onReschedule;
  final VoidCallback onTest;
  final ValueChanged<bool> onTaskReminders;
  final ValueChanged<bool> onDailyReview;
  final ValueChanged<int> onLead;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: colors.primarySoft.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: Row(
            children: [
              Icon(
                Icons.offline_bolt_outlined,
                size: 15,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  'Active on this device · '
                  '${pending ?? 0} notification'
                  '${(pending ?? 0) == 1 ? '' : 's'} queued',
                  style: AppText.bodySmall.copyWith(
                    color: colors.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: prefs.taskReminders,
          onChanged: busy ? null : onTaskReminders,
          title: Text(
            'Task reminders',
            style: AppText.bodySmall.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'Start, deadline, custom, and daily task reminders. Fine-tune each '
            'type in the notification centre.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 10.5,
            ),
          ),
        ),
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
              style: AppText.monoData.copyWith(color: colors.ink, fontSize: 12),
              items: const [
                DropdownMenuItem(value: 0, child: Text('At start')),
                DropdownMenuItem(value: 5, child: Text('5 min before')),
                DropdownMenuItem(value: 10, child: Text('10 min before')),
                DropdownMenuItem(value: 15, child: Text('15 min before')),
                DropdownMenuItem(value: 30, child: Text('30 min before')),
                DropdownMenuItem(value: 60, child: Text('1 hour before')),
              ],
              onChanged: busy || !prefs.taskReminders
                  ? null
                  : (next) {
                      if (next != null) {
                        onLead(next);
                      }
                    },
            ),
          ],
        ),
        const Divider(height: AppSpace.xl),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: prefs.dailyReview,
          onChanged: busy ? null : onDailyReview,
          title: Text(
            'Daily closing note',
            style: AppText.bodySmall.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'One quiet nudge to review the day · ${prefs.reviewLabel}.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 10.5,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            FilledButton.tonalIcon(
              onPressed: busy ? null : onOpen,
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Open notification centre'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onTest,
              icon: const Icon(Icons.notifications_active_outlined, size: 16),
              label: const Text('Send a test'),
            ),
            TextButton.icon(
              onPressed: busy ? null : onReschedule,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reschedule'),
            ),
            TextButton(
              onPressed: busy ? null : onDisable,
              child: const Text('Turn off'),
            ),
          ],
        ),
      ],
    );
  }
}
