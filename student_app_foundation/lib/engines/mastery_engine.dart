/// Mastery Engine (Bayesian Knowledge Tracing).
///
/// Pure, dependency-free — same pattern as every other file in this
/// directory. Implements the standard two-step BKT update (evidence step,
/// then learning-transition step) and nothing else: it takes a prior
/// probability and one new observation, and returns a new probability.
/// It never touches ErrorRecords/Events/MasteryStates directly — the
/// (future) Track D integration layer is responsible for: reading the
/// current MasteryState (or seeding priorProbability), reading the
/// triggering Event, calling this engine, then calling
/// `MasteryRepository.recomputeFrom(...)` with the result and the
/// triggering event's id. That separation is what lets this file be
/// tested with plain doubles and booleans, no database.
///
/// STATUS: UNVERIFIED — not run through a real Dart compiler/test runner
/// (no Flutter/Dart SDK in this environment). See
/// test/mastery_engine_test.dart.
///
/// DESIGN NOTE: BktParameters.defaults() below uses commonly-cited
/// ballpark BKT starting values (P(T)=0.1, P(G)=0.2, P(S)=0.1,
/// P(L0)=0.3) — these are the same INITIAL HEURISTIC status as every
/// other constant in this codebase (see error_engine.dart /
/// time_estimation_engine.dart / workload_engine.dart /
/// priority_engine.dart doc comments), not a specific calibrated result
/// for this app's actual students, and are exposed as a constructor
/// argument for exactly that reason. Per-subject/per-node parameter
/// calibration is explicitly out of scope for this engine and belongs to
/// the later Calibration/Simulation phase (Track E).
library mastery_engine;

/// The four standard BKT parameters, all probabilities in [0, 1].
class BktParameters {
  const BktParameters({
    required this.pTransition,
    required this.pGuess,
    required this.pSlip,
    required this.initialProbability,
  })  : assert(pTransition >= 0 && pTransition <= 1),
        assert(pGuess >= 0 && pGuess <= 1),
        assert(pSlip >= 0 && pSlip <= 1),
        assert(initialProbability >= 0 && initialProbability <= 1);

  /// P(T) — probability the student transitions from not-knowing to
  /// knowing after one practice opportunity, independent of whether they
  /// answered correctly.
  final double pTransition;

  /// P(G) — probability of a correct answer despite NOT knowing the
  /// skill (a lucky guess).
  final double pGuess;

  /// P(S) — probability of an INCORRECT answer despite knowing the
  /// skill (a slip/careless mistake — distinct from, but related in
  /// spirit to, ErrorEngine's `careless` classification; the two are not
  /// wired together in this foundation layer).
  final double pSlip;

  /// P(L0) — the probability assigned to a knowledge node the student
  /// has never been observed on (no MasteryState row yet). Used by the
  /// integration layer as the seed for `priorProbability` on first
  /// contact, not by this engine directly.
  final double initialProbability;

  /// INITIAL HEURISTIC — see file-level DESIGN NOTE.
  factory BktParameters.defaults() => const BktParameters(
        pTransition: 0.1,
        pGuess: 0.2,
        pSlip: 0.1,
        initialProbability: 0.3,
      );
}

class MasteryUpdateResult {
  const MasteryUpdateResult({
    required this.probabilityAfterEvidence,
    required this.probability,
    required this.confidence,
    required this.observationCount,
  });

  /// P(L | evidence) — the Bayesian posterior from the evidence step
  /// ALONE, before the learning-transition step is applied. Exposed
  /// separately (not just the final `probability`) because Explanation
  /// objects (Track D / INV-7) should be able to show "this is what the
  /// answer itself told us" distinctly from "and then we also assumed
  /// they might have learned something from the attempt."
  final double probabilityAfterEvidence;

  /// The new mastery probability (Accuracy) — what gets written to
  /// MasteryStates.probability. This is P(L | evidence) advanced one
  /// step by the transition probability.
  final double probability;

  /// [0, 1], DELIBERATELY SEPARATE from `probability` (per the Track A
  /// Cycle 2 requirement "Confidence منفصلة عن Accuracy"): how much
  /// evidence backs this estimate, independent of what the estimate is.
  /// A node observed twice and a node observed fifty times can land on
  /// the exact same `probability` with very different `confidence`.
  /// Saturating function of `observationCount` — see
  /// [MasteryEngine.confidenceSaturationConstant].
  final double confidence;

  /// Total observations this probability is now based on (prior count
  /// + 1 for the observation just processed) — the integration layer is
  /// responsible for persisting and re-supplying this across calls, since
  /// MasteryStates has no observationCount column (a deliberate no-schema-
  /// change decision this cycle; confidence can be recomputed by the
  /// integration layer from Event history if it does not want to carry
  /// this number itself).
  final int observationCount;
}

class MasteryEngine {
  const MasteryEngine({this.confidenceSaturationConstant = 5.0})
      : assert(confidenceSaturationConstant > 0);

  /// Controls how fast `confidence` approaches 1 as `observationCount`
  /// grows, via n / (n + k). INITIAL HEURISTIC, same status as the rest
  /// of this file's constants.
  final double confidenceSaturationConstant;

  /// One BKT update step. `priorProbability` is P(L) BEFORE this
  /// observation (either the previous MasteryState.probability, or
  /// `params.initialProbability` on first contact — the caller decides
  /// which, this engine does not special-case "first observation").
  MasteryUpdateResult compute({
    required double priorProbability,
    required bool correct,
    required BktParameters params,
    required int priorObservationCount,
  }) {
    if (priorProbability < 0 || priorProbability > 1) {
      throw ArgumentError.value(priorProbability, 'priorProbability',
          'must be in [0, 1].');
    }
    if (priorObservationCount < 0) {
      throw ArgumentError.value(priorObservationCount,
          'priorObservationCount', 'must be >= 0.');
    }

    // Evidence step (Bayes' rule).
    final double posterior;
    if (correct) {
      final numerator = priorProbability * (1 - params.pSlip);
      final denominator = numerator + (1 - priorProbability) * params.pGuess;
      posterior = denominator == 0 ? priorProbability : numerator / denominator;
    } else {
      final numerator = priorProbability * params.pSlip;
      final denominator =
          numerator + (1 - priorProbability) * (1 - params.pGuess);
      posterior = denominator == 0 ? priorProbability : numerator / denominator;
    }

    // Learning-transition step: even if the evidence didn't fully prove
    // mastery, the act of practicing gives another chance to have
    // transitioned from not-knowing to knowing.
    final afterTransition = posterior + (1 - posterior) * params.pTransition;

    final newObservationCount = priorObservationCount + 1;
    final confidence = newObservationCount /
        (newObservationCount + confidenceSaturationConstant);

    return MasteryUpdateResult(
      probabilityAfterEvidence: posterior.clamp(0.0, 1.0),
      probability: afterTransition.clamp(0.0, 1.0),
      confidence: confidence,
      observationCount: newObservationCount,
    );
  }
}
