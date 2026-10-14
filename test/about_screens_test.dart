import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:student_app/ui/screens/about_screen.dart';
import 'package:student_app/ui/screens/constitution_screen.dart';
import 'package:student_app/ui/theme/app_theme.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      builder: (context, c) =>
          Directionality(textDirection: TextDirection.rtl, child: c!),
      home: child,
    );

void main() {
  test('the constitution has eight articles, each with text', () {
    expect(ConstitutionScreen.articles.length, 8);
    for (final a in ConstitutionScreen.articles) {
      expect(a.$2.trim(), isNotEmpty);
      expect(a.$3.trim().length, greaterThan(20));
    }
  });

  testWidgets('constitution screen shows its title and first article',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    await tester.pumpWidget(_host(const ConstitutionScreen()));
    expect(find.text('دستور التطبيق'), findsWidgets);
    expect(find.textContaining('بياناتك لك'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('constitution introduces the app and states the AI model as a '
      'future plan', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 3600));
    await tester.pumpWidget(_host(const ConstitutionScreen()));
    expect(find.text('مرافق التلميذ'), findsWidgets);
    expect(find.text(ConstitutionScreen.aiTitle), findsOneWidget);
    expect(find.textContaining('لم يُنجَز بعد'), findsOneWidget);
    await tester.tap(find.text('عن التطبيق'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('about screen says what the app is and is not, and opens the '
      'constitution', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    await tester.pumpWidget(_host(const AboutScreen()));
    expect(find.text('مرافق التلميذ'), findsWidgets);
    expect(find.textContaining('ليس تطبيقًا رسميًا'), findsOneWidget);
    await tester.tap(find.text('دستور التطبيق'));
    await tester.pumpAndSettle();
    expect(find.byType(ConstitutionScreen), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
