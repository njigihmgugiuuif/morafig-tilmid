import 'package:test/test.dart';

import 'package:student_app/engines/priority_engine.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment).
void main() {
  const engine = PriorityEngine();

  const allSignalsMax = PrioritySignals(
    officialCoefficient: 1.0,
    longTermGoalAlignment: 1.0,
    examProximity: 1.0,
    masteryGap: 1.0,
    forgettingRisk: 1.0,
    deadlinePressure: 1.0,
  );

  const allSignalsZero = PrioritySignals(
    officialCoefficient: 0.0,
    longTermGoalAlignment: 0.0,
    examProximity: 0.0,
    masteryGap: 0.0,
    forgettingRisk: 0.0,
    deadlinePressure: 0.0,
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
        longTermGoalAlignment: null,
        examProximity: null,
        masteryGap: null,
        forgettingRisk: null,
        deadlinePressure: null,
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
        longTermGoalAlignment: 0.5,
        examProximity: null,
        masteryGap: null,
        forgettingRisk: null,
        deadlinePressure: null,
      );
      final r = engine.compute(signals: partial);
      expect(r.weightsUsed.keys, containsAll([
        PrioritySignalKind.officialCoefficient,
        PrioritySignalKind.longTermGoalAlignment,
      ]));
      expect(r.weightsUsed.keys.length, 2);
      final sum = r.weightsUsed.values.fold(0.0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('throws when every signal is null — nothing to score', () {
      const none = PrioritySignals(
        officialCoefficient: null,
        longTermGoalAlignment: null,
        examProximity: null,
        masteryGap: null,
        forgettingRisk: null,
        deadlinePressure: null,
      );
      expect(() => engine.compute(signals: none), throwsArgumentError);
    });
  });

  group('caller-supplied weights', () {
    test('weights not summing to 1.0 are renormalized, not rejected', () {
      final skewed = PriorityWeights({
        PrioritySignalKind.officialCoefficient: 2.0,
        PrioritySignalKind.longTermGoalAlignment: 2.0,
        PrioritySignalKind.examProximity: 2.0,
        PrioritySignalKind.masteryGap: 2.0,
        PrioritySignalKind.forgettingRisk: 2.0,
        PrioritySignalKind.deadlinePressure: 2.0,
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
        longTermGoalAlignment: 0.5,
        examProximity: 0.5,
        masteryGap: null,
        forgettingRisk: null,
        deadlinePressure: null,
      );
      final r = engine.compute(signals: half);
      expect(r.confidenceValue, closeTo(0.5, 1e-9));
    });

    test('full signals -> confidenceValue 1.0', () {
      final r = engine.compute(signals: allSignalsMax);
      expect(r.confidenceValue, closeTo(1.0, 1e-9));
    });
  });

  group('A-0: approved signal set, initial weights, legacy names', () {
    test('default weights are exactly the approved initial values', () {
      final w = PriorityWeights.defaults();
      expect(w[PrioritySignalKind.masteryGap], closeTo(0.30, 1e-12));
      expect(w[PrioritySignalKind.forgettingRisk], closeTo(0.20, 1e-12));
      expect(w[PrioritySignalKind.officialCoefficient], closeTo(0.20, 1e-12));
      expect(w[PrioritySignalKind.examProximity], closeTo(0.15, 1e-12));
      expect(w[PrioritySignalKind.deadlinePressure], closeTo(0.10, 1e-12));
      expect(
          w[PrioritySignalKind.longTermGoalAlignment], closeTo(0.05, 1e-12));
      expect(w.sum, closeTo(1.0, 1e-12));
    });

    test('the signal set is exactly the six approved names', () {
      expect(
        PrioritySignalKind.values.map((k) => k.name).toSet(),
        {
          'masteryGap',
          'forgettingRisk',
          'officialCoefficient',
          'examProximity',
          'deadlinePressure',
          'longTermGoalAlignment',
        },
      );
    });

    test('three live signals renormalise to 0.46 / 0.31 / 0.23', () {
      const live = PrioritySignals(
        masteryGap: 0.62,
        forgettingRisk: 0.48,
        officialCoefficient: null,
        examProximity: 0.76,
        deadlinePressure: null,
        longTermGoalAlignment: null,
      );
      final r = engine.compute(signals: live);
      expect(r.weightsUsed[PrioritySignalKind.masteryGap],
          closeTo(0.30 / 0.65, 1e-9));
      expect(r.weightsUsed[PrioritySignalKind.forgettingRisk],
          closeTo(0.20 / 0.65, 1e-9));
      expect(r.weightsUsed[PrioritySignalKind.examProximity],
          closeTo(0.15 / 0.65, 1e-9));
      expect(r.score, closeTo(0.6092, 0.001));
      expect(r.confidenceValue, closeTo(0.5, 1e-9));
    });

    test('legacy stored names map to the current names, new names pass '
        'through, unknown names stay unknown', () {
      expect(canonicalPrioritySignalName('personalWeakness'), 'masteryGap');
      expect(canonicalPrioritySignalName('examPriority'), 'examProximity');
      expect(
          canonicalPrioritySignalName('urgencyImportance'), 'deadlinePressure');
      expect(canonicalPrioritySignalName('learningPriority'),
          'longTermGoalAlignment');
      expect(canonicalPrioritySignalName('forgettingRisk'), 'forgettingRisk');
      expect(canonicalPrioritySignalName('officialCoefficient'),
          'officialCoefficient');
      expect(prioritySignalKindFromStoredName('personalWeakness'),
          PrioritySignalKind.masteryGap);
      expect(prioritySignalKindFromStoredName('masteryGap'),
          PrioritySignalKind.masteryGap);
      expect(prioritySignalKindFromStoredName('somethingElse'), isNull);
    });
  });
}
