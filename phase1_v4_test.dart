import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/reality_layer_domain.dart';
import 'package:student_app/export_import/export_import_service.dart';
import 'package:student_app/repositories/availability_repository.dart';
import 'package:student_app/repositories/reality_and_prerequisite_repositories.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'package:student_app/services/intelligence_service.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Phase 1 v4 data model: the four new tables, the three new nullable
/// columns, export/import (new format + backward compatibility with files
/// that predate v4) and the Reality Layer on the Sunday-first week.
/// All data is synthetic.
void main() {
  late AppDatabase db;
  late MinimalCurriculumSeed seed;

  setUp(() async {
    db = createInMemoryTestDatabase();
    seed = await seedMinimalCurriculum(db);
  });
  tearDown(() => db.close());

  group('v4 tables', () {
    test('the four new tables accept rows and apply their defaults',
        () async {
      final at = DateTime.utc(2026, 10, 1, 8);
      await db.into(db.energyFocusLogs).insert(EnergyFocusLogsCompanion.insert(
            studentId: seed.studentId,
            loggedAt: at,
            energyLevel: 4,
            focusLevel: 2,
          ));
      await db.into(db.academicTerms).insert(AcademicTermsCompanion.insert(
            academicYearId: seed.academicYearId,
            name: 'TEST-TERM-1',
            startDate: DateTime.utc(2000, 9, 1),
            endDate: DateTime.utc(2000, 12, 20),
          ));
      await db.into(db.holidays).insert(HolidaysCompanion.insert(
            academicYearId: seed.academicYearId,
            name: 'TEST-HOLIDAY',
            startDate: DateTime.utc(2000, 12, 21),
            endDate: DateTime.utc(2001, 1, 4),
          ));
      await db.into(db.goals).insert(GoalsCompanion.insert(
            studentId: seed.studentId,
            title: 'TEST-GOAL',
          ));

      final logs = await db.select(db.energyFocusLogs).get();
      expect(logs.single.energyLevel, 4);
      expect(logs.single.focusLevel, 2);
      expect((await db.select(db.academicTerms).get()).single.name,
          'TEST-TERM-1');
      expect((await db.select(db.holidays).get()).single.source,
          'USER_INPUT');
      final goal = (await db.select(db.goals).get()).single;
      expect(goal.status, 'active');
      expect(goal.subjectId, isNull);
      expect(goal.targetDate, isNull);
    });

    test('foreign keys are enforced on the new tables', () async {
      await expectLater(
        db.into(db.goals).insert(GoalsCompanion.insert(
              studentId: 'no-such-student',
              title: 'ORPHAN',
            )),
        throwsA(anything),
      );
      await expectLater(
        db.into(db.holidays).insert(HolidaysCompanion.insert(
              academicYearId: 'no-such-year',
              name: 'ORPHAN',
              startDate: DateTime.utc(2000, 1, 1),
              endDate: DateTime.utc(2000, 1, 2),
            )),
        throwsA(anything),
      );
    });

    test('Subjects.curriculumVersionId is NULL by default, can link a real '
        'version, and rejects an unknown one', () async {
      final subject = await (db.select(db.subjects)
            ..where((t) => t.id.equals(seed.subjectId)))
          .getSingle();
      expect(subject.curriculumVersionId, isNull);

      await (db.update(db.subjects)..where((t) => t.id.equals(seed.subjectId)))
          .write(SubjectsCompanion(
        curriculumVersionId: drift.Value(seed.curriculumVersionId),
      ));
      final linked = await (db.select(db.subjects)
            ..where((t) => t.id.equals(seed.subjectId)))
          .getSingle();
      expect(linked.curriculumVersionId, seed.curriculumVersionId);

      await expectLater(
        (db.update(db.subjects)..where((t) => t.id.equals(seed.subjectId)))
            .write(const SubjectsCompanion(
          curriculumVersionId: drift.Value('no-such-version'),
        )),
        throwsA(anything),
      );
    });

    test('MasteryStates.confidence and observationCount are NULL for a row '
        'written by the existing engine flow (nothing is invented)',
        () async {
      final task = await TaskRepository(db).createTask(
        knowledgeNodeId: seed.knowledgeNodeId,
        estimatedDurationMinutes: 30,
        isSplittable: false,
      );
      await TaskRepository(db)
          .markComplete(task, understanding: Understanding.good);
      final run = await IntelligenceService(db,
              clock: () => DateTime.utc(2026, 10, 1, 12))
          .processPendingEvents();
      expect(run.errors, isEmpty);

      final rows = await db.select(db.masteryStates).get();
      expect(rows, hasLength(1));
      expect(rows.single.confidence, isNull);
      expect(rows.single.observationCount, isNull);
    });
  });

  group('export / import', () {
    Future<void> fillNewData() async {
      await (db.update(db.subjects)..where((t) => t.id.equals(seed.subjectId)))
          .write(SubjectsCompanion(
        curriculumVersionId: drift.Value(seed.curriculumVersionId),
      ));
      await db.into(db.goals).insert(GoalsCompanion.insert(
            studentId: seed.studentId,
            title: 'TEST-GOAL',
          ));
      await db.into(db.holidays).insert(HolidaysCompanion.insert(
            academicYearId: seed.academicYearId,
            name: 'TEST-HOLIDAY',
            startDate: DateTime.utc(2000, 12, 21),
            endDate: DateTime.utc(2001, 1, 4),
          ));
    }

    test('export writes format 2 and includes the four new tables',
        () async {
      await fillNewData();
      final bundle = jsonDecode(await ExportImportService(db).exportAll())
          as Map<String, dynamic>;
      expect(bundle['schemaVersion'], 2);
      final tables = bundle['tables'] as Map<String, dynamic>;
      for (final t in const [
        'energy_focus_logs',
        'academic_terms',
        'holidays',
        'goals',
      ]) {
        expect(tables.containsKey(t), isTrue, reason: 'missing $t');
      }
      expect((tables['goals'] as List), hasLength(1));
      final subject = (tables['subjects'] as List).single as Map;
      expect(subject['curriculum_version_id'], seed.curriculumVersionId);
    });

    test('a format-2 export imports into an empty database, UUIDs and the '
        'subject->version link preserved (FK order cannot matter)',
        () async {
      await fillNewData();
      final json = await ExportImportService(db).exportAll();

      final target = createInMemoryTestDatabase();
      try {
        await ExportImportService(target).importAll(json);
        final goals = await target.select(target.goals).get();
        expect(goals, hasLength(1));
        expect(goals.single.title, 'TEST-GOAL');
        expect(await target.select(target.holidays).get(), hasLength(1));
        final subject = await (target.select(target.subjects)
              ..where((t) => t.id.equals(seed.subjectId)))
            .getSingle();
        expect(subject.curriculumVersionId, seed.curriculumVersionId);
      } finally {
        await target.close();
      }
    });

    test('an older format-1 file (no new tables, no new columns) still '
        'imports; the new data stays NULL/empty', () async {
      // Real data in the tables whose shape changed, then strip everything
      // v4 added from the exported JSON to emulate a file written by v3.
      final task = await TaskRepository(db).createTask(
        knowledgeNodeId: seed.knowledgeNodeId,
        estimatedDurationMinutes: 30,
        isSplittable: false,
      );
      await TaskRepository(db)
          .markComplete(task, understanding: Understanding.good);
      await IntelligenceService(db, clock: () => DateTime.utc(2026, 10, 1, 12))
          .processPendingEvents();

      final bundle = jsonDecode(await ExportImportService(db).exportAll())
          as Map<String, dynamic>;
      bundle['schemaVersion'] = 1;
      final tables = bundle['tables'] as Map<String, dynamic>;
      for (final t in const [
        'energy_focus_logs',
        'academic_terms',
        'holidays',
        'goals',
      ]) {
        tables.remove(t);
      }
      for (final row in (tables['mastery_states'] as List).cast<Map>()) {
        row.remove('confidence');
        row.remove('observation_count');
      }
      for (final row in (tables['subjects'] as List).cast<Map>()) {
        row.remove('curriculum_version_id');
      }

      final target = createInMemoryTestDatabase();
      try {
        await ExportImportService(target).importAll(jsonEncode(bundle));
        final mastery = await target.select(target.masteryStates).get();
        expect(mastery, hasLength(1));
        expect(mastery.single.confidence, isNull);
        expect(mastery.single.observationCount, isNull);
        final subject = await (target.select(target.subjects)
              ..where((t) => t.id.equals(seed.subjectId)))
            .getSingle();
        expect(subject.curriculumVersionId, isNull);
        expect(await target.select(target.goals).get(), isEmpty);
      } finally {
        await target.close();
      }
    });

    test('a file from a NEWER format, or a non-integer version, is '
        'rejected without writing anything', () async {
      final target = createInMemoryTestDatabase();
      try {
        for (final bad in const [
          '{"exportedAt":"x","schemaVersion":3,"tables":{}}',
          '{"exportedAt":"x","schemaVersion":"2","tables":{}}',
        ]) {
          await expectLater(
            ExportImportService(target).importAll(bad),
            throwsA(isA<ImportValidationException>()),
          );
        }
        expect(await target.select(target.students).get(), isEmpty);
      } finally {
        await target.close();
      }
    });
  });

  group('Reality Layer on the Sunday-first week', () {
    // 2026-09-27 is a Sunday. Stored day numbers: 7 = Sunday, 1 = Monday.
    final sunday = DateTime(2026, 9, 27);
    final nextSunday = DateTime(2026, 10, 4);

    test('a recurring Sunday (7) and Monday (1) availability each land on '
        'their own day, once, inside the Sunday-first week', () async {
      final availabilities = AvailabilityRepository(db);
      await availabilities.insert(
        studentId: seed.studentId,
        dayOfWeek: 7, // Sunday
        windowStartMinutes: 16 * 60,
        windowEndMinutes: 18 * 60,
        isRecurring: true,
      );
      await availabilities.insert(
        studentId: seed.studentId,
        dayOfWeek: 1, // Monday
        windowStartMinutes: 9 * 60,
        windowEndMinutes: 10 * 60,
        isRecurring: true,
      );

      final service = RealityLayerDomainService(
          availabilities, RealityConstraintRepository(db));
      final slots = await service.computeFreeSlots(
        studentId: seed.studentId,
        rangeStart: sunday,
        rangeEnd: nextSunday,
      );
      slots.sort((a, b) => a.start.compareTo(b.start));

      expect(slots, hasLength(2)); // next Sunday is the exclusive end
      expect(slots[0].start, DateTime(2026, 9, 27, 16));
      expect(slots[0].end, DateTime(2026, 9, 27, 18));
      expect(slots[1].start, DateTime(2026, 9, 28, 9));
      expect(slots[1].end, DateTime(2026, 9, 28, 10));
    });

    test('a hard constraint still removes time, a soft one does not',
        () async {
      final availabilities = AvailabilityRepository(db);
      await availabilities.insert(
        studentId: seed.studentId,
        dayOfWeek: 1, // Monday
        windowStartMinutes: 9 * 60,
        windowEndMinutes: 10 * 60,
        isRecurring: true,
      );
      final constraints = RealityConstraintRepository(db);
      await constraints.insertFromUser(
        studentId: seed.studentId,
        type: 'fixedCommitment',
        windowStart: DateTime(2026, 9, 28, 9, 30),
        windowEnd: DateTime(2026, 9, 28, 10, 30),
        isHard: true,
      );
      await constraints.insertFromUser(
        studentId: seed.studentId,
        type: 'rest',
        windowStart: DateTime(2026, 9, 28, 9),
        windowEnd: DateTime(2026, 9, 28, 9, 10),
        isHard: false,
      );

      final slots = await RealityLayerDomainService(
              availabilities, constraints)
          .computeFreeSlots(
        studentId: seed.studentId,
        rangeStart: sunday,
        rangeEnd: nextSunday,
      );
      expect(slots, hasLength(1));
      expect(slots.single.start, DateTime(2026, 9, 28, 9));
      expect(slots.single.end, DateTime(2026, 9, 28, 9, 30));
    });
  });
}
