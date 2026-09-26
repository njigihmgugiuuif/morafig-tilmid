import 'package:drift/drift.dart';

import '../database/app_database.dart';

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
  StudentRepository(this._db);
  final AppDatabase _db;

  Future<Student?> readExisting() {
    return _db.select(_db.students).getSingleOrNull();
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
}
