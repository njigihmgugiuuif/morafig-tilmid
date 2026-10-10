import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'lesson_wizard_screen.dart';
import 'teacher_account_tab.dart';
import 'teacher_dashboard_tab.dart';
import 'teacher_lessons_tab.dart';
import 'teacher_review_tab.dart';

/// Teacher shell: «لوحتي / الدروس / المراجعة / الحساب» (D-2 T02–T05).
///
/// Back (D-2 X01): from a tab other than «لوحتي» → «لوحتي»; from «لوحتي» →
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
      TeacherDashboardTab(
        rev: _rev,
        onNewLesson: () => _openWizard(),
        onOpenLesson: (id) => _openWizard(lessonId: id),
        onShowAll: () => setState(() => _index = 1),
      ),
      TeacherLessonsTab(
        rev: _rev,
        onNewLesson: () => _openWizard(),
        onOpenLesson: (id) => _openWizard(lessonId: id),
        onChanged: _refresh,
      ),
      TeacherReviewTab(
        rev: _rev,
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
          title: Text(const [
            'لوحتي',
            'الدروس',
            'المراجعة',
            'الحساب والصلاحيات'
          ][_index]),
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
          indicatorColor: AppColors.primary.withOpacity(0.12),
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'لوحتي'),
            NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book),
                label: 'الدروس'),
            NavigationDestination(
                icon: Icon(Icons.fact_check_outlined),
                selectedIcon: Icon(Icons.fact_check),
                label: 'المراجعة'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'الحساب'),
          ],
        ),
      ),
    );
  }
}
