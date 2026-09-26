import 'package:test/test.dart';

import 'package:student_app/engines/recovery_engine.dart';
import 'package:student_app/engines/workload_engine.dart' show WorkloadClassification;

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment).
void main() {
  const engine = RecoveryEngine();

  group('not a blanket policy — different contexts land on different '
      'decisions', () {
    test('workload impossible always yields replan, overriding every '
        'other factor', () {
      final r = engine.decide(const MissedTaskContext(
        taskId: 't1',
        priorityScore: 0.1,
        hoursUntilHardDeadline: 200,
        isPartiallyComplete: false,
        currentWorkloadStatus: WorkloadClassification.impossible,
      ));
      expect(r.decision, RecoveryDecisionKind.replan);
    });

    test('an imminent hard deadline yields keep, even at moderate '
        'priority', () {
      final r = engine.decide(const MissedTaskContext(
        taskId: 't1',
        priorityScore: 0.5,
        hoursUntilHardDeadline: 4,
        isPartiallyComplete: false,
        currentWorkloadStatus: WorkloadClassification.balanced,
      ));
      expect(r.decision, RecoveryDecisionKind.keep);
    });

    test('high priority + partially complete + no imminent deadline '
        'yields merge', () {
      final r = engine.decide(const MissedTaskContext(
        taskId: 't1',
        priorityScore: 0.85,
        hoursUntilHardDeadline: null,
        isPartiallyComplete: true,
        currentWorkloadStatus: WorkloadClassification.balanced,
      ));
      expect(r.decision, RecoveryDecisionKind.merge);
    });

    test('high priority, not partially complete, no imminent deadline '
        'yields move', () {
      final r = engine.decide(const MissedTaskContext(
        taskId: 't1',
        priorityScore: 0.85,
        hoursUntilHardDeadline: null,
        isPartiallyComplete: false,
        currentWorkloadStatus: WorkloadClassification.balanced,
      ));
      expect(r.decision, RecoveryDecisionKind.move);
    });

    test('low priority + overloaded workload yields dropTemporarily', () {
      final r = engine.decide(const MissedTaskContext(
        taskId: 't1',
        priorityScore: 0.1,
        hoursUntilHardDeadline: null,
        isPartiallyComplete: false,
        currentWorkloadStatus: WorkloadClassification.overload,
      ));
      expect(r.decision, RecoveryDecisionKind.dropTemporarily);
    });

    test('moderate priority, no imminent deadline, not overloaded yields '
        'defer', () {
      final r = engine.decide(const MissedTaskContext(
        taskId: 't1',
        priorityScore: 0.5,
        hoursUntilHardDeadline: null,
        isPartiallyComplete: false,
        currentWorkloadStatus: WorkloadClassification.balanced,
      ));
      expect(r.decision, RecoveryDecisionKind.defer);
    });

    test('two tasks missed at the exact same moment, differing only in '
        'priority, can land on two different decisions — this is the '
        'explicit "not everything moves to tomorrow" requirement', () {
      const base = (
        hoursUntilHardDeadline: null,
        isPartiallyComplete: false,
        currentWorkloadStatus: WorkloadClassification.overload,
      );
      final highPriority = engine.decide(MissedTaskContext(
        taskId: 'a',
        priorityScore: 0.9,
        hoursUntilHardDeadline: base.hoursUntilHardDeadline,
        isPartiallyComplete: base.isPartiallyComplete,
        currentWorkloadStatus: base.currentWorkloadStatus,
      ));
      final lowPriority = engine.decide(MissedTaskContext(
        taskId: 'b',
        priorityScore: 0.1,
        hoursUntilHardDeadline: base.hoursUntilHardDeadline,
        isPartiallyComplete: base.isPartiallyComplete,
        currentWorkloadStatus: base.currentWorkloadStatus,
      ));
      expect(highPriority.decision, isNot(lowPriority.decision));
    });
  });

  group('reasoning is always present', () {
    test('reasoning is never empty, for every branch', () {
      final contexts = [
        const MissedTaskContext(
            taskId: 't',
            priorityScore: 0.5,
            currentWorkloadStatus: WorkloadClassification.impossible,
            isPartiallyComplete: false),
        const MissedTaskContext(
            taskId: 't',
            priorityScore: 0.5,
            hoursUntilHardDeadline: 1,
            currentWorkloadStatus: WorkloadClassification.balanced,
            isPartiallyComplete: false),
        const MissedTaskContext(
            taskId: 't',
            priorityScore: 0.9,
            currentWorkloadStatus: WorkloadClassification.balanced,
            isPartiallyComplete: true),
      ];
      for (final c in contexts) {
        expect(engine.decide(c).reasoning, isNotEmpty);
      }
    });
  });
}
