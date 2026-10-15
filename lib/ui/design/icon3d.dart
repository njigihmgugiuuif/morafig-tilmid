import 'package:flutter/material.dart';

import 'primitives.dart';
import 'tokens.dart';

/// A rounded icon tile with a soft «almost 3-D» look: a light-to-deep
/// gradient, a glossy highlight on top, a thin rim light and a soft shadow
/// under it. Same colours as [MqIconTile] (same tone, same contrast), only
/// the depth is new, so it never lowers the icon's readability.
class Mq3dIcon extends StatelessWidget {
  const Mq3dIcon({
    super.key,
    required this.icon,
    this.tone = MqTone.brand,
    this.size = 52,
  });

  final IconData icon;
  final MqTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final c = p.tone(tone);
    final dark = p.isDark;
    final radius = BorderRadius.circular(size * 0.3);
    final top = Color.lerp(c.bg, Colors.white, dark ? 0.10 : 0.55)!;
    final bottom = Color.lerp(c.bg, c.fg, dark ? 0.22 : 0.16)!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, c.bg, bottom],
          stops: const [0.0, 0.45, 1.0],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: dark ? 0.10 : 0.70),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: c.fg.withValues(alpha: dark ? 0.30 : 0.26),
            blurRadius: size * 0.28,
            offset: Offset(0, size * 0.10),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glossy highlight along the top edge.
          Positioned(
            top: size * 0.05,
            left: size * 0.10,
            right: size * 0.10,
            height: size * 0.32,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.22),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.12 : 0.55),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Icon(
            icon,
            size: size * 0.52,
            color: c.fg,
            shadows: [
              Shadow(
                color: c.fg.withValues(alpha: 0.35),
                blurRadius: size * 0.10,
                offset: Offset(0, size * 0.04),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
