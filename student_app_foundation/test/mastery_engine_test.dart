import 'package:test/test.dart';

import 'package:student_app/engines/mastery_engine.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment).
void main() {
  const engine = MasteryEngine();
  final params = BktParameters.defaults();

  group('bounds', () {
    test('probability and probabilityAfterEvidence always stay in [0, 1]',
        () {
      for (final prior in [0.0, 0.01, 0.3, 0.5, 0.99, 1.0]) {
        for (final correct in [true, false]) {
          final r = engine.compute(
            priorProbability: prior,
            correct: correct,
            params: params,
            priorObservationCount: 0,
          );
          expect(r.probability, inInclusiveRange(0.0, 1.0));
          expect(r.probabilityAfterEvidence, inInclusiveRange(0.0, 1.0));
        }
      }
    });

    test('confidence always stays in [0, 1]', () {
      final r = engine.compute(
        priorProbability: 0.5,
        correct: true,
        params: params,
        priorObservationCount: 1000,
      );
      expect(r.confidence, inInclusiveRange(0.0, 1.0));
    });
  });

  group('evidence direction', () {
    test('a correct answer raises probabilityAfterEvidence above the '
        'prior, for plausible (low-guess, low-slip) parameters', () {
      final r = engine.compute(
        priorProbability: 0.3,
        correct: true,
        params: params,
        priorObservationCount: 0,
      );
      expect(r.probabilityAfterEvidence, greaterThan(0.3));
    });

    test('an incorrect answer lowers probabilityAfterEvidence below the '
        'prior, for plausible parameters', () {
      final r = engine.compute(
        priorProbability: 0.5,
        correct: false,
        params: params,
        priorObservationCount: 0,
      );
      expect(r.probabilityAfterEvidence, lessThan(0.5));
    });

    test('the transition step never decreases probability relative to '
        'probabilityAfterEvidence (P(T) >= 0 by construction)', () {
      final r = engine.compute(
        priorProbability: 0.4,
        correct: false,
        params: params,
        priorObservationCount: 0,
      );
      expect(r.probability, greaterThanOrEqualTo(r.probabilityAfterEvidence));
    });
  });

  group('confidence, separate from accuracy', () {
    test('two runs landing on the same probability can have different '
        'confidence, driven purely by observationCount', () {
      final fewObservations = engine.compute(
        priorProbability: 0.5,
        correct: true,
        params: params,
        priorObservationCount: 0,
      );
      final manyObservations = engine.compute(
        priorProbability: 0.5,
        correct: true,
        params: params,
        priorObservationCount: 49,
      );
      // Same prior + same observation -> same probability, but very
      // different observationCount -> different confidence.
      expect(fewObservations.probability, manyObservations.probability);
      expect(manyObservations.confidence,
          greaterThan(fewObservations.confidence));
    });

    test('confidence approaches 1 as observationCount grows large', () {
      final r = engine.compute(
        priorProbability: 0.5,
        correct: true,
        params: params,
        priorObservationCount: 100000,
      );
      expect(r.confidence, greaterThan(0.99));
    });

    test('observationCount increments by exactly 1 per call', () {
      final r = engine.compute(
        priorProbability: 0.5,
        correct: true,
        params: params,
        priorObservationCount: 7,
      );
      expect(r.observationCount, 8);
    });
  });

  group('extreme priors do not produce NaN (division-by-zero guard)', () {
    test('prior 0.0 with a guess probability of 0.0 does not divide by '
        'zero', () {
      const zeroGuessParams = BktParameters(
        pTransition: 0.1,
        pGuess: 0.0,
        pSlip: 0.1,
        initialProbability: 0.0,
      );
      final r = engine.compute(
        priorProbability: 0.0,
        correct: true,
        params: zeroGuessParams,
        priorObservationCount: 0,
      );
      expect(r.probability.isNaN, isFalse);
      expect(r.probabilityAfterEvidence.isNaN, isFalse);
    });

    test('prior 1.0 with a slip probability of 0.0 does not divide by '
        'zero', () {
      const zeroSlipParams = BktParameters(
        pTransition: 0.1,
        pGuess: 0.2,
        pSlip: 0.0,
        initialProbability: 1.0,
      );
      final r = engine.compute(
        priorProbability: 1.0,
        correct: false,
        params: zeroSlipParams,
        priorObservationCount: 0,
      );
      expect(r.probability.isNaN, isFalse);
      expect(r.probabilityAfterEvidence.isNaN, isFalse);
    });
  });

  group('validation', () {
    test('throws on out-of-range priorProbability', () {
      expect(
          () => engine.compute(
                priorProbability: 1.5,
                correct: true,
                params: params,
                priorObservationCount: 0,
              ),
          throwsArgumentError);
    });

    test('throws on negative priorObservationCount', () {
      expect(
          () => engine.compute(
                priorProbability: 0.5,
                correct: true,
                params: params,
                priorObservationCount: -1,
              ),
          throwsArgumentError);
    });
  });
}
