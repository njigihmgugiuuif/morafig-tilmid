import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../database/app_database.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// Root widget.
///
/// AppState is created here, ABOVE MaterialApp's Navigator, so that every
/// route (bottom sheets, dialogs, pushed screens such as Settings) can
/// reach it with `context.read<AppState>()`. Previously the provider lived
/// inside the `home` route only; routes opened through the Navigator
/// (e.g. the add-task / add-exam bottom sheets) are siblings of `home`,
/// not descendants, so they could not find it.
///
/// The live diagnostic (`_DiagnosticBootstrap`, below) confirmed on
/// 2026-10-01 that the Flutter engine and the Drift/WASM database work on
/// the production URL. It is kept, unused, so it can be switched back on
/// by passing it as `home` if ever needed again.
class MarafiqApp extends StatefulWidget {
  const MarafiqApp({super.key});

  @override
  State<MarafiqApp> createState() => _MarafiqAppState();
}

class _MarafiqAppState extends State<MarafiqApp> {
  late final Future<AppState> _future;

  @override
  void initState() {
    super.initState();
    _future = AppState.bootstrap();
  }

  Widget _app({required Widget home}) {
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
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: home,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _app(home: const _LoadingScreen());
        }
        if (snapshot.hasError) {
          return _app(home: _BootstrapErrorScreen(error: snapshot.error!));
        }
        return ChangeNotifierProvider<AppState>.value(
          value: snapshot.data!,
          child: _app(home: const _AppHome()),
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
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
              Text('$error',
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
}

/// Onboarding until a student exists locally, then the main shell.
class _AppHome extends StatelessWidget {
  const _AppHome();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return state.hasStudent ? const HomeShell() : const OnboardingScreen();
  }
}

class _StepResult {
  _StepResult(this.name);
  final String name;
  String status = 'لم يبدأ بعد';
  String detail = '';
  int? ms;
}

class _DiagnosticBootstrap extends StatefulWidget {
  const _DiagnosticBootstrap();
  @override
  State<_DiagnosticBootstrap> createState() => _DiagnosticBootstrapState();
}

class _DiagnosticBootstrapState extends State<_DiagnosticBootstrap> {
  final List<_StepResult> _steps = [
    _StepResult('المرحلة صفر: هل يعمل محرّك Flutter؟'),
    _StepResult('AppDatabase.open() — فتح الاتصال الحقيقي على app_db'),
    _StepResult('أول استعلام حقيقي (SELECT 1)'),
    _StepResult('CREATE TABLE (جدول اختبار مؤقت)'),
    _StepResult('INSERT (إدراج صف اختبار)'),
    _StepResult('SELECT (قراءة الصف)'),
    _StepResult('DROP TABLE (تنظيف كامل)'),
  ];
  final List<String> _fullErrors = [];
  bool _finished = false;
  static const _table = 'diagnostic_probe_tmp';

  @override
  void initState() {
    super.initState();
    _steps[0].status = 'نجاح';
    _steps[0].detail = 'إن كنتِ ترين هذه الشاشة، فمحرك Flutter يعمل بنجاح هنا.';
    _runRest();
  }

  Future<void> _step(int i, Future<void> Function() body,
      {Duration timeout = const Duration(seconds: 12)}) async {
    setState(() => _steps[i].status = 'جارٍ...');
    final sw = Stopwatch()..start();
    try {
      await body().timeout(timeout, onTimeout: () {
        throw TimeoutException(
            'انتهت المهلة (${timeout.inSeconds}ث) دون أي استجابة.');
      });
      sw.stop();
      setState(() {
        _steps[i].status = 'نجاح';
        _steps[i].ms = sw.elapsedMilliseconds;
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _steps[i].status = 'فشل';
        _steps[i].ms = sw.elapsedMilliseconds;
        _steps[i].detail = '$e';
      });
      _fullErrors.add('${_steps[i].name}\n$e\n$st');
      rethrow;
    }
  }

  Future<void> _runRest() async {
    AppDatabase? db;
    try {
      await _step(1, () async {
        db = AppDatabase.open();
      });
      await _step(2, () async {
        await db!.customStatement('SELECT 1;');
      });
      await _step(3, () async {
        await db!.customStatement(
            'CREATE TABLE IF NOT EXISTS $_table (id INTEGER PRIMARY KEY, note TEXT);');
      });
      await _step(4, () async {
        await db!.customStatement(
            "INSERT INTO $_table (note) VALUES ('diag');");
      });
      await _step(5, () async {
        final rows = await db!.customSelect('SELECT * FROM $_table;').get();
        if (rows.isEmpty) throw Exception('القراءة أعادت صفوفًا فارغة.');
      });
      await _step(6, () async {
        await db!.customStatement('DROP TABLE IF EXISTS $_table;');
      });
    } catch (_) {
      // Already recorded per-step.
    }
    setState(() => _finished = true);
  }

  String _report() {
    final b = StringBuffer();
    b.writeln('تقرير تشخيص مباشر داخل التطبيق الفعلي');
    b.writeln('الوقت: ${DateTime.now().toIso8601String()}');
    b.writeln('---');
    for (final s in _steps) {
      b.writeln('${s.name}: ${s.status}${s.ms != null ? ' (${s.ms}ms)' : ''}');
      if (s.detail.isNotEmpty) b.writeln('   ${s.detail}');
    }
    if (_fullErrors.isNotEmpty) {
      b.writeln('---');
      for (final e in _fullErrors) {
        b.writeln(e);
        b.writeln('...');
      }
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        title: const Text('تشخيص حي — مرافق التلميذ'),
        backgroundColor: AppColors.primary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final s in _steps)
            Card(
              child: ListTile(
                leading: Icon(
                  s.status == 'نجاح'
                      ? Icons.check_circle
                      : s.status == 'فشل'
                          ? Icons.cancel
                          : s.status == 'جارٍ...'
                              ? Icons.hourglass_top
                              : Icons.radio_button_unchecked,
                  color: s.status == 'نجاح'
                      ? Colors.green
                      : s.status == 'فشل'
                          ? Colors.red
                          : Colors.grey,
                ),
                title: Text(s.name),
                subtitle: Text(s.status +
                    (s.ms != null ? ' — ${s.ms}ms' : '') +
                    (s.detail.isNotEmpty ? '\n${s.detail}' : '')),
              ),
            ),
          const SizedBox(height: 16),
          if (_finished)
            ElevatedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('نسخ تقرير التشخيص'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _report()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ التقرير')),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}
