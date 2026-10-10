import 'package:flutter/material.dart';

import '../design/page.dart';
import '../design/primitives.dart';
import '../design/tokens.dart';
import '../library/library_screen.dart';
import '../teacher/teacher_entry_screen.dart';
import '../goals/goals_screen.dart';
import '../planning/energy_focus_screen.dart';
import '../planning/plan_calendar_screen.dart';
import '../planning/plan_review_screen.dart';
import '../reality/reality_hub_screen.dart';
import '../recovery/emergency_screen.dart';
import '../recovery/recovery_screen.dart';
import 'exams_screen.dart';
import 'settings_screen.dart';

/// «المزيد» (D-2 X04): exams, the library of teacher lessons, the SEPARATE
/// teacher entry, and settings. The teacher entry is
/// its own door (it opens the entry screen, not a setting).
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) => Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => screen));
    return MqPage(
      title: 'المزيد',
      showBack: false,
      children: [
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
        _Entry(
          icon: Icons.menu_book_outlined,
          tone: MqTone.brand,
          title: 'مكتبة الدروس',
          subtitle: 'دروس أساتذتك المستوردة',
          onTap: () => open(const LibraryScreen()),
        ),
        _Entry(
          icon: Icons.shield_outlined,
          tone: MqTone.info,
          title: 'مدخل الأستاذ',
          subtitle: 'كتابة الدروس وتصدير الحزم',
          onTap: () => open(const TeacherEntryScreen()),
        ),
        _Entry(
          icon: Icons.settings_outlined,
          tone: MqTone.neutral,
          title: 'الإعدادات',
          subtitle: 'المظهر والنسخ الاحتياطي',
          onTap: () => open(const SettingsScreen()),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MqCard(
        onTap: onTap,
        child: Row(
          children: [
            MqIconTile(icon: icon, tone: tone, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: MqType.h3.copyWith(color: p.ink)),
                  Text(subtitle, style: MqType.caption.copyWith(color: p.ink3)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: p.ink3, size: 20),
          ],
        ),
      ),
    );
  }
}
