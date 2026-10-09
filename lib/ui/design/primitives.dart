import 'dart:async';

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Semantic tones shared by chips, tiles, banners and bars (DS2 المكوّنات).
enum MqTone { neutral, brand, accent, ok, overdue, info }

@immutable
class MqToneColors {
  const MqToneColors(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

extension MqPaletteTones on MqPalette {
  MqToneColors tone(MqTone t) {
    switch (t) {
      case MqTone.brand:
        return MqToneColors(brandSoft, brand);
      case MqTone.accent:
        return MqToneColors(accentSoft, accentInk);
      case MqTone.ok:
        return MqToneColors(okSoft, ok);
      case MqTone.overdue:
        return MqToneColors(overdueSoft, overdue);
      case MqTone.info:
        return MqToneColors(infoSoft, info);
      case MqTone.neutral:
        return MqToneColors(surface2, ink2);
    }
  }
}

/// Anything tappable gets the same physical answer: a quick press-in.
class MqPressable extends StatefulWidget {
  const MqPressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final String? semanticLabel;

  @override
  State<MqPressable> createState() => _MqPressableState();
}

class _MqPressableState extends State<MqPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: MqMotion.of(context, MqMotion.quick),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

enum MqCardKind { surface, soft, flat }

/// Surface. `soft` is the quiet one for secondary information, `flat` has
/// no shadow, `surface` is the default.
class MqCard extends StatelessWidget {
  const MqCard({
    super.key,
    required this.child,
    this.kind = MqCardKind.surface,
    this.padding = const EdgeInsets.all(16),
    this.radius = MqSpace.radiusCard,
    this.onTap,
    this.color,
    this.semanticLabel,
  });

  final Widget child;
  final MqCardKind kind;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final bg = color ?? (kind == MqCardKind.soft ? p.surface2 : p.surface);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: kind == MqCardKind.soft || color != null
            ? null
            : Border.all(color: p.line),
        boxShadow: kind == MqCardKind.surface ? p.cardShadow : null,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return MqPressable(
        onTap: onTap, semanticLabel: semanticLabel, scale: 0.985, child: box);
  }
}

enum MqButtonKind { primary, accent, secondary, ghost, onHero, outlineOnHero }

/// The one button. An action that returns a Future disables the button and
/// shows a spinner until it finishes, so a double tap can never act twice
/// (the role the old DebouncedButton played, for every button now).
class MqButton extends StatefulWidget {
  const MqButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = MqButtonKind.primary,
    this.small = false,
    this.block = false,
  });

  final String label;
  final IconData? icon;
  final FutureOr<void> Function()? onPressed;
  final MqButtonKind kind;
  final bool small;
  final bool block;

  @override
  State<MqButton> createState() => _MqButtonState();
}

class _MqButtonState extends State<MqButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy || widget.onPressed == null) return;
    final result = widget.onPressed!();
    if (result is Future<void>) {
      setState(() => _busy = true);
      try {
        await result;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    Color bg;
    Color fg;
    Color? border;
    switch (widget.kind) {
      case MqButtonKind.primary:
        bg = p.brand;
        fg = p.onBrand;
        break;
      case MqButtonKind.accent:
        bg = p.accent;
        fg = const Color(0xFF2A1900);
        break;
      case MqButtonKind.secondary:
        bg = p.surface;
        fg = p.ink;
        border = p.line;
        break;
      case MqButtonKind.ghost:
        bg = Colors.transparent;
        fg = p.ink;
        break;
      case MqButtonKind.onHero:
        bg = Colors.white;
        fg = const Color(0xFF064B4D);
        break;
      case MqButtonKind.outlineOnHero:
        bg = Colors.transparent;
        fg = Colors.white;
        border = const Color(0x66FFFFFF);
        break;
    }
    final enabled = widget.onPressed != null;
    final height = widget.small ? 36.0 : 48.0;
    final iconSize = widget.small ? 16.0 : 20.0;
    final content = Row(
      mainAxisSize: widget.block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_busy)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: iconSize, color: fg),
        if (_busy || widget.icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MqType.label.copyWith(
              color: fg,
              fontSize: widget.small ? 13 : 15,
            ),
          ),
        ),
      ],
    );
    final box = AnimatedContainer(
      duration: MqMotion.of(context, MqMotion.quick),
      height: height,
      padding: EdgeInsets.symmetric(horizontal: widget.small ? 12 : 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius:
            BorderRadius.circular(widget.small ? 12 : MqSpace.radiusButton),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Center(widthFactor: widget.block ? null : 1, child: content),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: MqPressable(
        onTap: enabled ? _tap : null,
        scale: 0.96,
        child: widget.block ? SizedBox(width: double.infinity, child: box) : box,
      ),
    );
  }
}

/// 44px square icon button on a surface (touch target per DS1).
class MqIconButton extends StatelessWidget {
  const MqIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onHero = false,
  });

  final IconData icon;

  /// Spoken and shown as tooltip: every icon-only button needs one.
  final String label;
  final VoidCallback? onTap;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Tooltip(
      message: label,
      child: MqPressable(
        onTap: onTap,
        semanticLabel: label,
        child: Container(
          width: MqSpace.touch,
          height: MqSpace.touch,
          decoration: BoxDecoration(
            color: onHero ? const Color(0x29FFFFFF) : p.surface,
            borderRadius: BorderRadius.circular(MqSpace.radiusButton),
            border: onHero ? null : Border.all(color: p.line),
          ),
          child: Icon(icon, size: 22, color: onHero ? Colors.white : p.ink),
        ),
      ),
    );
  }
}

/// Small pill: status, source, count.
class MqChip extends StatelessWidget {
  const MqChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = MqTone.neutral,
    this.large = false,
    this.outline = false,
    this.onHero = false,
    this.colors,
  });

  final String label;
  final IconData? icon;
  final MqTone tone;
  final bool large;
  final bool outline;

  /// A translucent chip for use on the deep teal hero.
  final bool onHero;

  /// Explicit colours (a subject tone) — wins over [tone].
  final MqToneColors? colors;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    Color bg;
    Color fg;
    Border? border;
    if (onHero) {
      bg = const Color(0x29FFFFFF);
      fg = Colors.white;
    } else if (outline) {
      bg = Colors.transparent;
      fg = p.ink2;
      border = Border.all(color: p.line);
    } else {
      final c = colors ?? p.tone(tone);
      bg = c.bg;
      fg = c.fg;
    }
    return Container(
      height: large ? 34 : 26,
      padding: EdgeInsets.symmetric(horizontal: large ? 14 : 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: large ? 16 : 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: MqType.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
              fontSize: large ? 13 : 12,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A number or percentage shown with Latin digits in an isolated
/// left-to-right cell, so "68%" never turns into "%68" inside Arabic text.
class MqNum extends StatelessWidget {
  const MqNum(this.text, {super.key, this.style, this.color});
  final String text;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? MqType.h2).copyWith(
      fontFeatures: MqType.tabular,
      color: color ?? context.mq.ink,
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(text, style: base),
    );
  }
}

/// Rounded tile holding an icon (list rows, stat cards).
class MqIconTile extends StatelessWidget {
  const MqIconTile({
    super.key,
    required this.icon,
    this.tone = MqTone.brand,
    this.colors,
    this.size = 40,
  });

  final IconData icon;
  final MqTone tone;
  final MqToneColors? colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = colors ?? context.mq.tone(tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.5, color: c.fg),
    );
  }
}

/// Two- or three-way switch (اليوم / الأسبوع).
class MqSegmented<T> extends StatelessWidget {
  const MqSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  /// value -> label, in display order.
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(MqSpace.radiusButton),
      ),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: MqPressable(
                onTap: () => onChanged(entry.key),
                scale: 0.98,
                child: AnimatedContainer(
                  duration: MqMotion.of(context, MqMotion.base),
                  curve: MqMotion.enter,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        entry.key == selected ? p.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: entry.key == selected ? p.cardShadow : null,
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: MqMotion.of(context, MqMotion.base),
                    style: MqType.label.copyWith(
                      fontSize: 13,
                      color: entry.key == selected ? p.ink : p.ink2,
                    ),
                    child: Text(entry.value),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// «عنوان القسم» with an optional trailing action label.
class MqSectionTitle extends StatelessWidget {
  const MqSectionTitle(this.title, {super.key, this.trailing, this.onTrailing});
  final String title;
  final String? trailing;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: MqType.h3.copyWith(color: p.ink)),
          ),
          if (trailing != null)
            MqPressable(
              onTap: onTrailing,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Text(trailing!,
                    style: MqType.caption
                        .copyWith(color: p.brand, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}
