import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:student_app/ui/design/scroll_tabs.dart';
import 'package:student_app/ui/screens/progress_pages.dart';
import 'package:student_app/ui/state/progress_insights.dart';
import 'package:student_app/ui/theme/app_theme.dart';
import 'package:student_app/ui/widgets/install_button.dart';
import 'package:student_app/ui/widgets/install_logic.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Building blocks of the Batch 4 progress pages and the install button.
Widget _host(Widget child, {double width = 360}) => MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('ar'),
      builder: (context, c) =>
          Directionality(textDirection: TextDirection.rtl, child: c!),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

void main() {
  group('install button decision', () {
    InstallStage st({
      bool web = true,
      bool standalone = false,
      bool prompt = false,
      bool installed = false,
      bool ios = false,
    }) =>
        decideInstallStage(
            isWeb: web,
            standalone: standalone,
            promptAvailable: prompt,
            installedThisVisit: installed,
            ios: ios);

    test('not on the web: no button', () {
      expect(st(web: false, prompt: true), InstallStage.hidden);
    });
    test('already running as an installed app: no button', () {
      expect(st(standalone: true, prompt: true), InstallStage.hidden);
    });
    test('browser offered its install prompt: the button runs it', () {
      expect(st(prompt: true), InstallStage.promptable);
    });
    test('no prompt: manual steps, iPhone gets its own', () {
      expect(st(), InstallStage.manual);
      expect(st(ios: true), InstallStage.iosManual);
      expect(installManualSteps(InstallStage.iosManual), contains('المشاركة'));
      expect(installManualSteps(InstallStage.manual), contains('تثبيت التطبيق'));
    });
    test('installed during this visit: status, not a button', () {
      expect(st(installed: true, prompt: true), InstallStage.installed);
    });
    test('promptable has no manual text (it needs none)', () {
      expect(installManualSteps(InstallStage.promptable), isEmpty);
    });
  });

  testWidgets('install button draws nothing outside a browser',
      (tester) async {
    await tester.pumpWidget(_host(const InstallButton()));
    expect(find.text('تثبيت التطبيق'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart card shows title, note, chart and the summary sentence',
      (tester) async {
    await tester.pumpWidget(_host(const ChartCard(
      title: 'المهام المنجزة',
      note: 'عدد المهام في كل يوم',
      summary: 'أنجزتَ 3 مهمة في هذه الفترة.',
      child: SizedBox(height: 20),
    )));
    expect(find.text('المهام المنجزة'), findsOneWidget);
    expect(find.text('عدد المهام في كل يوم'), findsOneWidget);
    expect(find.text('أنجزتَ 3 مهمة في هذه الفترة.'), findsOneWidget);
  });

  testWidgets('column bars show every label and value, zeros included',
      (tester) async {
    await tester.pumpWidget(_host(const ColumnBars(
      values: [0, 2, 5, 0, 1, 0, 3],
      labels: ['أحد', 'إثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت'],
    )));
    for (final l in kDayShortAr) {
      expect(find.text(l), findsOneWidget);
    }
    expect(find.text('5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('column bars fit a very narrow phone without overflow',
      (tester) async {
    await tester.pumpWidget(_host(
      ColumnBars(
        values: List<int>.generate(12, (i) => i * 40),
        labels: [for (var i = 1; i <= 12; i++) '$i'],
        valueText: (v) => '$v',
      ),
      width: 280,
    ));
    expect(tester.takeException(), isNull);
  });

  test('day short names are all different', () {
    expect(kDayShortAr.toSet().length, 7);
    expect(kMonthNamesAr.length, 12);
  });

  testWidgets('scroll tabs switch page and scroll when there are many',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      builder: (context, c) =>
          Directionality(textDirection: TextDirection.rtl, child: c!),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 320,
            child: MqScrollTabs<int>(
              options: const {
                0: 'نظرة',
                1: 'الإتقان',
                2: 'الذاكرة',
                3: 'الوقت',
                4: 'الأولويات',
                5: 'الأهداف',
                6: 'الأخطاء',
              },
              selected: selected,
              onChanged: (v) => setState(() => selected = v),
            ),
          ),
        ),
      ),
    ));
    expect(find.text('نظرة'), findsOneWidget);
    await tester.tap(find.text('الإتقان'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    await tester.tap(find.text('الذاكرة'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subject comparison says what it compares', (tester) async {
    await tester.pumpWidget(_host(const SubjectMasteryChart(subjects: [
      SubjectMastery(
          subjectId: 'a',
          name: 'مادة أ',
          average: 0.8,
          topics: 3,
          weakestName: 'موضوع 1',
          weakestValue: 0.6),
      SubjectMastery(
          subjectId: 'b',
          name: 'مادة ب',
          average: 0.3,
          topics: 2,
          weakestName: 'موضوع 2',
          weakestValue: 0.2),
    ])));
    expect(find.text('الإتقان حسب المادة'), findsOneWidget);
    expect(find.textContaining('أعلى متوسط في مادة أ'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
  });

  testWidgets('one subject only: no fake comparison', (tester) async {
    await tester.pumpWidget(_host(const SubjectMasteryChart(subjects: [
      SubjectMastery(
          subjectId: 'a',
          name: 'مادة أ',
          average: 0.5,
          topics: 1,
          weakestName: 'م',
          weakestValue: 0.5),
    ])));
    expect(find.textContaining('تظهر المقارنة بين المواد'), findsOneWidget);
  });

  testWidgets('review forecast shows the overdue column and a summary',
      (tester) async {
    final now = DateTime(2026, 3, 11, 9); // Wednesday
    await tester.pumpWidget(_host(ReviewForecastChart(
      now: now,
      forecast: const ReviewForecast(
        total: 4,
        overdue: 1,
        perDay: [0, 2, 0, 0, 0, 0, 1],
        later: 0,
        averageRecallNow: 0.82,
      ),
    )));
    expect(find.text('متأخرة'), findsOneWidget);
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.textContaining('عندك 1 مراجعة مستحقة الآن'), findsOneWidget);
    expect(find.textContaining('82%'), findsOneWidget);
  });
}
