import 'package:flutter/material.dart';

import 'motion.dart';
import 'primitives.dart';
import 'tokens.dart';

/// The frame of a screen: a quiet top bar (back, caption + title, actions),
/// a scrolling body that eases in section by section, an optional floating
/// action, and pull-to-refresh when [onRefresh] is given.
///
/// There is no coloured app bar: the screen's own title is the hierarchy, and
/// the content starts higher, which is what makes the first look «a product»
/// rather than «a form».
class MqPage extends StatelessWidget {
  const MqPage({
    super.key,
    required this.title,
    this.caption,
    this.children = const <Widget>[],
    this.actions = const <Widget>[],
    this.onRefresh,
    this.floating,
    this.showBack,
    this.onBack,
    this.reveal = true,
    this.bodyBuilder,
  });

  final String title;
  final String? caption;
  final List<Widget> children;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  final Widget? floating;

  /// Defaults to «whether there is a screen to go back to».
  final bool? showBack;
  final VoidCallback? onBack;

  /// Ease the first eight children in one after another.
  final bool reveal;

  /// Replaces the default list body (for screens with their own layout).
  final WidgetBuilder? bodyBuilder;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final canBack = showBack ?? Navigator.of(context).canPop();

    Widget body;
    if (bodyBuilder != null) {
      body = bodyBuilder!(context);
    } else {
      final items = <Widget>[
        for (var i = 0; i < children.length; i++)
          reveal && i < 8 ? MqReveal(index: i, child: children[i]) : children[i],
      ];
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            MqSpace.screen, 4, MqSpace.screen, floating != null ? 96 : 28),
        children: items,
      );
      if (onRefresh != null) {
        body = RefreshIndicator(
          color: p.brand,
          backgroundColor: p.surface,
          onRefresh: onRefresh!,
          child: body,
        );
      }
    }

    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: floating,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  MqSpace.screen, 12, MqSpace.screen, 8),
              child: Row(
                children: [
                  if (canBack) ...[
                    MqIconButton(
                      icon: Icons.arrow_back_rounded,
                      label: 'رجوع',
                      onTap: onBack ?? () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (caption != null)
                          Text(caption!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MqType.caption.copyWith(color: p.ink3)),
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MqType.h1.copyWith(
                                color: p.ink, fontSize: canBack ? 20 : 24)),
                      ],
                    ),
                  ),
                  for (final a in actions) ...[
                    const SizedBox(width: 8),
                    a,
                  ],
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Primary floating action: a pill with icon and label, in the brand colour.
class MqFab extends StatelessWidget {
  const MqFab({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqPressable(
      onTap: onPressed,
      scale: 0.95,
      semanticLabel: label,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: p.brand,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: p.brand.withOpacity(p.isDark ? 0.0 : 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: p.onBrand),
            const SizedBox(width: 8),
            Text(label, style: MqType.label.copyWith(color: p.onBrand)),
          ],
        ),
      ),
    );
  }
}
