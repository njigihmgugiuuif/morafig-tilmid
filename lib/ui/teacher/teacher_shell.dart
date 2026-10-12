import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'lesson_wizard_screen.dart';
import 'teacher_account_tab.dart';
import 'teacher_lessons_tab.dart';

/// Teacher shell: «دروسي / حسابي». Writing a lesson goes straight to sending it.
///
/// Back: from «حسابي» → «دروسي»; from «دروسي» →
/// leaves the shell and returns to the teacher entry screen, NOT straight
/// to the student app.
class TeacherShell extends StatefulWidget {
  const TeacherShell({super.key});

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  int _index = 0;
  int _rev = 0;

  void _refresh() => setState(() => _rev++);

  Future<void> _openWizard({String? lessonId}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LessonWizardScreen(lessonId: lessonId),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      TeacherLessonsTab(
        rev: _rev,
        onNewLesson: () => _openWizard(),
        onOpenLesson: (id) => _openWizard(lessonId: id),
        onChanged: _refresh,
      ),
      TeacherAccountTab(rev: _rev, onChanged: _refresh),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_index != 0) {
          setState(() => _index = 0);
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(const ['دروسي', 'حسابي'][_index]),
          automaticallyImplyLeading: false,
          actions: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Chip(
                avatar: Icon(Icons.shield_outlined, size: 16),
                label: Text('وضع الأستاذ', style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: IndexedStack(index: _index, children: tabs),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          backgroundColor: Theme.of(context).colorScheme.surface,
          indicatorColor: context.mq.brandSoft,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book),
                label: 'دروسي'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'حسابي'),
          ],
        ),
      ),
    );
  }
}
