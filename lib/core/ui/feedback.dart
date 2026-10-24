import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'brand_mark.dart';
import 'surface_card.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.secondaryAction,
    this.icon,
    this.compact = false,
  });

  final String title;
  final String message;
  final Widget? action;
  final Widget? secondaryAction;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: compact ? AppSpace.xxl : AppSpace.x5,
            horizontal: AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: icon != null
                    ? Icon(icon, color: colors.primary, size: 26)
                    : const Center(child: BrandMark(size: 34)),
              ),
              const SizedBox(height: AppSpace.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppText.displayS.copyWith(color: colors.ink),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: colors.inkMuted),
              ),
              if (action != null || secondaryAction != null) ...[
                const SizedBox(height: AppSpace.xl),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [?action, ?secondaryAction],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet loading skeleton used while local queries settle.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({
    super.key,
    this.height = 120,
    this.radius = AppRadius.card,
  });

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.line),
      ),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.primary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      color: colors.rose.withValues(alpha: 0.06),
      borderColor: colors.rose.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colors.rose, size: 20),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.ink),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class ProgressHairline extends StatelessWidget {
  const ProgressHairline({
    super.key,
    required this.value,
    this.color,
    this.trackColor,
    this.height = 4,
  });

  final double value;
  final Color? color;
  final Color? trackColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final clamped = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor ?? colors.surfaceSunken),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: clamped,
              child: ColoredBox(color: color ?? colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
