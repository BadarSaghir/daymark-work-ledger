import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/enum_ui.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/form.dart';
import '../../core/ui/surface_card.dart';
import '../../core/utils/date_keys.dart';
import '../../core/utils/durations.dart';
import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../state/categories_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/stats_providers.dart';

class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final period = ref.watch(analyticsPeriodProvider);
    final analyticsAsync = ref.watch(analyticsProvider);
    final heatAsync = ref.watch(heatmapFocusProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final settings = ref.watch(settingsProvider).value;
    final data = analyticsAsync.value;
    final heat = heatAsync.value ?? const <String, int>{};
    final categoryById = {for (final c in categories) c.id: c};
    final wide = MediaQuery.sizeOf(context).width >= 1050;

    final header = PageHeader(
      eyebrow: 'The honest mirror',
      title: 'Insights',
      subtitle:
          'Not a scoreboard. A record of where the attention went, what it '
          'produced, and whether your plans tell the truth.',
      actions: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in AnalyticsPeriod.values)
              ChoicePill(
                label: option.label,
                selected: period == option,
                onTap: () =>
                    ref.read(analyticsPeriodProvider.notifier).state = option,
              ),
          ],
        ),
      ],
    );

    if (analyticsAsync.isLoading && data == null) {
      return PageWidth(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: AppSpace.xl),
              const LoadingBlock(height: 300),
              const SizedBox(height: AppSpace.lg),
              const LoadingBlock(height: 240),
            ],
          ),
        ),
      );
    }
    if (data == null) {
      return PageWidth(
        child: Column(
          children: [
            header,
            const SizedBox(height: AppSpace.xl),
            InlineError(
              message:
                  'Could not read insights: ${analyticsAsync.error ?? 'unknown error'}',
              onRetry: () => ref.invalidate(analyticsProvider),
            ),
          ],
        ),
      );
    }

    final days = data.focusByDay.entries.toList();
    final selectedDayCount = days.length;
    final avgFocus = data.activeDays == 0 ? 0 : data.focusMs ~/ data.activeDays;
    final topCategory = data.topCategoryId == null
        ? null
        : categoryById[data.topCategoryId];
    final dailyTarget = settings?.dailyWeightTarget ?? 25;
    final completionOfTarget = dailyTarget == 0
        ? 0.0
        : data.outputPoints / dailyTarget;

    final kpis = _KpiGrid(
      children: [
        _KpiCard(
          label: 'Focus time',
          value: formatCompactMs(data.focusMs),
          hint: '${formatDelta(data.focusDelta)} vs previous period',
          hintColor: data.focusDelta >= 0 ? colors.green : colors.rose,
          icon: Icons.timer_outlined,
          color: colors.accent,
        ),
        _KpiCard(
          label: 'Output weight',
          value: formatPoints(data.outputPoints),
          hint: '${(completionOfTarget * 100).round()}% of one daily target',
          icon: Icons.speed_rounded,
          color: colors.primary,
        ),
        _KpiCard(
          label: 'Completion',
          value: '${(data.completionRate * 100).round()}%',
          hint:
              '${data.completedCount} of ${math.max(data.plannedTasks.length, data.completedCount)} planned',
          icon: Icons.check_circle_outline_rounded,
          color: colors.green,
        ),
        _KpiCard(
          label: 'Estimate accuracy',
          value: data.estimateSamples == 0
              ? '—'
              : formatDelta(data.estimateDrift),
          hint: data.estimateSamples == 0
              ? 'Needs estimates + tracked time'
              : '${data.estimateSamples} completed with estimates',
          icon: Icons.straighten_rounded,
          color: colors.gold,
        ),
      ],
    );

    final focusPanel = _Panel(
      title: 'Attention over time',
      subtitle: period == AnalyticsPeriod.week
          ? 'This week, by day'
          : '${dateLabel(data.start)} – ${dateLabel(addDays(data.end, -1))}',
      child: SizedBox(
        height: 190,
        child: _FocusChart(days: days, selectedDayCount: selectedDayCount),
      ),
    );

    final categoryPanel = _Panel(
      title: 'Where the weight went',
      subtitle: topCategory == null
          ? 'Time by category'
          : '${topCategory.name} carried the most attention',
      child: _CategoryBreakdown(
        categoryFocusMs: data.categoryFocusMs,
        categoryById: categoryById,
        totalMs: data.focusMs,
        unassignedMs: data.unassignedFocusMs,
      ),
    );

    final heatPanel = _Panel(
      title: 'The last twelve weeks',
      subtitle: 'Each square is a day of focus. Darker means more time.',
      child: _Heatmap(map: heat),
    );

    final rhythmPanel = _Panel(
      title: 'Rhythm',
      subtitle: 'Consistency is quieter than intensity.',
      child: Column(
        children: [
          _RhythmRow(
            label: 'Active days',
            value: '${data.activeDays}',
            sub: 'of $selectedDayCount',
          ),
          _RhythmRow(
            label: 'Average focus',
            value: formatCompactMs(avgFocus),
            sub: 'per active day',
          ),
          _RhythmRow(
            label: 'Journal days',
            value: '${data.journalDays}',
            sub: 'written',
          ),
          _RhythmRow(
            label: 'Unassigned time',
            value: formatCompactMs(data.unassignedFocusMs),
            sub: 'no task attached',
          ),
          const SizedBox(height: AppSpace.sm),
          _KindBars(kindFocusMs: data.kindFocusMs, totalMs: data.focusMs),
        ],
      ),
    );

    final completedPanel = _Panel(
      title: 'Closed loops',
      subtitle: '${data.completedCount} completed in this period',
      child: data.completedTasks.isEmpty
          ? Text(
              'Nothing completed in this period yet. The list is allowed to '
              'start small.',
              style: AppText.bodySmall.copyWith(
                color: colors.inkFaint,
                fontStyle: FontStyle.italic,
              ),
            )
          : Column(
              children: [
                for (final view in data.completedTasks.take(7))
                  InkWell(
                    onTap: () => openTaskDetail(context, view.task.id),
                    borderRadius: BorderRadius.circular(AppRadius.badge),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_rounded,
                            size: 13,
                            color: colors.green,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              view.task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.bodySmall.copyWith(
                                color: colors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${dateLabel(view.task.completedAt!)} · '
                            '${formatPoints(view.points)}',
                            style: AppText.monoData.copyWith(
                              color: colors.inkFaint,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );

    final estimatePanel = _Panel(
      title: 'Does your estimate tell the truth?',
      subtitle: data.estimateSamples == 0
          ? 'Estimate a task and track it to unlock this.'
          : 'On ${data.estimateSamples} completed tasks with both estimate and time',
      child: data.estimateSamples == 0
          ? Text(
              'Estimates are a promise to your future self. Start with a rough '
              'number; the ledger will tell you how you are doing.',
              style: AppText.bodySmall.copyWith(
                color: colors.inkMuted,
                height: 1.6,
              ),
            )
          : Row(
              children: [
                SizedBox(
                  width: 76,
                  height: 76,
                  child: CustomPaint(
                    painter: _RatioDial(
                      ratio: data.estimateRatio,
                      color: data.estimateDrift.abs() < 0.15
                          ? colors.green
                          : data.estimateDrift > 0
                          ? colors.gold
                          : colors.blue,
                      track: colors.surfaceSunken,
                    ),
                    child: Center(
                      child: Text(
                        '${(data.estimateRatio * 100).round()}%',
                        style: AppText.monoData.copyWith(
                          color: colors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.estimateDrift.abs() < 0.15
                            ? 'Your estimates are close.'
                            : data.estimateDrift > 0
                            ? 'You tend to underestimate.'
                            : 'You tend to overestimate.',
                        style: AppText.bodyMedium.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatCompactMs(data.actualMinutesOnEstimated * 60000)} '
                        'actual against '
                        '${formatCompactMs(data.estimatedMinutes * 60000)} '
                        'estimated.',
                        style: AppText.bodySmall.copyWith(
                          color: colors.inkMuted,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data.estimateSamples < 4
                            ? 'Small sample. Keep going before drawing conclusions.'
                            : 'Ratio = actual ÷ estimate. 100% is a perfect promise.',
                        style: AppText.bodySmall.copyWith(
                          color: colors.inkFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );

    return PageWidth(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: AppSpace.xl),
            kpis,
            const SizedBox(height: AppSpace.xl),
            if (wide) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: focusPanel),
                  const SizedBox(width: AppSpace.x3),
                  SizedBox(width: 320, child: rhythmPanel),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: categoryPanel),
                  const SizedBox(width: AppSpace.lg),
                  Expanded(flex: 5, child: estimatePanel),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: heatPanel),
                  const SizedBox(width: AppSpace.lg),
                  Expanded(flex: 4, child: completedPanel),
                ],
              ),
            ] else ...[
              focusPanel,
              const SizedBox(height: AppSpace.lg),
              rhythmPanel,
              const SizedBox(height: AppSpace.lg),
              categoryPanel,
              const SizedBox(height: AppSpace.lg),
              estimatePanel,
              const SizedBox(height: AppSpace.lg),
              heatPanel,
              const SizedBox(height: AppSpace.lg),
              completedPanel,
            ],
            const SizedBox(height: AppSpace.lg),
            Text(
              'Insights are computed from your local records. The longer you '
              'keep the ledger, the more honest the mirror becomes.',
              style: AppText.bodySmall.copyWith(
                color: colors.inkFaint,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - AppSpace.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.md,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
    this.hintColor,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;
  final Color? hintColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label.toUpperCase(),
                style: AppText.label.copyWith(
                  color: colors.inkFaint,
                  fontSize: 8.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            value,
            style: AppText.monoLarge.copyWith(color: colors.ink, fontSize: 26),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodySmall.copyWith(
              color: hintColor ?? colors.inkFaint,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppText.titleM.copyWith(color: colors.ink, fontSize: 15.5),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          child,
        ],
      ),
    );
  }
}

class _FocusChart extends StatelessWidget {
  const _FocusChart({required this.days, required this.selectedDayCount});

  final List<MapEntry<String, int>> days;
  final int selectedDayCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxValue = days.fold<int>(1, (max, entry) {
      return entry.value > max ? entry.value : max;
    });
    final every = days.length <= 8 ? 1 : (days.length / 6).ceil();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < days.length; index++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == days.length - 1 ? 0 : 3),
              child: Tooltip(
                message:
                    '${dateLabel(parseDateKey(days[index].key))}\n${formatCompactMs(days[index].value)}',
                child: Column(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: days[index].value == 0
                              ? 0.015
                              : (days[index].value / maxValue).clamp(0.03, 1.0),
                          widthFactor: 0.62,
                          child: Container(
                            decoration: BoxDecoration(
                              color: days[index].value == 0
                                  ? colors.line
                                  : colors.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      index % every == 0
                          ? weekdayShort(parseDateKey(days[index].key))
                          : '',
                      style: AppText.bodySmall.copyWith(
                        color: colors.inkFaint,
                        fontSize: 8.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.categoryFocusMs,
    required this.categoryById,
    required this.totalMs,
    required this.unassignedMs,
  });

  final Map<String, int> categoryFocusMs;
  final Map<String, Category> categoryById;
  final int totalMs;
  final int unassignedMs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = categoryFocusMs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty || totalMs == 0) {
      return Text(
        'No time logged in this period yet. The chart fills as the clock runs.',
        style: AppText.bodySmall.copyWith(
          color: colors.inkFaint,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Column(
      children: [
        for (final entry in entries.take(7))
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: entry.key.isEmpty
                            ? colors.inkFaint
                            : (categoryById[entry.key]?.colorValue ??
                                  colors.inkFaint),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        entry.key.isEmpty
                            ? 'Unassigned'
                            : (categoryById[entry.key]?.name ??
                                  'Deleted category'),
                        style: AppText.bodySmall.copyWith(color: colors.ink),
                      ),
                    ),
                    Text(
                      '${(entry.value / totalMs * 100).round()}% · '
                      '${formatCompactMs(entry.value)}',
                      style: AppText.monoData.copyWith(
                        color: colors.inkFaint,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: colors.surfaceSunken),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (entry.value / totalMs).clamp(0.0, 1.0),
                          child: ColoredBox(
                            color: entry.key.isEmpty
                                ? colors.inkFaint
                                : (categoryById[entry.key]?.colorValue ??
                                      colors.inkFaint),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.map});

  final Map<String, int> map;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final today = startOfDay(DateTime.now());
    final start = addDays(startOfWeek(today), -77);
    final days = [for (var i = 0; i < 84; i++) addDays(start, i)];
    final maxValue = map.values.fold<int>(1, (a, b) => b > a ? b : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cell = math.min(15.0, (constraints.maxWidth - 11 * 3) / 12);
            return Row(
              children: [
                for (var week = 0; week < 12; week++)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Column(
                      children: [
                        for (var day = 0; day < 7; day++)
                          _HeatCell(
                            date: days[week * 7 + day],
                            value: map[dateKey(days[week * 7 + day])] ?? 0,
                            maxValue: maxValue,
                            size: cell,
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Text(
              'Less',
              style: AppText.bodySmall.copyWith(
                color: colors.inkFaint,
                fontSize: 9,
              ),
            ),
            const SizedBox(width: 4),
            for (final alpha in [0.08, 0.22, 0.42, 0.68, 1.0])
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: alpha),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const SizedBox(width: 4),
            Text(
              'More',
              style: AppText.bodySmall.copyWith(
                color: colors.inkFaint,
                fontSize: 9,
              ),
            ),
            const Spacer(),
            Text(
              '12 weeks',
              style: AppText.monoData.copyWith(
                color: colors.inkFaint,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.date,
    required this.value,
    required this.maxValue,
    required this.size,
  });

  final DateTime date;
  final int value;
  final int maxValue;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final alpha = value == 0 ? 0.075 : (0.16 + 0.8 * (value / maxValue));
    return Tooltip(
      message: '${dateLabel(date)} · ${formatCompactMs(value)}',
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: isToday(date)
              ? colors.accent
              : colors.primary.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(2.5),
          border: isToday(date)
              ? Border.all(color: colors.accent, width: 1)
              : null,
        ),
      ),
    );
  }
}

class _RhythmRow extends StatelessWidget {
  const _RhythmRow({
    required this.label,
    required this.value,
    required this.sub,
  });

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppText.bodySmall.copyWith(color: colors.inkMuted),
            ),
          ),
          Text(
            value,
            style: AppText.monoData.copyWith(color: colors.ink, fontSize: 13),
          ),
          const SizedBox(width: 5),
          Text(
            sub,
            style: AppText.bodySmall.copyWith(
              color: colors.inkFaint,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _KindBars extends StatelessWidget {
  const _KindBars({required this.kindFocusMs, required this.totalMs});

  final Map<WorkKind, int> kindFocusMs;
  final int totalMs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (totalMs == 0) return const SizedBox.shrink();
    return Column(
      children: [
        for (final kind in WorkKind.values)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 62,
                  child: Text(
                    kind.label,
                    style: AppText.bodySmall.copyWith(
                      color: colors.inkMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: colors.surfaceSunken),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: ((kindFocusMs[kind] ?? 0) / totalMs)
                                .clamp(0.0, 1.0),
                            child: ColoredBox(color: kind.color(colors)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 36,
                  child: Text(
                    formatCompactMs(kindFocusMs[kind] ?? 0),
                    textAlign: TextAlign.right,
                    style: AppText.monoData.copyWith(
                      color: colors.inkFaint,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RatioDial extends CustomPainter {
  _RatioDial({required this.ratio, required this.color, required this.track});

  final double ratio;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 5;
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, base);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * (ratio.clamp(0.0, 2.0) / 2),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RatioDial oldDelegate) =>
      oldDelegate.ratio != ratio || oldDelegate.color != color;
}
