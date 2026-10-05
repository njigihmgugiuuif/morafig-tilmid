import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../domain/enums.dart';
import 'curriculum_repository.dart';

/// The student together with the rows they point at (read-only). `educationLevel`,
/// `stream` are null when the student has not said (NULL = unknown).
class StudentProfile {
  const StudentProfile({
    required this.student,
    required this.academicYear,
    this.educationLevel,
    this.stream,
  });

  final Student student;
  final AcademicYear academicYear;
  final EducationLevel? educationLevel;
  final StudyStream? stream;

  String? get curriculumVersionId => student.curriculumVersionId;
}

/// Handles first-run onboarding: creating the single Student row this
/// personal app is built around, plus the AcademicYear it must reference
/// (Students.currentAcademicYearId is a required foreign key — see
/// database/tables/core_tables.dart). Both are created together in one
/// transaction so we never end up with a Student pointing at a year that
/// doesn't exist.
///
/// This repository intentionally only supports ONE student. If a
/// Student row already exists, createInitialStudent throws rather than
/// silently creating a second one — matching the "single student per
/// local database" rule documented on the Students table.
class StudentRepository {
  StudentRepository(this._db) : _curriculum = CurriculumRepository(_db);
  final AppDatabase _db;
  final CurriculumRepository _curriculum;

  Future<Student?> readExisting() {
    return _db.select(_db.students).getSingleOrNull();
  }

  /// Edits the basic profile entered at onboarding.
  Future<void> updateProfile({
    required String studentId,
    required String fullNameOrNickname,
    required int sleepFloorMinMinutes,
  }) async {
    await (_db.update(_db.students)..where((t) => t.id.equals(studentId)))
        .write(StudentsCompanion(
      fullNameOrNickname: Value(fullNameOrNickname),
      sleepFloorMinMinutes: Value(sleepFloorMinMinutes),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  Future<Student> createInitialStudent({
    required String fullNameOrNickname,
    required int sleepFloorMinMinutes,
  }) async {
    return _db.transaction(() async {
      final existing = await _db.select(_db.students).getSingleOrNull();
      if (existing != null) {
        throw StateError(
          'A Student already exists locally — this app supports one '
          'student per install. Refusing to create a second one.',
        );
      }

      final now = DateTime.now();
      // Algerian academic year convention: runs September → June/July.
      // If we're before September, we're still in the year that started
      // last September.
      final startYear = now.month >= 9 ? now.year : now.year - 1;
      final label = '$startYear-${startYear + 1}';

      final existingYear = await (_db.select(_db.academicYears)
            ..where((t) => t.label.equals(label)))
          .getSingleOrNull();

      final year = existingYear ??
          await _db.into(_db.academicYears).insertReturning(
                AcademicYearsCompanion.insert(
                  label: label,
                  startDate: DateTime(startYear, 9, 1),
                  endDate: DateTime(startYear + 1, 6, 30),
                ),
              );

      return _db.into(_db.students).insertReturning(
            StudentsCompanion.insert(
              fullNameOrNickname: fullNameOrNickname,
              currentAcademicYearId: year.id,
              sleepFloorMinMinutes: Value(sleepFloorMinMinutes),
            ),
          );
    });
  }

  // ---------------------------------------------------------------------
  // Student Integration (schema v6, DEVIATION-19)
  // ---------------------------------------------------------------------

  /// The student with their academic year, level and stream. Null when no
  /// student exists yet.
  Future<StudentProfile?> readProfile() async {
    final student = await readExisting();
    if (student == null) return null;
    final year = await (_db.select(_db.academicYears)
          ..where((t) => t.id.equals(student.currentAcademicYearId)))
        .getSingle();
    EducationLevel? level;
    final levelId = student.educationLevelId;
    if (levelId != null) {
      level = await (_db.select(_db.educationLevels)
            ..where((t) => t.id.equals(levelId)))
          .getSingleOrNull();
    }
    StudyStream? stream;
    final streamId = student.streamId;
    if (streamId != null) {
      stream = await (_db.select(_db.streams)
            ..where((t) => t.id.equals(streamId)))
          .getSingleOrNull();
    }
    return StudentProfile(
      student: student,
      academicYear: year,
      educationLevel: level,
      stream: stream,
    );
  }

  Future<Student> _requireStudent(String studentId) async {
    final student = await (_db.select(_db.students)
          ..where((t) => t.id.equals(studentId)))
        .getSingleOrNull();
    if (student == null) {
      throw ArgumentError.value(studentId, 'studentId', 'does not exist.');
    }
    return student;
  }

  /// Records the level and (optionally) the stream the student follows. The
  /// stream, when given, must belong to that level. Omitting [streamId]
  /// clears it (NULL = unknown / no stream), it is never guessed.
  Future<Student> setAcademicTrack({
    required String studentId,
    required String educationLevelId,
    String? streamId,
  }) {
    return _db.transaction(() async {
      await _requireStudent(studentId);
      final level = await (_db.select(_db.educationLevels)
            ..where((t) => t.id.equals(educationLevelId)))
          .getSingleOrNull();
      if (level == null) {
        throw ArgumentError.value(
            educationLevelId, 'educationLevelId', 'does not exist.');
      }
      if (streamId != null) {
        final stream = await (_db.select(_db.streams)
              ..where((t) => t.id.equals(streamId)))
            .getSingleOrNull();
        if (stream == null) {
          throw ArgumentError.value(streamId, 'streamId', 'does not exist.');
        }
        if (stream.educationLevelId != educationLevelId) {
          throw ArgumentError.value(streamId, 'streamId',
              'does not belong to education level $educationLevelId.');
        }
      }
      await (_db.update(_db.students)..where((t) => t.id.equals(studentId)))
          .write(StudentsCompanion(
        educationLevelId: Value(educationLevelId),
        streamId: Value(streamId),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
      return _requireStudent(studentId);
    });
  }

  /// Moves the student to another academic year. A curriculum version belongs
  /// to one academic year, so a linked version that belongs to a different
  /// year is unlinked in the same transaction (a stale link is never kept).
  Future<Student> setCurrentAcademicYear({
    required String studentId,
    required String academicYearId,
  }) {
    return _db.transaction(() async {
      final student = await _requireStudent(studentId);
      final year = await (_db.select(_db.academicYears)
            ..where((t) => t.id.equals(academicYearId)))
          .getSingleOrNull();
      if (year == null) {
        throw ArgumentError.value(
            academicYearId, 'academicYearId', 'does not exist.');
      }
      var unlinkVersion = false;
      final versionId = student.curriculumVersionId;
      if (versionId != null) {
        final version = await _curriculum.readCurriculumVersion(versionId);
        unlinkVersion = version == null || version.academicYearId != academicYearId;
      }
      await (_db.update(_db.students)..where((t) => t.id.equals(studentId)))
          .write(StudentsCompanion(
        currentAcademicYearId: Value(academicYearId),
        curriculumVersionId: unlinkVersion
            ? const Value<String?>(null)
            : const Value<String?>.absent(),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
      return _requireStudent(studentId);
    });
  }

  /// Links the student to a curriculum version. Only a version that is KNOWN
  /// AND VERIFIED (status ACTIVE) and that belongs to the student's current
  /// academic year can be linked; UNKNOWN / CONFLICT / FROZEN / REPEALED are
  /// refused. The link is not a licence to consume the curriculum: whether it
  /// may be consumed is decided again at read time (see
  /// domain/student_context_domain.dart), so a version that later becomes
  /// FROZEN or REPEALED stops being usable without touching the student row.
  Future<Student> setCurriculumVersion({
    required String studentId,
    required String curriculumVersionId,
  }) {
    return _db.transaction(() async {
      final student = await _requireStudent(studentId);
      final version = await _curriculum.readCurriculumVersion(curriculumVersionId);
      if (version == null) {
        throw PolicyDataGuardViolation(
            'CurriculumVersion $curriculumVersionId does not exist.');
      }
      if (version.academicYearId != student.currentAcademicYearId) {
        throw PolicyDataGuardViolation(
            'CurriculumVersion $curriculumVersionId belongs to a different '
            'academic year than the student\'s current one.');
      }
      final status = PolicyStatus.fromDb(version.status);
      if (!status.usableForCalculation) {
        throw PolicyDataGuardViolation(
            'CurriculumVersion $curriculumVersionId has status '
            '${status.name}; a student can only be linked to an ACTIVE '
            '(known and verified) curriculum version.');
      }
      await (_db.update(_db.students)..where((t) => t.id.equals(studentId)))
          .write(StudentsCompanion(
        curriculumVersionId: Value(curriculumVersionId),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
      return _requireStudent(studentId);
    });
  }

  /// Removes the curriculum-version link (back to "not linked" = unknown).
  Future<Student> clearCurriculumVersion(String studentId) async {
    await _requireStudent(studentId);
    await (_db.update(_db.students)..where((t) => t.id.equals(studentId)))
        .write(StudentsCompanion(
      curriculumVersionId: const Value<String?>(null),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
    return _requireStudent(studentId);
  }
}
