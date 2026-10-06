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
/// SIGNAL SET AND WEIGHTS (A-0, DEVIATION-20): the six signals and their
/// initial weights follow the approved final intelligence spec, not the
/// names the first foundation layer used. The weights are the spec's
/// INITIAL values (a starting point to be calibrated, not official facts):
///   masteryGap 0.30, forgettingRisk 0.20, officialCoefficient 0.20,
///   examProximity 0.15, deadlinePressure 0.10, longTermGoalAlignment 0.05.
/// Calibration bounds for w2..w6 are NOT in the repository and are not
/// invented here. The Error Engine's pattern is deliberately NOT a signal:
/// it may only influence mastery/confidence inside its own engine.
///
/// "forgettingRisk" keeps its pre-A-0 name for now: the spec's AMPLIFIED
/// forgetting formula is not in the repository, so the value stays the
/// plain 1 - retrievability until that formula is found (open item).
library priority_engine;

/// The six signals of the approved spec. Each is [0,1] or null.
///  - masteryGap: 1 - mastery probability (higher = needs more learning).
///  - forgettingRisk: 1 - FSRS retrievability now (see note above).
///  - officialCoefficient: normalised official coefficient, only from a
///    verified ACTIVE source (null otherwise).
///  - examProximity: ramp over days to the nearest exam.
///  - deadlinePressure: pressure of a task's own deadline (null if none).
///  - longTermGoalAlignment: alignment with the student's long-term goal
///    (null if no goal is set).
enum PrioritySignalKind {
  masteryGap,
  forgettingRisk,
  officialCoefficient,
  examProximity,
  deadlinePressure,
  longTermGoalAlignment,
}

/// Names written by earlier versions into Explanation.factorsJson /
/// excludedFactorsJson / dominantFactor and PriorityStates.weightsUsedJson.
/// Those rows are never rewritten (Explanations are append-only); readers
/// use [canonicalPrioritySignalName] to understand both generations.
/// `personalWeakness` was always the value 1 - mastery, i.e. masteryGap.
/// `learningPriority` was never populated (always excluded).
const Map<String, String> legacyPrioritySignalNames = {
  'personalWeakness': 'masteryGap',
  'examPriority': 'examProximity',
  'urgencyImportance': 'deadlinePressure',
  'learningPriority': 'longTermGoalAlignment',
};

/// Maps a stored factor name (old or new) to the current name.
String canonicalPrioritySignalName(String stored) =>
    legacyPrioritySignalNames[stored] ?? stored;

/// The current kind for a stored factor name (old or new), or null if the
/// name is unknown.
PrioritySignalKind? prioritySignalKindFromStoredName(String stored) {
  final name = canonicalPrioritySignalName(stored);
  for (final k in PrioritySignalKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

/// All six signals, each [0,1] or null when genuinely unavailable (e.g.
/// no exam scheduled yet -> examProximity is null, not 0 — 0 would falsely
/// assert "definitely no exam urgency," null correctly means "this
/// component has no opinion," and is excluded + renormalized around,
/// never defaulted to a specific number).
class PrioritySignals {
  const PrioritySignals({
    required this.masteryGap,
    required this.forgettingRisk,
    required this.officialCoefficient,
    required this.examProximity,
    required this.deadlinePressure,
    required this.longTermGoalAlignment,
  });

  final double? masteryGap;
  final double? forgettingRisk;
  final double? officialCoefficient;
  final double? examProximity;
  final double? deadlinePressure;
  final double? longTermGoalAlignment;

  Map<PrioritySignalKind, double?> asMap() => {
        PrioritySignalKind.masteryGap: masteryGap,
        PrioritySignalKind.forgettingRisk: forgettingRisk,
        PrioritySignalKind.officialCoefficient: officialCoefficient,
        PrioritySignalKind.examProximity: examProximity,
        PrioritySignalKind.deadlinePressure: deadlinePressure,
        PrioritySignalKind.longTermGoalAlignment: longTermGoalAlignment,
      };
}

class PriorityWeights {
  const PriorityWeights(this._weights);

  final Map<PrioritySignalKind, double> _weights;

  /// The spec's INITIAL weights (sum = 1.0) — see the file-level note.
  factory PriorityWeights.defaults() => const PriorityWeights({
        PrioritySignalKind.masteryGap: 0.30,
        PrioritySignalKind.forgettingRisk: 0.20,
        PrioritySignalKind.officialCoefficient: 0.20,
        PrioritySignalKind.examProximity: 0.15,
        PrioritySignalKind.deadlinePressure: 0.10,
        PrioritySignalKind.longTermGoalAlignment: 0.05,
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
