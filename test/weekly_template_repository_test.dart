import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/engines/scheduling_engine.dart';
import 'package:student_app/engines/weekly_planner.dart';
import 'package:student_app/engines/weekly_timeline_engine.dart';
import 'package:student_app/repositories/weekly_template_repository.dart';

import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Database path of the Weekly Timeline: the student's template is stored
/// (real in-memory SQLite), read back as engine input, expanded into a real
/// week and planned. The data used here is synthetic test data, never a
/// real timetable.
void main() {
  group('WeeklyTemplateRepository', () {
    late AppDatabase db;
    late String studentId;
    late WeeklyTemplateRepository repo;

    setUp(() async {
      db = createInMemoryTestDatabase();
      studentId = (await seedMinimalCurriculum(db)).studentId;
      repo = WeeklyTemplateRepository(db);
    });
    tearDown(() => db.close());

    test('starts empty: no default timetable is ever invented', () async {
      expect(await repo.readForStudent(studentId), isEmpty);
      expect(await repo.readSlotsForStudent(studentId), isEmpty);
    });

    test('stores a valid entry with source USER_INPUT and a UUID id',
        () async {
      final e = await repo.insertFromUser(
        studentId: studentId,
        dayOfWeek: 7,
        startMinutes: 480,
        endMinutes: 600,
        kind: TimelineBlockKind.school,
        label: 'test block',
      );
      expect(e.source, 'USER_INPUT');
      expect(e.id.length, 36);
      expect(e.isHard, isTrue);
      expect((await repo.readForStudent(studentId)), hasLength(1));
    });

    test('rejects invalid input without writing anything', () async {
      Future<void> bad({
        int day = 1,
        int start = 480,
        int end = 540,
        TimelineBlockKind kind = TimelineBlockKind.school,
      }) =>
          repo.insertFromUser(
            studentId: studentId,
            dayOfWeek: day,
            startMinutes: start,
            endMinutes: end,
            kind: kind,
          );

      Future<void> rejects(Future<void> f) => expectLater(
          f, throwsA(isA<InvalidWeeklyTemplateEntry>()));

      await rejects(bad(day: 0));
      await rejects(bad(day: 8));
      await rejects(bad(start: -1));
      await rejects(bad(start: 1440));
      await rejects(bad(start: 600, end: 600));
      await rejects(bad(end: 2881));
      await rejects(bad(kind: TimelineBlockKind.study));
      await rejects(bad(kind: TimelineBlockKind.exam));
      expect(await repo.readForStudent(studentId), isEmpty);
    });

    test('a template entry for a missing student is rejected by the database',
        () async {
      await expectLater(
        repo.insertFromUser(
          studentId: 'no-such-student',
          dayOfWeek: 1,
          startMinutes: 480,
          endMinutes: 540,
          kind: TimelineBlockKind.school,
        ),
        throwsA(anything),
      );
    });

    test('deleteById removes only that entry', () async {
      final a = await repo.insertFromUser(
          studentId: studentId,
          dayOfWeek: 1,
          startMinutes: 480,
          endMinutes: 540,
          kind: TimelineBlockKind.school);
      await repo.insertFromUser(
          studentId: studentId,
          dayOfWeek: 2,
          startMinutes: 480,
          endMinutes: 540,
          kind: TimelineBlockKind.school);
      expect(await repo.deleteById(a.id), 1);
      final left = await repo.readForStudent(studentId);
      expect(left, hasLength(1));
      expect(left.single.dayOfWeek, 2);
    });

    test('database -> template -> Sunday-first week -> plan, end to end',
        () async {
      // Synthetic: school Sunday 08:00-15:00, sleep Sunday 22:00 -> 06:00.
      await repo.insertFromUser(
          studentId: studentId,
          dayOfWeek: 7,
          startMinutes: 8 * 60,
          endMinutes: 15 * 60,
          kind: TimelineBlockKind.school);
      await repo.insertFromUser(
          studentId: studentId,
          dayOfWeek: 7,
          startMinutes: 22 * 60,
          endMinutes: 30 * 60,
          kind: TimelineBlockKind.sleep);

      final slots = await repo.readSlotsForStudent(studentId);
      expect(slots, hasLength(2));

      final sunday = DateTime(2026, 9, 27);
      final fixed = WeekTimelineEngine.expandTemplate(
          weekStart: sunday, slots: slots);
      final plan = const WeeklyPlanner().plan(
        weekStart: sunday,
        studyWindows: [
          TimeSlot(start: DateTime(2026, 9, 27, 15), end: DateTime(2026, 9, 27, 22)),
        ],
        fixedBlocks: fixed,
        orderedItems: const [
          SchedulableItem(
            taskId: 'math',
            priorityScore: 0.9,
            totalDurationMinutes: 60,
            isSplittable: false,
            prerequisiteSatisfied: true,
          ),
        ],
      );

      final chunk = plan.scheduling.chunksFor('math').single;
      expect(chunk.start, DateTime(2026, 9, 27, 15));
      final kinds = plan.timeline.days.first.blocks.map((b) => b.kind).toList();
      expect(kinds, [
        TimelineBlockKind.school,
        TimelineBlockKind.study,
        TimelineBlockKind.sleep,
      ]);
      // Sleep crosses midnight: it also appears on Monday morning.
      expect(plan.timeline.days[1].blocks.first.kind, TimelineBlockKind.sleep);
      expect(plan.timeline.days[1].blocks.first.end, DateTime(2026, 9, 28, 6));
    });
  });
}
