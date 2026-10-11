import 'package:flutter/material.dart';

import 'primitives.dart';
import 'tokens.dart';

/// A point of a [MqLineChart]. `x` is any increasing number (days, order of
/// events); `y` is a value between 0 and 1.
class MqPoint {
  const MqPoint(this.x, this.y);
  final double x;
  final double y;
}

/// A vertical marker on a [MqLineChart] (e.g. «الآن»).
class MqMarker {
  const MqMarker(this.x, this.label);
  final double x;
  final String label;
}

/// Line chart for values from 0 to 1. Everything drawn comes from the points
/// handed in: the chart never smooths, extends or invents a value. The plot
/// is always left-to-right (earlier on the left), with the two end labels
/// given by the caller, so the time direction is the same for every chart.
class MqLineChart extends StatelessWidget {
  const MqLineChart({
    super.key,
    required this.points,
    required this.startLabel,
    required this.endLabel,
    this.markers = const [],
    this.threshold,
    this.thresholdLabel,
    this.color,
    this.height = 150,
    this.semanticLabel,
    this.showDots = true,
  });

  final List<MqPoint> points;
  final String startLabel;
  final String endLabel;
  final List<MqMarker> markers;

  /// Optional horizontal reference line (0..1) such as the retention target.
  final double? threshold;
  final String? thresholdLabel;
  final Color? color;
  final double height;
  final String? semanticLabel;
  final bool showDots;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Semantics(
      label: semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: CustomPaint(
                painter: _LinePainter(
                  points: points,
                  markers: markers,
                  threshold: threshold,
                  color: color ?? p.brand,
                  grid: p.line,
                  ink: p.ink3,
                  accent: p.accent,
                  soft: (color ?? p.brand).withOpacity(0.12),
                  showDots: showDots,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(startLabel,
                    style: MqType.caption.copyWith(color: p.ink3)),
                if (thresholdLabel != null)
                  Text(thresholdLabel!,
                      style: MqType.caption.copyWith(color: p.accent)),
                Text(endLabel, style: MqType.caption.copyWith(color: p.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.markers,
    required this.threshold,
    required this.color,
    required this.grid,
    required this.ink,
    required this.accent,
    required this.soft,
    required this.showDots,
  });

  final List<MqPoint> points;
  final List<MqMarker> markers;
  final double? threshold;
  final Color color;
  final Color grid;
  final Color ink;
  final Color accent;
  final Color soft;
  final bool showDots;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    double yOf(double v) => pad + h * (1 - v.clamp(0.0, 1.0));

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final g in const [0.0, 0.5, 1.0]) {
      canvas.drawLine(Offset(pad, yOf(g)), Offset(pad + w, yOf(g)), gridPaint);
    }
    if (points.isEmpty) return;

    final minX = points.first.x;
    var maxX = points.last.x;
    if (maxX <= minX) maxX = minX + 1;
    double xOf(double v) => pad + w * ((v - minX) / (maxX - minX));

    if (threshold != null) {
      final dash = Paint()
        ..color = accent
        ..strokeWidth = 1.2;
      final y = yOf(threshold!);
      for (double x = pad; x < pad + w; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), dash);
      }
    }

    for (final m in markers) {
      if (m.x < minX || m.x > maxX) continue;
      final x = xOf(m.x);
      canvas.drawLine(
          Offset(x, pad),
          Offset(x, pad + h),
          Paint()
            ..color = ink
            ..strokeWidth = 1);
      final tp = TextPainter(
        text: TextSpan(
            text: m.label, style: TextStyle(color: ink, fontSize: 11)),
        textDirection: TextDirection.rtl,
      )..layout();
      final dx = (x + 4 + tp.width > size.width) ? x - 4 - tp.width : x + 4;
      tp.paint(canvas, Offset(dx, pad));
    }

    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(xOf(points[i].x), yOf(points[i].y));
      if (i == 0) {
        line.moveTo(o.dx, o.dy);
      } else {
        line.lineTo(o.dx, o.dy);
      }
    }
    final fill = Path.from(line)
      ..lineTo(xOf(points.last.x), pad + h)
      ..lineTo(xOf(points.first.x), pad + h)
      ..close();
    canvas.drawPath(fill, Paint()..color = soft);
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    if (showDots) {
      for (final pt in points) {
        canvas.drawCircle(
            Offset(xOf(pt.x), yOf(pt.y)), 3.5, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.points != points ||
      old.markers != markers ||
      old.threshold != threshold ||
      old.color != color;
}

/// One row of [MqPairedBars].
class MqPairRow {
  const MqPairRow(this.label, this.first, this.second);
  final String label;
  final double first;
  final double second;
}

/// Two bars per row on the same scale (e.g. planned vs actual minutes,
/// needed vs available). Both bars use the largest value of all rows as the
/// full width, so the lengths can be compared by eye.
class MqPairedBars extends StatelessWidget {
  const MqPairedBars({
    super.key,
    required this.rows,
    required this.firstLabel,
    required this.secondLabel,
    this.unit = 'د',
  });

  final List<MqPairRow> rows;
  final String firstLabel;
  final String secondLabel;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    var maxV = 1.0;
    for (final r in rows) {
      if (r.first > maxV) maxV = r.first;
      if (r.second > maxV) maxV = r.second;
    }
    Widget bar(double v, Color c) => Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(children: [
                Container(height: 9, color: p.surface2),
                FractionallySizedBox(
                  widthFactor: (v / maxV).clamp(0.0, 1.0),
                  child: Container(height: 9, color: c),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: MqNum('${v.round()} $unit',
                style: MqType.caption, color: p.ink3),
          ),
        ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          _Legend(color: p.brand, label: firstLabel),
          const SizedBox(width: 14),
          _Legend(color: p.accent, label: secondLabel),
        ]),
        const SizedBox(height: 10),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.label, style: MqType.body.copyWith(color: p.ink)),
                const SizedBox(height: 4),
                bar(r.first, p.brand),
                const SizedBox(height: 4),
                bar(r.second, p.accent),
              ],
            ),
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: MqType.caption.copyWith(color: context.mq.ink2)),
      ]);
}

/// A bar split in segments that add up to the whole (done / remaining,
/// due / later). Segments with value 0 are skipped.
class MqSegmentBar extends StatelessWidget {
  const MqSegmentBar({super.key, required this.segments, this.height = 12});
  final List<(double, Color)> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final total = segments.fold<double>(0, (a, s) => a + s.$1);
    if (total <= 0) {
      return Container(
          height: height,
          decoration: BoxDecoration(
              color: p.surface2, borderRadius: BorderRadius.circular(6)));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: height,
        child: Row(children: [
          for (final s in segments)
            if (s.$1 > 0)
              Expanded(
                  flex: (s.$1 * 1000).round().clamp(1, 1000000),
                  child: Container(color: s.$2)),
        ]),
      ),
    );
  }
}
