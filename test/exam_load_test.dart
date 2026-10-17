import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/enums.dart';
import 'package:student_app/engines/scheduling_engine.dart' show TimeSlot;
import 'package:student_app/engines/weekly_timeline_engine.dart';
import 'package:student_app/repositories/availability_repository.dart';
import 'package:student_app/repositories/exam_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'package:student_app/repositories/weekly_template_repository.dart';
import 'package:student_app/ui/state/exam_load.dart';

import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// «الحمل قبل الامتحانات»: needed minutes of the subject's open tasks next to
/// the free study time before the exam. All data is SYNTHETIC.
void main() {
  group('ExamLoadMath.freeMinutes', () {
    final from = DateTime(2026, 10, 11, 7);
    final to = DateTime(2026, 10, 13, 8);

    TimeSlot slot(DateTime d, int h1, int m1, int h2, int m2) => TimeSlot(
        start: DateTime(d.year, d.month, d.day, h1, m1),
        end: DateTime(d.year, d.month, d.day, h2, m2));

    test('adds the windows inside the range', () {
      final windows = [
        slot(DateTime(2026, 10, 11), 16, 0, 18, 0),
        slot(DateTime(2026, 10, 12), 16, 0, 17, 0),
      ];
      expect(
          ExamLoadMath.freeMinutes(
              windows: windows, blocks: const [], from: from, to: to),
          180);
    });

    test('clips what is before now and after the exam', () {
      final windows = [
        slot(DateTime(2026, 10, 11), 5, 0, 9, 0), // 07:00..09:00 counts
        slot(DateTime(2026, 10, 13), 7, 0, 10, 0), // up to 08:00 counts
        slot(DateTime(2026, 10, 14), 7, 0, 10, 0), // after the exam
      ];
      expect(
          ExamLoadMath.freeMinutes(
              windows: windows, blocks: const [], from: from, to: to),
          120 + 60);
    });

    test('overlapping windows are counted once', () {
      final windows = [
        slot(DateTime(2026, 10, 11), 16, 0, 18, 0),
        slot(DateTime(2026, 10, 11), 17, 0, 19, 0),
      ];
      expect(
          ExamLoadMath.freeMinutes(
              windows: windows, blocks: const [], from: from, to: to),
          180);
    });

    test('hard blocks are removed, soft blocks are not', () {
      final windows = [slot(DateTime(2026, 10, 11), 16, 0, 18, 0)];
      final hard = TimelineBlock(
        kind: TimelineBlockKind.school,
        start: DateTime(2026, 10, 11, 16, 30),
        end: DateTime(2026, 10, 11, 17),
      );
      final soft = TimelineBlock(
        kind: TimelineBlockKind.rest,
        start: DateTime(2026, 10, 11, 17),
        end: DateTime(2026, 10, 11, 18),
        isHard: false,
      );
      expect(
          ExamLoadMath.freeMinutes(
              windows: windows, blocks: [hard, soft], from: from, to: to),
          90);
    });

    test('an exam that is not after now has no free time', () {
      expect(
          ExamLoadMath.freeMinutes(
              windows: [slot(DateTime(2026, 10, 11), 16, 0, 18, 0)],
              blocks: const [],
              from: from,
              to: from),
          0);
    });
  });

  group('ExamLoadMath.summaryFor states only the two numbers', () {
    test('no open task', () {
      expect(
          ExamLoadMath.summaryFor(
              needed: 0, available: 100, hasAvailability: true, openTasks: 0),
          'لا مهام مفتوحة لهذه المادة.');
    });

    test('no free time entered', () {
      final s = ExamLoadMath.summaryFor(
          needed: 120, available: 0, hasAvailability: false, openTasks: 2);
      expect(s, contains('لم تُدخل أوقات فراغك'));
    });

    test('enough, and not enough', () {
      final more = ExamLoadMath.summaryFor(
          needed: 60, available: 150, hasAvailability: true, openTasks: 1);
      expect(more, contains('يزيد المتاح'));
      final less = ExamLoadMath.summaryFor(
          needed: 150, available: 60, hasAvailability: true, openTasks: 1);
      expect(less, contains('ينقص المتاح'));
      final none = ExamLoadMath.summaryFor(
          needed: 150, available: 0, hasAvailability: true, openTasks: 1);
      expect(none, contains('لا وقت فراغ متاح'));
    });
  });

  group('ExamLoadReader on a real in-memory database', () {
    late AppDatabase db;
    late MinimalCurriculumSeed seed;
    final now = DateTime(2026, 10, 11, 7); // a Sunday, 07:00

    setUp(() async {
      db = createInMemoryTestDatabase();
      seed = await seedMinimalCurriculum(db);
    });
    tearDown(() => db.close());

    Future<void> examOnTuesday() => ExamRepository(db)
        .insert(
          subjectId: seed.subjectId,
          examDate: DateTime(2026, 10, 13, 8),
          examType: ExamType.summative,
        )
        .then((_) {});

    Future<Task> task(int minutes) => TaskRepository(db).createTask(
          knowledgeNodeId: seed.knowledgeNodeId,
          estimatedDurationMinutes: minutes,
          isSplittable: false,
        );

    test('no exam: no rows', () async {
      final d = await ExamLoadReader(db).read(seed.studentId, now);
      expect(d.rows, isEmpty);
    });

    test('no free window entered: needed is shown, available is unknown',
        () async {
      await examOnTuesday();
      await task(100);
      final d = await ExamLoadReader(db).read(seed.studentId, now);
      expect(d.hasAvailability, isFalse);
      expect(d.rows, hasLength(1));
      expect(d.rows.single.neededMinutes, 100);
      expect(d.rows.single.availableMinutes, 0);
      expect(d.rows.single.openTasks, 1);
      expect(d.rows.single.daysAway, 2);
    });

    test('free windows minus the school block, up to the exam', () async {
      await examOnTuesday();
      await task(100);
      final av = AvailabilityRepository(db);
      // Sunday (stored 7) 16:00..18:00 and Monday (1) 16:00..17:00.
      await av.insert(
          studentId: seed.studentId,
          dayOfWeek: 7,
          windowStartMinutes: 960,
          windowEndMinutes: 1080,
          isRecurring: true);
      await av.insert(
          studentId: seed.studentId,
          dayOfWeek: 1,
          windowStartMinutes: 960,
          windowEndMinutes: 1020,
          isRecurring: true);
      // Sunday school block 16:30..17:00 (hard) takes 30 minutes away.
      await WeeklyTemplateRepository(db).insertFromUser(
        studentId: seed.studentId,
        dayOfWeek: 7,
        startMinutes: 990,
        endMinutes: 1020,
        kind: TimelineBlockKind.school,
      );

      final d = await ExamLoadReader(db).read(seed.studentId, now);
      expect(d.hasAvailability, isTrue);
      final row = d.rows.single;
      expect(row.neededMinutes, 100);
      expect(row.availableMinutes, 90 + 60);
      expect(row.gapMinutes, 50);
    });

    test('a finished task is not counted', () async {
      await examOnTuesday();
      final t = await task(100);
      await TaskRepository(db).markComplete(t, understanding: 'good');
      final d = await ExamLoadReader(db).read(seed.studentId, now);
      expect(d.rows.single.neededMinutes, 0);
      expect(d.rows.single.openTasks, 0);
    });

    test('a past exam is not shown', () async {
      await ExamRepository(db).insert(
        subjectId: seed.subjectId,
        examDate: DateTime(2026, 10, 1, 8),
        examType: ExamType.summative,
      );
      final d = await ExamLoadReader(db).read(seed.studentId, now);
      expect(d.rows, isEmpty);
    });
  });
}
