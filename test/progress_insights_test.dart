import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/enums.dart';
import 'package:student_app/engines/workload_engine.dart';
import 'package:student_app/repositories/exam_repository.dart';
import 'package:student_app/repositories/goal_repository.dart';
import 'package:student_app/repositories/study_session_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'package:student_app/repositories/workload_repository.dart';
import 'package:student_app/services/intelligence_service.dart';
import 'package:student_app/ui/state/progress_insights.dart';
import 'fixtures/seed_data.dart';

/// Batch 4: the progress pages read stored data only. All data is SYNTHETIC.
/// Each test checks that a number on screen equals what a repository or an
/// engine stored, or that an empty source says so instead of inventing data.
void main() {
  late AppDatabase db;
  late MinimalCurriculumSeed seed;

  setUp(() async {
    db = createInMemoryTestDatabase();
    seed = await seedMinimalCurriculum(db);
  });
  tearDown(() => db.close());

  Future<Task> newTask() => TaskRepository(db).createTask(
        knowledgeNodeId: seed.knowledgeNodeId,
        estimatedDurationMinutes: 30,
        isSplittable: false,
      );

  Future<void> complete(String understanding) async {
    final t = await newTask();
    await TaskRepository(db).markComplete(t, understanding: understanding);
    final r = await IntelligenceService(db).processPendingEvents();
    expect(r.errors, isEmpty);
  }

  group('formatting and summaries (pure)', () {
    test('minutes read naturally', () {
      expect(formatMinutes(45), '45 د');
      expect(formatMinutes(120), '2 س');
      expect(formatMinutes(135), '2 س و 15 د');
    });

    test('calendar days are not affected by the clock time', () {
      expect(
          calendarDaysBetween(
              DateTime(2026, 3, 8, 23, 59), DateTime(2026, 3, 9, 0, 1)),
          1);
      expect(
          calendarDaysBetween(DateTime(2026, 3, 9), DateTime(2026, 3, 8)), -1);
    });

    test('no sessions and no tasks says so', () {
      expect(
          summarizePeriod(
              sessions: 0,
              plannedMinutes: 0,
              endedSessions: 0,
              recordedSessions: 0,
              endedPlannedMinutes: 0,
              actualMinutes: 0,
              completedTasks: 0,
              missedSessions: 0),
          contains('لا جلسات'));
    });

    test('ended sessions without a record never claim zero study', () {
      final s = summarizePeriod(
          sessions: 2,
          plannedMinutes: 120,
          endedSessions: 2,
          recordedSessions: 0,
          endedPlannedMinutes: 120,
          actualMinutes: 0,
          completedTasks: 0,
          missedSessions: 2);
      expect(s, contains('ستظهر المقارنة بعد تسجيل جلسات الدراسة'));
      expect(s, isNot(contains('سجّلتَ فعليًا')));
    });

    test('workload words come from the stored status', () {
      expect(workloadStatusLabel('overload'), 'عبء زائد');
      expect(workloadStatusLabel('zzz'), 'عبء غير معروف');
    });
  });

  group('mastery by subject', () {
    test('empty without evaluations', () async {
      expect(await ProgressInsights(db).subjectMastery(seed.studentId), isEmpty);
    });

    test('the subject average is the stored mastery of its topics', () async {
      await complete(Understanding.good);
      await complete(Understanding.good);
      final rows = await ProgressInsights(db).subjectMastery(seed.studentId);
      expect(rows.length, 1);
      expect(rows.single.topics, 1);
      final stored = await db.select(db.masteryStates).get();
      expect(rows.single.average, closeTo(stored.single.probability, 1e-9));
      expect(rows.single.weakestValue, closeTo(stored.single.probability, 1e-9));
    });
  });

  group('review forecast', () {
    test('no memory states: empty with a reason', () async {
      final f =
          await ProgressInsights(db).reviewForecast(seed.studentId, DateTime.now());
      expect(f.total, 0);
      expect(f.summary, contains('لا مراجعات'));
    });

    test('every topic is counted exactly once', () async {
      await complete(Understanding.good);
      final f =
          await ProgressInsights(db).reviewForecast(seed.studentId, DateTime.now());
      expect(f.total, 1);
      expect(f.overdue + f.perDay.fold<int>(0, (a, b) => a + b) + f.later, 1);
      expect(f.averageRecallNow, isNotNull);
      expect(f.averageRecallNow!, inInclusiveRange(0.0, 1.0));
    });

    test('far-future review falls under «later», past review under overdue',
        () async {
      await complete(Understanding.good);
      final m = (await db.select(db.memoryStates).get()).single;
      final now = DateTime.now();
      // Looking from 100 days later the stored review date has passed.
      final afterwards = await ProgressInsights(db)
          .reviewForecast(seed.studentId, now.add(const Duration(days: 100)));
      expect(afterwards.overdue, 1);
      // Looking from before the review date it is not overdue.
      final early = await ProgressInsights(db).reviewForecast(
          seed.studentId, m.nextReviewDate.subtract(const Duration(days: 30)));
      expect(early.overdue, 0);
      expect(early.later, 1);
    });
  });

  group('time periods', () {
    // Wed 11 March 2026; the Sunday-first week is Sun 8 .. Sat 14 March.
    final anchor = DateTime(2026, 3, 11);
    final now = DateTime(2026, 3, 12, 12);

    test('empty week: 7 distinct columns and an honest message', () async {
      final r = await ProgressInsights(db)
          .periodReport(TimePeriod.week, anchor, now);
      expect(r.buckets.length, 7);
      expect({for (final b in r.buckets) b.shortLabel}.length, 7);
      expect(r.hasAnything, isFalse);
      expect(r.summary, contains('لا جلسات'));
    });

    test('month and year have the right number of columns', () async {
      final m = await ProgressInsights(db)
          .periodReport(TimePeriod.month, anchor, now);
      expect(m.buckets.length, 5); // March 2026 starts on a Sunday, 31 days
      final y = await ProgressInsights(db)
          .periodReport(TimePeriod.year, anchor, now);
      expect(y.buckets.length, 12);
    });

    test('planned vs recorded vs missed come from the stored sessions',
        () async {
      final task = await newTask();
      final repo = StudySessionRepository(db);
      final s1 = await repo.insertPlanned(
          taskId: task.id,
          plannedStart: DateTime(2026, 3, 9, 10),
          plannedEnd: DateTime(2026, 3, 9, 11));
      await repo.recordActual(
          sessionId: s1.id,
          actualStart: DateTime(2026, 3, 9, 10, 5),
          actualEnd: DateTime(2026, 3, 9, 10, 50));
      await repo.insertPlanned(
          taskId: task.id,
          plannedStart: DateTime(2026, 3, 10, 10),
          plannedEnd: DateTime(2026, 3, 10, 11)); // ended, never recorded
      await repo.insertPlanned(
          taskId: task.id,
          plannedStart: DateTime(2026, 3, 14, 10),
          plannedEnd: DateTime(2026, 3, 14, 11)); // still in the future

      final r = await ProgressInsights(db)
          .periodReport(TimePeriod.week, anchor, now);
      expect(r.sessions, 3);
      expect(r.endedSessions, 2);
      expect(r.recordedSessions, 1);
      expect(r.plannedMinutes, 180);
      expect(r.endedPlannedMinutes, 120);
      expect(r.actualMinutes, 45);
      expect(r.missedSessions, 1);
      expect(r.canCompare, isTrue);
      expect(r.buckets[1].plannedMinutes, 60); // Monday
      expect(r.buckets[1].actualMinutes, 45);
      expect(r.buckets[2].missedSessions, 1); // Tuesday
      expect(r.buckets[6].plannedMinutes, 60); // Saturday, in the future
      expect(r.buckets[6].actualMinutes, 0);
      expect(r.summary, contains('45'));
      expect(r.summary, contains('فاتتك 1'));

      // The same sessions seen as a month: all in the second week column.
      final m = await ProgressInsights(db)
          .periodReport(TimePeriod.month, anchor, now);
      expect(m.buckets[1].plannedMinutes, 180);
      expect(m.plannedMinutes, 180);
    });

    test('a different week does not see these sessions', () async {
      final task = await newTask();
      await StudySessionRepository(db).insertPlanned(
          taskId: task.id,
          plannedStart: DateTime(2026, 3, 9, 10),
          plannedEnd: DateTime(2026, 3, 9, 11));
      final next = await ProgressInsights(db).periodReport(
          TimePeriod.week, DateTime(2026, 3, 18), now);
      expect(next.sessions, 0);
    });

    test('finished tasks are counted from the recorded completions', () async {
      await complete(Understanding.good);
      await complete(Understanding.notUnderstood);
      final t = DateTime.now();
      final r = await ProgressInsights(db)
          .periodReport(TimePeriod.year, t, t.add(const Duration(minutes: 1)));
      expect(r.completedTasks, 2);
      expect(r.buckets.fold<int>(0, (a, b) => a + b.completedTasks), 2);
    });
  });

  group('workload', () {
    test('none stored: null (the page shows its empty state)', () async {
      expect(await ProgressInsights(db).workload(seed.studentId), isNull);
    });

    test('shows exactly what the workload engine stored', () async {
      const r = WorkloadEngine();
      await WorkloadRepository(db).recomputeFrom(
          studentId: seed.studentId,
          result: r.compute(neededMinutes: 600, availableMinutes: 300));
      final w = (await ProgressInsights(db).workload(seed.studentId))!;
      expect(w.neededMinutes, 600);
      expect(w.availableMinutes, 300);
      expect(w.status, 'impossible');
      expect(w.summary, contains('غير قابل'));
    });

    test('no availability: no verdict, and it says where to add it', () async {
      await WorkloadRepository(db).recomputeFrom(
          studentId: seed.studentId,
          result: const WorkloadEngine()
              .compute(neededMinutes: 120, availableMinutes: 0));
      final w = (await ProgressInsights(db).workload(seed.studentId))!;
      expect(w.hasAvailability, isFalse);
      expect(w.summary, contains('واقعي'));
    });
  });

  group('priorities and exams', () {
    test('nothing stored: empty lists', () async {
      final d = await ProgressInsights(db)
          .priorities(seed.studentId, DateTime.now());
      expect(d.ranked, isEmpty);
      expect(d.exams, isEmpty);
    });

    test('an exam shows days left and no readiness before any evaluation',
        () async {
      final now = DateTime.now();
      await ExamRepository(db).insert(
          subjectId: seed.subjectId,
          examDate: now.add(const Duration(days: 10)),
          examType: ExamType.summative);
      final d = await ProgressInsights(db).priorities(seed.studentId, now);
      expect(d.exams.length, 1);
      expect(d.exams.single.daysAway, inInclusiveRange(9, 10));
      expect(d.exams.single.masteryAverage, isNull);
      expect(d.exams.single.summary, contains('لا تقييمات'));
    });

    test('after an evaluation the exam shows the subject average', () async {
      await complete(Understanding.good);
      final now = DateTime.now();
      await ExamRepository(db).insert(
          subjectId: seed.subjectId,
          examDate: now.add(const Duration(days: 3)),
          examType: ExamType.bac);
      final d = await ProgressInsights(db).priorities(seed.studentId, now);
      final stored = (await db.select(db.masteryStates).get()).single;
      expect(d.exams.single.masteryAverage,
          closeTo(stored.probability, 1e-9));
    });
  });

  group('goals and gaps', () {
    test('no goals and no evaluations: empty', () async {
      final d = await ProgressInsights(db)
          .goalsAndGaps(seed.studentId, DateTime.now());
      expect(d.goals, isEmpty);
      expect(d.weakest, isEmpty);
    });

    test('a goal tied to a subject shows its days left and task counts',
        () async {
      await complete(Understanding.good);
      await newTask();
      final now = DateTime.now();
      await GoalRepository(db).insertFromUser(
          studentId: seed.studentId,
          title: 'هدف تجريبي',
          subjectId: seed.subjectId,
          targetDate: now.add(const Duration(days: 20)));
      final d = await ProgressInsights(db).goalsAndGaps(seed.studentId, now);
      final g = d.goals.single;
      expect(g.daysLeft, inInclusiveRange(19, 20));
      expect(g.doneTasks, 1);
      expect(g.openTasks, 1);
      expect(g.masteryAverage, isNotNull);
      expect(d.weakest.length, 1);
    });

    test('active goals come before achieved ones', () async {
      final repo = GoalRepository(db);
      final a = await repo.insertFromUser(
          studentId: seed.studentId, title: 'منجز');
      await repo.setStatus(a.id, GoalRepository.statusAchieved);
      await repo.insertFromUser(studentId: seed.studentId, title: 'جارٍ');
      final d = await ProgressInsights(db)
          .goalsAndGaps(seed.studentId, DateTime.now());
      expect(d.goals.first.goal.title, 'جارٍ');
      expect(d.goals.last.goal.status, GoalRepository.statusAchieved);
    });
  });
}
