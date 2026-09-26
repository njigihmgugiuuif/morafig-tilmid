import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// Root widget. Boots the database + local state once (via a
/// FutureBuilder around AppState.bootstrap()), then decides between the
/// onboarding flow and the main app shell based on whether a Student
/// already exists — this is the single first-run / no-data-yet decision
/// point for the whole app.
class MarafiqApp extends StatelessWidget {
  const MarafiqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مرافق التلميذ',
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
      builder: (context, child) {
        // Force RTL directionality app-wide regardless of platform
        // locale detection quirks on some browsers/emulators — belt and
        // suspenders alongside the Locale('ar') above.
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _AppBootstrap(),
    );
  }
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();
  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late final Future<AppState> _future;

  @override
  void initState() {
    super.initState();
    _future = AppState.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.primary,
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }
        if (snapshot.hasError) {
          // First-run failure is the worst possible place for a silent
          // crash — show the actual error and a way forward instead of a
          // blank/frozen screen.
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.danger),
                    const SizedBox(height: 12),
                    const Text('تعذّر تشغيل قاعدة البيانات المحلية',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}',
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => SystemNavigator.pop(),
                      child: const Text('إغلاق'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final appState = snapshot.data!;
        return ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: Consumer<AppState>(
            builder: (context, state, _) {
              return state.hasStudent
                  ? const HomeShell()
                  : const OnboardingScreen();
            },
          ),
        );
      },
    );
  }
}
