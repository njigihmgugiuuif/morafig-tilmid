import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/nav.dart';
import '../widgets/exit_confirm_scope.dart';
import 'dashboard_screen.dart';
import 'more_screen.dart';
import 'progress_screen.dart';
import 'tasks_hub_screen.dart';
import 'today_screen.dart';

/// Persistent shell of the student's five sections (D-1 DS3, D-2 X04):
/// الرئيسية · اليوم · المهام · التقدم · المزيد.
///
/// Where the earlier six tabs went (nothing was removed):
///   - «الأولويات» is the second page of «المهام» (TasksHubScreen).
///   - «الامتحانات» is an entry of «المزيد».
///
/// Tabs live in one stack (MqTabStack) so switching never grows the
/// Navigator back-stack and every tab keeps its own state.
///
/// Back (D-2 X01):
///   - on a tab other than «الرئيسية» → jump to «الرئيسية» (not exit);
///   - on «الرئيسية» → ExitConfirmScope's double-press logic (O-15: PopScope
///     over the existing Navigator, no new package).
/// Pushed screens, dialogs and sheets are routes above this shell, so the
/// Navigator closes them first.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _items = <MqNavItem>[
    MqNavItem(
        label: 'الرئيسية',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded),
    MqNavItem(
        label: 'اليوم',
        icon: Icons.calendar_today_outlined,
        selectedIcon: Icons.calendar_today_rounded),
    MqNavItem(
        label: 'المهام',
        icon: Icons.checklist_rounded,
        selectedIcon: Icons.checklist_rounded),
    MqNavItem(
        label: 'التقدم',
        icon: Icons.show_chart_rounded,
        selectedIcon: Icons.insights_rounded),
    MqNavItem(
        label: 'المزيد',
        icon: Icons.grid_view_outlined,
        selectedIcon: Icons.grid_view_rounded),
  ];

  bool _handleBackPress() {
    if (_index != 0) {
      setState(() => _index = 0);
      return false; // handled locally — do not treat as exit intent
    }
    return true; // already home — let ExitConfirmScope run its logic
  }

  void _goTo(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return ExitConfirmScope(
      onBackPressed: _handleBackPress,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: MqTabStack(
            index: _index,
            children: [
              DashboardScreen(onGoToTab: _goTo, active: _index == 0),
              TodayScreen(active: _index == 1),
              TasksHubScreen(active: _index == 2),
              const ProgressScreen(),
              const MoreScreen(),
            ],
          ),
        ),
        bottomNavigationBar: MqBottomNav(
          items: _items,
          selected: _index,
          onSelected: _goTo,
        ),
      ),
    );
  }
}
