import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// The Daymark symbol: a rising arc, a baseline, and a persimmon mark.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 34,
    this.showWordmark = false,
    this.wordmarkColor,
    this.onTap,
  });

  final double size;
  final bool showWordmark;
  final Color? wordmarkColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _BrandMarkPainter(
        arc: colors.primary,
        dot: colors.accent,
        baseline: colors.primary.withValues(alpha: 0.85),
      ),
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(dimension: size, child: mark),
        if (showWordmark) ...[
          SizedBox(width: size * 0.3),
          Text(
            'Daymark',
            style: AppText.displayM.copyWith(
              color: wordmarkColor ?? colors.ink,
              fontSize: size * 0.72,
              letterSpacing: -0.6,
            ),
          ),
        ],
      ],
    );
    if (onTap == null) {
      return Semantics(label: 'Daymark', child: content);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  _BrandMarkPainter({
    required this.arc,
    required this.dot,
    required this.baseline,
  });

  final Color arc;
  final Color dot;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final center = Offset(size.width / 2, size.height * 0.64);
    final radius = size.width * 0.32;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final arcPaint = Paint()
      ..color = arc
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect, math.pi, math.pi, false, arcPaint);

    final baselinePaint = Paint()
      ..color = baseline
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke * 0.65;
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.8),
      Offset(size.width * 0.82, size.height * 0.8),
      baselinePaint,
    );

    canvas.drawCircle(
      Offset(center.dx + radius, center.dy),
      stroke * 0.78,
      Paint()..color = dot,
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) =>
      oldDelegate.arc != arc ||
      oldDelegate.dot != dot ||
      oldDelegate.baseline != baseline;
}

/// A tiny label with a live dot.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.color, this.size = 7});

  final Color? color;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.colors.accent;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.45,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
          ],
        ),
      ),
    );
  }
}
