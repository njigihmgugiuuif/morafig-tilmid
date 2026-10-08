import 'package:flutter/material.dart';

import '../library/library_screen.dart';
import '../teacher/teacher_entry_screen.dart';
import 'settings_screen.dart';

/// «المزيد» (D-2 X04): the library of teacher lessons, the SEPARATE teacher
/// entry, and the existing settings. The teacher entry is its own door (it
/// opens the entry screen, not a setting).
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) => Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => screen));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('المزيد',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('مكتبة الدروس'),
            subtitle: const Text('دروس أساتذتك المستوردة'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => open(const LibraryScreen()),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('مدخل الأستاذ'),
            subtitle: const Text('كتابة الدروس وتصدير الحزم'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => open(const TeacherEntryScreen()),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('الإعدادات'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => open(const SettingsScreen()),
          ),
        ),
      ],
    );
  }
}
