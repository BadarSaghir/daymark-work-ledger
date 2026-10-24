import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Bottom sheet on compact screens, centred dialog on medium/expanded.
Future<T?> showAppSheet<T>(
  BuildContext context,
  Widget Function(BuildContext context) builder, {
  double maxWidth = 640,
  bool dismissible = true,
  EdgeInsets padding = const EdgeInsets.fromLTRB(
    AppSpace.xl,
    AppSpace.sm,
    AppSpace.xl,
    AppSpace.xl,
  ),
}) {
  final width = MediaQuery.sizeOf(context).width;
  final compact = width < AppBreakpoints.compact;

  if (compact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.93,
            ),
            child: Material(
              color: sheetContext.colors.surface,
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.sheet),
              ),
              child: Padding(padding: padding, child: builder(sheetContext)),
            ),
          ),
        );
      },
    );
  }

  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpace.xxl),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.88,
        ),
        child: Material(
          color: dialogContext.colors.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sheet),
              border: Border.all(color: dialogContext.colors.line),
            ),
            child: Padding(padding: padding, child: builder(dialogContext)),
          ),
        ),
      ),
    ),
  );
}

class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.onClose,
    this.showHandle = true,
    this.icon,
    this.maxContentWidth,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onClose;
  final bool showHandle;
  final IconData? icon;
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    Widget content = child;
    if (maxContentWidth != null) {
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth!),
          child: content,
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHandle && compact)
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpace.md),
              decoration: BoxDecoration(
                color: colors.lineStrong,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Icon(icon, size: 19, color: colors.primary),
              ),
              const SizedBox(width: AppSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, size: 19),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        Flexible(child: SingleChildScrollView(child: content)),
        if (footer != null) ...[
          const SizedBox(height: AppSpace.lg),
          const Divider(),
          const SizedBox(height: AppSpace.lg),
          footer!,
        ],
      ],
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      final tone = danger ? colors.rose : colors.primary;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppSpace.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Material(
            color: colors.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: colors.line),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.badge),
                      ),
                      child: Icon(
                        icon ?? Icons.help_outline_rounded,
                        color: tone,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    Text(
                      title,
                      style: Theme.of(dialogContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      message,
                      style: Theme.of(dialogContext).textTheme.bodyLarge
                          ?.copyWith(color: colors.inkMuted),
                    ),
                    const SizedBox(height: AppSpace.xxl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: Text(cancelLabel),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        FilledButton(
                          style: danger
                              ? FilledButton.styleFrom(
                                  backgroundColor: colors.rose,
                                  foregroundColor: Colors.white,
                                )
                              : null,
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: Text(confirmLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

void showToast(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), action: action, duration: duration),
    );
}

Widget sectionDivider(BuildContext context) => Padding(
  padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
  child: Divider(color: context.colors.line, height: 1),
);
