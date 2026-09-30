// Standalone diagnostic entry point — NOT the production app, and NOT
// reachable through it. Built as a SEPARATE Flutter Web target (see
// .github/workflows/unzip-and-deploy.yml, the "Build diagnostic page"
// step, which invokes `flutter build web -t lib/main_diagnose.dart`
// into build/web/diagnose/) specifically so that adding this diagnostic
// requires zero changes to lib/main.dart, lib/ui/app.dart, or any
// production screen/route.
//
// Purpose: test #5 from the diagnostic request — the REAL Drift
// connection path — which cannot be exercised from a plain HTML/JS page
// (web/diagnose_database.html covers tests #1-#4/#6 instead) because it
// depends on compiled Dart code. This file therefore calls the exact
// same AppDatabase.open() / openConnection() used in production,
// unmodified, against the real 'app_db' database name (per the
// instruction not to alter connection_web.dart or fabricate a
// substitute path). To avoid touching any production table, every
// write here targets a uniquely-named temporary table that is dropped
// again in the final step; no Students/Tasks/etc. row is ever read,
// written, or migrated beyond drift's own normal schemaVersion check
// (which already runs on every real app launch regardless of this
// diagnostic).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:student_app/database/app_database.dart';

void main() {
  runApp(const _DiagnoseApp());
}

class _DiagnoseApp extends StatelessWidget {
  const _DiagnoseApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تشخيص اتصال Drift الحقيقي',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _DiagnoseScreen(),
    );
  }
}

class _Step {
  _Step(this.name);
  final String name;
  String status = 'لم يُنفّذ';
  String detail = '';
  int? elapsedMs;
}

class _DiagnoseScreen extends StatefulWidget {
  const _DiagnoseScreen();
  @override
  State<_DiagnoseScreen> createState() => _DiagnoseScreenState();
}

class _DiagnoseScreenState extends State<_DiagnoseScreen> {
  final List<_Step> _steps = [
    _Step('AppDatabase.open() — فتح الاتصال الحقيقي على app_db'),
    _Step('أول استعلام حقيقي (SELECT 1) — هنا يحدث التعليق الصامت إن وُجد'),
    _Step('CREATE TABLE (جدول اختبار مؤقت فريد الاسم)'),
    _Step('INSERT (إدراج صف اختبار)'),
    _Step('SELECT (قراءة الصف المُدرَج)'),
    _Step('DROP TABLE (حذف جدول الاختبار — تنظيف كامل)'),
  ];
  bool _running = true;
  bool _done = false;
  final List<String> _fullErrors = [];
  static const _table = 'drift_diagnostic_probe_tmp';

  @override
  void initState() {
    super.initState();
    _runAll();
  }

  Future<void> _step(int i, Future<void> Function() body,
      {Duration timeout = const Duration(seconds: 12)}) async {
    setState(() => _steps[i].status = 'جارٍ...');
    final sw = Stopwatch()..start();
    try {
      await body().timeout(timeout, onTimeout: () {
        throw TimeoutException(
            'انتهت المهلة (${timeout.inSeconds} ثوانٍ) دون أي استجابة.');
      });
      sw.stop();
      setState(() {
        _steps[i].status = 'نجاح';
        _steps[i].elapsedMs = sw.elapsedMilliseconds;
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _steps[i].status = 'فشل';
        _steps[i].elapsedMs = sw.elapsedMilliseconds;
        _steps[i].detail = '$e';
      });
      _fullErrors.add('${_steps[i].name}\n$e\n$st');
      rethrow;
    }
  }

  Future<void> _runAll() async {
    AppDatabase? db;
    try {
      await _step(0, () async {
        db = AppDatabase.open();
      });

      await _step(1, () async {
        await db!.customStatement('SELECT 1;');
      });

      await _step(2, () async {
        await db!.customStatement(
            'CREATE TABLE IF NOT EXISTS $_table (id INTEGER PRIMARY KEY, note TEXT);');
      });

      await _step(3, () async {
        await db!.customStatement(
            "INSERT INTO $_table (note) VALUES ('diagnostic-probe');");
      });

      await _step(4, () async {
        final rows = await db!.customSelect('SELECT * FROM $_table;').get();
        if (rows.isEmpty) {
          throw Exception('نجح الإدراج لكن القراءة أعادت صفوفًا فارغة.');
        }
      });

      await _step(5, () async {
        await db!.customStatement('DROP TABLE IF EXISTS $_table;');
      });
    } catch (_) {
      // Failure already recorded per-step above; stop the chain here so
      // later steps correctly stay at "لم يُنفّذ" instead of being
      // silently skipped without explanation.
    }

    setState(() {
      _running = false;
      _done = true;
    });
  }

  String _buildReport() {
    final b = StringBuffer();
    b.writeln('تقرير تشخيص اتصال Drift الحقيقي — DB-DIAG-CONN-001');
    b.writeln('الوقت: ${DateTime.now().toIso8601String()}');
    b.writeln('الرابط: ${Uri.base}');
    b.writeln('---');
    for (final s in _steps) {
      b.writeln(
          '${s.name}: ${s.status}${s.elapsedMs != null ? ' (${s.elapsedMs} ms)' : ''}');
      if (s.detail.isNotEmpty) b.writeln('   السبب: ${s.detail}');
    }
    if (_fullErrors.isNotEmpty) {
      b.writeln('---');
      b.writeln('تفاصيل كاملة للأخطاء (رسالة + مكدس البرمجي):');
      for (final e in _fullErrors) {
        b.writeln(e);
        b.writeln('...');
      }
    }
    return b.toString();
  }

  IconData _iconFor(String status) {
    switch (status) {
      case 'نجاح':
        return Icons.check_circle;
      case 'فشل':
        return Icons.cancel;
      case 'جارٍ...':
        return Icons.hourglass_top;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  Color _colorFor(String status) {
    switch (status) {
      case 'نجاح':
        return Colors.green;
      case 'فشل':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تشخيص اتصال Drift الحقيقي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_running) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          for (final s in _steps)
            Card(
              child: ListTile(
                leading: Icon(_iconFor(s.status), color: _colorFor(s.status)),
                title: Text(s.name),
                subtitle: Text(
                  s.status +
                      (s.elapsedMs != null ? ' — ${s.elapsedMs} ms' : '') +
                      (s.detail.isNotEmpty ? '\n${s.detail}' : ''),
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (_done)
            ElevatedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('نسخ تقرير التشخيص'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _buildReport()));
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
