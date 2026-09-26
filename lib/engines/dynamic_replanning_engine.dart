/// Dynamic Replanning Engine — FOUNDATION LAYER.
///
/// Pure, dependency-free decision logic (same status as
/// scheduling_engine.dart's foundation layer). Answers exactly one
/// question: given a batch of deviation signals since the last schedule
/// was produced, should the Scheduling Engine be re-run? It does NOT
/// re-run scheduling itself (that stays scheduling_engine.dart's job) and
/// it does NOT decide what happens to any individual task (that is
/// recovery_engine.dart's job, this same cycle). This file exists
/// specifically so "should we replan at all" is one small, testable,
/// hysteresis-aware decision, instead of being buried inside a bigger
/// engine where every minor deviation would silently trigger a full
/// re-schedule.
///
/// STATUS: UNVERIFIED — not run through a real Dart compiler/test runner
/// (no Flutter/Dart SDK in this environment). See
/// test/dynamic_replanning_engine_test.dart.
library dynamic_replanning_engine;

enum ReplanTriggerKind {
  /// A StudySession's observedDurationMinutes differed from its planned
  /// duration by more than the threshold.
  durationDeviation,

  /// A planned StudySession simply didn't happen (no actualStart/End).
  missedSession,

  /// A new RealityConstraint appeared that overlaps already-planned time
  /// (e.g. an unexpectedEvent).
  newUnavailability,

  /// WorkloadEngine's classification changed since the last schedule was
  /// produced (e.g. balanced -> overload).
  workloadStatusChanged,

  /// The student explicitly asked to replan.
  manualRequest,
}

class ReplanningSignal {
  const ReplanningSignal({required this.kind, this.magnitudeMinutes});

  final ReplanTriggerKind kind;

  /// Only meaningful for durationDeviation (the |planned - observed|
  /// minutes gap) — null for every other kind, which are inherently
  /// binary events rather than a magnitude.
  final int? magnitudeMinutes;
}

class ReplanningDecision {
  const ReplanningDecision({
    required this.shouldReplan,
    required this.reasoning,
    required this.triggeringSignals,
  });

  final bool shouldReplan;
  final String reasoning;

  /// Every signal that actually contributed to the decision (empty when
  /// shouldReplan is false), so the caller's Explanation object can cite
  /// exactly what triggered it, not just "something changed."
  final List<ReplanningSignal> triggeringSignals;
}

class DynamicReplanningEngine {
  const DynamicReplanningEngine({
    this.durationDeviationThresholdMinutes = 15,
  });

  /// Hysteresis band for durationDeviation: a session running 2 minutes
  /// over plan should NOT re-trigger a full replan on its own — only a
  /// deviation at or above this many minutes does. INITIAL HEURISTIC,
  /// same status as every other constant in this codebase.
  ///
  /// missedSession, newUnavailability, workloadStatusChanged, and
  /// manualRequest have no hysteresis band — each is inherently a
  /// discrete event, not a magnitude that could be "slightly" over a
  /// threshold, so each always triggers a replan on its own.
  final int durationDeviationThresholdMinutes;

  ReplanningDecision evaluate(List<ReplanningSignal> signals) {
    final triggering = <ReplanningSignal>[];

    for (final s in signals) {
      switch (s.kind) {
        case ReplanTriggerKind.durationDeviation:
          final mag = s.magnitudeMinutes ?? 0;
          if (mag >= durationDeviationThresholdMinutes) {
            triggering.add(s);
          }
          break;
        case ReplanTriggerKind.missedSession:
        case ReplanTriggerKind.newUnavailability:
        case ReplanTriggerKind.workloadStatusChanged:
        case ReplanTriggerKind.manualRequest:
          triggering.add(s);
          break;
      }
    }

    if (triggering.isEmpty) {
      return const ReplanningDecision(
        shouldReplan: false,
        reasoning: 'No signal met its trigger threshold — the existing '
            'schedule is still close enough to reality to leave in place.',
        triggeringSignals: [],
      );
    }

    final kinds = triggering.map((s) => s.kind.name).toSet().join(', ');
    return ReplanningDecision(
      shouldReplan: true,
      reasoning: 'Triggered by: $kinds.',
      triggeringSignals: triggering,
    );
  }
}
