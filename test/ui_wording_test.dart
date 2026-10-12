import 'dart:io';

import 'package:test/test.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Plain-Arabic rule: technical words the student or teacher would not use
/// must not appear in any text shown on screen. Comments are not shown, so
/// they are ignored; only code lines are scanned.
void main() {
  const banned = <String>[
    'حزمة',
    'الحزمة',
    'استيراد',
    'استورد',
    'مستورد',
    'تصدير',
    'صدّر',
    'صُدّر',
    'يُصدَّر',
    'بصمة',
    'البصمة',
    'PWA',
  ];

  test('no screen text uses the technical words the school asked to drop', () {
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      var n = 0;
      for (final raw in f.readAsLinesSync()) {
        n++;
        final trimmed = raw.trimLeft();
        if (trimmed.startsWith('//')) continue;
        final cut = raw.indexOf(RegExp(r'\s//'));
        final line = cut >= 0 ? raw.substring(0, cut) : raw;
        for (final w in banned) {
          if (line.contains(w)) hits.add('${f.path}:$n «$w»');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
