import 'dart:math' as math;

/// Memory Engine: FSRS-4.5 (Free Spaced Repetition Scheduler).
///
/// Pure, dependency-free reimplementation of the published FSRS-4.5
/// formulas — no external package, no Drift/Flutter import, so this file
/// can be unit-tested in complete isolation from the database layer.
/// This matches the project decision recorded in
/// algeria-build-ready-plan.md: reimplement the published math natively
/// in Dart rather than depend on a third-party library or its license.
///
/// Formulas transcribed from the public FSRS-4.5 specification, cross-
/// checked against a published reference implementation with full working
/// code: https://borretti.me/article/implementing-fsrs-in-100-lines
/// (itself derived from https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm).
/// Default parameter weights (w0..w18) are the FSRS-4.5 published
/// defaults, trained on a large aggregate Anki review dataset — NOT
/// specific to this app's students. They are the correct INITIAL values;
/// nothing here should be read as claiming they are calibrated for this
/// student population.
///
/// STATUS: UNVERIFIED. This file has not been run through a real Dart
/// compiler or test runner (no Flutter/Dart SDK in the environment that
/// wrote it) — see test/memory_engine_test.dart, which is itself
/// UNVERIFIED for the same reason. Every formula below should be
/// confirmed against the reference source above once a real toolchain is
/// available, before this engine is wired into recomputation.
library memory_engine;

/// A review grade, matching the FSRS 4-point scale.
enum MemoryGrade { forgot, hard, good, easy }

extension on MemoryGrade {
  /// FSRS formulas are defined over the grade as a number 1..4.
  double get g {
    switch (this) {
      case MemoryGrade.forgot:
        return 1.0;
      case MemoryGrade.hard:
        return 2.0;
      case MemoryGrade.good:
        return 3.0;
      case MemoryGrade.easy:
        return 4.0;
    }
  }
}

/// The (Difficulty, Stability, Retrievability) memory state for a single
/// (student, knowledge node) pair, as tracked by MemoryStates.
class MemoryDsr {
  const MemoryDsr({required this.difficulty, required this.stability});

  /// D ∈ [1, 10]. Higher = harder to recall / decays faster.
  final double difficulty;

  /// S — stability in days: the time for retrievability to fall from 1
  /// to 0.9 if this card were never reviewed again.
  final double stability;
}

class MemoryEngine {
  const MemoryEngine({List<double>? weights})
      : _w = weights ?? _defaultWeights;

  /// FSRS-4.5 published default weights w0..w18. See file-level doc
  /// comment for source. A per-student-calibrated weight set (from a
  /// future optimizer, out of scope for this phase) would be passed in
  /// via the constructor instead of using these defaults.
  static const List<double> _defaultWeights = [
    0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046,
    1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315,
    2.9898, 0.51655, 0.6621,
  ];

  final List<double> _w;

  // Forgetting-curve shape constants (fixed, not learned parameters).
  static const double _factor = 19.0 / 81.0;
  static const double _decay = -0.5;

  double _clampDifficulty(double d) => d.clamp(1.0, 10.0);

  /// R(t, S): probability of recall after `elapsedDays` since the last
  /// review, given stability `stability`. R(0, S) = 1 by construction.
  double retrievability(double elapsedDays, double stability) {
    if (stability <= 0) {
      throw ArgumentError.value(
          stability, 'stability', 'must be > 0 — a memory state with zero '
          'or negative stability is not representable by this model.');
    }
    return math.pow(1.0 + _factor * (elapsedDays / stability), _decay)
        .toDouble();
  }

  /// I(desiredRetention, S): days until predicted retrievability decays
  /// to `desiredRetention`, given current stability `stability`. This is
  /// the "next review interval" the Scheduler should offer as a candidate
  /// slot (final placement is the Scheduler's job, not this engine's).
  double intervalForDesiredRetention({
    required double desiredRetention,
    required double stability,
  }) {
    if (desiredRetention <= 0 || desiredRetention >= 1) {
      throw ArgumentError.value(desiredRetention, 'desiredRetention',
          'must be in (0, 1) exclusive.');
    }
    final raw = (stability / _factor) *
        (math.pow(desiredRetention, 1.0 / _decay).toDouble() - 1.0);
    // A memory state can never be scheduled in the past or for "today
    // already happened" — the smallest meaningful unit here is 1 day.
    return math.max(raw, 1.0);
  }

  /// Initial (D, S) the FIRST time a knowledge node is ever reviewed.
  /// There is no prior memory state to update from.
  MemoryDsr initialState(MemoryGrade grade) {
    final s0 = switch (grade) {
      MemoryGrade.forgot => _w[0],
      MemoryGrade.hard => _w[1],
      MemoryGrade.good => _w[2],
      MemoryGrade.easy => _w[3],
    };
    final d0 = _clampDifficulty(_w[4] - math.exp(_w[5] * (grade.g - 1.0)) + 1.0);
    return MemoryDsr(difficulty: d0, stability: s0);
  }

  /// Update (D, S) after a review of a knowledge node that ALREADY had a
  /// memory state. `elapsedDays` is the actual days since the previous
  /// review (used to compute `retrievabilityAtReview` internally by the
  /// caller — see [reviewFrom] for the convenience wrapper that does
  /// both steps together, which is what the repository should call).
  MemoryDsr _updateState({
    required MemoryDsr previous,
    required double retrievabilityAtReview,
    required MemoryGrade grade,
  }) {
    final newStability = grade == MemoryGrade.forgot
        ? _stabilityOnFailure(
            difficulty: previous.difficulty,
            stability: previous.stability,
            retrievability: retrievabilityAtReview,
          )
        : _stabilityOnSuccess(
            difficulty: previous.difficulty,
            stability: previous.stability,
            retrievability: retrievabilityAtReview,
            grade: grade,
          );
    final newDifficulty = _updatedDifficulty(previous.difficulty, grade);
    return MemoryDsr(difficulty: newDifficulty, stability: newStability);
  }

  double _stabilityOnSuccess({
    required double difficulty,
    required double stability,
    required double retrievability,
    required MemoryGrade grade,
  }) {
    final tD = 11.0 - difficulty;
    final tS = math.pow(stability, -_w[9]).toDouble();
    final tR = math.exp(_w[10] * (1.0 - retrievability)) - 1.0;
    final hardPenalty = grade == MemoryGrade.hard ? _w[15] : 1.0;
    final easyBonus = grade == MemoryGrade.easy ? _w[16] : 1.0;
    final c = math.exp(_w[8]);
    final alpha = 1.0 + tD * tS * tR * hardPenalty * easyBonus * c;
    return stability * alpha;
  }

  double _stabilityOnFailure({
    required double difficulty,
    required double stability,
    required double retrievability,
  }) {
    final dF = math.pow(difficulty, -_w[12]).toDouble();
    final sF = math.pow(stability + 1.0, _w[13]).toDouble() - 1.0;
    final rF = math.exp(_w[14] * (1.0 - retrievability));
    final candidate = dF * sF * rF * _w[11];
    // Stability after forgetting can never exceed stability before —
    // forgetting cannot make a memory MORE stable.
    return math.min(candidate, stability);
  }

  double _updatedDifficulty(double previousDifficulty, MemoryGrade grade) {
    final deltaD = -_w[6] * (grade.g - 3.0);
    final dPrime =
        previousDifficulty + deltaD * ((10.0 - previousDifficulty) / 9.0);
    // Mean-reversion toward the initial difficulty of an "easy" first
    // review, weighted by w7. Pulls difficulty back toward a plausible
    // baseline over many reviews instead of drifting unboundedly.
    final easyD0 = initialState(MemoryGrade.easy).difficulty;
    return _clampDifficulty(_w[7] * easyD0 + (1.0 - _w[7]) * dPrime);
  }

  /// Convenience entry point the repository should call: given the
  /// PREVIOUS memory state and how many days have elapsed since that
  /// state's last review, computes retrievability at the moment of THIS
  /// review, then updates (D, S) for the new grade.
  MemoryDsr reviewFrom({
    required MemoryDsr previous,
    required double elapsedDaysSincePreviousReview,
    required MemoryGrade grade,
  }) {
    final r = retrievability(elapsedDaysSincePreviousReview, previous.stability);
    return _updateState(
      previous: previous,
      retrievabilityAtReview: r,
      grade: grade,
    );
  }
}
