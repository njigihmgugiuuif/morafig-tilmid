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
      out[task.id] = result.decision.name;
    }
    return out;
  }

  WorkloadClassification _classificationFromName(String? name) {
    for (final c in WorkloadClassification.values) {
      if (c.name == name) return c;
    }
    // No stored workload means no plan was ever generated, so nothing can
    // have been missed; the neutral class keeps Recovery's table usable.
    return WorkloadClassification.balanced;
  }

  // ------------------------------------------------------------------
  // Reading the world
  // ------------------------------------------------------------------

  Future<_Prepared?> _prepare(DateTime? weekOf) async {
    final student = await StudentRepository(_db).readExisting();
    if (student == null) return null;

    final now = _clock();
    final weekStart =
        WeekCalendar.startOfWeek((weekOf ?? now).toLocal());
    final weekEnd = WeekCalendar.endOfWeek(weekStart);

    // Floor: nothing is placed before "now" (rounded up to the next minute)
    // nor inside a session that is running right now.
    var floor = weekStart;
    final local = now.toLocal();
    if (local.isAfter(weekStart)) {
      var f = DateTime(local.year, local.month, local.day, local.hour,
          local.minute);
      if (f.isBefore(local)) f = f.add(const Duration(minutes: 1));
      if (f.isAfter(floor)) floor = f;
    }
    final sessionsRepo = StudySessionRepository(_db);
    for (final s in await sessionsRepo.readUnexecutedStraddling(floor)) {
      if (s.plannedEnd.isAfter(floor)) floor = s.plannedEnd;
    }

    // Fixed blocks: the student's template + the student's constraints.
    final fixed = <TimelineBlock>[];
    final slots =
        await WeeklyTemplateRepository(_db).readSlotsForStudent(student.id);
    fixed.addAll(WeekTimelineEngine.expandTemplate(
        weekStart: weekStart, slots: slots));
    final constraints =
        await RealityConstraintRepository(_db).readForStudent(student.id);
    for (final c in constraints) {
      if (!c.windowEnd.isAfter(c.windowStart)) continue;
      if (!c.windowEnd.isAfter(weekStart) || !c.windowStart.isBefore(weekEnd)) {
        continue;
      }
      fixed.add(TimelineBlock(
        kind: _kindForConstraint(c.type),
        start: c.windowStart,
        end: c.windowEnd,
        label: c.type,
        refId: c.id,
        isHard: c.isHard,
      ));
    }

    // Exams of this week are markers (an exam has no stored duration, so no
    // duration is invented).
    final exams = ExamRepository(_db);
    final weekExams = await exams.readInRange(from: weekStart, to: weekEnd);
    final markers = [
      for (final e in weekExams)
        TimelineMarker(at: e.examDate, refId: e.id, label: 'exam'),
    ];

    // Study windows: declared availability minus HARD constraints.
    final reality = RealityLayerDomainService(
      AvailabilityRepository(_db),
      RealityConstraintRepository(_db),
    );
    final windows = await reality.computeFreeSlots(
      studentId: student.id,
      rangeStart: weekStart,
      rangeEnd: weekEnd,
    );

    // Recovery directives that still apply to this week.
    final directives = <String, String>{};
    final dropped = <String>{};
    directives.addAll(await _directivesForWeek(weekStart, weekEnd));
    for (final e in directives.entries) {
      if (e.value == RecoveryDecisionKind.dropTemporarily.name) {
        dropped.add(e.key);
      }
    }

    // Candidates.
    final taskRows = (await _db.select(_db.tasks).get())
        .where((t) => t.completionStatus != 'complete')
        .toList();
    final graph = KnowledgeGraphDomainService(
      PrerequisiteRepository(_db),
      MasteryRepository(_db),
      curriculum: CurriculumRepository(_db),
    );
    final priority = PriorityRepository(_db);
    final explanations = ExplanationRepository(_db);
    final candidates = <_Candidate>[];
    for (final t in taskRows) {
      if (t.remainingDurationMinutes <= 0) continue;
      final ps = await priority.read(t.id);
      Map<PrioritySignalKind, double>? factors;
      if (ps != null) {
        factors = await _factorValues(explanations, ps.explanationId);
      }
      final pre = await graph.checkDirectHardPrerequisites(
        studentId: student.id,
        knowledgeNodeId: t.knowledgeNodeId,
        masteryThreshold: prerequisiteMasteryThreshold,
      );
      candidates.add(_Candidate(
        task: t,
        score: ps == null ? 0.0 : ps.score.clamp(0.0, 1.0),
        prioritised: ps != null,
        prerequisiteSatisfied: pre.satisfied,
        factorValues: factors,
      ));
    }

    // Merge anchors: tasks that already have a FUTURE planned session.
    final anchors = <String>{};
    for (final s in await sessionsRepo.readOverlapping(floor, weekEnd)) {
      if (s.actualStart == null) anchors.add(s.taskId);
    }

    final days = await ExaminationDomainService(exams)
        .daysUntilNearestExam(now: now);

    return _Prepared(
      student: student,
      now: now,
      weekStart: weekStart,
      floor: floor,
      fixedBlocks: fixed,
      studyWindows: windows,
      markers: markers,
      candidates: candidates,
      droppedTaskIds: dropped,
      directives: directives,
      daysUntilNearestExam: days,
      anchorTaskIds: anchors,
    );
  }

  /// Recovery decisions that apply to a week: those whose TRIGGERING missed
  /// session was planned inside that week. Read through the TaskMissed event
  /// (not through a wall-clock time), so it is the same on every run. The
  /// latest decision per task wins.
  Future<Map<String, String>> _directivesForWeek(
    DateTime weekStart,
    DateTime weekEnd,
  ) async {
    final events = EventRepository(_db);
    final records = await RecoveryRepository(_db).readAll();
    records.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final out = <String, String>{};
    for (final r in records) {
      final ev = await events.readById(r.triggerEventId);
      if (ev == null) continue;
      try {
        final payload = jsonDecode(ev.payloadJson) as Map<String, dynamic>;
        final start = DateTime.tryParse('${payload['plannedStart']}');
        if (start == null) continue;
        if (!start.isBefore(weekStart) && start.isBefore(weekEnd)) {
          out[r.affectedTaskId] = r.decision;
        }
      } catch (_) {}
    }
    return out;
  }

  Future<Map<PrioritySignalKind, double>?> _factorValues(
    ExplanationRepository repo,
    String explanationId,
  ) async {
    try {
      final ex = await repo.readById(explanationId);
      if (ex == null) return null;
      final raw = jsonDecode(ex.factorsJson);
      if (raw is! Map) return null;
      final out = <PrioritySignalKind, double>{};
      raw.forEach((k, v) {
        final kind = prioritySignalKindFromStoredName(k.toString());
        if (kind == null || v is! Map) return;
        final value = v['value'];
        if (value is num) out[kind] = value.toDouble();
      });
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  TimelineBlockKind _kindForConstraint(String type) {
    switch (type) {
      case 'school':
        return TimelineBlockKind.school;
      case 'commute':
        return TimelineBlockKind.commute;
      case 'fixedCommitment':
        return TimelineBlockKind.commitment;
      case 'rest':
        return TimelineBlockKind.rest;
      case 'sleep':
        return TimelineBlockKind.sleep;
      case 'activity':
        return TimelineBlockKind.activity;
      default:
        return TimelineBlockKind.unexpected;
    }
  }

  // ------------------------------------------------------------------
  // Computing the plan (no writes)
  // ------------------------------------------------------------------

  Future<_Computed> _compute(_Prepared p) async {
    final normalItems = _order(p, null);
    final plan1 = _runPlanner(p, normalItems);

    final needed = p.candidates
        .where((c) =>
            c.prerequisiteSatisfied && !p.droppedTaskIds.contains(c.task.id))
        .fold<int>(0, (s, c) => s + c.task.remainingDurationMinutes);
    final available =
        plan1.freeSlots.fold<int>(0, (s, f) => s + f.durationMinutes);
    final normalWorkload =
        workloadEngine.compute(neededMinutes: needed, availableMinutes: available);

    final eval = emergency.evaluate(
      daysUntilNearestExam: p.daysUntilNearestExam,
      currentWorkloadStatus: normalWorkload.classification,
    );

    if (!eval.triggered) {
      return _Computed(
        plan: plan1,
        orderedItems: normalItems,
        normalWorkload: normalWorkload,
        finalWorkload: normalWorkload,
        emergencyTrigger: null,
        emergencyReasoning: eval.reasoning,
      );
    }

    // Emergency: only the ORDER changes (weights); fixed blocks, study
    // windows and prerequisite checks are exactly the same inputs.
    final items = _order(p, eval.trigger);
    final plan = _runPlanner(p, items);
    final looser = emergency.adjustWorkloadEngine(workloadEngine);
    return _Computed(
      plan: plan,
      orderedItems: items,
      normalWorkload: normalWorkload,
      finalWorkload: looser.compute(
          neededMinutes: needed, availableMinutes: available),
      emergencyTrigger: eval.trigger,
      emergencyReasoning: eval.reasoning,
    );
  }

  WeekPlan _runPlanner(_Prepared p, List<SchedulableItem> items) {
    final plan = planner.plan(
      weekStart: p.weekStart,
      studyWindows: p.studyWindows,
      fixedBlocks: p.fixedBlocks,
      orderedItems: items,
      notBefore: p.floor,
      now: p.floor,
      markers: p.markers,
    );
    _assertHardBlocksRespected(plan, p.fixedBlocks);
    return plan;
  }

  /// Safety net: no chunk may overlap a HARD fixed block (sleep, school,
  /// commute, commitments...). By construction it cannot, so a failure here
  /// is a bug and the plan is never saved.
  void _assertHardBlocksRespected(WeekPlan plan, List<TimelineBlock> fixed) {
    for (final c in plan.scheduling.scheduledChunks) {
      for (final b in fixed.where((b) => b.isHard)) {
        if (c.start.isBefore(b.end) && c.end.isAfter(b.start)) {
          throw StateError(
              'Plan violates hard ${b.kind.name} block for task ${c.taskId}.');
        }
      }
    }
  }

  /// Priority order with Recovery directives, and Emergency weights when
  /// [trigger] is not null. Deterministic: same inputs, same order.
  List<SchedulableItem> _order(_Prepared p, EmergencyTriggerKind? trigger) {
    double scoreOf(_Candidate c) {
      if (trigger == null || c.factorValues == null) return c.score;
      final v = c.factorValues!;
      final signals = PrioritySignals(
        masteryGap: v[PrioritySignalKind.masteryGap],
        forgettingRisk: v[PrioritySignalKind.forgettingRisk],
        officialCoefficient: v[PrioritySignalKind.officialCoefficient],
        examProximity: v[PrioritySignalKind.examProximity],
        deadlinePressure: v[PrioritySignalKind.deadlinePressure],
        longTermGoalAlignment: v[PrioritySignalKind.longTermGoalAlignment],
      );
      return const PriorityEngine()
          .compute(
            signals: signals,
            weights:
                emergency.adjustPriorityWeights(PriorityWeights.defaults(), trigger),
          )
          .score;
    }

    int group(_Candidate c) {
      final d = p.directives[c.task.id];
      if (d == RecoveryDecisionKind.keep.name) return 0;
      if (d == RecoveryDecisionKind.defer.name) return 2;
      return 1;
    }

    final pool =
        p.candidates.where((c) => !p.droppedTaskIds.contains(c.task.id)).toList();
    final scored = {for (final c in pool) c.task.id: scoreOf(c)};
    pool.sort((a, b) {
      final g = group(a).compareTo(group(b));
      if (g != 0) return g;
      final s = scored[b.task.id]!.compareTo(scored[a.task.id]!);
      if (s != 0) return s;
      final t = a.task.createdAt.compareTo(b.task.createdAt);
      if (t != 0) return t;
      return a.task.id.compareTo(b.task.id);
    });

    // merge: place the task right after an already-planned task of the same
    // knowledge node, so the scheduler puts them in the same free slot.
    for (final c in List<_Candidate>.of(pool)) {
      if (p.directives[c.task.id] != RecoveryDecisionKind.merge.name) continue;
      final anchorIdx = pool.indexWhere((o) =>
          o.task.id != c.task.id &&
          o.task.knowledgeNodeId == c.task.knowledgeNodeId &&
          p.anchorTaskIds.contains(o.task.id));
      if (anchorIdx < 0) continue;
      final anchorId = pool[anchorIdx].task.id;
      pool.removeWhere((o) => o.task.id == c.task.id);
      final idx = pool.indexWhere((o) => o.task.id == anchorId);
      pool.insert(idx + 1, c);
    }

    return [
      for (final c in pool)
        SchedulableItem(
          taskId: c.task.id,
          priorityScore: scored[c.task.id]!.clamp(0.0, 1.0),
          totalDurationMinutes: c.task.remainingDurationMinutes,
          isSplittable: c.task.isSplittable,
          minimumChunkDurationMinutes: c.task.minimumChunkDurationMinutes,
          maximumChunkDurationMinutes: c.task.maximumChunkDurationMinutes,
          prerequisiteSatisfied: c.prerequisiteSatisfied,
        ),
    ];
  }

  // ------------------------------------------------------------------
  // Saving
  // ------------------------------------------------------------------

  Future<PlanGenerationResult> _persist(
    _Prepared p,
    _Computed c,
    ReplanReason reason,
    String detail,
  ) {
    return _db.transaction(() async {
      final weekEnd = WeekCalendar.endOfWeek(p.weekStart);
      final sessions = StudySessionRepository(_db);

      // What the future part of the week looked like before this plan.
      final before = <ScheduledChunk>[];
      for (final s in await sessions.readOverlapping(p.floor, weekEnd)) {
        if (s.actualStart == null && !s.plannedStart.isBefore(p.floor)) {
          before.add(ScheduledChunk(
              taskId: s.taskId, start: s.plannedStart, end: s.plannedEnd));
        }
      }
      final changes = WeekTimelineEngine.diffChunks(
          before, c.plan.scheduling.scheduledChunks);

      // Replace the future, unexecuted part; the past is never rewritten.
      await sessions.deleteUnexecutedStartingIn(p.floor, weekEnd);
      var saved = 0;
      var minutes = 0;
      final taskById = {for (final k in p.candidates) k.task.id: k.task};
      final chunksByTask = <String, List<ScheduledChunk>>{};
      for (final ch in c.plan.scheduling.scheduledChunks) {
        chunksByTask.putIfAbsent(ch.taskId, () => []).add(ch);
      }
      for (final entry in chunksByTask.entries) {
        final task = taskById[entry.key];
        final useSegments =
            task != null && (task.isSplittable || entry.value.length > 1);
        var order = 0;
        if (useSegments) {
          final existing = await sessions.readSegmentsForTask(entry.key);
          for (final s in existing) {
            if (s.segmentOrder >= order) order = s.segmentOrder + 1;
          }
        }
        for (final ch in entry.value) {
          String? segmentId;
          if (useSegments) {
            final seg = await sessions.insertSegment(
              parentTaskId: entry.key,
              segmentDurationMinutes: ch.minutesAllocated,
              segmentOrder: order++,
            );
            segmentId = seg.id;
          }
          await sessions.insertPlanned(
            taskId: entry.key,
            taskSegmentId: segmentId,
            plannedStart: ch.start,
            plannedEnd: ch.end,
          );
          saved++;
          minutes += ch.minutesAllocated;
        }
      }

      // Workload snapshot (the facts, normal thresholds).
      await WorkloadRepository(_db).recomputeFrom(
        studentId: p.student.id,
        result: c.normalWorkload,
      );

      // Emergency state, with hysteresis: enter once, exit once.
      final emergencyRepo = EmergencyRepository(_db);
      final active = await emergencyRepo.readActive(p.student.id);
      if (c.emergencyTrigger != null && active == null) {
        final defaults = PriorityWeights.defaults();
        await emergencyRepo.enter(
          studentId: p.student.id,
          trigger: c.emergencyTrigger!,
          enteredAt: p.now.toUtc(),
          originalWeightsSnapshot: {
            for (final k in PrioritySignalKind.values) k.name: defaults[k],
          },
        );
        await _emit('EmergencyEntered', {
          'trigger': c.emergencyTrigger!.name,
          'reasoning': c.emergencyReasoning,
        }, triggersReplan: false);
      } else if (c.emergencyTrigger == null && active != null) {
        await emergencyRepo.exit(id: active.id, exitedAt: p.now.toUtc());
        await _emit('EmergencyExited', {
          'reasoning': c.emergencyReasoning,
        }, triggersReplan: false);
      }

      final unprioritised = [
        for (final k in p.candidates)
          if (!k.prioritised &&
              !p.droppedTaskIds.contains(k.task.id) &&
              k.prerequisiteSatisfied)
            k.task.id,
      ];
      final unscheduled = c.plan.scheduling.unscheduledQueue;
      final gaps = [
        for (final g in c.plan.gaps)
          GapFindingSummary(code: g.code, taskId: g.taskId),
      ];

      // Explanation (append-only) + the event that points at it.
      final version = await _db.into(_db.dataStateVersions).insertReturning(
            DataStateVersionsCompanion.insert(
              snapshotTimestamp: p.now.toUtc(),
              relatedEventId: 'plan-generation',
            ),
          );
      final changeJson = [
        for (final ch in changes)
          {
            'taskId': ch.taskId,
            'kind': ch.kind.name,
            'minutesBefore': ch.minutesBefore,
            'minutesAfter': ch.minutesAfter,
          },
      ];
      final explanation = await ExplanationRepository(_db).insertRow(
        ExplanationsCompanion.insert(
          factorsJson: jsonEncode({
            'reason': reason.name,
            'detail': detail,
            'changes': changeJson,
            'workload': {
              'needed': c.normalWorkload.neededMinutes,
              'available': c.normalWorkload.availableMinutes,
              'classification': c.normalWorkload.classification.name,
            },
            'emergency': c.emergencyTrigger?.name,
            'recoveryDirectives': p.directives,
          }),
          excludedFactorsJson: jsonEncode({
            'dropped': p.droppedTaskIds.toList(),
            'unscheduled': [
              for (final u in unscheduled)
                {'taskId': u.taskId, 'reason': u.reason.name},
            ],
          }),
          dominantFactor: reason.name,
          hardConstraintsCheckedJson: jsonEncode([
            'hard_fixed_blocks',
            'sleep_blocks',
            'prerequisites',
            'study_windows',
          ]),
          versionBundleId: version.id,
        ),
      );

      final event = await _emit('PlanGenerated', {
        'weekStart': p.weekStart.toIso8601String(),
        'reason': reason.name,
        'detail': detail,
        'sessions': saved,
        'scheduledMinutes': minutes,
        'unscheduled': [
          for (final u in unscheduled)
            {
              'taskId': u.taskId,
              'reason': u.reason.name,
              if (u.minutesRemaining != null)
                'minutesRemaining': u.minutesRemaining,
            },
        ],
        'gaps': [for (final g in gaps) g.code],
        'emergency': c.emergencyTrigger?.name,
        'workload': c.normalWorkload.classification.name,
        'explanationId': explanation.id,
        'generatedAt': p.now.toUtc().toIso8601String(),
      }, triggersReplan: false);

      return PlanGenerationResult(
        weekStart: p.weekStart,
        sessionsSaved: saved,
        scheduledMinutes: minutes,
        unscheduled: unscheduled,
        gaps: gaps,
        changes: changes,
        unprioritizedTaskIds: unprioritised,
        droppedTaskIds: p.droppedTaskIds.toList(),
        emergencyActive: c.emergencyTrigger != null,
        workload: c.finalWorkload.classification,
        reason: reason,
        explanationId: explanation.id,
        planEventId: event.id,
      );
    });
  }

  // ------------------------------------------------------------------
  // Events
  // ------------------------------------------------------------------

  Future<Event> _emit(
    String type,
    Map<String, Object?> payload, {
    required bool triggersReplan,
  }) {
    if (!EventTypeValidator.isKnown(type)) {
      throw StateError('Unknown event type "$type".');
    }
    // Informational events (plan/emergency) are born processed; TaskMissed
    // stays unprocessed so IntelligenceService marks it and refreshes
    // priorities on its next run.
    final bornProcessed = type != 'TaskMissed';
    return EventRepository(_db).insertRow(
      EventsCompanion.insert(
        type: type,
        payloadJson: jsonEncode(payload),
        triggersReplan: triggersReplan,
        processedAt: bornProcessed ? Value(_clock().toUtc()) : const Value.absent(),
      ),
    );
  }

  /// When a plan was generated, by the SERVICE clock (stored in the event
  /// payload) so every comparison uses one clock; falls back to the row's
  /// own creation time for an event written without it.
  DateTime _generatedAt(Event e) {
    try {
      final p = jsonDecode(e.payloadJson) as Map<String, dynamic>;
      final t = DateTime.tryParse('${p['generatedAt']}');
      if (t != null) return t;
    } catch (_) {}
    return e.createdAt;
  }

  Future<Event?> _lastPlanEvent(DateTime weekStart) async {
    final all = await EventRepository(_db).readByType('PlanGenerated');
    Event? last;
    for (final e in all) {
      try {
        final p = jsonDecode(e.payloadJson) as Map<String, dynamic>;
        final ws = DateTime.tryParse('${p['weekStart']}');
        if (ws != null && ws.isAtSameMomentAs(weekStart)) last = e;
      } catch (_) {}
    }
    return last;
  }
}
