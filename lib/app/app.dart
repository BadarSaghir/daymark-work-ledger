import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/ui/brand_mark.dart';
import '../features/accounts/local_account_ui.dart';
import '../features/onboarding/onboarding_page.dart';
import '../state/local_account_controller.dart';
import '../state/settings_controller.dart';
import 'shell/app_shell.dart';

class DaymarkApp extends ConsumerWidget {
  const DaymarkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value;
    final local = ref.watch(localAccountProvider);
    final signedOut = local != null && !local.signedIn;
    final mode = switch (settings?.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    return MaterialApp(
      title: 'Daymark',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      scrollBehavior: const _QuietScrollBehavior(),
      home: signedOut
          ? const LocalAccountGate()
          : settingsAsync.when(
              loading: () => const _BootSplash(),
              error: (error, stack) => _SettingsFailure(error: error),
              data: (value) =>
                  value.onboarded ? const AppShell() : const OnboardingPage(),
            ),
    );
  }
}

class _QuietScrollBehavior extends MaterialScrollBehavior {
  const _QuietScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 54, showWordmark: true),
            const SizedBox(height: 22),
            SizedBox(
              width: 120,
              height: 2,
              child: LinearProgressIndicator(
                backgroundColor: colors.line,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Opening the ledger',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsFailure extends StatelessWidget {
  const _SettingsFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.x3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 44),
                const SizedBox(height: AppSpace.xl),
                Text(
                  'Could not read your settings',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.rose),
                ),
                const SizedBox(height: AppSpace.xl),
                Text(
                  'Your local database is still intact. Restart Daymark; if the '
                  'message persists, restore a backup.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.inkMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
