import 'priority_engine.dart' show PriorityWeights, PrioritySignalKind;
import 'workload_engine.dart' show WorkloadClassification, WorkloadEngine;

/// Emergency Mode Engine — FOUNDATION LAYER.
///
/// Pure, dependency-free decision logic. Detects whether emergency
/// conditions apply (mirrors domain/enums.dart's EmergencyTrigger:
/// examProximity | workloadImpossible), and — this cycle's explicit rule
/// — Emergency Mode changes ONLY weights and thresholds. It NEVER
/// produces anything that could let a caller bypass a hard structural
/// constraint:
///   - It has no access to sleep-floor or prerequisite-ordering logic at
///     all (those live in reality_layer_domain.dart / scheduling_engine.dart
///     respectively) — architecturally, not just by convention, this file
///     cannot violate them because it never sees a TimeSlot or a
///     Prerequisite edge.
///   - adjustPriorityWeights() only ever returns a PriorityWeights object,
///     which priority_engine.dart's own compute() ALWAYS renormalizes to
///     sum to 1.0 regardless of what this file hands it — so this file
///     deliberately does not duplicate that renormalization logic itself
///     (single source of truth stays in priority_engine.dart).
///   - adjustWorkloadEngine() only ever returns a new WorkloadEngine with
///     looser ratio ceilings — it cannot touch anything else about how
///     workload is computed.
///
/// STATUS: UNVERIFIED — not run through a real Dart compiler/test runner
/// (no Flutter/Dart SDK in this environment). See
/// test/emergency_engine_test.dart.
///
/// DESIGN NOTE: examProximityDays and the reweight/loosen multipliers
/// below are INITIAL HEURISTIC values, same status as every other
/// cross-cutting constant in this codebase.
library emergency_engine;

enum EmergencyTriggerKind { examProximity, workloadImpossible }

class EmergencyEvaluation {
  const EmergencyEvaluation({
    required this.triggered,
    this.trigger,
    required this.reasoning,
  });

  final bool triggered;
  final EmergencyTriggerKind? trigger;
  final String reasoning;
}

class EmergencyModeEngine {
  const EmergencyModeEngine({
    this.examProximityDays = 3,
    this.examSignalBoostMultiplier = 2.0,
    this.urgencySignalBoostMultiplier = 1.5,
    this.workloadCeilingLoosenFactor = 1.2,
  })  : assert(examProximityDays >= 0),
        assert(examSignalBoostMultiplier >= 1.0),
        assert(urgencySignalBoostMultiplier >= 1.0),
        assert(workloadCeilingLoosenFactor >= 1.0);

  /// A nearest-exam distance at or below this many days is
  /// examProximity. INITIAL HEURISTIC.
  final int examProximityDays;

  /// How much examPriority's raw weight is multiplied by before
  /// priority_engine.dart renormalizes everything back to sum 1.0.
  /// INITIAL HEURISTIC.
  final double examSignalBoostMultiplier;

  /// Same idea, applied to urgencyImportance — used for the
  /// workloadImpossible trigger (deadline pressure across the board
  /// matters more than any single exam). INITIAL HEURISTIC.
  final double urgencySignalBoostMultiplier;

  /// Multiplies WorkloadEngine's balancedCeiling/overloadCeiling (not
  /// underloadCeiling — there is no "emergency underload" concept) so
  /// slightly-over-capacity days stop reading as overload/impossible
  /// purely from the classification boundary shifting, while the
  /// UNDERLYING neededMinutes/availableMinutes numbers — and every hard
  /// constraint that produced them — stay exactly as computed. INITIAL
  /// HEURISTIC.
  final double workloadCeilingLoosenFactor;

  EmergencyEvaluation evaluate({
    required int? daysUntilNearestExam,
    required WorkloadClassification currentWorkloadStatus,
  }) {
    if (currentWorkloadStatus == WorkloadClassification.impossible) {
      return const EmergencyEvaluation(
        triggered: true,
        trigger: EmergencyTriggerKind.workloadImpossible,
        reasoning: 'Workload classification is impossible — entering '
            'Emergency Mode to reweight priority toward urgency, not to '
            'remove any constraint that made it impossible.',
      );
    }

    if (daysUntilNearestExam != null &&
        daysUntilNearestExam <= examProximityDays) {
      return EmergencyEvaluation(
        triggered: true,
        trigger: EmergencyTriggerKind.examProximity,
        reasoning: 'Nearest exam is $daysUntilNearestExam day(s) away '
            '(<= $examProximityDays) — entering Emergency Mode to reweight '
            'priority toward exam-relevant material.',
      );
    }

    return const EmergencyEvaluation(
      triggered: false,
      trigger: null,
      reasoning: 'No emergency condition met — normal weights/thresholds '
          'stay in effect.',
    );
  }

  /// Returns NEW raw weights (not yet renormalized — priority_engine.dart
  /// does that on every compute() call regardless). Only ever multiplies
  /// existing weights upward for the relevant signal(s); never sets a
  /// weight to zero, never touches signal VALUES, only their WEIGHTS.
  PriorityWeights adjustPriorityWeights(
    PriorityWeights original,
    EmergencyTriggerKind trigger,
  ) {
    final boosted = <PrioritySignalKind, double>{};
    for (final k in PrioritySignalKind.values) {
      var w = original[k];
      if (trigger == EmergencyTriggerKind.examProximity &&
          k == PrioritySignalKind.examPriority) {
        w *= examSignalBoostMultiplier;
      }
      if (trigger == EmergencyTriggerKind.workloadImpossible &&
          k == PrioritySignalKind.urgencyImportance) {
        w *= urgencySignalBoostMultiplier;
      }
      boosted[k] = w;
    }
    return PriorityWeights(boosted);
  }

  /// Returns a NEW WorkloadEngine instance with looser balanced/overload
  /// ceilings — the original engine (and everything it was computed
  /// from) is left untouched; this is purely "how do we CLASSIFY the
  /// same numbers differently while in emergency mode," never "let's
  /// change the numbers."
  WorkloadEngine adjustWorkloadEngine(WorkloadEngine original) {
    return WorkloadEngine(
      underloadCeiling: original.underloadCeiling,
      balancedCeiling: original.balancedCeiling * workloadCeilingLoosenFactor,
      overloadCeiling: original.overloadCeiling * workloadCeilingLoosenFactor,
    );
  }
}
