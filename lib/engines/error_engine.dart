import 'dart:math' as math;

/// Error Engine.
///
/// Pure, dependency-free — no Drift/Flutter import, unit-testable in
/// isolation, same pattern as memory_engine.dart. Turns a raw history of
/// ErrorRecords (student, knowledgeNode) into a bounded [0,1] "error
/// signal" plus structured risk flags, for consumption by the Priority
/// Engine as the `personalWeakness` signal (see priority_engine.dart) and
/// by the (future) Recovery Engine triage logic.
///
/// ErrorRecords themselves are a raw append-only log (see
/// error_repository.dart) — this engine never writes anything; it only
/// reads a window of records and computes derived numbers. It is
/// deliberately re-run on demand (not incrementally maintained), the same
/// "recompute from source of truth" pattern used by Mastery and Memory.
///
/// STATUS: UNVERIFIED. Not run through a real Dart compiler/test runner —
/// see test/error_engine_test.dart, same standing limitation as the rest
/// of this codebase (no Flutter/Dart SDK in this environment).
///
/// DESIGN NOTE: the type weights and thresholds below are INITIAL
/// HEURISTIC values (same status as the Priority Engine's w1-w6 in
/// algeria-intelligence-final-spec.md and the FSRS default weights) —
/// they are reasoned-about starting points, not calibrated against real
/// student data, and are exposed as constructor parameters (backed, in a
/// future integration pass, by ThresholdRegistryEntries rows) rather than
/// hardcoded so they can be tuned without touching this file.
library error_engine;

enum ErrorKind { careless, conceptual, missingPrerequisite }

/// One raw observation this engine consumes. `daysAgo` is relative to the
/// moment of computation (>= 0); the repository is responsible for
/// converting ErrorRecords.timestamp into this relative form.
class ErrorObservation {
  const ErrorObservation({required this.kind, required this.daysAgo});

  final ErrorKind kind;
  final double daysAgo;
}

/// The computed result for one (student, knowledgeNode) pair.
class ErrorSignalResult {
  const ErrorSignalResult({
    required this.signal,
    required this.counts,
    required this.prerequisiteRiskFlag,
    required this.conceptualRiskFlag,
    required this.observationCount,
  });

  /// Bounded [0,1] recency-weighted error intensity. 0 = no recent error
  /// evidence; approaches 1 as recent, high-severity errors accumulate.
  /// Monotonically increasing in both frequency and severity, with
  /// diminishing returns (see [ErrorEngine._saturate]) so a very long
  /// history cannot blow the signal past 1.
  final double signal;

  /// Raw counts per kind within the window the caller supplied — for
  /// display/explanation purposes (Explanation objects), not further math.
  final Map<ErrorKind, int> counts;

  /// True when missingPrerequisite errors, within the window, meet or
  /// exceed [ErrorEngine.prerequisiteRiskThreshold] — a signal that the
  /// (future) Recovery Engine should consider inserting/reinforcing a
  /// prerequisite node rather than just rescheduling more practice.
  final bool prerequisiteRiskFlag;

  /// True when the recency-weighted conceptual-error contribution alone
  /// meets or exceeds [ErrorEngine.conceptualRiskThreshold] — distinct
  /// from prerequisiteRiskFlag because a conceptual-error pattern usually
  /// means "needs different explanation," not "needs an earlier node."
  final bool conceptualRiskFlag;

  final int observationCount;
}

class ErrorEngine {
  const ErrorEngine({
    this.halfLifeDays = 14.0,
    this.carelessWeight = 0.3,
    this.conceptualWeight = 0.7,
    this.missingPrerequisiteWeight = 1.0,
    this.saturationConstant = 3.0,
    this.prerequisiteRiskThreshold = 2,
    this.conceptualRiskThreshold = 0.5,
  }) : assert(halfLifeDays > 0),
       assert(saturationConstant > 0);

  /// Recency half-life in days: an error this many days old contributes
  /// half the weight of an identical error happening today. 14 days is an
  /// INITIAL HEURISTIC (roughly "two weeks of relevance"), not derived
  /// from data.
  final double halfLifeDays;

  /// Per-kind severity weights, INITIAL HEURISTIC and deliberately
  /// ordered missingPrerequisite > conceptual > careless: a careless slip
  /// says little about understanding, a conceptual error says the model
  /// of the material is wrong, and a missing-prerequisite error means the
  /// student is missing a dependency entirely — structurally the most
  /// serious of the three.
  final double carelessWeight;
  final double conceptualWeight;
  final double missingPrerequisiteWeight;

  /// Controls how quickly the saturating signal approaches 1 as weighted
  /// evidence accumulates — see [_saturate].
  final double saturationConstant;

  /// Raw missingPrerequisite count (within the caller's window) at or
  /// above which [ErrorSignalResult.prerequisiteRiskFlag] is set.
  final int prerequisiteRiskThreshold;

  /// Recency-weighted conceptual-only contribution (see
  /// [_weightedContribution]) at or above which
  /// [ErrorSignalResult.conceptualRiskFlag] is set. Expressed on the same
  /// [0, weight] scale as a single very-recent conceptual error, so 0.5
  /// roughly means "at least one fairly recent conceptual error, or
  /// several older ones."
  final double conceptualRiskThreshold;

  double _recencyWeight(double daysAgo) {
    if (daysAgo < 0) {
      throw ArgumentError.value(
          daysAgo, 'daysAgo', 'must be >= 0 — an observation cannot be in '
          'the future relative to computation time.');
    }
    return math.pow(0.5, daysAgo / halfLifeDays).toDouble();
  }

  double _typeWeight(ErrorKind kind) {
    switch (kind) {
      case ErrorKind.careless:
        return carelessWeight;
      case ErrorKind.conceptual:
        return conceptualWeight;
      case ErrorKind.missingPrerequisite:
        return missingPrerequisiteWeight;
    }
  }

  /// Maps unbounded weighted evidence to a value from 0 up to (but never
  /// reaching) 1, with diminishing returns, so neither a single old error
  /// nor an unbounded pile of errors can push the signal outside its
  /// contract range: 1 minus e to the power of (-evidence / k).
  double _saturate(double weightedEvidence) {
    return 1.0 - math.exp(-weightedEvidence / saturationConstant);
  }

  ErrorSignalResult compute(List<ErrorObservation> observations) {
    final counts = <ErrorKind, int>{
      for (final k in ErrorKind.values) k: 0,
    };
    var totalWeighted = 0.0;
    var conceptualWeighted = 0.0;

    for (final obs in observations) {
      counts[obs.kind] = counts[obs.kind]! + 1;
      final contribution = _recencyWeight(obs.daysAgo) * _typeWeight(obs.kind);
      totalWeighted += contribution;
      if (obs.kind == ErrorKind.conceptual) {
        conceptualWeighted += contribution;
      }
    }

    return ErrorSignalResult(
      signal: _saturate(totalWeighted),
      counts: counts,
      prerequisiteRiskFlag:
          counts[ErrorKind.missingPrerequisite]! >= prerequisiteRiskThreshold,
      conceptualRiskFlag: conceptualWeighted >= conceptualRiskThreshold,
      observationCount: observations.length,
    );
  }
}
