import 'package:test/test.dart';

import 'package:student_app/domain/examination_domain.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment). Only the pure
/// `examPrioritySignal` static method is tested — `daysUntilNearestExam`
/// requires a real database and is a Track D/E integration-test concern.
void main() {
  group('examPrioritySignal()', () {
    test('null daysUntilExam -> null signal, never a fabricated urgency',
        () {
      expect(ExaminationDomainService.examPrioritySignal(null), isNull);
    });

    test('exam day itself (0 days) -> signal 1.0', () {
      expect(ExaminationDomainService.examPrioritySignal(0), 1.0);
    });

    test('negative daysUntilExam (an exam that already started/passed) '
        'still saturates at 1.0, not an error', () {
      expect(ExaminationDomainService.examPrioritySignal(-1), 1.0);
    });

    test('at or beyond the horizon -> signal 0.0', () {
      expect(
          ExaminationDomainService.examPrioritySignal(21, horizonDays: 21),
          0.0);
      expect(
          ExaminationDomainService.examPrioritySignal(100, horizonDays: 21),
          0.0);
    });

    test('signal decreases monotonically as daysUntilExam increases', () {
      final near = ExaminationDomainService.examPrioritySignal(2, horizonDays: 21)!;
      final far = ExaminationDomainService.examPrioritySignal(15, horizonDays: 21)!;
      expect(near, greaterThan(far));
    });

    test('signal always stays within [0, 1]', () {
      for (final d in [-5, 0, 1, 10, 20, 21, 50]) {
        final s = ExaminationDomainService.examPrioritySignal(d, horizonDays: 21)!;
        expect(s, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
