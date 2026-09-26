import 'package:test/test.dart';

import 'package:student_app/engines/emergency_engine.dart';
import 'package:student_app/engines/priority_engine.dart';
import 'package:student_app/engines/workload_engine.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment).
void main() {
  const engine = EmergencyModeEngine();

  group('evaluate()', () {
    test('workloadImpossible overrides/takes priority over exam '
        'proximity when both are true', () {
      final e = engine.evaluate(
        daysUntilNearestExam: 1,
        currentWorkloadStatus: WorkloadClassification.impossible,
      );
      expect(e.triggered, isTrue);
      expect(e.trigger, EmergencyTriggerKind.workloadImpossible);
    });

    test('exam within the proximity window triggers examProximity', () {
      final e = engine.evaluate(
        daysUntilNearestExam: 2,
        currentWorkloadStatus: WorkloadClassification.balanced,
      );
      expect(e.triggered, isTrue);
      expect(e.trigger, EmergencyTriggerKind.examProximity);
    });

    test('exam beyond the proximity window, normal workload -> not '
        'triggered', () {
      final e = engine.evaluate(
        daysUntilNearestExam: 30,
        currentWorkloadStatus: WorkloadClassification.balanced,
      );
      expect(e.triggered, isFalse);
      expect(e.trigger, isNull);
    });

    test('null exam date, normal workload -> not triggered', () {
      final e = engine.evaluate(
        daysUntilNearestExam: null,
        currentWorkloadStatus: WorkloadClassification.underload,
      );
      expect(e.triggered, isFalse);
    });
  });

  group('adjustPriorityWeights() — weights only, always still valid '
      'after renormalization', () {
    test('examProximity boosts examPriority weight above the others, and '
        'the result still renormalizes to a valid score via '
        'PriorityEngine', () {
      final base = PriorityWeights.defaults();
      final boosted =
          engine.adjustPriorityWeights(base, EmergencyTriggerKind.examProximity);

      expect(boosted[PrioritySignalKind.examPriority],
          greaterThan(base[PrioritySignalKind.examPriority]));
      // Every other weight is untouched.
      expect(boosted[PrioritySignalKind.officialCoefficient],
          base[PrioritySignalKind.officialCoefficient]);

      // The boosted weights still work end-to-end through the real
      // renormalization contract in priority_engine.dart — this file
      // does not duplicate that logic.
      const signals = PrioritySignals(
        officialCoefficient: 0.5,
        learningPriority: 0.5,
        examPriority: 1.0,
        personalWeakness: 0.5,
        forgettingRisk: 0.5,
        urgencyImportance: 0.5,
      );
      final result =
          const PriorityEngine().compute(signals: signals, weights: boosted);
      expect(result.score, inInclusiveRange(0.0, 1.0));
      // With examPriority weighted higher and examPriority=1.0 (the max
      // signal value here), the boosted score must be >= the unboosted
      // score for the same signals.
      final unboosted =
          const PriorityEngine().compute(signals: signals, weights: base);
      expect(result.score, greaterThanOrEqualTo(unboosted.score));
    });

    test('workloadImpossible boosts urgencyImportance weight only', () {
      final base = PriorityWeights.defaults();
      final boosted = engine.adjustPriorityWeights(
          base, EmergencyTriggerKind.workloadImpossible);
      expect(boosted[PrioritySignalKind.urgencyImportance],
          greaterThan(base[PrioritySignalKind.urgencyImportance]));
      expect(boosted[PrioritySignalKind.examPriority],
          base[PrioritySignalKind.examPriority]);
    });
  });

  group('adjustWorkloadEngine() — thresholds only, never the underlying '
      'numbers', () {
    test('balanced/overload ceilings loosen; underload ceiling is '
        'untouched', () {
      const original = WorkloadEngine();
      final loosened = engine.adjustWorkloadEngine(original);

      expect(loosened.underloadCeiling, original.underloadCeiling);
      expect(loosened.balancedCeiling, greaterThan(original.balancedCeiling));
      expect(loosened.overloadCeiling, greaterThan(original.overloadCeiling));
    });

    test('the SAME needed/available numbers can classify differently '
        'under the loosened engine, purely via the ceiling shift — the '
        'numbers themselves are never touched by this file', () {
      const original = WorkloadEngine();
      final loosened = engine.adjustWorkloadEngine(original);

      final normalResult =
          original.compute(neededMinutes: 110, availableMinutes: 100);
      final emergencyResult =
          loosened.compute(neededMinutes: 110, availableMinutes: 100);

      expect(normalResult.neededMinutes, emergencyResult.neededMinutes);
      expect(normalResult.availableMinutes, emergencyResult.availableMinutes);
      expect(normalResult.ratio, emergencyResult.ratio);
      // Same ratio, potentially different classification.
      expect(normalResult.classification, WorkloadClassification.overload);
      expect(emergencyResult.classification, WorkloadClassification.balanced);
    });
  });
}
