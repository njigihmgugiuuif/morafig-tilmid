import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/enums.dart';
import 'package:student_app/engines/recovery_engine.dart';
import 'package:student_app/engines/scheduling_engine.dart';
import 'package:student_app/engines/weekly_planner.dart';
import 'package:student_app/engines/weekly_timeline_engine.dart';
import 'package:student_app/repositories/availability_repository.dart';
import 'package:student_app/repositories/emergency_repository.dart';
import 'package:student_app/repositories/event_repository.dart';
import 'package:student_app/repositories/exam_repository.dart';
import 'package:student_app/repositories/explanation_and_override_repositories.dart';
import 'package:student_app/repositories/reality_and_prerequisite_repositories.dart';
import 'package:student_app/repositories/recovery_repository.dart';
import 'package:student_app/repositories/study_session_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'package:student_app/repositories/weekly_template_repository.dart';
import 'package:student_app/repositories/workload_repository.dart';
import 'package:student_app/services/planning_service.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// B (DEVIATION-22): the planning service against a real in-memory database.
/// All data is SYNTHETIC. The service clock is fixed in 2030 so every
/// "created after the last plan" comparison is decided by the clock under
/// test, never by the wall clock of the machine running the tests.
void main() {
  late AppDatabase db;
  late MinimalCurriculumSeed seed;
  late DateTime now;

  // Sunday 6 October 2030 (local midnight).
  DateTime at(int day, int h, [int m = 0]) => DateTime(2030, 10, 6 + day, h, m);

  setUp(() async {
    db = createInMemoryTestDatabase();
    seed = await seedMinimalCurriculum(db);
    now = at(0, 8);
  });
  tearDown(() => db.close());

  PlanningService svc() => PlanningService(db, clock: () => now);

  // ---- helpers (declared before use) ---------------------------------

  Future<void> addAvailabilityEveryDay(int startMin, int endMin) async {
    for (var d = 1; d <= 7; d++) {
      await AvailabilityRepository(db).insert(
        studentId: seed.studentId,
        dayOfWeek: d,
        windowStartMinutes: startMin,
        windowEndMinutes: endMin,
        isRecurring: true,
      );
    }
  }

  Future<void> addAvailabilityOn(int storedDay, int startMin, int endMin) =>
      AvailabilityRepository(db).insert(
        studentId: seed.studentId,
        dayOfWeek: storedDay,
        windowStartMinutes: startMin,
        windowEndMinutes: endMin,
        isRecurring: true,
      );

  Future<void> addSleepEveryDay() async {
    for (var d = 1; d <= 7; d++) {
      await WeeklyTemplateRepository(db).insertFromUser(
        studentId: seed.studentId,
        dayOfWeek: d,
        startMinutes: 1320,
        endMinutes: 1800,
        kind: TimelineBlockKind.sleep,
      );
    }
  }

  Future<Task> newTask(int minutes,
          {bool splittable = false, String? nodeId}) =>
      TaskRepository(db).createTask(
        knowledgeNodeId: nodeId ?? seed.knowledgeNodeId,
        estimatedDurationMinutes: minutes,
        isSplittable: splittable,
      );

  Future<void> setPriority(Task t, double score,
      {Map<String, double>? values}) async {
    final version = await db.into(db.dataStateVersions).insertReturning(
          DataStateVersionsCompanion.insert(
            snapshotTimestamp: DateTime.utc(2030, 10, 1),
            relatedEventId: 'test',
          ),
        );
    final factors = <String, Map<String, double>>{
      for (final e in (values ?? {'masteryGap': score}).entries)
        e.key: {'value': e.value, 'weight': 0.0, 'contribution': 0.0},
    };
    final ex = await ExplanationRepository(db).insertRow(
      ExplanationsCompanion.insert(
        factorsJson: jsonEncode(factors),
        excludedFactorsJson: '[]',
        dominantFactor: values?.keys.first ?? 'masteryGap',
        hardConstraintsCheckedJson: '[]',
        versionBundleId: version.id,
      ),
    );
    await db.into(db.priorityStates).insert(PriorityStatesCompanion.insert(
          taskId: t.id,
          score: score,
          confidenceLevel: 'high',
          confidenceValue: 1.0,
          weightsUsedJson: '{}',
          explanationId: ex.id,
        ));
  }

  Future<String> secondNode() async {
    final first = await (db.select(db.knowledgeNodes)
          ..where((t) => t.id.equals(seed.knowledgeNodeId)))
        .getSingle();
    final node = await db.into(db.knowledgeNodes).insertReturning(
        KnowledgeNodesCompanion.insert(
            lessonId: first.lessonId, name: 'TEST-NODE-2'));
    return node.id;
  }

  Future<void> addDirective(
      Task t, RecoveryDecisionKind d, DateTime plannedStart) async {
    final ev = await EventRepository(db).insertRow(EventsCompanion.insert(
      type: 'TaskMissed',
      payloadJson: jsonEncode({
        'taskId': t.id,
        'sessionId': 'synthetic-${t.id}',
        'plannedStart': plannedStart.toIso8601String(),
        'plannedEnd':
            plannedStart.add(const Duration(minutes: 60)).toIso8601String(),
      }),
      triggersReplan: true,
      processedAt: drift.Value(DateTime.utc(2030, 10, 1)),
    ));
    await RecoveryRepository(db).record(
      triggerEventId: ev.id,
      affectedTaskId: t.id,
      result: RecoveryDecisionResult(decision: d, reasoning: 'TEST'),
    );
  }

  Future<List<StudySession>> allSessions() =>
      StudySessionRepository(db).readOverlapping(at(0, 0), at(7, 0));

  Future<List<StudySession>> sessionsOf(Task t) async =>
      (await allSessions()).where((s) => s.taskId == t.id).toList();

  int minuteOfDay(DateTime d) => d.hour * 60 + d.minute;

  Future<int> countEvents(String type) async =>
      (await EventRepository(db).readByType(type)).length;

  // ---- tests -----------------------------------------------------------

  group('hard constraints', () {
    test('study time is never placed inside the declared sleep window',
        () async {
      await addSleepEveryDay(); // 22:00 -> 06:00, hard
      await addAvailabilityEveryDay(1200, 1410); // 20:00 -> 23:30
      final tasks = <Task>[];
      for (var i = 0; i < 7; i++) {
        final t = await newTask(90);
        await setPriority(t, 0.9 - i * 0.05);
        tasks.add(t);
      }

      final r = await svc().generateWeekPlan();
      expect(r, isNotNull);
      expect(r!.sessionsSaved, 7);
      for (final s in await allSessions()) {
        expect(minuteOfDay(s.plannedStart), greaterThanOrEqualTo(1200));
        expect(minuteOfDay(s.plannedEnd), lessThanOrEqualTo(1320),
            reason: 'a session ran into the sleep block');
      }
    });

    test('a window that overlaps a hard commitment never receives study time',
        () async {
      await addAvailabilityEveryDay(960, 1140); // 16:00 -> 19:00
      await db.into(db.realityConstraints).insert(
            RealityConstraintsCompanion.insert(
              studentId: seed.studentId,
              type: 'fixedCommitment',
              windowStart: at(0, 16, 30),
              windowEnd: at(0, 17, 30),
              isHard: true,
            ),
          );
      for (var i = 0; i < 3; i++) {
        final t = await newTask(60);
        await setPriority(t, 0.9 - i * 0.1);
      }
      await svc().generateWeekPlan();
      for (final s in await allSessions()) {
        final overlaps = s.plannedStart.isBefore(at(0, 17, 30)) &&
            s.plannedEnd.isAfter(at(0, 16, 30));
        expect(overlaps, isFalse);
      }
    });
  });

  group('unscheduled reasons', () {
    test('a non-splittable task that does not fit gets a reason, never '
        'silently dropped', () async {
      await addAvailabilityOn(7, 960, 1020); // Sunday 16:00 -> 17:00 only
      final big = await newTask(90);
      final small = await newTask(30);
      await setPriority(big, 0.9);
      await setPriority(small, 0.5);

      final r = await svc().generateWeekPlan();
      expect(r!.unscheduled.length, 1);
      expect(r.unscheduled.single.taskId, big.id);
      expect(r.unscheduled.single.reason, UnscheduledReason.noSlotAvailable);
      expect(await sessionsOf(big), isEmpty);
      final placed = await sessionsOf(small);
      expect(placed.single.plannedStart.isAtSameMomentAs(at(0, 16)), isTrue);
      expect(r.gaps.map((g) => g.code), contains('unplaced_no_slot'));
    });

    test('a task whose prerequisite is not mastered stays unscheduled with '
        'its reason', () async {
      await addAvailabilityEveryDay(960, 1140);
      final node2 = await secondNode();
      await PrerequisiteRepository(db).insert(
        knowledgeNodeId: node2,
        requiresNodeId: seed.knowledgeNodeId,
        isHard: true,
        relationType: 'derived',
      );
      final blocked = await newTask(60, nodeId: node2);
      final free = await newTask(60);
      await setPriority(blocked, 0.99);
      await setPriority(free, 0.2);

      final r = await svc().generateWeekPlan();
      expect(
          r!.unscheduled
              .where((u) => u.taskId == blocked.id)
              .single
              .reason,
          UnscheduledReason.prerequisiteNotSatisfied);
      expect(await sessionsOf(blocked), isEmpty);
      expect(await sessionsOf(free), isNotEmpty);
    });

    test('a task with no Priority is placed after every prioritised task and '
        'reported, never given an invented score', () async {
      await addAvailabilityOn(7, 960, 1080); // Sunday 16:00 -> 18:00
      final p = await newTask(60);
      final u = await newTask(60);
      await setPriority(p, 0.1);

      final r = await svc().generateWeekPlan();
      expect(r!.unprioritizedTaskIds, [u.id]);
      final ps = (await sessionsOf(p)).single;
      final us = (await sessionsOf(u)).single;
      expect(ps.plannedStart.isBefore(us.plannedStart), isTrue);
    });
  });

  group('a full week, Sunday to Saturday', () {
    test('21 tasks fill three evening hours on each of the seven days',
        () async {
      // School Sunday..Thursday (stored 7,1,2,3,4), sleep every night.
      for (final d in [7, 1, 2, 3, 4]) {
        await WeeklyTemplateRepository(db).insertFromUser(
          studentId: seed.studentId,
          dayOfWeek: d,
          startMinutes: 480,
          endMinutes: 840,
          kind: TimelineBlockKind.school,
        );
      }
      await addSleepEveryDay();
      await addAvailabilityEveryDay(960, 1140);

      final tasks = <Task>[];
      for (var i = 0; i < 21; i++) {
        final t = await newTask(60);
        await setPriority(t, 1.0 - i * 0.04);
        tasks.add(t);
      }

      final r = await svc().generateWeekPlan();
      expect(r!.sessionsSaved, 21);
      expect(r.scheduledMinutes, 1260);
      expect(r.unscheduled, isEmpty);
      expect(r.weekStart.isAtSameMomentAs(at(0, 0)), isTrue);

      final perDay = <int, int>{};
      for (final s in await allSessions()) {
        final idx = WeekCalendar.indexInWeek(s.plannedStart);
        perDay[idx] = (perDay[idx] ?? 0) + 1;
        expect(minuteOfDay(s.plannedStart), greaterThanOrEqualTo(960));
        expect(minuteOfDay(s.plannedEnd), lessThanOrEqualTo(1140));
      }
      expect(perDay.keys.toSet(), {0, 1, 2, 3, 4, 5, 6});
      expect(perDay.values.every((n) => n == 3), isTrue);

      // The highest priority is the first thing of the week.
      final first = (await sessionsOf(tasks.first)).single;
      expect(first.plannedStart.isAtSameMomentAs(at(0, 16)), isTrue);

      // The plan is auditable: event, explanation, workload snapshot.
      expect(await countEvents('PlanGenerated'), 1);
      final ex = await ExplanationRepository(db).readById(r.explanationId);
      expect(ex, isNotNull);
      expect(jsonDecode(ex!.factorsJson)['reason'], 'manual');
      final wl = await WorkloadRepository(db).read(seed.studentId);
      expect(wl?.totalEstimatedTimeNeededMinutes, 1260);
      expect(wl?.totalAvailableTimeMinutes, 1260);
    });
  });

  group('splittable tasks', () {
    test('a splittable task is saved as one segment per chunk', () async {
      await addAvailabilityOn(7, 960, 1020); // 60 min Sunday
      await addAvailabilityOn(1, 960, 1020); // 60 min Monday
      final t = await newTask(100, splittable: true);
      await setPriority(t, 0.8);

      final r = await svc().generateWeekPlan();
      expect(r!.sessionsSaved, 2);
      final segs = await StudySessionRepository(db).readSegmentsForTask(t.id);
      expect(segs.length, 2);
      expect(segs.map((s) => s.segmentOrder), [0, 1]);
      expect(segs.fold<int>(0, (a, s) => a + s.segmentDurationMinutes), 100);
      expect(r.unscheduled, isEmpty);
    });
  });

  group('app open: first plan, missed day, hysteresis', () {
    test('no student -> nothing happens', () async {
      final empty = createInMemoryTestDatabase();
      addTearDown(empty.close);
      final r = await PlanningService(empty, clock: () => now).onAppOpen();
      expect(r.status, 'noStudent');
    });

    test('the first app open creates the plan; the second changes nothing',
        () async {
      await addAvailabilityEveryDay(960, 1140);
      final t = await newTask(60);
      await setPriority(t, 0.6);

      final a = await svc().onAppOpen();
      expect(a.status, 'firstPlan');
      expect(a.generation!.sessionsSaved, 1);

      final b = await svc().onAppOpen();
      expect(b.errors, isEmpty);
      expect(b.status, 'unchanged');
      expect(await countEvents('PlanGenerated'), 1);
    });

    test('a missed day: TaskMissed events, one Recovery decision per task '
        '(not one blanket rule), then a new plan', () async {
      await addAvailabilityEveryDay(960, 1140);
      final x = await newTask(60);
      final y = await newTask(60);
      final z = await newTask(60);
      await setPriority(x, 0.9);
      await setPriority(y, 0.5);
      await setPriority(z, 0.2);

      await svc().generateWeekPlan();
      expect((await sessionsOf(x)).single.plannedStart.day, 6);

      // Sunday evening: nothing was done.
      now = at(0, 20);
      final r = await svc().onAppOpen();

      expect(r.errors, isEmpty);
      expect(r.status, 'replanned');
      expect(r.missedTaskIds.toSet(), {x.id, y.id, z.id});
      expect(r.recoveryDecisions[x.id], 'move');
      expect(r.recoveryDecisions[y.id], 'defer');
      expect(r.recoveryDecisions[z.id], 'defer');
      expect(r.replanReasons, contains('missed_session'));

      expect(await countEvents('TaskMissed'), 3);
      expect(await countEvents('PlanInvalidated'), 1);
      expect(await countEvents('PlanGenerated'), 2);
      final records = await RecoveryRepository(db).readAll();
      expect(records.length, 3);
      expect(records.every((rec) => rec.reasoning.isNotEmpty), isTrue);

      // The missed Sunday sessions stay as history; new ones are on Monday,
      // X (move) before the deferred ones.
      final xs = await sessionsOf(x);
      expect(xs.length, 2);
      final mondayX = xs.where((s) => s.plannedStart.day == 7).single;
      final mondayY =
          (await sessionsOf(y)).where((s) => s.plannedStart.day == 7).single;
      final mondayZ =
          (await sessionsOf(z)).where((s) => s.plannedStart.day == 7).single;
      expect(mondayX.plannedStart.isAtSameMomentAs(at(1, 16)), isTrue);
      expect(mondayX.plannedStart.isBefore(mondayY.plannedStart), isTrue);
      expect(mondayY.plannedStart.isBefore(mondayZ.plannedStart), isTrue);

      // Running again does not flag the same sessions twice.
      final again = await svc().onAppOpen();
      expect(again.status, 'unchanged');
      expect(await countEvents('TaskMissed'), 3);
      expect(await countEvents('PlanGenerated'), 2);
    });

    test('a small deviation does not replan (hysteresis)', () async {
      await addAvailabilityEveryDay(960, 1140);
      final t = await newTask(60);
      await setPriority(t, 0.9);
      await svc().generateWeekPlan();
      final session = (await sessionsOf(t)).single;

      await svc().recordSessionActual(
          sessionId: session.id,
          actualStart: at(0, 16),
          actualEnd: at(0, 17, 5)); // 5 minutes over
      now = at(0, 17, 30);
      final r = await svc().onAppOpen();

      expect(r.errors, isEmpty);
      expect(r.status, 'unchanged');
      expect(r.missedTaskIds, isEmpty);
      expect(await countEvents('PlanGenerated'), 1);
    });

    test('a deviation at or above the threshold replans', () async {
      await addAvailabilityEveryDay(960, 1140);
      final t = await newTask(60);
      await setPriority(t, 0.9);
      await svc().generateWeekPlan();
      final session = (await sessionsOf(t)).single;

      await svc().recordSessionActual(
          sessionId: session.id,
          actualStart: at(0, 16),
          actualEnd: at(0, 17, 20)); // 20 minutes over
      now = at(0, 17, 30);
      final r = await svc().onAppOpen();

      expect(r.status, 'replanned');
      expect(r.replanReasons, contains('duration_deviation'));
      expect(r.generation!.reason, ReplanReason.taskFinishedLate);
      expect(await countEvents('PlanGenerated'), 2);
    });

    test('a new unavailability over still-planned time replans around it',
        () async {
      await addAvailabilityEveryDay(960, 1140);
      for (var i = 0; i < 4; i++) {
        final t = await newTask(60);
        await setPriority(t, 0.9 - i * 0.1);
      }
      await svc().generateWeekPlan(); // Sunday x3, Monday x1 at 16:00
      expect((await allSessions()).length, 4);

      await db.into(db.realityConstraints).insert(
            RealityConstraintsCompanion.insert(
              studentId: seed.studentId,
              type: 'unexpectedEvent',
              windowStart: at(1, 16),
              windowEnd: at(1, 18),
              isHard: true,
              createdAt: drift.Value(at(0, 9)),
            ),
          );
      now = at(0, 10);
      final r = await svc().onAppOpen();

      expect(r.status, 'replanned');
      expect(r.replanReasons, contains('new_unavailability'));
      for (final s in await allSessions()) {
        final overlaps = s.plannedStart.isBefore(at(1, 18)) &&
            s.plannedEnd.isAfter(at(1, 16));
        expect(overlaps, isFalse);
      }
    });

    test('a task added after the plan is picked up', () async {
      await addAvailabilityEveryDay(960, 1140);
      final t = await newTask(60);
      await setPriority(t, 0.9);
      await svc().generateWeekPlan();

      final added = await db.into(db.tasks).insertReturning(
            TasksCompanion.insert(
              knowledgeNodeId: seed.knowledgeNodeId,
              estimatedDurationMinutes: 45,
              remainingDurationMinutes: 45,
              sourceType: 'regular',
              createdAt: drift.Value(at(0, 9)),
            ),
          );
      now = at(0, 10);
      final r = await svc().onAppOpen();

      expect(r.status, 'replanned');
      expect(r.replanReasons, contains('task_added'));
      expect(await sessionsOf(added), isNotEmpty);
    });
  });

  group('replanning keeps the past', () {
    test('replanNow rewrites only the future, and records PlanInvalidated',
        () async {
      await addAvailabilityEveryDay(960, 1140);
      for (var i = 0; i < 6; i++) {
        final t = await newTask(60);
        await setPriority(t, 0.9 - i * 0.1);
      }
      await svc().generateWeekPlan(); // Sunday x3, Monday x3
      final sundayBefore = (await allSessions())
          .where((s) => s.plannedStart.day == 6)
          .map((s) => s.id)
          .toSet();
      expect(sundayBefore.length, 3);

      now = at(1, 8); // Monday morning
      await svc().replanNow();

      final sundayAfter = (await allSessions())
          .where((s) => s.plannedStart.day == 6)
          .map((s) => s.id)
          .toSet();
      expect(sundayAfter, sundayBefore);
      expect(await countEvents('PlanInvalidated'), 1);
      expect(await countEvents('PlanGenerated'), 2);
    });
  });

  group('Recovery directives', () {
    test('dropTemporarily keeps a task out of this week and says so',
        () async {
      await addAvailabilityEveryDay(960, 1140);
      final keep = await newTask(60);
      final drop = await newTask(60);
      await setPriority(keep, 0.6);
      await setPriority(drop, 0.2);
      await addDirective(drop, RecoveryDecisionKind.dropTemporarily, at(0, 16));

      final r = await svc().generateWeekPlan();
      expect(r!.droppedTaskIds, [drop.id]);
      expect(await sessionsOf(drop), isEmpty);
      expect(await sessionsOf(keep), isNotEmpty);
    });

    test('keep goes before higher-priority tasks; defer goes after lower ones',
        () async {
      await addAvailabilityOn(7, 960, 1140); // three one-hour places, Sunday
      final top = await newTask(60);
      final kept = await newTask(60);
      final deferred = await newTask(60);
      await setPriority(top, 0.9);
      await setPriority(kept, 0.3);
      await setPriority(deferred, 0.8);
      await addDirective(kept, RecoveryDecisionKind.keep, at(0, 16));
      await addDirective(deferred, RecoveryDecisionKind.defer, at(0, 16));

      await svc().generateWeekPlan();
      final starts = <String, DateTime>{
        for (final t in [top, kept, deferred])
          t.id: (await sessionsOf(t)).single.plannedStart,
      };
      expect(starts[kept.id]!.isBefore(starts[top.id]!), isTrue);
      expect(starts[top.id]!.isBefore(starts[deferred.id]!), isTrue);
    });

    test('merge puts the task right after an already-planned task of the same '
        'knowledge node', () async {
      await addAvailabilityOn(7, 960, 1140);
      final node2 = await secondNode();
      final b = await newTask(60); // node 1, will be merged
      final c = await newTask(60, nodeId: node2);
      final a = await newTask(60); // node 1, the anchor
      await setPriority(b, 0.95);
      await setPriority(c, 0.9);
      await setPriority(a, 0.5);

      await svc().generateWeekPlan(); // normal order: b, c, a
      await addDirective(b, RecoveryDecisionKind.merge, at(0, 16));
      await svc().replanNow();

      final startOf = <String, DateTime>{
        for (final t in [a, b, c])
          t.id: (await sessionsOf(t)).single.plannedStart,
      };
      expect(startOf[c.id]!.isBefore(startOf[a.id]!), isTrue);
      expect(startOf[a.id]!.isBefore(startOf[b.id]!), isTrue);
    });
  });

  group('Emergency mode', () {
    Future<(Task, Task, Task)> emergencySetup() async {
      await addSleepEveryDay();
      await addAvailabilityEveryDay(960, 1380); // 16:00 -> 23:00
      final node2 = await secondNode();
      await PrerequisiteRepository(db).insert(
        knowledgeNodeId: node2,
        requiresNodeId: seed.knowledgeNodeId,
        isHard: true,
        relationType: 'derived',
      );
      // X: weak mastery, no exam signal. Y: strong exam signal.
      final x = await newTask(60);
      final y = await newTask(60);
      final z = await newTask(60, nodeId: node2); // blocked by a prerequisite
      await setPriority(x, 0.6,
          values: {'masteryGap': 0.9, 'examProximity': 0.0});
      await setPriority(y, 0.4667,
          values: {'masteryGap': 0.2, 'examProximity': 1.0});
      await setPriority(z, 0.99);
      return (x, y, z);
    }

    test('without an exam the normal order holds', () async {
      final (x, y, _) = await emergencySetup();
      final r = await svc().generateWeekPlan();
      expect(r!.emergencyActive, isFalse);
      final sx = (await sessionsOf(x)).single.plannedStart;
      final sy = (await sessionsOf(y)).single.plannedStart;
      expect(sx.isBefore(sy), isTrue);
    });

    test('a near exam reweights the order only; sleep and prerequisites '
        'stay untouched; entering and leaving happen once', () async {
      final (x, y, z) = await emergencySetup();
      await ExamRepository(db).insert(
          subjectId: seed.subjectId,
          examDate: at(2, 12),
          examType: ExamType.summative);

      final r = await svc().generateWeekPlan();
      expect(r!.emergencyActive, isTrue);
      final active = await EmergencyRepository(db).readActive(seed.studentId);
      expect(active?.triggerReason, 'examProximity');
      expect(await countEvents('EmergencyEntered'), 1);

      // The exam-heavy task now comes first.
      final sx = (await sessionsOf(x)).single.plannedStart;
      final sy = (await sessionsOf(y)).single.plannedStart;
      expect(sy.isBefore(sx), isTrue);

      // Sleep is intact.
      for (final s in await allSessions()) {
        expect(minuteOfDay(s.plannedStart), greaterThanOrEqualTo(960));
        expect(minuteOfDay(s.plannedEnd), lessThanOrEqualTo(1320));
      }
      // The prerequisite is still respected, with its reason.
      expect(await sessionsOf(z), isEmpty);
      expect(
          r.unscheduled.where((u) => u.taskId == z.id).single.reason,
          UnscheduledReason.prerequisiteNotSatisfied);

      // Planning again while the exam is still near does not enter twice.
      await svc().generateWeekPlan();
      expect(await countEvents('EmergencyEntered'), 1);

      // Once the exam has passed, the next plan leaves emergency mode.
      now = at(9, 8);
      final after = await svc().generateWeekPlan(weekOf: now);
      expect(after!.emergencyActive, isFalse);
      expect(await EmergencyRepository(db).readActive(seed.studentId), isNull);
      expect(await countEvents('EmergencyExited'), 1);
    });
  });

  group('planned vs actual', () {
    test('compareWeekWithActual reports on-track and missed tasks', () async {
      await addAvailabilityEveryDay(960, 1140);
      final done = await newTask(60);
      final skipped = await newTask(60);
      await setPriority(done, 0.9);
      await setPriority(skipped, 0.5);
      await svc().generateWeekPlan();

      final s = (await sessionsOf(done)).single;
      await svc().recordSessionActual(
          sessionId: s.id, actualStart: s.plannedStart, actualEnd: s.plannedEnd);

      final byTask = {
        for (final r in await svc().compareWeekWithActual()) r.taskId: r,
      };
      expect(byTask[done.id]!.status, RealityStatus.onTrack);
      expect(byTask[skipped.id]!.status, RealityStatus.missed);
    });
  });
}
