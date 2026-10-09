import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// The mark of «مرافق التلميذ» (D-1 DS1 فكرة الهوية): an arch for the road,
/// three pillars for the steps, an amber dot for «الآن». It says: I am
/// beside you on the road.
///
/// With [animate] it draws itself once — the arch first, then the pillars
/// rise, then the dot lands. That is the only decorative motion in the app,
/// and it appears on the welcome and loading screens only.
class MqLogo extends StatefulWidget {
  const MqLogo({
    super.key,
    this.size = 64,
    this.animate = false,
    this.onDark = false,
  });

  final double size;
  final bool animate;

  /// Light arch and pillars, for the deep teal ground.
  final bool onDark;

  @override
  State<MqLogo> createState() => _MqLogoState();
}

class _MqLogoState extends State<MqLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    if (widget.animate) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: 'شعار مرافق التلميذ',
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _LogoPainter(
              t: reduce ? 1.0 : _c.value,
              arch: widget.onDark ? Colors.white : p.brandDeep,
              pillars: widget.onDark ? const Color(0xFF8FCFC8) : p.brand,
              dot: const Color(0xFFF5A524),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({
    required this.t,
    required this.arch,
    required this.pillars,
    required this.dot,
  });

  final double t;
  final Color arch;
  final Color pillars;
  final Color dot;

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    canvas.save();
    canvas.scale(s, s);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Arch: M10 46 c0-14 8-26 22-26 s22 12 22 26
    final path = Path()
      ..moveTo(10, 46)
      ..cubicTo(10, 32, 18, 20, 32, 20)
      ..cubicTo(46, 20, 54, 32, 54, 46);
    final archT = Curves.easeOutCubic.transform(_seg(t, 0.0, 0.6));
    if (archT > 0) {
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * archT),
        stroke..color = arch,
      );
    }

    // Pillars rise from the baseline (y = 46).
    final pillarT = Curves.easeOutCubic.transform(_seg(t, 0.4, 0.8));
    if (pillarT > 0) {
      stroke.color = pillars;
      void pillar(double x, double top) {
        final y = 46 - (46 - top) * pillarT;
        canvas.drawLine(Offset(x, 46), Offset(x, y), stroke);
      }

      pillar(22, 37);
      pillar(32, 30);
      pillar(42, 37);
    }

    // The dot lands last, with a small overshoot.
    final dotT = _seg(t, 0.7, 1.0);
    if (dotT > 0) {
      final scale = Curves.easeOutBack.transform(dotT);
      canvas.drawCircle(
          const Offset(32, 14), 6 * math.max(0.0, scale), Paint()..color = dot);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.t != t ||
      old.arch != arch ||
      old.pillars != pillars ||
      old.dot != dot;
}

/// The logo on a rounded tile, the way it appears as an app mark.
class MqLogoTile extends StatelessWidget {
  const MqLogoTile({super.key, this.size = 88, this.animate = false});
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF064B4D),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: MqLogo(size: size * 0.64, animate: animate, onDark: true),
    );
  }
}
