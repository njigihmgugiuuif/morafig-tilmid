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
}
