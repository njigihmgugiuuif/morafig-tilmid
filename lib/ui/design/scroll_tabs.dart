import 'package:flutter/material.dart';

import 'primitives.dart';
import 'tokens.dart';

/// A row of pills that scrolls sideways, for a page switcher with more
/// options than fit in a [MqSegmented] on a small phone. The selected pill is
/// scrolled into view. Same look family as the segmented control.
class MqScrollTabs<T> extends StatefulWidget {
  const MqScrollTabs({
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
  State<MqScrollTabs<T>> createState() => _MqScrollTabsState<T>();
}

class _MqScrollTabsState<T> extends State<MqScrollTabs<T>> {
  final Map<T, GlobalKey> _keys = {};

  GlobalKey _keyFor(T k) => _keys.putIfAbsent(k, () => GlobalKey());

  @override
  void didUpdateWidget(MqScrollTabs<T> old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keyFor(widget.selected).currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              duration: const Duration(milliseconds: 220),
              alignment: 0.5,
              curve: Curves.easeOutCubic);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return SizedBox(
      height: MqSpace.touch,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final e in widget.options.entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: MqPressable(
                key: _keyFor(e.key),
                onTap: () => widget.onChanged(e.key),
                semanticLabel: e.value,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: e.key == widget.selected ? p.brand : p.surface2,
                    borderRadius:
                        BorderRadius.circular(MqSpace.radiusButton),
                  ),
                  child: Text(
                    e.value,
                    style: MqType.label.copyWith(
                      fontSize: 14,
                      color: e.key == widget.selected ? p.onBrand : p.ink2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
