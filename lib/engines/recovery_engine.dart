import 'workload_engine.dart' show WorkloadClassification;

/// Recovery Engine — FOUNDATION LAYER.
///
/// Pure, dependency-free decision logic. Decides, ONE missed/affected
/// task at a time, which of the six RecoveryDecision outcomes (matching
/// RecoveryRecords.decision's documented vocabulary exactly: keep, move,
/// merge, defer, dropTemporarily, replan) applies — and always returns a
/// human-readable `reasoning` string, because RecoveryRecords.reasoning
/// is a required (non-nullable) column and this cycle's rules require
/// every decision to be explainable, not just applied.
///
/// EXPLICITLY NOT a blanket "move every missed task to tomorrow" policy
/// (this cycle's stated rule) — see the decision table in [decide] below:
/// outcome depends on priority, deadline proximity, partial-completion
/// state, and current workload pressure, and different tasks missed at
/// the same moment can land on different decisions.
///
/// STATUS: UNVERIFIED — not run through a real Dart compiler/test runner
/// (no Flutter/Dart SDK in this environment). See
/// test/recovery_engine_test.dart.
///
/// DESIGN NOTE: the decision table below is an INITIAL HEURISTIC —
/// reasoned about, not calibrated against real student data or an
/// external spec document (same status as every other cross-cutting
/// constant in this codebase). The six outcome MEANINGS this engine
/// assumes are documented on [RecoveryDecisionKind] itself since no
/// external spec text defining them was available in this session —
/// flagged as follow-up to reconcile against
/// algeria-intelligence-final-spec.md if its definitions differ.
library recovery_engine;

/// Mirrors domain/enums.dart's RecoveryDecision exactly (name-for-name),
/// duplicated here rather than imported so this pure-Dart file has zero
/// dependency on the database layer (same reasoning as every other
/// engine in this directory) — recovery_repository.dart (Track D) is
/// responsible for the 1:1 mapping between this enum and the DB enum.
enum RecoveryDecisionKind {
  /// Leave the task scheduled where/when it already was — the student
  /// can still realistically do it (today, same urgency), untouched.
  keep,

  /// Reschedule it to the next available slot (via scheduling_engine.dart
  /// on the next run) — no imminent deadline forces urgency, but it still
  /// needs to happen.
  move,

  /// Combine the remaining (already-partially-done) work into the next
  /// already-planned session for the same knowledge node, rather than
  /// re-inserting it as a separate standalone item.
  merge,

  /// Push it later without urgency — low stakes, no imminent deadline.
  defer,

  /// Skip this occurrence entirely for now; revisit later rather than
  /// compounding an already-overloaded schedule. Temporarily, not
  /// permanently — nothing about this decision deletes the Task itself.
  dropTemporarily,

  /// This task's fate cannot be decided in isolation — hand off to
  /// dynamic_replanning_engine.dart for a full re-schedule pass (used
  /// when the whole workload situation, not just this one task, is
  /// broken).
  replan,
}

class MissedTaskContext {
  const MissedTaskContext({
    required this.taskId,
    required this.priorityScore,
    this.hoursUntilHardDeadline,
    required this.isPartiallyComplete,
    required this.currentWorkloadStatus,
  }) : assert(priorityScore >= 0 && priorityScore <= 1);

  final String taskId;

  /// [0, 1], from priority_engine.dart.
  final double priorityScore;

  /// Hours until the nearest HARD Deadline affecting this task, or null
  /// if none is known. Never a soft deadline — those are absorbed into
  /// priorityScore's urgencyImportance signal already, not re-consulted
  /// here (avoids double-counting the same information twice).
  final double? hoursUntilHardDeadline;

  final bool isPartiallyComplete;
  final WorkloadClassification currentWorkloadStatus;
}

class RecoveryDecisionResult {
  const RecoveryDecisionResult({
    required this.decision,
    required this.reasoning,
  });

  final RecoveryDecisionKind decision;
  final String reasoning;
}

class RecoveryEngine {
  const RecoveryEngine({
    this.highPriorityThreshold = 0.7,
    this.lowPriorityThreshold = 0.3,
    this.nearDeadlineHours = 24.0,
  });

  final double highPriorityThreshold;
  final double lowPriorityThreshold;
  final double nearDeadlineHours;

  RecoveryDecisionResult decide(MissedTaskContext ctx) {
    // Workload-impossible overrides everything else for this task: the
    // whole plan is broken, not just this one item, so a single-task
    // decision would be premature — hand off to a full replan.
    if (ctx.currentWorkloadStatus == WorkloadClassification.impossible) {
      return const RecoveryDecisionResult(
        decision: RecoveryDecisionKind.replan,
        reasoning: 'Current workload status is impossible — this task '
            "can't be triaged in isolation; the whole schedule needs a "
            'replan pass.',
      );
    }

    final nearDeadline = ctx.hoursUntilHardDeadline != null &&
        ctx.hoursUntilHardDeadline! <= nearDeadlineHours;

    if (nearDeadline) {
      return RecoveryDecisionResult(
        decision: RecoveryDecisionKind.keep,
        reasoning: 'Hard deadline within ${ctx.hoursUntilHardDeadline!.toStringAsFixed(1)}'
            ' hours — stays scheduled for immediate catch-up regardless of '
            'workload pressure.',
      );
    }

    if (ctx.isPartiallyComplete && ctx.priorityScore >= highPriorityThreshold) {
      return const RecoveryDecisionResult(
        decision: RecoveryDecisionKind.merge,
        reasoning: 'High priority and already partially done — combine the '
            'remaining work into the next planned session for the same '
            'node instead of restarting it as a separate item.',
      );
    }

    if (ctx.priorityScore >= highPriorityThreshold) {
      return const RecoveryDecisionResult(
        decision: RecoveryDecisionKind.move,
        reasoning: 'High priority, no imminent hard deadline — reschedule '
            'to the next available slot.',
      );
    }

    if (ctx.priorityScore <= lowPriorityThreshold &&
        ctx.currentWorkloadStatus == WorkloadClassification.overload) {
      return const RecoveryDecisionResult(
        decision: RecoveryDecisionKind.dropTemporarily,
        reasoning: 'Low priority and the schedule is already overloaded — '
            'skip this occurrence for now rather than compounding the '
            'overload; revisit later.',
      );
    }

    return const RecoveryDecisionResult(
      decision: RecoveryDecisionKind.defer,
      reasoning: 'Moderate priority, no imminent deadline, workload not '
          'overloaded — push later without urgency.',
    );
  }
}
