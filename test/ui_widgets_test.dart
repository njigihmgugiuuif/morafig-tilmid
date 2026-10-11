import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:student_app/ui/design/charts.dart';
import 'package:student_app/ui/theme/app_theme.dart';
import 'package:student_app/ui/widgets/unsaved_changes_scope.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Widget checks for the shared building blocks of the final UI: the charts
/// draw without errors (also with no data) and the unsaved-changes guard asks
/// before closing a form that has changes.
Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('ar'),
      builder: (context, c) =>
          Directionality(textDirection: TextDirection.rtl, child: c!),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('line chart draws a curve with a marker and a threshold',
      (tester) async {
    await tester.pumpWidget(_host(const MqLineChart(
      points: [MqPoint(0, 1), MqPoint(5, 0.8), MqPoint(10, 0.6)],
      markers: [MqMarker(4, 'الآن')],
      threshold: 0.9,
      thresholdLabel: '٩٠٪',
      startLabel: 'بداية',
      endLabel: 'نهاية',
    )));
    expect(tester.takeException(), isNull);
    expect(find.text('بداية'), findsOneWidget);
    expect(find.text('نهاية'), findsOneWidget);
  });

  testWidgets('line chart with no points draws only the frame',
      (tester) async {
    await tester.pumpWidget(_host(const MqLineChart(
        points: [], startLabel: 'أ', endLabel: 'ب')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paired bars show every row label and both legends',
      (tester) async {
    await tester.pumpWidget(_host(const MqPairedBars(
      rows: [MqPairRow('الرياضيات', 60, 45), MqPairRow('الفيزياء', 30, 0)],
      firstLabel: 'المخطَّط',
      secondLabel: 'الفعلي',
    )));
    expect(find.text('الرياضيات'), findsOneWidget);
    expect(find.text('الفيزياء'), findsOneWidget);
    expect(find.text('المخطَّط'), findsOneWidget);
    expect(find.text('الفعلي'), findsOneWidget);
  });

  testWidgets('segment bar tolerates a zero total', (tester) async {
    await tester.pumpWidget(_host(const MqSegmentBar(segments: [
      (0.0, Colors.green),
      (0.0, Colors.grey),
    ])));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsaved changes: back asks first, and "ignore" leaves',
      (tester) async {
    var dirty = true;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => UnsavedChangesScope(
                    isDirty: () => dirty,
                    child: const Scaffold(body: Text('النموذج')),
                  ),
                ),
              ),
              child: const Text('افتح'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
    expect(find.text('النموذج'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('تجاهل التغييرات؟'), findsOneWidget);
    expect(find.text('النموذج'), findsOneWidget);

    await tester.tap(find.text('تجاهل وخروج'));
    await tester.pumpAndSettle();
    expect(find.text('النموذج'), findsNothing);
  });

  testWidgets('unsaved changes: with nothing changed, back closes at once',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => UnsavedChangesScope(
                    isDirty: () => false,
                    child: const Scaffold(body: Text('النموذج')),
                  ),
                ),
              ),
              child: const Text('افتح'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('النموذج'), findsNothing);
    expect(find.text('تجاهل التغييرات؟'), findsNothing);
  });
}
