import 'package:flutter/material.dart';

import '../design/page.dart';
import '../design/primitives.dart';
import '../design/tokens.dart';
import '../goals/goals_screen.dart';
import '../planning/energy_focus_screen.dart';
import '../planning/plan_calendar_screen.dart';
import '../planning/plan_review_screen.dart';
import '../reality/reality_hub_screen.dart';
import '../recovery/emergency_screen.dart';
import '../recovery/recovery_screen.dart';
import 'exams_screen.dart';

/// «المزيد»: the tools, as near-square cards, two per row. Settings stay as
/// the button on the home screen; the constitution (with the app's
/// introduction) is a card on the home screen too.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) => Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => screen));
    final items = <_Entry>[
      _Entry(
        icon: Icons.event_outlined,
        tone: MqTone.accent,
        title: 'الامتحانات والاستحقاقات',
        subtitle: 'أقرب الامتحانات وإضافة امتحان',
        onTap: () => open(const ExamsScreen()),
      ),
      _Entry(
        icon: Icons.tune_rounded,
        tone: MqTone.brand,
        title: 'واقعي',
        subtitle: 'أسبوعك، أوقات فراغك، الظروف الطارئة، الفصول والعطل',
        onTap: () => open(const RealityHubScreen()),
      ),
      _Entry(
        icon: Icons.autorenew_rounded,
        tone: MqTone.info,
        title: 'مراجعة الخطة',
        subtitle: 'إعادة التخطيط، المخطَّط مقابل الفعلي، الفجوات',
        onTap: () => open(const PlanReviewScreen()),
      ),
      _Entry(
        icon: Icons.calendar_month_outlined,
        tone: MqTone.neutral,
        title: 'الشهر والسنة',
        subtitle: 'نظرة على الجلسات المخطَّطة',
        onTap: () => open(const PlanCalendarScreen()),
      ),
      _Entry(
        icon: Icons.history_toggle_off_rounded,
        tone: MqTone.accent,
        title: 'ما فاتني',
        subtitle: 'جلسات انتهت دون تنفيذ وقرار التعافي',
        onTap: () => open(const RecoveryScreen()),
      ),
      _Entry(
        icon: Icons.bolt_rounded,
        tone: MqTone.overdue,
        title: 'وضع الطوارئ',
        subtitle: 'هل هو مفعّل ولماذا',
        onTap: () => open(const EmergencyScreen()),
      ),
      _Entry(
        icon: Icons.flag_outlined,
        tone: MqTone.ok,
        title: 'أهدافي',
        subtitle: 'سجّل أهدافك وتابعها',
        onTap: () => open(const GoalsScreen()),
      ),
      _Entry(
        icon: Icons.battery_charging_full_outlined,
        tone: MqTone.neutral,
        title: 'طاقتي وتركيزي',
        subtitle: 'سجلّ بسيط لحالتك',
        onTap: () => open(const EnergyFocusScreen()),
      ),
    ];
    return MqPage(
      title: 'المزيد',
      showBack: false,
      children: [
        for (var i = 0; i < items.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              height: 176,
              child: Row(
                children: [
                  Expanded(child: items[i]),
                  const SizedBox(width: 12),
                  Expanded(
                      child: i + 1 < items.length
                          ? items[i + 1]
                          : const SizedBox.shrink()),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final MqTone tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqCard(
      onTap: onTap,
      semanticLabel: title,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MqIconTile(icon: icon, tone: tone, size: 46),
          const SizedBox(height: 10),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MqType.h3.copyWith(color: p.ink)),
          const SizedBox(height: 4),
          Expanded(
            child: Text(subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: MqType.caption.copyWith(color: p.ink3)),
          ),
        ],
      ),
    );
  }
}
