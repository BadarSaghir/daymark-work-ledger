import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/sheets.dart';
import '../../core/ui/surface_card.dart';
import '../../data/services/notification_service.dart';
import '../../state/notification_controller.dart';

/// Offline reminders scheduled by the operating system from the local ledger.
class RemindersCard extends ConsumerStatefulWidget {
  const RemindersCard({super.key});

  @override
  ConsumerState<RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends ConsumerState<RemindersCard> {
  bool _busy = false;
  int? _pending;

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
    final count = await _run<int>(
      'Rescheduling',
      () => ref.read(reminderControllerProvider.notifier).syncNow(),
    );
    if (count == null || !mounted) return;
    showToast(
      context,
      count == 0
          ? 'Nothing to schedule yet. Add a start time or deadline to a task.'
          : '$count reminders scheduled',
    );
  }

  Future<void> _requestPermission() async {
    final granted = await _run<bool>(
      'Permission request',
      () => ref.read(reminderControllerProvider.notifier).requestPermission(),
    );
    if (granted == null || !mounted) return;
    showToast(
      context,
      granted
          ? 'Notification permission is granted'
          : 'Notifications are still blocked for Daymark',
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
          duration: const Duration(seconds: 5),
        );
      } else if (mounted) {
        showToast(context, 'Offline reminders are on');
      }
      await _refreshPending();
    } catch (error) {
      if (mounted) showToast(context, 'Could not enable reminders: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(ReminderPreferences next) async {
    await _run(
      'Updating reminders',
      () => ref.read(reminderControllerProvider.notifier).savePreferences(next),
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
                      'Offline reminders',
                      style: AppText.titleM.copyWith(
                        color: colors.ink,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scheduled on this device by the operating system. No '
                      'push service, no network, no account.',
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
              else if (async.valueOrNull?.enabled == true && _pending != null)
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
                    '$_pending scheduled',
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
              message: 'Could not read reminder settings: $error',
              onRetry: () {
                ref.invalidate(reminderControllerProvider);
                _refreshPending();
              },
            ),
            data: (prefs) => !prefs.enabled
                ? _DisabledPrompt(busy: _busy, onEnable: _enable)
                : _EnabledSettings(
                    prefs: prefs,
                    busy: _busy,
                    pending: _pending,
                    onDisable: () => _save(prefs.copyWith(enabled: false)),
                    onTaskReminders: (value) =>
                        _save(prefs.copyWith(taskReminders: value)),
                    onDailyReview: (value) =>
                        _save(prefs.copyWith(dailyReview: value)),
                    onLead: (value) =>
                        _save(prefs.copyWith(leadMinutes: value)),
                    onPickTime: () => _pickReviewTime(prefs),
                    onReschedule: _reschedule,
                    onTest: () => _run(
                      'Test notification',
                      () => ref
                          .read(reminderControllerProvider.notifier)
                          .sendTest(),
                    ),
                    onPermission: _requestPermission,
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
          title: 'Close the day',
          body: 'A few minutes to mark what moved and what stalled.',
          icon: Icons.nightlight_outlined,
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'Task starts, deadlines, and a daily closing note are all computed '
          'from your ledger and handed to your device. Nothing leaves it.',
          style: AppText.bodySmall.copyWith(
            color: colors.inkMuted,
            fontSize: 10.8,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy ? null : onEnable,
            icon: const Icon(Icons.notifications_active_outlined, size: 17),
            label: const Text('Turn on reminders'),
          ),
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

class _EnabledSettings extends StatelessWidget {
  const _EnabledSettings({
    required this.prefs,
    required this.busy,
    required this.pending,
    required this.onDisable,
    required this.onTaskReminders,
    required this.onDailyReview,
    required this.onLead,
    required this.onPickTime,
    required this.onReschedule,
    required this.onTest,
    required this.onPermission,
  });

  final ReminderPreferences prefs;
  final bool busy;
  final int? pending;
  final VoidCallback onDisable;
  final ValueChanged<bool> onTaskReminders;
  final ValueChanged<bool> onDailyReview;
  final ValueChanged<int> onLead;
  final VoidCallback onPickTime;
  final VoidCallback onReschedule;
  final VoidCallback onTest;
  final VoidCallback onPermission;

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
                  'Active on this device · works without a connection',
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
            'Task starts & deadlines',
            style: AppText.bodySmall.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'Only tasks with a scheduled start or a due time.',
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
                      if (next != null) onLead(next);
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
            'One quiet nudge to review the day.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 10.5,
            ),
          ),
        ),
        if (prefs.dailyReview)
          Row(
            children: [
              Text(
                'Remind me at',
                style: AppText.bodySmall.copyWith(color: colors.inkMuted),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: busy ? null : onPickTime,
                icon: const Icon(Icons.schedule_rounded, size: 15),
                label: Text(prefs.reviewLabel),
              ),
            ],
          ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            FilledButton.tonalIcon(
              onPressed: busy ? null : onReschedule,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reschedule'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onTest,
              icon: const Icon(Icons.notifications_outlined, size: 16),
              label: const Text('Send a test'),
            ),
            TextButton(
              onPressed: busy ? null : onPermission,
              child: const Text('Permission'),
            ),
            TextButton(
              onPressed: busy ? null : onDisable,
              child: const Text('Turn off'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Timing is handled by the OS and may be adjusted by battery saver. '
          'Daymark never uses exact alarms. Reminders refresh whenever the '
          'ledger changes and when the app opens.',
          style: AppText.bodySmall.copyWith(
            color: colors.inkFaint,
            fontSize: 9.8,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
