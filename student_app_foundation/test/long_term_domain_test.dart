import 'package:test/test.dart';

import 'package:student_app/domain/long_term_domain.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment). Only the pure
/// `classifyHorizon` static method is tested — `hasUpcomingBacExam`
/// requires a real database and is a Track D/E integration-test concern.
void main() {
  final now = DateTime(2026, 9, 25);

  group('classifyHorizon()', () {
    test('an exam this week classifies as immediate', () {
      expect(
        LongTermDomainService.classifyHorizon(
            now: now, examDate: now.add(const Duration(days: 3))),
        AcademicHorizon.immediate,
      );
    });

    test('an exam in three weeks classifies as thisMonth', () {
      expect(
        LongTermDomainService.classifyHorizon(
            now: now, examDate: now.add(const Duration(days: 20))),
        AcademicHorizon.thisMonth,
      );
    });

    test('an exam in two months classifies as thisTerm', () {
      expect(
        LongTermDomainService.classifyHorizon(
            now: now, examDate: now.add(const Duration(days: 60))),
        AcademicHorizon.thisTerm,
      );
    });

    test('an exam six months out classifies as fullYear', () {
      expect(
        LongTermDomainService.classifyHorizon(
            now: now, examDate: now.add(const Duration(days: 180))),
        AcademicHorizon.fullYear,
      );
    });

    test('boundaries are inclusive on the near side (<=7, <=30, <=120)',
        () {
      expect(
        LongTermDomainService.classifyHorizon(
            now: now, examDate: now.add(const Duration(days: 7))),
        AcademicHorizon.immediate,
      );
      expect(
        LongTermDomainService.classifyHorizon(
            now: now, examDate: now.add(const Duration(days: 30))),
        AcademicHorizon.thisMonth,
      );
      expect(
        LongTermDomainService.classifyHorizon(
            now: now, examDate: now.add(const Duration(days: 120))),
        AcademicHorizon.thisTerm,
      );
    });
  });
}
