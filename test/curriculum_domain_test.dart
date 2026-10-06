import 'package:test/test.dart';

import 'package:student_app/domain/curriculum_domain.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment). Only the pure
/// `normalizeCoefficient` static method is tested here — the async
/// `officialCoefficientSignal` method requires a real database and is a
/// Track D/E integration-test concern, not this cycle's.
void main() {
  group('normalizeCoefficient()', () {
    test('coefficient at the ceiling normalizes to 1.0', () {
      expect(CurriculumDomainService.normalizeCoefficient(7.0, 7.0), 1.0);
    });

    test('coefficient at zero normalizes to 0.0', () {
      expect(CurriculumDomainService.normalizeCoefficient(0.0, 7.0), 0.0);
    });

    test('coefficient above the ceiling is clamped to 1.0, never exceeds '
        'it', () {
      expect(CurriculumDomainService.normalizeCoefficient(10.0, 7.0), 1.0);
    });

    test('mid-range coefficient normalizes proportionally', () {
      expect(
          CurriculumDomainService.normalizeCoefficient(3.5, 7.0), closeTo(0.5, 1e-9));
    });

    test('throws when the caller-supplied ceiling is not positive', () {
      expect(() => CurriculumDomainService.normalizeCoefficient(1.0, 0.0),
          throwsArgumentError);
      expect(() => CurriculumDomainService.normalizeCoefficient(1.0, -3.0),
          throwsArgumentError);
    });
  });

  // A-1 (DEVIATION-21). Synthetic numbers only; none is an official value.
  group('normalizeAgainstStreamMax() — pure', () {
    test('the highest usable coefficient of the stream maps to 1.0', () {
      expect(
        CurriculumDomainService.normalizeAgainstStreamMax(
            coefficient: 5.0, usableCoefficients: [5.0, 3.0, 2.0]),
        closeTo(1.0, 1e-12),
      );
    });

    test('other coefficients are proportional to the highest', () {
      expect(
        CurriculumDomainService.normalizeAgainstStreamMax(
            coefficient: 3.0, usableCoefficients: [6.0, 3.0]),
        closeTo(0.5, 1e-12),
      );
    });

    test('the ceiling comes from the data, not from an assumed number', () {
      // 10 / 20 = 0.5: a hard-coded ceiling such as 7 would give 1.0.
      expect(
        CurriculumDomainService.normalizeAgainstStreamMax(
            coefficient: 10.0, usableCoefficients: [10.0, 20.0]),
        closeTo(0.5, 1e-12),
      );
    });

    test('fewer than two usable loads -> null, never 1.0', () {
      expect(CurriculumDomainService.minimumUsableLoads, 2);
      expect(
        CurriculumDomainService.normalizeAgainstStreamMax(
            coefficient: 5.0, usableCoefficients: [5.0]),
        isNull,
      );
      expect(
        CurriculumDomainService.normalizeAgainstStreamMax(
            coefficient: 5.0, usableCoefficients: []),
        isNull,
      );
    });

    test('zero or negative entries do not count as usable loads', () {
      expect(
        CurriculumDomainService.normalizeAgainstStreamMax(
            coefficient: 5.0, usableCoefficients: [5.0, 0.0, -1.0]),
        isNull,
      );
    });

    test('the subject\'s own coefficient null, zero or negative -> null', () {
      expect(
        CurriculumDomainService.normalizeAgainstStreamMax(
            coefficient: null, usableCoefficients: [5.0, 3.0]),
        isNull,
      );
      expect(
        CurriculumDomainService.normalizeAgainstStreamMax(
            coefficient: 0.0, usableCoefficients: [5.0, 3.0]),
        isNull,
      );
      expect(
        CurriculumDomainService.normalizeAgainstStreamMax(
            coefficient: -2.0, usableCoefficients: [5.0, 3.0]),
        isNull,
      );
    });
  });
}
