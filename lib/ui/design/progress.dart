import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'primitives.dart';
import 'tokens.dart';

/// Circular progress. It animates to its value, and in a right-to-left
/// layout it fills counter-clockwise from the top, the mirror of the
/// left-to-right reading direction (D-1 DS1: «التقدم سهم يسارًا»).
class MqRing extends StatelessWidget {
  const MqRing({
    super.key,
    required this.value,
    this.size = 64,
    this.thickness = 7,
    this.color,
    this.track,
    this.center,
  });

  /// 0..1. Values outside are clamped.
  final double value;
  final double size;
  final double thickness;
  final Color? color;
  final Color? track;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        duration: MqMotion.of(context, MqMotion.slow),
        curve: MqMotion.enter,
        builder: (context, v, child) => CustomPaint(
          painter: _RingPainter(
            value: v,
            thickness: thickness,
            color: color ?? p.brand,
            track: track ?? p.surface2,
            clockwise: !rtl,
          ),
          child: child,
        ),
        child: Center(child: center),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.thickness,
    required this.color,
    required this.track,
    required this.clockwise,
  });

  final double value;
  final double thickness;
  final Color color;
  final Color track;
  final bool clockwise;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(thickness / 2, thickness / 2,
        size.width - thickness, size.height - thickness);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..color = color;
    final sweep = math.pi * 2 * value * (clockwise ? 1 : -1);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.track != track ||
      old.thickness != thickness ||
      old.clockwise != clockwise;
}

/// Horizontal bar. Starts at the reading-start edge (the right in Arabic).
class MqBar extends StatelessWidget {
  const MqBar({
    super.key,
    required this.value,
    this.tone = MqTone.brand,
    this.height = 8,
    this.onHero = false,
  });

  final double value;
  final MqTone tone;
  final double height;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final fill = onHero ? Colors.white : p.tone(tone).fg;
    final track = onHero ? const Color(0x33FFFFFF) : p.surface2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: height,
        color: track,
        alignment: AlignmentDirectional.centerStart,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: target),
          duration: MqMotion.of(context, MqMotion.slow),
          curve: MqMotion.enter,
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
