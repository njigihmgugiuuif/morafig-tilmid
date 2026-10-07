import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/enums.dart';
import 'package:student_app/domain/exam_link_domain.dart';
import 'package:student_app/repositories/academic_calendar_repository.dart';
import 'package:student_app/repositories/exam_repository.dart';
import 'package:student_app/repositories/goal_repository.dart';
import 'package:student_app/repositories/study_session_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// B (DEVIATION-22): the new repositories and the exam-linking read.
/// All data is SYNTHETIC.
void main() {
  late AppDatabase db;
  late MinimalCurriculumSeed seed;

  setUp(() async {
    db = createInMemoryTestDatabase();
    seed = await seedMinimalCurriculum(db);
  });
  tearDown(() => db.close());

  DateTime at(int day, int h, [int m = 0]) => DateTime(2030, 10, 6 + day, h, m);

  Future<Task> newTask({bool splittable = false}) =>
      TaskRepository(db).createTask(
        knowledgeNodeId: seed.knowledgeNodeId,
        estimatedDurationMinutes: 60,
        isSplittable: splittable,
      );

  group('StudySessionRepository', () {
    test('insertPlanned stores a planned session; end must follow start',
        () async {
      final repo = StudySessionRepository(db);
      final t = await newTask();
      final s = await repo.insertPlanned(
          taskId: t.id, plannedStart: at(0, 16), plannedEnd: at(0, 17));
      expect(s.actualStart, isNull);
      expect(s.observedDurationMinutes, isNull);
      expect(
          () => repo.insertPlanned(
              taskId: t.id, plannedStart: at(0, 17), plannedEnd: at(0, 16)),
          throwsArgumentError);
    });

    test('recordActual stores the real time and the observed minutes, once',
        () async {
      final repo = StudySessionRepository(db);
      final t = await newTask(splittable: true);
      final seg = await repo.insertSegment(
          parentTaskId: t.id, segmentDurationMinutes: 60, segmentOrder: 0);
      final s = await repo.insertPlanned(
          taskId: t.id,
          taskSegmentId: seg.id,
          plannedStart: at(0, 16),
          plannedEnd: at(0, 17));

      final done = await repo.recordActual(
          sessionId: s.id, actualStart: at(0, 16, 5), actualEnd: at(0, 17, 10));
      expect(done.observedDurationMinutes, 65);

      final segments = await repo.readSegmentsForTask(t.id);
      expect(segments.single.executedAt, isNotNull);

      expect(
          () => repo.recordActual(
              sessionId: s.id, actualStart: at(0, 18), actualEnd: at(0, 19)),
          throwsStateError);
      expect(
          () => repo.recordActual(
              sessionId: 'nope', actualStart: at(0, 18), actualEnd: at(0, 19)),
          throwsStateError);
    });

    test('deleteUnexecutedStartingIn removes only the future unexecuted part',
        () async {
      final repo = StudySessionRepository(db);
      final t = await newTask(splittable: true);
      final segPast = await repo.insertSegment(
          parentTaskId: t.id, segmentDurationMinutes: 60, segmentOrder: 0);
      final segFuture = await repo.insertSegment(
          parentTaskId: t.id, segmentDurationMinutes: 60, segmentOrder: 1);
      final past = await repo.insertPlanned(
          taskId: t.id,
          taskSegmentId: segPast.id,
          plannedStart: at(0, 16),
          plannedEnd: at(0, 17));
      final executed = await repo.insertPlanned(
          taskId: t.id, plannedStart: at(2, 16), plannedEnd: at(2, 17));
      await repo.recordActual(
          sessionId: executed.id,
          actualStart: at(2, 16),
          actualEnd: at(2, 17));
      await repo.insertPlanned(
          taskId: t.id,
          taskSegmentId: segFuture.id,
          plannedStart: at(3, 16),
          plannedEnd: at(3, 17));

      final removed = await repo.deleteUnexecutedStartingIn(at(1, 0), at(7, 0));
      expect(removed, 1);

      final left = await repo.readForTask(t.id);
      expect(left.map((s) => s.id).toSet(), {past.id, executed.id});
      final segments = await repo.readSegmentsForTask(t.id);
      expect(segments.map((s) => s.id).toSet(), {segPast.id});
    });

    test('readUnexecutedEndedBy and readUnexecutedStraddling', () async {
      final repo = StudySessionRepository(db);
      final t = await newTask();
      await repo.insertPlanned(
          taskId: t.id, plannedStart: at(0, 16), plannedEnd: at(0, 17));
      expect(await repo.readUnexecutedEndedBy(at(0, 16, 30)), isEmpty);
      expect((await repo.readUnexecutedEndedBy(at(0, 17))).length, 1);
      expect((await repo.readUnexecutedStraddling(at(0, 16, 30))).length, 1);
      expect(await repo.readUnexecutedStraddling(at(0, 17, 30)), isEmpty);
    });
  });

  group('GoalRepository', () {
    test('stores a goal typed by the student; trims and validates the title',
        () async {
      final repo = GoalRepository(db);
      final g = await repo.insertFromUser(
          studentId: seed.studentId,
          title: '  TEST-GOAL  ',
          subjectId: seed.subjectId);
      expect(g.title, 'TEST-GOAL');
      expect(g.status, 'active');
      await expectLater(
          repo.insertFromUser(studentId: seed.studentId, title: '   '),
          throwsA(isA<InvalidGoal>()));
    });

    test('status changes are validated; active reads exclude other statuses',
        () async {
      final repo = GoalRepository(db);
      final a = await repo.insertFromUser(
          studentId: seed.studentId,
          title: 'TEST-A',
          subjectId: seed.subjectId);
      final b = await repo.insertFromUser(
          studentId: seed.studentId, title: 'TEST-B');
      await repo.setStatus(b.id, GoalRepository.statusAchieved);
      await expectLater(
          repo.setStatus(a.id, 'weird'), throwsA(isA<InvalidGoal>()));
      await expectLater(repo.setStatus('missing', GoalRepository.statusDropped),
          throwsA(isA<InvalidGoal>()));

      final active = await repo.readActiveForStudent(seed.studentId);
      expect(active.map((g) => g.id), [a.id]);
      final forSubject =
          await repo.readActiveForSubject(seed.studentId, seed.subjectId);
      expect(forSubject.map((g) => g.id), [a.id]);
    });
  });

  group('AcademicCalendarRepository', () {
    test('terms and holidays: validated, ordered, end day inclusive', () async {
      final repo = AcademicCalendarRepository(db);
      final term = await repo.insertTerm(
          academicYearId: seed.academicYearId,
          name: 'TEST-TERM-1',
          startDate: DateTime(2030, 9, 1),
          endDate: DateTime(2030, 12, 15));
      final hol = await repo.insertHolidayFromUser(
          academicYearId: seed.academicYearId,
          name: 'TEST-HOLIDAY',
          startDate: DateTime(2030, 10, 20),
          endDate: DateTime(2030, 10, 22));

      expect(hol.source, 'USER_INPUT');
      expect((await repo.readTerms(seed.academicYearId)).single.id, term.id);

      final first = await repo.termContaining(
          seed.academicYearId, DateTime(2030, 9, 1, 9));
      expect(first?.id, term.id);
      final lastDay = await repo.termContaining(
          seed.academicYearId, DateTime(2030, 12, 15, 23, 59));
      expect(lastDay?.id, term.id);
      expect(
          await repo.termContaining(seed.academicYearId, DateTime(2030, 12, 16)),
          isNull);

      expect(
          (await repo.holidaysCovering(seed.academicYearId, DateTime(2030, 10, 22)))
              .length,
          1);
      expect(
          await repo.holidaysCovering(seed.academicYearId, DateTime(2030, 10, 23)),
          isEmpty);
    });

    test('invalid entries are refused', () async {
      final repo = AcademicCalendarRepository(db);
      await expectLater(
          repo.insertTerm(
              academicYearId: seed.academicYearId,
              name: ' ',
              startDate: DateTime(2030, 9, 1),
              endDate: DateTime(2030, 9, 2)),
          throwsA(isA<InvalidCalendarEntry>()));
      await expectLater(
          repo.insertHolidayFromUser(
              academicYearId: seed.academicYearId,
              name: 'TEST',
              startDate: DateTime(2030, 9, 5),
              endDate: DateTime(2030, 9, 4)),
          throwsA(isA<InvalidCalendarEntry>()));
    });
  });

  group('ExamRepository additions', () {
    test('readById, readInRange and levelIdForSubject', () async {
      final repo = ExamRepository(db);
      final e1 = await repo.insert(
          subjectId: seed.subjectId,
          examDate: at(1, 9),
          examType: ExamType.summative);
      await repo.insert(
          subjectId: seed.subjectId,
          examDate: at(9, 9),
          examType: ExamType.formative);

      expect((await repo.readById(e1.id))?.id, e1.id);
      expect(await repo.readById('missing'), isNull);

      final week = await repo.readInRange(from: at(0, 0), to: at(7, 0));
      expect(week.map((e) => e.id), [e1.id]);

      final subject = await (db.select(db.subjects)
            ..where((t) => t.id.equals(seed.subjectId)))
          .getSingle();
      expect(await repo.levelIdForSubject(seed.subjectId),
          subject.educationLevelId);
      expect(await repo.levelIdForSubject('missing'), isNull);
    });
  });

  group('ExamLinkService', () {
    test('links an exam to level, goals, term and holiday, with warnings',
        () async {
      final exams = ExamRepository(db);
      final goals = GoalRepository(db);
      final calendar = AcademicCalendarRepository(db);
      final service = ExamLinkService(exams, goals, calendar);

      await calendar.insertTerm(
          academicYearId: seed.academicYearId,
          name: 'TEST-TERM-1',
          startDate: DateTime(2030, 9, 1),
          endDate: DateTime(2030, 12, 15));
      await calendar.insertHolidayFromUser(
          academicYearId: seed.academicYearId,
          name: 'TEST-HOLIDAY',
          startDate: DateTime(2030, 10, 7),
          endDate: DateTime(2030, 10, 8));
      final goal = await goals.insertFromUser(
          studentId: seed.studentId,
          title: 'TEST-GOAL',
          subjectId: seed.subjectId);
      await goals.insertFromUser(
          studentId: seed.studentId, title: 'TEST-OTHER-SUBJECT-FREE');

      final onHoliday = await exams.insert(
          subjectId: seed.subjectId,
          examDate: at(1, 9),
          examType: ExamType.summative);
      final ctx = await service.contextFor(onHoliday,
          studentId: seed.studentId, academicYearId: seed.academicYearId);

      expect(ctx.term?.name, 'TEST-TERM-1');
      expect(ctx.onHoliday, isTrue);
      expect(ctx.activeGoals.map((g) => g.id), [goal.id]);
      expect(ctx.educationLevelId, isNotNull);
      expect(ctx.warnings, contains('exam_on_holiday'));
      expect(ctx.warnings, isNot(contains('exam_outside_terms')));

      final outside = await exams.insert(
          subjectId: seed.subjectId,
          examDate: DateTime(2031, 3, 1),
          examType: ExamType.bac);
      final ctx2 = await service.contextFor(outside,
          studentId: seed.studentId, academicYearId: seed.academicYearId);
      expect(ctx2.term, isNull);
      expect(ctx2.warnings, contains('exam_outside_terms'));
    });

    test('no term entered means no outside-terms warning (nothing invented)',
        () async {
      final exams = ExamRepository(db);
      final service = ExamLinkService(
          exams, GoalRepository(db), AcademicCalendarRepository(db));
      final e = await exams.insert(
          subjectId: seed.subjectId,
          examDate: at(1, 9),
          examType: ExamType.summative);
      final ctx = await service.contextFor(e,
          studentId: seed.studentId,
          academicYearId: seed.academicYearId,
          studentLevelId: 'some-other-level');
      expect(ctx.term, isNull);
      expect(ctx.warnings, isNot(contains('exam_outside_terms')));
      expect(ctx.warnings, contains('exam_level_differs_from_student'));
    });

    test('upcomingContexts returns the exams from now on, soonest first',
        () async {
      final exams = ExamRepository(db);
      final service = ExamLinkService(
          exams, GoalRepository(db), AcademicCalendarRepository(db));
      final later = await exams.insert(
          subjectId: seed.subjectId,
          examDate: at(5, 9),
          examType: ExamType.summative);
      final sooner = await exams.insert(
          subjectId: seed.subjectId,
          examDate: at(2, 9),
          examType: ExamType.summative);
      await exams.insert(
          subjectId: seed.subjectId,
          examDate: at(-3, 9),
          examType: ExamType.formative);

      final list = await service.upcomingContexts(
          now: at(0, 8),
          studentId: seed.studentId,
          academicYearId: seed.academicYearId);
      expect(list.map((c) => c.exam.id), [sooner.id, later.id]);
    });
  });
}
