import 'package:test/test.dart';

import 'package:student_app/engines/priority_engine.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment).
void main() {
  const engine = PriorityEngine();

  const allSignalsMax = PrioritySignals(
    officialCoefficient: 1.0,
    learningPriority: 1.0,
    examPriority: 1.0,
    personalWeakness: 1.0,
    forgettingRisk: 1.0,
    urgencyImportance: 1.0,
  );

  const allSignalsZero = PrioritySignals(
    officialCoefficient: 0.0,
    learningPriority: 0.0,
    examPriority: 0.0,
    personalWeakness: 0.0,
    forgettingRisk: 0.0,
    urgencyImportance: 0.0,
  );

  group('compute() — bounds', () {
    test('all-1.0 signals with default weights -> score 1.0', () {
      final r = engine.compute(signals: allSignalsMax);
      expect(r.score, closeTo(1.0, 1e-9));
    });

    test('all-0.0 signals with default weights -> score 0.0', () {
      final r = engine.compute(signals: allSignalsZero);
      expect(r.score, closeTo(0.0, 1e-9));
    });

    test('default weights sum to 1.0', () {
      expect(PriorityWeights.defaults().sum, closeTo(1.0, 1e-9));
    });
  });

  group('null-signal exclusion + renormalization', () {
    test('a null signal is excluded, not treated as 0', () {
      const onlyOneKnown = PrioritySignals(
        officialCoefficient: 1.0,
        learningPriority: null,
        examPriority: null,
        personalWeakness: null,
        forgettingRisk: null,
        urgencyImportance: null,
      );
      final r = engine.compute(signals: onlyOneKnown);
      // The single known signal is 1.0 and, after renormalization, carries
      // 100% of the weight -> score must be 1.0, not diluted toward 0 by
      // the five unknown signals.
      expect(r.score, closeTo(1.0, 1e-9));
    });

    test('weightsUsed only contains kinds with non-null signals, and '
        'sums to 1.0', () {
      const partial = PrioritySignals(
        officialCoefficient: 0.5,
        learningPriority: 0.5,
        examPriority: null,
        personalWeakness: null,
        forgettingRisk: null,
        urgencyImportance: null,
      );
      final r = engine.compute(signals: partial);
      expect(r.weightsUsed.keys, containsAll([
        PrioritySignalKind.officialCoefficient,
        PrioritySignalKind.learningPriority,
      ]));
      expect(r.weightsUsed.keys.length, 2);
      final sum = r.weightsUsed.values.fold(0.0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('throws when every signal is null — nothing to score', () {
      const none = PrioritySignals(
        officialCoefficient: null,
        learningPriority: null,
        examPriority: null,
        personalWeakness: null,
        forgettingRisk: null,
        urgencyImportance: null,
      );
      expect(() => engine.compute(signals: none), throwsArgumentError);
    });
  });

  group('caller-supplied weights', () {
    test('weights not summing to 1.0 are renormalized, not rejected', () {
      final skewed = PriorityWeights({
        PrioritySignalKind.officialCoefficient: 2.0,
        PrioritySignalKind.learningPriority: 2.0,
        PrioritySignalKind.examPriority: 2.0,
        PrioritySignalKind.personalWeakness: 2.0,
        PrioritySignalKind.forgettingRisk: 2.0,
        PrioritySignalKind.urgencyImportance: 2.0,
      });
      final r = engine.compute(signals: allSignalsMax, weights: skewed);
      expect(r.score, closeTo(1.0, 1e-9));
      expect(r.usedFallbackWeights, isFalse);
    });

    test('all-zero weights fall back to defaults rather than dividing by '
        'zero', () {
      final zeroWeights = PriorityWeights({
        for (final k in PrioritySignalKind.values) k: 0.0,
      });
      final r = engine.compute(signals: allSignalsMax, weights: zeroWeights);
      expect(r.usedFallbackWeights, isTrue);
      expect(r.score, closeTo(1.0, 1e-9));
    });
  });

  group('confidenceValue', () {
    test('confidenceValue is the fraction of non-null signals', () {
      const half = PrioritySignals(
        officialCoefficient: 0.5,
        learningPriority: 0.5,
        examPriority: 0.5,
        personalWeakness: null,
        forgettingRisk: null,
        urgencyImportance: null,
      );
      final r = engine.compute(signals: half);
      expect(r.confidenceValue, closeTo(0.5, 1e-9));
    });

    test('full signals -> confidenceValue 1.0', () {
      final r = engine.compute(signals: allSignalsMax);
      expect(r.confidenceValue, closeTo(1.0, 1e-9));
    });
  });
}
