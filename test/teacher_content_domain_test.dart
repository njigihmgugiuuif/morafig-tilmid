import 'package:test/test.dart';

import 'package:student_app/domain/teacher_content_domain.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
void main() {
  group('levels and badge', () {
    test('only 1, 2, 3 are internal levels', () {
      expect(isValidInternalLevel(1), isTrue);
      expect(isValidInternalLevel(2), isTrue);
      expect(isValidInternalLevel(3), isTrue);
      expect(isValidInternalLevel(0), isFalse);
      expect(isValidInternalLevel(4), isFalse);
      expect(isValidInternalLevel(null), isFalse);
      expect(kInternalLevels, [1, 2, 3]);
    });

    test('the badge text is the agreed one', () {
      expect(kTeacherBadge, 'أستاذ · غير رسمي');
    });
  });

  group('status path', () {
    test('allowed moves', () {
      expect(canTransition(LessonStatus.draft, LessonStatus.inReview), isTrue);
      expect(canTransition(LessonStatus.inReview, LessonStatus.published), isTrue);
      expect(canTransition(LessonStatus.inReview, LessonStatus.draft), isTrue);
      expect(canTransition(LessonStatus.published, LessonStatus.draft), isTrue);
    });
    test('refused moves', () {
      expect(canTransition(LessonStatus.draft, LessonStatus.published), isFalse);
      expect(canTransition(LessonStatus.published, LessonStatus.inReview), isFalse);
      for (final s in LessonStatus.values) {
        expect(canTransition(s, s), isFalse);
      }
    });
  });

  group('field validation', () {
    test('mandatory fields', () {
      final issues = validateLessonFields(
          title: ' ', subjectName: '', internalLevel: 5, teacherName: '');
      expect(issues.map((i) => i.code), containsAll([
        'title_required',
        'subject_required',
        'level_invalid',
        'teacher_required',
      ]));
      expect(
          validateLessonFields(
              title: 'ت', subjectName: 'م', internalLevel: 2, teacherName: 'أ'),
          isEmpty);
    });

    test('section is not part of validation (it never decides anything)', () {
      // validateLessonFields has no section parameter at all.
      expect(
          validateLessonFields(
              title: 'ت', subjectName: 'م', internalLevel: 1, teacherName: 'أ'),
          isEmpty);
    });
  });

  group('nodes', () {
    NodeDraft n(String k, String name,
            {int? from, int? to, String? req}) =>
        NodeDraft(key: k, name: name, pageFrom: from, pageTo: to, requiresKey: req);

    test('valid nodes pass', () {
      expect(
          validateNodes([n('a', 'أ', from: 1, to: 2), n('b', 'ب', req: 'a')], 4),
          isEmpty);
    });
    test('range outside pages / half range / reversed', () {
      expect(validateNodes([n('a', 'أ', from: 1, to: 9)], 4).single.code,
          'node_range_invalid');
      expect(validateNodes([n('a', 'أ', from: 1)], 4).single.code,
          'node_range_incomplete');
      expect(validateNodes([n('a', 'أ', from: 3, to: 2)], 4).single.code,
          'node_range_invalid');
    });
    test('duplicate and empty names', () {
      final codes =
          validateNodes([n('a', 'أ'), n('b', 'أ'), n('c', ' ')], 1).map((i) => i.code);
      expect(codes, containsAll(['node_name_duplicate', 'node_name_required']));
    });
    test('requires: self, missing, cycle', () {
      expect(validateNodes([n('a', 'أ', req: 'a')], 1).single.code,
          'node_requires_self');
      expect(validateNodes([n('a', 'أ', req: 'zzz')], 1).single.code,
          'node_requires_missing');
      final cyc = validateNodes([n('a', 'أ', req: 'b'), n('b', 'ب', req: 'a')], 1);
      expect(cyc.map((i) => i.code), contains('node_requires_cycle'));
    });
  });

  group('readiness for review', () {
    test('needs at least one page', () {
      final issues = readinessForReview(
          title: 'ت',
          subjectName: 'م',
          internalLevel: 1,
          teacherName: 'أ',
          pageCount: 0,
          nodes: const []);
      expect(issues.single.code, 'pages_required');
    });
  });

  group('images', () {
    test('format is read from the bytes', () {
      expect(sniffImageMime([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
      expect(sniffImageMime([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
          'image/png');
      expect(
          sniffImageMime([
            0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50
          ]),
          'image/webp');
      expect(sniffImageMime([1, 2, 3, 4]), isNull);
      expect(sniffImageMime(const []), isNull);
    });
  });

  group('helpers', () {
    test('movedItem moves and clamps', () {
      expect(movedItem([1, 2, 3], 0, 1), [2, 1, 3]);
      expect(movedItem([1, 2, 3], 2, -1), [1, 3, 2]);
      expect(movedItem([1, 2, 3], 0, -1), [1, 2, 3]);
      expect(movedItem([1, 2, 3], 2, 1), [1, 2, 3]);
    });
    test('formatBytes', () {
      expect(formatBytes(500), '500 ب');
      expect(formatBytes(2048), '2.0 ك.ب');
      expect(formatBytes(3 * 1024 * 1024), '3.0 م.ب');
    });
  });
}
