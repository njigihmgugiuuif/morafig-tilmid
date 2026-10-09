import 'package:flutter/material.dart';

import 'primitives.dart';
import 'tokens.dart';

class MqNavItem {
  const MqNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Bottom navigation of the five sections (D-1 DS3). A pill grows behind the
/// selected icon and the label gains weight; the bar floats on a surface with
/// a hairline, honouring the bottom safe area.
class MqBottomNav extends StatelessWidget {
  const MqBottomNav({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<MqNavItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(6, 8, 6, 8 + bottom),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _NavButton(
                item: items[i],
                selected: i == selected,
                onTap: () => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final MqNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final color = selected ? p.brand : p.ink3;
    return MqPressable(
      onTap: onTap,
      scale: 0.94,
      semanticLabel: item.label,
      child: SizedBox(
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: MqMotion.of(context, MqMotion.base),
              curve: MqMotion.enter,
              width: selected ? 58 : 34,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? p.brandSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: AnimatedSwitcher(
                duration: MqMotion.of(context, MqMotion.quick),
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  key: ValueKey<bool>(selected),
                  size: 22,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: MqMotion.of(context, MqMotion.base),
              style: MqType.caption.copyWith(
                fontSize: 11,
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(item.label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}
