import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/exit_confirm_scope.dart';
import 'teacher_entry_screen.dart';

/// True when the browser address asks for the teacher panel:
/// `…/morafig-tilmid/#/teacher` (or `…/teacher/`, which redirects there).
bool isTeacherPortalAddress(Uri uri) {
  final f = uri.fragment;
  return f == '/teacher' ||
      f.startsWith('/teacher/') ||
      f.startsWith('/teacher?');
}

/// The teacher panel as its OWN application root, separate from the student
/// app: its own MaterialApp, its own state (no student, no student database
/// reads, no planning) and its own entry screen. The student's screens and
/// «المزيد» menu are not reachable from here, and the student app has no door
/// into this one.
class TeacherPortalApp extends StatefulWidget {
  const TeacherPortalApp({super.key});

  @override
  State<TeacherPortalApp> createState() => _TeacherPortalAppState();
}

class _TeacherPortalAppState extends State<TeacherPortalApp> {
  late final AppState _state = AppState.teacherPortal();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: _state,
      child: MaterialApp(
        title: 'لوحة الأستاذ · مرافق التلميذ',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        // Any address (including the browser's «/teacher») opens the entry.
        initialRoute: '/',
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => ExitConfirmScope(
            onBackPressed: () => true,
            child: const TeacherEntryScreen(),
          ),
        ),
      ),
    );
  }
}
