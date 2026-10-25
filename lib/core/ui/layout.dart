import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class Layout {
  Layout._();

  /// Phone-first layout detection. Width alone is not enough: a phone in
  /// landscape is still a phone, while a narrow desktop window is not.
  static bool isCompact(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width < AppBreakpoints.compact ||
        (size.shortestSide < 600 && size.width < 1000);
  }

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppBreakpoints.expanded;

  static double bottomInset(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom;

  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (isCompact(context)) {
      return const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.x6,
      );
    }
    if (width < AppBreakpoints.expanded) {
      return const EdgeInsets.fromLTRB(
        AppSpace.xxl,
        AppSpace.xl,
        AppSpace.xxl,
        AppSpace.x6,
      );
    }
    return const EdgeInsets.fromLTRB(
      AppSpace.x4,
      AppSpace.x3,
      AppSpace.x4,
      AppSpace.x6,
    );
  }
}

/// Constrains and pads page content. Pages own their scroll view so the shell
/// can keep scroll position while navigating.
class PageWidth extends StatelessWidget {
  const PageWidth({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.maxContent,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? Layout.pagePadding(context),
          child: child,
        ),
      ),
    );
  }
}

/// A soft tint in the top-left of the canvas adds depth without gradients
/// dominating the interface.
class CanvasWash extends StatelessWidget {
  const CanvasWash({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.9, -1.0),
          radius: 1.4,
          colors: [
            colors.primary.withValues(alpha: 0.055),
            colors.canvas.withValues(alpha: 0),
          ],
        ),
      ),
      child: child,
    );
  }
}
