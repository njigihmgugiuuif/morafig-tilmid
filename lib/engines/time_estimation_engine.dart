import 'dart:math' as math;

/// Time Estimation Engine.
///
/// Pure, dependency-free (same pattern as memory_engine.dart /
/// error_engine.dart). Produces the fields TimeEstimates already has
/// columns for (estimatedDurationMinutes, confidenceLevel, confidenceValue,
/// basis) from two possible inputs: a curriculum-derived default duration
/// for a (subject, sessionType), and a history of observed actual
/// durations the student took for that same pair.
///
/// STATUS: UNVERIFIED — not run through a real Dart compiler/test runner
/// (no Flutter/Dart SDK in this environment). See
/// test/time_estimation_engine_test.dart.
///
/// DESIGN NOTE: the blend/confidence constants below are INITIAL
/// HEURISTIC values, exposed as constructor parameters rather than
/// hardcoded, same status as error_engine.dart's weights and the Priority
/// Engine's w1-w6.
library time_estimation_engine;

enum TimeEstimateBasis { curriculumDefault, observedHistory, hybrid }

enum TimeConfidenceLevel { low, medium, high }

/// One observed actual duration, most-recent-first ordering not required
/// — `daysAgo` carries the recency information the engine needs.
class ObservedDuration {
  const ObservedDuration({required this.minutes, required this.daysAgo});

  final int minutes;
  final double daysAgo;
}

class TimeEstimateResult {
  const TimeEstimateResult({
    required this.estimatedDurationMinutes,
    required this.confidenceLevel,
    required this.confidenceValue,
    required this.basis,
  });

  final int estimatedDurationMinutes;
  final TimeConfidenceLevel confidenceLevel;

  /// [0, 1] continuous confidence — confidenceLevel is a bucketed view of
  /// this same value (see [TimeEstimationEngine._levelFor]).
  final double confidenceValue;
  final TimeEstimateBasis basis;
}

class TimeEstimationEngine {
  const TimeEstimationEngine({
    this.recencyHalfLifeDays = 30.0,
    this.trustGrowthConstant = 4.0,
    this.fallbackDurationMinutes = 30,
    this.lowConfidenceCeiling = 0.35,
    this.mediumConfidenceCeiling = 0.7,
  }) : assert(recencyHalfLifeDays > 0),
       assert(trustGrowthConstant > 0);

  /// Observed-sample recency half-life, in days. 30 days is an INITIAL
  /// HEURISTIC — recent sessions matter more because pacing/difficulty
  /// context shifts across a school term.
  final double recencyHalfLifeDays;

  /// Controls how fast trust in the observed mean grows with sample
  /// count, via n / (n + k). k=4 means: after ~4 effective (recency-
  /// weighted) samples the observed mean already carries half the
  /// blending weight against the curriculum default. INITIAL HEURISTIC.
  final double trustGrowthConstant;

  /// Used only when NEITHER a curriculum default NOR any observed sample
  /// exists — the estimate must still be a positive number for the
  /// Workload Engine to sum, so this is a documented, clearly-labeled
  /// last resort, never silently confused with a real estimate (basis is
  /// still reported as curriculumDefault with confidenceValue 0, so
  /// callers can detect this case).
  final int fallbackDurationMinutes;

  final double lowConfidenceCeiling;
  final double mediumConfidenceCeiling;

  double _recencyWeight(double daysAgo) {
    if (daysAgo < 0) {
      throw ArgumentError.value(daysAgo, 'daysAgo', 'must be >= 0.');
    }
    return math.pow(0.5, daysAgo / recencyHalfLifeDays).toDouble();
  }

  TimeConfidenceLevel _levelFor(double value) {
    if (value < lowConfidenceCeiling) return TimeConfidenceLevel.low;
    if (value < mediumConfidenceCeiling) return TimeConfidenceLevel.medium;
    return TimeConfidenceLevel.high;
  }

  /// `curriculumDefaultMinutes` is null when curriculum data is UNKNOWN
  /// or the applicable SubjectLoad row's status is not usable (see
  /// PolicyStatus.usableForCalculation in domain/enums.dart) — the caller
  /// (repository layer) is responsible for that guard, never this engine.
  TimeEstimateResult compute({
    required int? curriculumDefaultMinutes,
    required List<ObservedDuration> observedSamples,
  }) {
    if (observedSamples.isEmpty) {
      if (curriculumDefaultMinutes != null) {
        return TimeEstimateResult(
          estimatedDurationMinutes: curriculumDefaultMinutes,
          confidenceLevel: TimeConfidenceLevel.low,
          confidenceValue: 0.2,
          basis: TimeEstimateBasis.curriculumDefault,
        );
      }
      return TimeEstimateResult(
        estimatedDurationMinutes: fallbackDurationMinutes,
        confidenceLevel: TimeConfidenceLevel.low,
        confidenceValue: 0.0,
        basis: TimeEstimateBasis.curriculumDefault,
      );
    }

    var weightSum = 0.0;
    var weightedMinutesSum = 0.0;
    for (final o in observedSamples) {
      final w = _recencyWeight(o.daysAgo);
      weightSum += w;
      weightedMinutesSum += w * o.minutes;
    }
    final observedMean = weightedMinutesSum / weightSum;

    // Sample-count component of confidence: effective (recency-weighted)
    // count, saturating toward 1 as evidence accumulates.
    final sampleConfidence = weightSum / (weightSum + trustGrowthConstant);

    // Variance component: tighter agreement across samples -> higher
    // confidence. Coefficient of variation, saturated the same way.
    final variance = observedSamples
            .map((o) => math.pow(o.minutes - observedMean, 2))
            .fold<double>(0.0, (a, b) => a + b) /
        observedSamples.length;
    final stdDev = math.sqrt(variance);
    final coefficientOfVariation =
        observedMean == 0 ? 1.0 : (stdDev / observedMean);
    final consistencyConfidence = 1.0 / (1.0 + coefficientOfVariation);

    final observedConfidence =
        (sampleConfidence + consistencyConfidence) / 2.0;

    if (curriculumDefaultMinutes == null) {
      return TimeEstimateResult(
        estimatedDurationMinutes: observedMean.round(),
        confidenceLevel: _levelFor(observedConfidence),
        confidenceValue: observedConfidence,
        basis: TimeEstimateBasis.observedHistory,
      );
    }

    // Hybrid: blend weight toward the observed mean grows with sample
    // trust (same n/(n+k) shape as sampleConfidence, computed directly
    // from the effective weighted count so it is not double-saturated).
    final blendWeight = weightSum / (weightSum + trustGrowthConstant);
    final blended = blendWeight * observedMean +
        (1.0 - blendWeight) * curriculumDefaultMinutes;
    // Hybrid confidence is at least as high as observed-alone confidence
    // (a curriculum default as a prior only ever adds information), and
    // is nudged upward by how much the two sources already agree.
    final agreement = 1.0 -
        math.min(
          1.0,
          (blended - curriculumDefaultMinutes).abs() /
              math.max(1.0, curriculumDefaultMinutes.toDouble()),
        );
    final hybridConfidence =
        math.min(1.0, observedConfidence + 0.15 * agreement);

    return TimeEstimateResult(
      estimatedDurationMinutes: blended.round(),
      confidenceLevel: _levelFor(hybridConfidence),
      confidenceValue: hybridConfidence,
      basis: TimeEstimateBasis.hybrid,
    );
  }
}
