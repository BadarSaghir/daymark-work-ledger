import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/ui/brand_mark.dart';
import '../core/utils/durations.dart';
import '../state/timer_controller.dart';
import 'task_actions.dart';

class TimerPill extends ConsumerWidget {
  const TimerPill({super.key, required this.onOpen, this.compact = false});

  final VoidCallback onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timerProvider).valueOrNull;
    final session = state?.session;
    if (session == null) return const SizedBox.shrink();
    final colors = context.colors;
    final elapsed = state!.elapsed;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          constraints: BoxConstraints(maxWidth: compact ? 340 : 320),
          padding: EdgeInsets.fromLTRB(
            compact ? 13 : 12,
            compact ? 8 : 9,
            7,
            compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            color: colors.ink,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: colors.ink.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LiveDot(
                color: state.isRunning
                    ? colors.accent
                    : colors.inkFaint.withValues(alpha: 0.8),
                size: 7,
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodySmall.copyWith(
                        color: colors.canvas.withValues(alpha: 0.72),
                        fontSize: 10.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatStopwatch(elapsed),
                      style: AppText.monoData.copyWith(
                        color: colors.canvas,
                        fontSize: compact ? 14.5 : 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _PillButton(
                icon: state.isRunning
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tooltip: state.isRunning ? 'Pause' : 'Resume',
                onTap: () {
                  if (state.isRunning) {
                    ref.read(timerProvider.notifier).pause();
                  } else {
                    ref.read(timerProvider.notifier).resume();
                  }
                },
              ),
              const SizedBox(width: 4),
              _PillButton(
                icon: Icons.stop_rounded,
                tooltip: 'Stop and save',
                onTap: () => confirmStopTimer(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.canvas.withValues(alpha: 0.1),
          ),
          child: Icon(icon, size: 17, color: colors.canvas),
        ),
      ),
    );
  }
}
