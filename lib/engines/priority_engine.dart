/// Priority Engine — FOUNDATION LAYER ONLY.
///
/// Pure, dependency-free (same pattern as the other engines in this
/// directory). This is deliberately scoped to "foundation": it defines
/// the signal-merge contract (inputs already-normalized [0,1] signals,
/// mandatory weight renormalization, score clamping, a completeness-based
/// confidence value) exactly as algeria-intelligence-final-spec.md and
/// the subsequent audit fix require, WITHOUT wiring the six signals to
/// their real sources (curriculum coefficient, Mastery, Memory,
/// ErrorEngine, exam dates, reality-layer urgency). That wiring is
/// Track D (Integration) — this file has no import of any other engine
/// or of Drift, on purpose, so it can be tested as pure signal-merge
/// logic in isolation first.
///
/// STATUS: UNVERIFIED — not run through a real Dart compiler/test runner
/// (no Flutter/Dart SDK in this environment). See
/// test/priority_engine_test.dart.
///
/// DESIGN NOTE: PriorityWeights.defaults() below is an EQUAL-WEIGHT
/// placeholder (1/6 each), not a reproduction of specific w1-w6 values
/// from an external document — this file was written without that
/// document available in this session. It is intentionally a safe,
/// neutral starting point (no signal privileged over another) rather
/// than a guess at numbers this session cannot verify, and is exposed as
/// a swappable constructor argument for that reason. Re-deriving the
/// originally-designed w1-w6 (with their documented rationale/calibration
/// bounds) against the actual spec is flagged as follow-up work, not done
/// silently here.
library priority_engine;

/// The six signal categories from the Master Blueprint / Intelligence
/// Spec: official curriculum coefficient, current mastery gap ("learning
/// priority" — 1 - masteryProbability, higher = needs more learning),
/// exam-proximity priority, personal weakness (from ErrorEngine),
/// memory forgetting risk (from MemoryEngine's retrievability, inverted:
/// higher = more likely to have decayed), and general urgency/importance
/// (deadline pressure independent of exams, e.g. an assignment due date).
enum PrioritySignalKind {
  officialCoefficient,
  learningPriority,
  examPriority,
  personalWeakness,
  forgettingRisk,
  urgencyImportance,
}

/// All six signals, each [0,1] or null when genuinely unavailable (e.g.
/// no exam scheduled yet -> examPriority is null, not 0 — 0 would falsely
/// assert "definitely no exam urgency," null correctly means "this
/// component has no opinion," and is excluded + renormalized around,
/// never defaulted to a specific number).
class PrioritySignals {
  const PrioritySignals({
    required this.officialCoefficient,
    required this.learningPriority,
    required this.examPriority,
    required this.personalWeakness,
    required this.forgettingRisk,
    required this.urgencyImportance,
  });

  final double? officialCoefficient;
  final double? learningPriority;
  final double? examPriority;
  final double? personalWeakness;
  final double? forgettingRisk;
  final double? urgencyImportance;

  Map<PrioritySignalKind, double?> asMap() => {
        PrioritySignalKind.officialCoefficient: officialCoefficient,
        PrioritySignalKind.learningPriority: learningPriority,
        PrioritySignalKind.examPriority: examPriority,
        PrioritySignalKind.personalWeakness: personalWeakness,
        PrioritySignalKind.forgettingRisk: forgettingRisk,
        PrioritySignalKind.urgencyImportance: urgencyImportance,
      };
}

class PriorityWeights {
  const PriorityWeights(this._weights);

  final Map<PrioritySignalKind, double> _weights;

  /// Equal-weight neutral default — see file-level DESIGN NOTE.
  factory PriorityWeights.defaults() => PriorityWeights({
        for (final k in PrioritySignalKind.values) k: 1.0 / 6.0,
      });

  double operator [](PrioritySignalKind k) => _weights[k] ?? 0.0;

  double get sum => _weights.values.fold(0.0, (a, b) => a + b);
}

class PriorityResult {
  const PriorityResult({
    required this.score,
    required this.confidenceValue,
    required this.weightsUsed,
    required this.usedFallbackWeights,
  });

  /// Clamped [0,1]. The single number Scheduling/Recovery/Emergency Mode
  /// (Track B) consume.
  final double score;

  /// Simplified completeness-based confidence: fraction of the six
  /// signals that were non-null. This is a partial instantiation of the
  /// full confidence() formula from the final intelligence spec
  /// (completeness/estimate/sample-size/freshness) — only the
  /// completeness term is computable at this foundation layer, since
  /// sample-size and freshness belong to the individual engines that
  /// produced each signal, not to the merge step itself. Full confidence
  /// composition is Track D work.
  final double confidenceValue;

  /// The renormalized weights actually used for this computation (after
  /// excluding null signals and redistributing their weight), for the
  /// Explanation object (Track D) to record verbatim per INV-7
  /// (determinism/auditability).
  final Map<PrioritySignalKind, double> weightsUsed;

  /// True if the caller's weights did not sum to ~1.0 (or summed to ~0)
  /// even before null-signal exclusion, and PriorityWeights.defaults()
  /// was used instead — mirrors the audit's mandatory-renormalization
  /// fix ("zero-sum-weights fallback to default weights").
  final bool usedFallbackWeights;
}

class PriorityEngine {
  const PriorityEngine({this.weightSumTolerance = 1e-6});

  final double weightSumTolerance;

  PriorityResult compute({
    required PrioritySignals signals,
    PriorityWeights? weights,
  }) {
    var effectiveWeights = weights ?? PriorityWeights.defaults();
    var usedFallback = false;

    if ((effectiveWeights.sum - 1.0).abs() > 0.01 &&
        effectiveWeights.sum.abs() > weightSumTolerance) {
      // Caller-supplied weights don't sum to 1 but aren't degenerately
      // zero either — still renormalize (divide through by the sum)
      // rather than falling back, per the audit's primary fix.
      final s = effectiveWeights.sum;
      effectiveWeights = PriorityWeights({
        for (final k in PrioritySignalKind.values) k: effectiveWeights[k] / s,
      });
    } else if (effectiveWeights.sum.abs() <= weightSumTolerance) {
      // Degenerate (all-zero, or caller error): fall back to the
      // documented default rather than dividing by ~0.
      effectiveWeights = PriorityWeights.defaults();
      usedFallback = true;
    }

    final signalMap = signals.asMap();
    final availableKinds =
        signalMap.entries.where((e) => e.value != null).map((e) => e.key);

    if (availableKinds.isEmpty) {
      throw ArgumentError(
          'PrioritySignals had no non-null signal at all — there is '
          'nothing to score. This indicates a caller bug (Track D should '
          'never invoke the Priority Engine for a task with zero known '
          'signals), not a valid zero-priority state.');
    }

    final availableWeightSum =
        availableKinds.fold(0.0, (a, k) => a + effectiveWeights[k]);

    final Map<PrioritySignalKind, double> weightsUsed;
    if (availableWeightSum.abs() <= weightSumTolerance) {
      // Every available signal happened to have ~zero weight assigned —
      // fall back to equal weighting across just the available signals,
      // rather than producing a meaningless divide-by-~0 renormalization.
      final equalShare = 1.0 / availableKinds.length;
      weightsUsed = {for (final k in availableKinds) k: equalShare};
      usedFallback = true;
    } else {
      weightsUsed = {
        for (final k in availableKinds)
          k: effectiveWeights[k] / availableWeightSum,
      };
    }

    var score = 0.0;
    for (final k in availableKinds) {
      score += weightsUsed[k]! * signalMap[k]!;
    }
    score = score.clamp(0.0, 1.0);

    final confidenceValue = availableKinds.length / PrioritySignalKind.values.length;

    return PriorityResult(
      score: score,
      confidenceValue: confidenceValue,
      weightsUsed: weightsUsed,
      usedFallbackWeights: usedFallback,
    );
  }
}
