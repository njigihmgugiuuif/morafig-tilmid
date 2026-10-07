import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../database/app_database.dart';
import '../domain/examination_domain.dart';
import '../domain/knowledge_graph_domain.dart';
import '../domain/reality_layer_domain.dart';
import '../engines/dynamic_replanning_engine.dart';
import '../engines/emergency_engine.dart';
import '../engines/priority_engine.dart';
import '../engines/recovery_engine.dart';
import '../engines/scheduling_engine.dart';
import '../engines/weekly_planner.dart';
import '../engines/weekly_timeline_engine.dart';
import '../engines/workload_engine.dart';
import '../events/event_types.dart';
import '../repositories/availability_repository.dart';
import '../repositories/curriculum_repository.dart';
import '../repositories/deadline_repository.dart';
import '../repositories/emergency_repository.dart';
import '../repositories/event_repository.dart';
import '../repositories/exam_repository.dart';
import '../repositories/explanation_and_override_repositories.dart';
import '../repositories/mastery_repository.dart';
import '../repositories/priority_repository.dart';
import '../repositories/reality_and_prerequisite_repositories.dart';
import '../repositories/recovery_repository.dart';
import '../repositories/student_repository.dart';
import '../repositories/study_session_repository.dart';
import '../repositories/weekly_template_repository.dart';
import '../repositories/workload_repository.dart';

/// Result of one plan generation (B).
class PlanGenerationResult {
  const PlanGenerationResult({
    required this.weekStart,
    required this.sessionsSaved,
    required this.scheduledMinutes,
    required this.unscheduled,
    required this.gaps,
    required this.changes,
    required this.unprioritizedTaskIds,
    required this.droppedTaskIds,
    required this.emergencyActive,
    required this.workload,
    required this.reason,
    required this.explanationId,
    required this.planEventId,
  });

  final DateTime weekStart;
  final int sessionsSaved;
  final int scheduledMinutes;

  /// Every task that did not get its full time, with the scheduler's own
  /// reason (nothing is silently dropped).
  final List<UnscheduledEntry> unscheduled;
  final List<GapFindingSummary> gaps;
  final List<PlanChange> changes;

  /// Tasks that have no Priority yet (no signal available). They were
  /// placed AFTER every prioritised task, never given an invented score.
  final List<String> unprioritizedTaskIds;

  /// Tasks Recovery set aside temporarily (dropTemporarily) for this week.
  final List<String> droppedTaskIds;
  final bool emergencyActive;
  final WorkloadClassification workload;
  final ReplanReason reason;
  final String explanationId;
  final String planEventId;
}

/// A Gap finding reduced to what is stored / shown (stable code + task).
class GapFindingSummary {
  const GapFindingSummary({required this.code, this.taskId});
  final String code;
  final String? taskId;
}

/// What happened when the app was opened (B).
class AppOpenResult {
  const AppOpenResult({
    required this.status,
    required this.missedTaskIds,
    required this.recoveryDecisions,
    required this.replanReasons,
    required this.generation,
    required this.errors,
  });

  /// `noStudent` | `firstPlan` | `replanned` | `unchanged`.
  final String status;
  final List<String> missedTaskIds;

  /// taskId -> RecoveryDecisionKind.name for the tasks decided in this run.
  final Map<String, String> recoveryDecisions;
  final List<String> replanReasons;
  final PlanGenerationResult? generation;
  final List<String> errors;

  bool get replanned => status == 'firstPlan' || status == 'replanned';
}

class _Candidate {
  _Candidate({
    required this.task,
    required this.score,
    required this.prioritised,
    required this.prerequisiteSatisfied,
    required this.factorValues,
  });
  final Task task;
  final double score;
  final bool prioritised;
  final bool prerequisiteSatisfied;

  /// Signal values stored with the task's Priority explanation, or null.
  final Map<PrioritySignalKind, double>? factorValues;
}

class _Prepared {
  _Prepared({
    required this.student,
    required this.now,
    required this.weekStart,
    required this.floor,
    required this.fixedBlocks,
    required this.studyWindows,
    required this.markers,
    required this.candidates,
    required this.droppedTaskIds,
    required this.directives,
    required this.daysUntilNearestExam,
    required this.anchorTaskIds,
  });
  final Student student;
  final DateTime now;
  final DateTime weekStart;
  final DateTime floor;
  final List<TimelineBlock> fixedBlocks;
  final List<TimeSlot> studyWindows;
  final List<TimelineMarker> markers;
  final List<_Candidate> candidates;
  final Set<String> droppedTaskIds;

  /// taskId -> latest RecoveryDecisionKind.name decided this week.
  final Map<String, String> directives;
  final int? daysUntilNearestExam;

  /// Tasks that already have a future planned session (merge anchors).
  final Set<String> anchorTaskIds;
}

class _Computed {
  _Computed({
    required this.plan,
    required this.orderedItems,
    required this.normalWorkload,
    required this.finalWorkload,
    required this.emergencyTrigger,
    required this.emergencyReasoning,
  });
  final WeekPlan plan;
  final List<SchedulableItem> orderedItems;
  final WorkloadResult normalWorkload;
  final WorkloadResult finalWorkload;
  final EmergencyTriggerKind? emergencyTrigger;
  final String emergencyReasoning;
}

/// B — the planning service (DEVIATION-22).
///
/// It is the only place that joins the engines that already existed:
///
///   Priority (A, PriorityStates)  ->  order
///   Reality (template + hard constraints + availability)  ->  free slots
///   Knowledge Graph  ->  prerequisiteSatisfied
///   Workload + Emergency  ->  weights/thresholds ONLY (never a constraint)
///   WeeklyPlanner (Scheduling + Weekly Timeline + Gap Detection)  ->  plan
///   Recovery / Dynamic Replanning  ->  what to do when reality differs
///
/// and SAVES the result (StudySessions / TaskSegments) with events and an
/// Explanation, so a plan is auditable. It never edits an engine, never
/// writes Reality (the student does), never invents a school timetable and
/// never places study time inside a hard block: [_assertHardBlocksRespected]
/// re-checks the finished plan and throws before anything is saved.
///
/// There is no background work (no server): [onAppOpen] is the trigger.
class PlanningService {
  PlanningService(
    this._db, {
    DateTime Function()? clock,
    this.prerequisiteMasteryThreshold = 0.5,
    this.planner = const WeeklyPlanner(),
    this.replanning = const DynamicReplanningEngine(),
    this.recovery = const RecoveryEngine(),
    this.emergency = const EmergencyModeEngine(),
    this.workloadEngine = const WorkloadEngine(),
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Mastery a prerequisite node must reach before a dependent task may be
  /// placed. INITIAL HEURISTIC (no approved value exists in the project);
  /// flagged for the owner in DEVIATION-22.
  final double prerequisiteMasteryThreshold;

  final WeeklyPlanner planner;
  final DynamicReplanningEngine replanning;
  final RecoveryEngine recovery;
  final EmergencyModeEngine emergency;
  final WorkloadEngine workloadEngine;

  // ------------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------------

  /// Builds and SAVES the plan of the week containing [weekOf] (default: the
  /// current week). Returns null when there is no student yet.
  Future<PlanGenerationResult?> generateWeekPlan({
    DateTime? weekOf,
    ReplanReason reason = ReplanReason.manual,
    String detail = '',
  }) async {
    final prepared = await _prepare(weekOf);
    if (prepared == null) return null;
    final computed = await _compute(prepared);
    return _persist(prepared, computed, reason, detail);
  }

  /// The app-open trigger: records missed sessions, decides Recovery for each
  /// missed task, and replans only when a signal justifies it (hysteresis is
  /// the Dynamic Replanning Engine's own). Errors are collected, never thrown.
  Future<AppOpenResult> onAppOpen({DateTime? weekOf}) async {
    final errors = <String>[];
    final missedTaskIds = <String>[];
    final decisions = <String, String>{};
    try {
      final student = await StudentRepository(_db).readExisting();
      if (student == null) {
        return const AppOpenResult(
          status: 'noStudent',
          missedTaskIds: [],
          recoveryDecisions: {},
          replanReasons: [],
          generation: null,
          errors: [],
        );
      }
      final now = _clock();

      // 1. Missed sessions -> TaskMissed events -> Recovery decisions.
      try {
        final missed = await _detectMissed(student, now);
        missedTaskIds.addAll(missed.keys);
        decisions.addAll(await _decideRecovery(student, missed, now));
      } catch (e) {
        errors.add('missed: $e');
      }

      // 2. Current state of the world, computed once, nothing saved yet.
      final prepared = await _prepare(weekOf);
      if (prepared == null) {
        return AppOpenResult(
          status: 'noStudent',
          missedTaskIds: missedTaskIds,
          recoveryDecisions: decisions,
          replanReasons: const [],
          generation: null,
          errors: errors,
        );
      }
      final computed = await _compute(prepared);

      // 3. First plan for this week?
      final lastPlan = await _lastPlanEvent(prepared.weekStart);
      if (lastPlan == null) {
        final g = await _persist(prepared, computed, ReplanReason.manual,
            'first_plan_for_week');
        return AppOpenResult(
          status: 'firstPlan',
          missedTaskIds: missedTaskIds,
          recoveryDecisions: decisions,
          replanReasons: const ['first_plan_for_week'],
          generation: g,
          errors: errors,
        );
      }

      // 4. Signals since the last plan.
      final lastAt = _generatedAt(lastPlan);
      final signals = <ReplanningSignal>[];
      final reasons = <String>[];
      ReplanReason primary = ReplanReason.manual;
      var primarySet = false;
      void note(ReplanReason r, String text) {
        reasons.add(text);
        if (!primarySet) {
          primary = r;
          primarySet = true;
        }
      }

      for (var i = 0; i < missedTaskIds.length; i++) {
        signals.add(const ReplanningSignal(
            kind: ReplanTriggerKind.missedSession));
      }
      if (missedTaskIds.isNotEmpty) {
        note(ReplanReason.taskNotCompleted, 'missed_session');
      }

      final sessions = StudySessionRepository(_db);
      final weekEnd = WeekCalendar.endOfWeek(prepared.weekStart);
      final inWeek =
          await sessions.readOverlapping(prepared.weekStart, weekEnd);
      for (final s in inWeek) {
        final obs = s.observedDurationMinutes;
        final aEnd = s.actualEnd;
        if (obs == null || aEnd == null || !aEnd.isAfter(lastAt)) continue;
        final planned = s.plannedEnd.difference(s.plannedStart).inMinutes;
        final mag = (obs - planned).abs();
        signals.add(ReplanningSignal(
            kind: ReplanTriggerKind.durationDeviation, magnitudeMinutes: mag));
        if (mag >= replanning.durationDeviationThresholdMinutes) {
          note(obs > planned
              ? ReplanReason.taskFinishedLate
              : ReplanReason.taskFinishedEarly, 'duration_deviation');
        }
      }

      // New hard/soft unavailability that overlaps time that is still planned.
      final futurePlanned = inWeek
          .where((s) =>
              s.actualStart == null && s.plannedEnd.isAfter(prepared.now))
          .toList();
      final constraints =
          await RealityConstraintRepository(_db).readForStudent(student.id);
      for (final c in constraints) {
        if (!c.createdAt.isAfter(lastAt)) continue;
        final overlaps = futurePlanned.any((s) =>
            s.plannedStart.isBefore(c.windowEnd) &&
            s.plannedEnd.isAfter(c.windowStart));
        if (overlaps) {
          signals.add(const ReplanningSignal(
              kind: ReplanTriggerKind.newUnavailability));
          note(ReplanReason.scheduleChanged, 'new_unavailability');
        }
      }

      // Workload classification changed since the last plan.
      final storedWorkload = await WorkloadRepository(_db).read(student.id);
      if (storedWorkload != null &&
          storedWorkload.status != computed.normalWorkload.classification.name) {
        signals.add(const ReplanningSignal(
            kind: ReplanTriggerKind.workloadStatusChanged));
        note(ReplanReason.scheduleChanged, 'workload_status_changed');
      }

      final decision = replanning.evaluate(signals);

      // Things the student changed that the Dynamic Replanning Engine has no
      // signal kind for. They are caller-level triggers, reported as such.
      var extra = false;
      final newTasks = prepared.candidates
          .where((c) => c.task.createdAt.isAfter(lastAt))
          .isNotEmpty;
      if (newTasks) {
        extra = true;
        note(ReplanReason.taskAdded, 'task_added');
      }
      final avail = await AvailabilityRepository(_db).readForStudent(student.id);
      if (avail.any((a) => a.createdAt.isAfter(lastAt))) {
        extra = true;
        note(ReplanReason.availabilityChanged, 'availability_added');
      }
      final template =
          await WeeklyTemplateRepository(_db).readForStudent(student.id);
      if (template.any((t) => t.createdAt.isAfter(lastAt))) {
        extra = true;
        note(ReplanReason.scheduleChanged, 'weekly_template_added');
      }

      if (!decision.shouldReplan && !extra) {
        return AppOpenResult(
          status: 'unchanged',
          missedTaskIds: missedTaskIds,
          recoveryDecisions: decisions,
          replanReasons: const [],
          generation: null,
          errors: errors,
        );
      }

      await _emit('PlanInvalidated', {
        'weekStart': prepared.weekStart.toIso8601String(),
        'reasons': reasons,
        'engineReasoning': decision.reasoning,
      }, triggersReplan: false);
      final g = await _persist(
          prepared, computed, primary, reasons.join(','));
      return AppOpenResult(
        status: 'replanned',
        missedTaskIds: missedTaskIds,
        recoveryDecisions: decisions,
        replanReasons: reasons,
        generation: g,
        errors: errors,
      );
    } catch (e) {
      errors.add('plan: $e');
      return AppOpenResult(
        status: 'unchanged',
        missedTaskIds: missedTaskIds,
        recoveryDecisions: decisions,
        replanReasons: const [],
        generation: null,
        errors: errors,
      );
    }
  }

  /// Student-requested replan (the ReplanTriggerKind.manualRequest case).
  Future<PlanGenerationResult?> replanNow({
    DateTime? weekOf,
    String detail = 'manual_request',
  }) async {
    final prepared = await _prepare(weekOf);
    if (prepared == null) return null;
    await _emit('PlanInvalidated', {
      'weekStart': prepared.weekStart.toIso8601String(),
      'reasons': ['manual_request'],
    }, triggersReplan: false);
    final computed = await _compute(prepared);
    return _persist(prepared, computed, ReplanReason.manual, detail);
  }

  /// Stores what really happened in a session (used by the UI later).
  Future<StudySession> recordSessionActual({
    required String sessionId,
    required DateTime actualStart,
    required DateTime actualEnd,
  }) =>
      StudySessionRepository(_db).recordActual(
        sessionId: sessionId,
        actualStart: actualStart,
        actualEnd: actualEnd,
      );

  /// Planned vs actual per task for one week (the engine's own comparison).
  Future<List<TaskReality>> compareWeekWithActual({DateTime? weekOf}) async {
    final weekStart = WeekCalendar.startOfWeek((weekOf ?? _clock()).toLocal());
    final weekEnd = WeekCalendar.endOfWeek(weekStart);
    final rows =
        await StudySessionRepository(_db).readOverlapping(weekStart, weekEnd);
    final planned = [
      for (final s in rows)
        ScheduledChunk(
            taskId: s.taskId, start: s.plannedStart, end: s.plannedEnd),
    ];
    final actual = <ActualSession>[];
    for (final s in rows) {
      final a = s.actualStart;
      final b = s.actualEnd;
      if (a != null && b != null && b.isAfter(a)) {
        actual.add(ActualSession(taskId: s.taskId, start: a, end: b));
      }
    }
    return const WeekTimelineEngine()
        .compareWithActual(planned: planned, actual: actual);
  }

  // ------------------------------------------------------------------
  // Missed sessions and Recovery
  // ------------------------------------------------------------------

  /// Writes a TaskMissed event for every planned session that ended without
  /// an actual and has not been flagged yet (idempotent). Returns
  /// taskId -> id of the LAST new TaskMissed event of that task.
  Future<Map<String, String>> _detectMissed(Student student, DateTime now) async {
    final sessions = StudySessionRepository(_db);
    final ended = await sessions.readUnexecutedEndedBy(now);
    if (ended.isEmpty) return {};

    final already = <String>{};
    for (final e in await EventRepository(_db).readByType('TaskMissed')) {
      try {
        final p = jsonDecode(e.payloadJson) as Map<String, dynamic>;
        final id = p['sessionId'];
        if (id is String) already.add(id);
      } catch (_) {}
    }

    final out = <String, String>{};
    for (final s in ended) {
      if (already.contains(s.id)) continue;
      final task = await (_db.select(_db.tasks)
            ..where((t) => t.id.equals(s.taskId)))
          .getSingleOrNull();
      // A task finished by other means is not "missed".
      if (task == null || task.completionStatus == 'complete') continue;
      final ev = await _emit('TaskMissed', {
        'taskId': s.taskId,
        'sessionId': s.id,
        'plannedStart': s.plannedStart.toIso8601String(),
        'plannedEnd': s.plannedEnd.toIso8601String(),
      }, triggersReplan: true);
      out[s.taskId] = ev.id;
    }
    return out;
  }

  /// One Recovery decision per missed task, stored with its reasoning.
  Future<Map<String, String>> _decideRecovery(
    Student student,
    Map<String, String> missed,
    DateTime now,
  ) async {
    if (missed.isEmpty) return {};
    final stored = await WorkloadRepository(_db).read(student.id);
    final workload = _classificationFromName(stored?.status);
    final deadlines = DeadlineRepository(_db);
    final priority = PriorityRepository(_db);
    final repo = RecoveryRepository(_db);

    final out = <String, String>{};
    for (final entry in missed.entries) {
      final task = await (_db.select(_db.tasks)
            ..where((t) => t.id.equals(entry.key)))
          .getSingleOrNull();
      if (task == null) continue;
      final ps = await priority.read(task.id);
      final dates = await deadlines.readHardDueDatesForTask(
        taskId: task.id,
        sourceAssignmentId: task.sourceAssignmentId,
      );
      double? hours;
      for (final d in dates) {
        final h = d.difference(now).inMinutes / 60.0;
        if (hours == null || h < hours) hours = h;
      }
      final result = recovery.decide(MissedTaskContext(
        taskId: task.id,
        priorityScore: (ps?.score ?? 0.0).clamp(0.0, 1.0),
        hoursUntilHardDeadline: hours,
        isPartiallyComplete: task.completionStatus == 'partial' ||
            task.remainingDurationMinutes < task.estimatedDurationMinutes,
        currentWorkloadStatus: workload,
      ));
      await repo.record(
        triggerEventId: entry.value,
        affectedTaskId: task.id,
        result: result,
      );
      out[task.id] = result.de
