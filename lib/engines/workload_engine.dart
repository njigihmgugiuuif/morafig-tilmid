/// Workload Engine.
///
/// Pure, dependency-free (same pattern as the other engines in this
/// directory). Produces exactly the fields WorkloadStates already has
/// columns for: totalEstimatedTimeNeededMinutes,
/// totalAvailableTimeMinutes, status. The repository is responsible for
/// summing Tasks/TimeEstimates into `neededMinutes` and Availability/
/// RealityConstraint rows into `availableMinutes` before calling this —
/// this engine only classifies the two already-summed numbers, so it has
/// no database dependency and no knowledge of where the numbers came
/// from.
///
/// STATUS: UNVERIFIED — not run through a real Dart compiler/test runner
/// (no Flutter/Dart SDK in this environment). See
/// test/workload_engine_test.dart.
///
/// DESIGN NOTE: the ratio thresholds below are INITIAL HEURISTIC values,
/// same status as every other cross-cutting constant in this codebase
/// (see error_engine.dart / time_estimation_engine.dart doc comments) —
/// exposed as constructor parameters, not hardcoded, pending a future
/// ThresholdRegistryEntries-backed calibration pass.
library workload_engine;

enum WorkloadClassification { underload, balanced, overload, impossible }

class WorkloadResult {
  const WorkloadResult({
    required this.neededMinutes,
    required this.availableMinutes,
    required this.ratio,
    required this.classification,
  });

  final int neededMinutes;
  final int availableMinutes;

  /// needed / available. Infinity when available == 0 and needed > 0 —
  /// represented as double.infinity, never as a thrown error, because
  /// "zero available time with pending work" is a real, classifiable
  /// (impossible) state, not a bug.
  final double ratio;
  final WorkloadClassification classification;
}

class WorkloadEngine {
  const WorkloadEngine({
    this.underloadCeiling = 0.6,
    this.balancedCeiling = 0.95,
    this.overloadCeiling = 1.15,
  }) : assert(underloadCeiling > 0),
       assert(balancedCeiling > underloadCeiling),
       assert(overloadCeiling > balancedCeiling);

  /// ratio <= this -> underload. INITIAL HEURISTIC.
  final double underloadCeiling;

  /// underloadCeiling < ratio <= this -> balanced. INITIAL HEURISTIC.
  final double balancedCeiling;

  /// balancedCeiling < ratio <= this -> overload (tight but still
  /// nominally fits with zero slack). Beyond this -> impossible, because
  /// exceeding total available time by more than ~15% cannot realistically
  /// be absorbed by compressing sessions or trimming slack alone.
  /// INITIAL HEURISTIC.
  final double overloadCeiling;

  WorkloadResult compute({
    required int neededMinutes,
    required int availableMinutes,
  }) {
    if (neededMinutes < 0) {
      throw ArgumentError.value(
          neededMinutes, 'neededMinutes', 'must be >= 0.');
    }
    if (availableMinutes < 0) {
      throw ArgumentError.value(
          availableMinutes, 'availableMinutes', 'must be >= 0.');
    }

    final ratio = availableMinutes == 0
        ? (neededMinutes == 0 ? 0.0 : double.infinity)
        : neededMinutes / availableMinutes;

    final WorkloadClassification classification;
    if (ratio <= underloadCeiling) {
      classification = WorkloadClassification.underload;
    } else if (ratio <= balancedCeiling) {
      classification = WorkloadClassification.balanced;
    } else if (ratio <= overloadCeiling) {
      classification = WorkloadClassification.overload;
    } else {
      classification = WorkloadClassification.impossible;
    }

    return WorkloadResult(
      neededMinutes: neededMinutes,
      availableMinutes: availableMinutes,
      ratio: ratio,
      classification: classification,
    );
  }
}
