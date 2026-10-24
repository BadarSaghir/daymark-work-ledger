import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/brand_mark.dart';
import '../../core/ui/form.dart';
import '../../state/repository_providers.dart';
import '../../state/settings_controller.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _name = TextEditingController();
  double _weightTarget = 25;
  int _focusMinutes = 300;
  String _themeMode = 'system';
  bool _demo = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_demo) {
        await ref.read(demoServiceProvider).load();
      }
      await ref
          .read(settingsProvider.notifier)
          .completeOnboarding(
            displayName: _name.text.trim().isEmpty
                ? 'friend'
                : _name.text.trim(),
            dailyWeightTarget: _weightTarget,
            dailyFocusMinutes: _focusMinutes,
            themeMode: _themeMode,
          );
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not set up the ledger: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 960;

    final story = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        BrandMark(size: 38, showWordmark: true),
        const SizedBox(height: AppSpace.x3),
        Text(
          'Every effort,\nmarked.',
          style: AppText.displayXl.copyWith(
            color: colors.ink,
            fontSize: wide ? 54 : 40,
            height: 1.02,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(
            'Daymark is a private work ledger. Plan the day, break the work '
            'into steps, time what matters, and keep an honest record of where '
            'the hours went.',
            style: AppText.body.copyWith(
              color: colors.inkMuted,
              fontSize: 15.5,
              height: 1.65,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.x3),
        for (final pillar in const [
          (
            Icons.edit_calendar_outlined,
            'Plan with weight, not wishful lists',
            'Effort, priority, and category importance make the day visible.',
          ),
          (
            Icons.checklist_rounded,
            'Break big work into steps',
            'Progress belongs to the parts. The points follow the parts.',
          ),
          (
            Icons.timer_outlined,
            'Time it honestly',
            'One live clock, paused segments, every minute accounted for.',
          ),
          (
            Icons.lock_outline_rounded,
            'Nothing leaves this device',
            'SQLite on your disk. Markdown you can read. Backups you own.',
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.badge),
                  ),
                  child: Icon(pillar.$1, size: 17, color: colors.primary),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pillar.$2,
                        style: AppText.bodyMedium.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pillar.$3,
                        style: AppText.bodySmall.copyWith(
                          color: colors.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Text(
          'NO ACCOUNT  ·  NO CLOUD  ·  NO SURVEILLANCE',
          style: AppText.label.copyWith(
            color: colors.inkFaint,
            fontSize: 8.5,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );

    final setup = Container(
      padding: EdgeInsets.all(wide ? AppSpace.x4 : AppSpace.xl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        border: Border.all(color: colors.line),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 48,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Set up your ledger',
            style: AppText.displayM.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'A few decisions now. All of them can change later.',
            style: AppText.bodySmall.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.xl),
          const FormLabel('What should Daymark call you?'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Your name',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 19),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          Row(
            children: [
              const Expanded(child: FormLabel('Daily weight target')),
              Text(
                '${_weightTarget.round()} pts',
                style: AppText.monoData.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: _weightTarget,
            min: 6,
            max: 60,
            divisions: 54,
            onChanged: (value) => setState(() => _weightTarget = value),
          ),
          Text(
            'A normal focused day is roughly 20–30 points. The target is a '
            'compass, not a quota.',
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 10.8,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              const Expanded(child: FormLabel('Daily focus target')),
              Text(
                _focusLabel(_focusMinutes),
                style: AppText.monoData.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: _focusMinutes.toDouble(),
            min: 60,
            max: 600,
            divisions: 18,
            onChanged: (value) => setState(() => _focusMinutes = value.round()),
          ),
          const SizedBox(height: AppSpace.md),
          const FormLabel('Appearance'),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final (value, label, icon) in [
                ('system', 'System', Icons.brightness_auto_outlined),
                ('light', 'Light', Icons.light_mode_outlined),
                ('dark', 'Dark', Icons.dark_mode_outlined),
              ])
                ChoicePill(
                  label: label,
                  icon: icon,
                  selected: _themeMode == value,
                  onTap: () => setState(() => _themeMode = value),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: colors.surfaceSunken.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: colors.line),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 18, color: colors.gold),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start with a demo workspace',
                        style: AppText.bodySmall.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'A few realistic tasks, notes, and tracked hours so you '
                        'can feel the product immediately.',
                        style: AppText.bodySmall.copyWith(
                          color: colors.inkMuted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _demo,
                  onChanged: (value) => setState(() => _demo = value),
                  activeThumbColor: colors.onPrimary,
                  activeTrackColor: colors.primary,
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              _error!,
              style: AppText.bodySmall.copyWith(color: colors.rose),
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          FilledButton.icon(
            onPressed: _saving ? null : _enter,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_forward_rounded, size: 19),
            label: Text(_demo ? 'Load demo & enter' : 'Open my ledger'),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Your database lives in this app’s local support folder. '
            'Backups are plain ZIP files you can inspect.',
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 10.2,
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: colors.canvas,
      body: Stack(
        children: [
          const Positioned.fill(child: _Backdrop()),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? AppSpace.x5 : AppSpace.xl,
                vertical: wide ? AppSpace.x4 : AppSpace.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: story),
                            const SizedBox(width: AppSpace.x5),
                            SizedBox(width: 500, child: setup),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            BrandMark(size: 30, showWordmark: true),
                            const SizedBox(height: AppSpace.xl),
                            Text(
                              'Every effort, marked.',
                              style: AppText.displayL.copyWith(
                                color: colors.ink,
                              ),
                            ),
                            const SizedBox(height: AppSpace.sm),
                            Text(
                              'A private, offline ledger for the work you mean '
                              'to do — and the work that actually happens.',
                              style: AppText.body.copyWith(
                                color: colors.inkMuted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: AppSpace.xl),
                            setup,
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _focusLabel(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '${hours}h';
    return '${hours}h ${rest}m';
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.8, -0.9),
          radius: 1.2,
          colors: [
            colors.primary.withValues(alpha: 0.09),
            colors.canvas.withValues(alpha: 0),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _HairlineGrid(color: colors.line.withValues(alpha: 0.35)),
      ),
    );
  }
}

class _HairlineGrid extends CustomPainter {
  _HairlineGrid({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.6;
    const step = 48.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_HairlineGrid oldDelegate) => oldDelegate.color != color;
}
