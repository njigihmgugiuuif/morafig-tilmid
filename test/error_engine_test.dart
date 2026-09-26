import 'package:test/test.dart';

import 'package:student_app/engines/error_engine.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment). Property tests, same style as
/// test/memory_engine_test.dart.
void main() {
  const engine = ErrorEngine();

  group('compute() — empty/no evidence', () {
    test('no observations -> signal 0, no flags', () {
      final r = engine.compute(const []);
      expect(r.signal, 0.0);
      expect(r.prerequisiteRiskFlag, isFalse);
      expect(r.conceptualRiskFlag, isFalse);
      expect(r.observationCount, 0);
    });
  });

  group('compute() — bounds and monotonicity', () {
    test('signal always stays within the 0-to-1 range, never reaching 1',
        () {
      final many = List.generate(
          50,
          (i) => ErrorObservation(
              kind: ErrorKind.missingPrerequisite, daysAgo: 0.0));
      final r = engine.compute(many);
      expect(r.signal, greaterThanOrEqualTo(0.0));
      expect(r.signal, lessThan(1.0));
    });

    test('more recent errors produce a higher signal than older ones, '
        'for the same count/type', () {
      final recent = engine.compute(const [
        ErrorObservation(kind: ErrorKind.conceptual, daysAgo: 0.0),
      ]);
      final old = engine.compute(const [
        ErrorObservation(kind: ErrorKind.conceptual, daysAgo: 60.0),
      ]);
      expect(recent.signal, greaterThan(old.signal));
    });

    test('more errors never decreases the signal', () {
      final one = engine.compute(const [
        ErrorObservation(kind: ErrorKind.careless, daysAgo: 1.0),
      ]);
      final two = engine.compute(const [
        ErrorObservation(kind: ErrorKind.careless, daysAgo: 1.0),
        ErrorObservation(kind: ErrorKind.careless, daysAgo: 1.0),
      ]);
      expect(two.signal, greaterThanOrEqualTo(one.signal));
    });

    test('a missingPrerequisite error contributes at least as much as a '
        'careless one at the same recency, by construction of the '
        'default weights', () {
      final careless = engine.compute(const [
        ErrorObservation(kind: ErrorKind.careless, daysAgo: 0.0),
      ]);
      final missing = engine.compute(const [
        ErrorObservation(kind: ErrorKind.missingPrerequisite, daysAgo: 0.0),
      ]);
      expect(missing.signal, greaterThan(careless.signal));
    });
  });

  group('risk flags', () {
    test('prerequisiteRiskFlag set once missingPrerequisite count meets '
        'the threshold', () {
      final belowThreshold = engine.compute(const [
        ErrorObservation(kind: ErrorKind.missingPrerequisite, daysAgo: 0.0),
      ]);
      expect(belowThreshold.prerequisiteRiskFlag, isFalse);

      final atThreshold = engine.compute(const [
        ErrorObservation(kind: ErrorKind.missingPrerequisite, daysAgo: 0.0),
        ErrorObservation(kind: ErrorKind.missingPrerequisite, daysAgo: 1.0),
      ]);
      expect(atThreshold.prerequisiteRiskFlag, isTrue);
    });

    test('conceptualRiskFlag ignores careless/missingPrerequisite errors',
        () {
      final r = engine.compute(const [
        ErrorObservation(kind: ErrorKind.careless, daysAgo: 0.0),
        ErrorObservation(kind: ErrorKind.careless, daysAgo: 0.0),
        ErrorObservation(kind: ErrorKind.careless, daysAgo: 0.0),
      ]);
      expect(r.conceptualRiskFlag, isFalse);
    });

    test('counts map reflects exact per-kind occurrences', () {
      final r = engine.compute(const [
        ErrorObservation(kind: ErrorKind.careless, daysAgo: 0.0),
        ErrorObservation(kind: ErrorKind.careless, daysAgo: 3.0),
        ErrorObservation(kind: ErrorKind.conceptual, daysAgo: 1.0),
      ]);
      expect(r.counts[ErrorKind.careless], 2);
      expect(r.counts[ErrorKind.conceptual], 1);
      expect(r.counts[ErrorKind.missingPrerequisite], 0);
    });
  });

  group('validation', () {
    test('throws on negative daysAgo', () {
      expect(
          () => engine.compute(const [
                ErrorObservation(kind: ErrorKind.careless, daysAgo: -1.0),
              ]),
          throwsArgumentError);
    });
  });
}
