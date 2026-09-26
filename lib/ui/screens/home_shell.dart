import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/exit_confirm_scope.dart';
import 'dashboard_screen.dart';
import 'exams_screen.dart';
import 'priorities_screen.dart';
import 'progress_screen.dart';
import 'tasks_screen.dart';

/// Persistent shell for the 5 main sections, shown after onboarding is
/// complete. Uses IndexedStack (not re-pushing a new route per tab) so
/// switching tabs never grows the Navigator back-stack and each tab keeps
/// its own scroll/tab-controller state when you switch away and back.
///
/// Android/system back-button behavior implemented here explicitly:
///   1st back press while on a tab other than "الرئيسية" → jump to
///      "الرئيسية" (matches user expectation: back = go toward home, not
///      exit).
///   back press while already on "الرئيسية" → falls through to
///      ExitConfirmScope's double-press-to-exit logic.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    TasksScreen(),
    ProgressScreen(),
    PrioritiesScreen(),
    ExamsScreen(),
  ];

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
    NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'المهام'),
    NavigationDestination(icon: Icon(Icons.trending_up_outlined), selectedIcon: Icon(Icons.trending_up), label: 'التقدم'),
    NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag), label: 'الأولويات'),
    NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: 'الامتحانات'),
  ];

  bool _handleBackPress() {
    if (_index != 0) {
      setState(() => _index = 0);
      return false; // handled locally — do not treat as exit intent
    }
    return true; // already home — let ExitConfirmScope run its logic
  }

  @override
  Widget build(BuildContext context) {
    return ExitConfirmScope(
      onBackPressed: _handleBackPress,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(index: _index, children: _screens),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: Colors.white,
          indicatorColor: AppColors.primary.withOpacity(0.12),
          destinations: _destinations,
        ),
      ),
    );
  }
}
