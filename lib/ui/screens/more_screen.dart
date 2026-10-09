import 'package:flutter/material.dart';

import '../design/page.dart';
import '../design/primitives.dart';
import '../design/tokens.dart';
import '../library/library_screen.dart';
import '../teacher/teacher_entry_screen.dart';
import 'exams_screen.dart';
import 'settings_screen.dart';

/// «المزيد» (D-2 X04): exams, the library of teacher lessons, the SEPARATE
/// teacher entry, and settings. The reality, recovery, goals and curriculum
/// entries join this list in later batches of phase E. The teacher entry is
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
