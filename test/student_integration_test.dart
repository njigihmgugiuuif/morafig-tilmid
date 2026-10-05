import 'package:drift/drift.dart' as drift;
import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/enums.dart';
import 'package:student_app/domain/student_context_domain.dart';
import 'package:student_app/repositories/content_repository.dart';
import 'package:student_app/repositories/curriculum_repository.dart';
import 'package:student_app/repositories/mastery_repository.dart';
import 'package:student_app/repositories/student_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'package:student_app/services/intelligence_service.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Student Integration (DEVIATION-19). All data is SYNTHETIC test data (see
/// fixtures/seed_data.dart); nothing here is an official Algerian value.
void main() {
  late AppDatabase db;
  late StudentRepository students;
  late CurriculumRepository curriculum;
  late StudentContextService context;
  late MinimalCurriculumSeed seed;

  setUp(() async {
    db = createInMemoryTestDatabase();
    seed = await seedMinimalCurriculum(db);
    students = StudentRepository(db);
    curriculum = CurriculumRepository(db);
    context = StudentContextService(students, curriculum);
  });
  tearDown(() => db.close());

  Future<CurriculumVersion> makeVersion(PolicyStatus status,
      {String? yearId}) async {
    final doc = await db.into(db.policyDocuments).insertReturning(
          PolicyDocumentsCompanion.insert(
            documentNumber: 'TEST-DOC-${status.name}',
            documentType: 'test-fixture',
            issuingAuthority: 'test-fixture',
            verificationStatus: 'primaryVerified',
          ),
        );
    return curriculum.createVersion(
      academicYearId: yearId ?? seed.academicYearId,
      status: status,
      sourcePolicyDocumentId: doc.id,
    );
  }

  Future<AcademicYear> makeOtherYear() => db.into(db.academicYears).insertReturning(
        AcademicYearsCompanion.insert(
          label: 'TEST-YEAR-OTHER',
          startDate: DateTime.utc(2001, 9, 1),
          endDate: DateTime.utc(2002, 6, 30),
        ),
      );

  Future<EducationLevel> makeLevel(String name, int order) =>
      db.into(db.educationLevels).insertReturning(
          EducationLevelsCompanion.insert(name: name, order: order));

  Future<StudyStream> makeStream(String name, String levelId) =>
      db.into(db.streams).insertReturning(
          StreamsCompanion.insert(name: name, educationLevelId: levelId));

  group('profile', () {
    test('a student created before v6 has NULL level / stream / version, and '
        'is still readable', () async {
      final p = await students.readProfile();
      expect(p, isNotNull);
      expect(p!.student.id, equals(seed.studentId));
      expect(p.academicYear.id, equals(seed.academicYearId));
      expect(p.educationLevel, isNull);
      expect(p.stream, isNull);
      expect(p.curriculumVersionId, isNull);
    });

    test('createInitialStudent links the student to an academic year and '
        'refuses a second student', () async {
      final fresh = createInMemoryTestDatabase();
      try {
        final repo = StudentRepository(fresh);
        expect(await repo.readProfile(), isNull);
        final s = await repo.createInitialStudent(
            fullNameOrNickname: 'TEST-NEW', sleepFloorMinMinutes: 420);
        final p = await repo.readProfile();
        expect(p!.student.id, equals(s.id));
        expect(p.academicYear.id, equals(s.currentAcademicYearId));
        expect(p.educationLevel, isNull);
        expect(p.curriculumVersionId, isNull);
        expect(
          () => repo.createInitialStudent(
              fullNameOrNickname: 'TEST-SECOND', sleepFloorMinMinutes: 420),
          throwsStateError,
        );
      } finally {
        await fresh.close();
      }
    });

    test('updateProfile does not touch the level, stream or version',
        () async {
      final level = await makeLevel('TEST-LEVEL-A', 5);
      await students.setAcademicTrack(
          studentId: seed.studentId, educationLevelId: level.id);
      await students.updateProfile(
          studentId: seed.studentId,
          fullNameOrNickname: 'TEST-RENAMED',
          sleepFloorMinMinutes: 480);
      final p = await students.readProfile();
      expect(p!.student.fullNameOrNickname, equals('TEST-RENAMED'));
      expect(p.educationLevel!.id, equals(level.id));
    });
  });

  group('level and stream', () {
    test('records a level and a stream that belongs to it', () async {
      final level = await makeLevel('TEST-LEVEL-A', 5);
      final stream = await makeStream('TEST-STREAM-A', level.id);
      await students.setAcademicTrack(
          studentId: seed.studentId,
          educationLevelId: level.id,
          streamId: stream.id);
      final p = await students.readProfile();
      expect(p!.educationLevel!.id, equals(level.id));
      expect(p.stream!.id, equals(stream.id));
    });

    test('omitting the stream clears it (never guessed)', () async {
      final level = await makeLevel('TEST-LEVEL-A', 5);
      final stream = await makeStream('TEST-STREAM-A', level.id);
      await students.setAcademicTrack(
          studentId: seed.studentId,
          educationLevelId: level.id,
          streamId: stream.id);
      await students.setAcademicTrack(
          studentId: seed.studentId, educationLevelId: level.id);
      final p = await students.readProfile();
      expect(p!.educationLevel!.id, equals(level.id));
      expect(p.stream, isNull);
    });

    test('refuses an unknown level, an unknown stream, a stream of another '
        'level and an unknown student', () async {
      final levelA = await makeLevel('TEST-LEVEL-A', 5);
      final levelB = await makeLevel('TEST-LEVEL-B', 6);
      final streamB = await makeStream('TEST-STREAM-B', levelB.id);
      expect(
          () => students.setAcademicTrack(
              studentId: seed.studentId, educationLevelId: 'nope'),
          throwsArgumentError);
      expect(
          () => students.setAcademicTrack(
              studentId: seed.studentId,
              educationLevelId: levelA.id,
              streamId: 'nope'),
          throwsArgumentError);
      expect(
          () => students.setAcademicTrack(
              studentId: seed.studentId,
              educationLevelId: levelA.id,
              streamId: streamB.id),
          throwsArgumentError);
      expect(
          () => students.setAcademicTrack(
              studentId: 'nope', educationLevelId: levelA.id),
          throwsArgumentError);
      // Nothing was written by the refused calls.
      final p = await students.readProfile();
      expect(p!.educationLevel, isNull);
      expect(p.stream, isNull);
    });
  });

  group('academic year', () {
    test('moving to another year unlinks a version of the old year',
        () async {
      await students.setCurriculumVersion(
          studentId: seed.studentId,
          curriculumVersionId: seed.curriculumVersionId);
      final other = await makeOtherYear();
      final s = await students.setCurrentAcademicYear(
          studentId: seed.studentId, academicYearId: other.id);
      expect(s.currentAcademicYearId, equals(other.id));
      expect(s.curriculumVersionId, isNull);
    });

    test('staying in the same year keeps the linked version', () async {
      await students.setCurriculumVersion(
          studentId: seed.studentId,
          curriculumVersionId: seed.curriculumVersionId);
      final s = await students.setCurrentAcademicYear(
          studentId: seed.studentId, academicYearId: seed.academicYearId);
      expect(s.curriculumVersionId, equals(seed.curriculumVersionId));
    });

    test('a missing year is refused', () async {
      expect(
          () => students.setCurrentAcademicYear(
              studentId: seed.studentId, academicYearId: 'nope'),
          throwsArgumentError);
    });
  });

  group('curriculum version link', () {
    test('an ACTIVE version of the current year can be linked and cleared',
        () async {
      final s = await students.setCurriculumVersion(
          studentId: seed.studentId,
          curriculumVersionId: seed.curriculumVersionId);
      expect(s.curriculumVersionId, equals(seed.curriculumVersionId));
      final cleared = await students.clearCurriculumVersion(seed.studentId);
      expect(cleared.curriculumVersionId, isNull);
    });

    test('UNKNOWN / CONFLICT / FROZEN / REPEALED versions are refused',
        () async {
      for (final status in [
        PolicyStatus.unknown,
        PolicyStatus.conflict,
        PolicyStatus.frozen,
        PolicyStatus.repealed,
      ]) {
        final v = await makeVersion(status);
        expect(
          () => students.setCurriculumVersion(
              studentId: seed.studentId, curriculumVersionId: v.id),
          throwsA(isA<PolicyDataGuardViolation>()),
          reason: '${status.name} must not be linkable',
        );
      }
      final p = await students.readProfile();
      expect(p!.curriculumVersionId, isNull);
    });

    test('a version of another academic year, or a missing one, is refused',
        () async {
      final other = await makeOtherYear();
      final v = await makeVersion(PolicyStatus.active, yearId: other.id);
      expect(
        () => students.setCurriculumVersion(
            studentId: seed.studentId, curriculumVersionId: v.id),
        throwsA(isA<PolicyDataGuardViolation>()),
      );
      expect(
        () => students.setCurriculumVersion(
            studentId: seed.studentId, curriculumVersionId: 'nope'),
        throwsA(isA<PolicyDataGuardViolation>()),
      );
    });
  });

  group('StudentContextService (consumption gate)', () {
    test('no student: nothing to consume', () async {
      final fresh = createInMemoryTestDatabase();
      try {
        final svc = StudentContextService(
            StudentRepository(fresh), CurriculumRepository(fresh));
        expect(await svc.current(), isNull);
        expect(await svc.usableCurriculumVersionId(), isNull);
      } finally {
        await fresh.close();
      }
    });

    test('a student with no linked version has UNKNOWN curriculum, never '
        'ACTIVE', () async {
      final ctx = await context.current();
      expect(ctx!.status, equals(PolicyStatus.unknown));
      expect(ctx.linkedToVersion, isFalse);
      expect(ctx.curriculumUsable, isFalse);
      expect(await context.usableCurriculumVersionId(), isNull);
    });

    test('a linked ACTIVE version is usable', () async {
      await students.setCurriculumVersion(
          studentId: seed.studentId,
          curriculumVersionId: seed.curriculumVersionId);
      final ctx = await context.current();
      expect(ctx!.status, equals(PolicyStatus.active));
      expect(ctx.curriculumUsable, isTrue);
      expect(await context.usableCurriculumVersionId(),
          equals(seed.curriculumVersionId));
    });

    test('a version that later becomes FROZEN or CONFLICT stops being usable '
        'without touching the student row', () async {
      await students.setCurriculumVersion(
          studentId: seed.studentId,
          curriculumVersionId: seed.curriculumVersionId);
      await curriculum.changeVersionStatus(
          curriculumVersionId: seed.curriculumVersionId,
          newStatus: PolicyStatus.frozen);
      var ctx = await context.current();
      expect(ctx!.status, equals(PolicyStatus.frozen));
      expect(ctx.curriculumUsable, isFalse);
      expect(await context.usableCurriculumVersionId(), isNull);

      await curriculum.changeVersionStatus(
          curriculumVersionId: seed.curriculumVersionId,
          newStatus: PolicyStatus.conflict);
      ctx = await context.current();
      expect(ctx!.status, equals(PolicyStatus.conflict));
      expect(await context.usableCurriculumVersionId(), isNull);
    });

    test('a version that later becomes REPEALED is never consumed: the gate '
        'throws, loudly', () async {
      await students.setCurriculumVersion(
          studentId: seed.studentId,
          curriculumVersionId: seed.curriculumVersionId);
      await curriculum.changeVersionStatus(
          curriculumVersionId: seed.curriculumVersionId,
          newStatus: PolicyStatus.repealed);
      final ctx = await context.current();
      expect(ctx!.status, equals(PolicyStatus.repealed));
      expect(ctx.curriculumUsable, isFalse);
      expect(() => context.usableCurriculumVersionId(),
          throwsA(isA<PolicyDataGuardViolation>()));
    });

    test('a stale link to a version of another year is UNKNOWN', () async {
      final other = await makeOtherYear();
      final v = await makeVersion(PolicyStatus.active, yearId: other.id);
      // Bypass the repository on purpose to simulate stale data.
      await (db.update(db.students)..where((t) => t.id.equals(seed.studentId)))
          .write(StudentsCompanion(curriculumVersionId: drift.Value(v.id)));
      final ctx = await context.current();
      expect(ctx!.status, equals(PolicyStatus.unknown));
      expect(ctx.reason, contains('different academic year'));
      expect(await context.usableCurriculumVersionId(), isNull);
    });

    test('effective dates are applied only when asOf is given', () async {
      await students.setCurriculumVersion(
          studentId: seed.studentId,
          curriculumVersionId: seed.curriculumVersionId);
      await (db.update(db.curriculumVersions)
            ..where((t) => t.id.equals(seed.curriculumVersionId)))
          .write(CurriculumVersionsCompanion(
        effectiveTo: drift.Value(DateTime.utc(2026, 1, 1)),
      ));
      expect(await context.usableCurriculumVersionId(),
          equals(seed.curriculumVersionId));
      final ended = await context.current(asOf: DateTime.utc(2026, 10, 1));
      expect(ended!.windowState, equals(VersionWindowState.ended));
      expect(ended.curriculumUsable, isFalse);
      expect(
          await context.usableCurriculumVersionId(
              asOf: DateTime.utc(2026, 10, 1)),
          isNull);
    });
  });

  group('wiring into the Core', () {
    test('new content goes under the student\'s own level when set',
        () async {
      final content = ContentRepository(db);
      final level = await makeLevel('TEST-LEVEL-A', 5);
      // Two levels exist now and the student has none: must not throw.
      final fallback = await content.getOrCreateDefaultLevel();
      expect(fallback.id, isNotEmpty);

      await students.setAcademicTrack(
          studentId: seed.studentId, educationLevelId: level.id);
      final own = await content.getOrCreateDefaultLevel();
      expect(own.id, equals(level.id));
    });

    test('with no level anywhere the placeholder is still created as before',
        () async {
      final fresh = createInMemoryTestDatabase();
      try {
        final level = await ContentRepository(fresh).getOrCreateDefaultLevel();
        expect(level.name, isNotEmpty);
        final again = await ContentRepository(fresh).getOrCreateDefaultLevel();
        expect(again.id, equals(level.id));
      } finally {
        await fresh.close();
      }
    });

    test('the learning loop still works for a student with a full profile',
        () async {
      final level = await makeLevel('TEST-LEVEL-A', 5);
      final stream = await makeStream('TEST-STREAM-A', level.id);
      await students.setAcademicTrack(
          studentId: seed.studentId,
          educationLevelId: level.id,
          streamId: stream.id);
      await students.setCurriculumVersion(
          studentId: seed.studentId,
          curriculumVersionId: seed.curriculumVersionId);

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
      final mastery = await MasteryRepository(db)
          .read(seed.studentId, seed.knowledgeNodeId);
      expect(mastery, isNotNull);
    });
  });
}
