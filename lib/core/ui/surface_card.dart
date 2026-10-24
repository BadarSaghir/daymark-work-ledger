import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The primary container language: warm surface, hairline border, generous
/// radius. No drop shadows unless elevated (sheets/popovers).
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.xl),
    this.onTap,
    this.color,
    this.borderColor,
    this.borderRadius = AppRadius.card,
    this.showBorder = true,
    this.clip = true,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double borderRadius;
  final bool showBorder;
  final bool clip;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(borderRadius);
    final content = Padding(padding: padding, child: child);

    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: Material(
        color: color ?? colors.surface,
        borderRadius: radius,
        clipBehavior: clip ? Clip.antiAlias : Clip.none,
        child: InkWell(
          onTap: onTap,
          hoverColor: colors.surfaceRaised,
          highlightColor: colors.primary.withValues(alpha: 0.04),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: showBorder
                  ? Border.all(color: borderColor ?? colors.line)
                  : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colors.inkFaint),
                  ),
                  const SizedBox(height: AppSpace.xs),
                ],
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.inkMuted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
    this.compact = false,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: colors.inkFaint),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              Text(
                title,
                style:
                    (compact
                            ? Theme.of(context).textTheme.headlineMedium
                            : Theme.of(context).textTheme.displayMedium)
                        ?.copyWith(height: 1.05),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpace.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppBreakpoints.prose,
                  ),
                  child: Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: colors.inkMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: AppSpace.lg),
          Wrap(spacing: AppSpace.sm, children: actions),
        ],
      ],
    );
  }
}

/// Small label + icon pill. Colour is never the only signal.
class BadgePill extends StatelessWidget {
  const BadgePill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.background,
    this.borderColor,
    this.compact = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;
  final Color? borderColor;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = color ?? colors.inkMuted;
    final content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpace.sm : AppSpace.md,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background ?? foreground.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 11 : 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              letterSpacing: 0.2,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 10.5 : 11.5,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: content,
    );
  }
}

class KeyHint extends StatelessWidget {
  const KeyHint(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(5),
        color: colors.surface,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.inkFaint,
          fontSize: 10,
          letterSpacing: 0,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class MetaText extends StatelessWidget {
  const MetaText(
    this.text, {
    super.key,
    this.icon,
    this.color,
    this.maxLines = 1,
  });

  final String text;
  final IconData? icon;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color ?? colors.inkFaint),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color ?? colors.inkMuted, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}
