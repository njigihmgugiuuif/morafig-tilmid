import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Thin repository over Availabilities. Like ExamRepository, no
/// per-student scoping is strictly required (single-student local DB),
/// but studentId is still accepted/stored since Availabilities.studentId
/// is a required column in the schema (Foundation phase decision, not
/// revisited here).
class AvailabilityRepository {
  AvailabilityRepository(this._db);
  final AppDatabase _db;

  Future<Availability> insert({
    required String studentId,
    int? dayOfWeek,
    DateTime? specificDate,
    required int windowStartMinutes,
    required int windowEndMinutes,
    required bool isRecurring,
  }) {
    return _db.into(_db.availabilities).insertReturning(
          AvailabilitiesCompanion.insert(
            studentId: studentId,
            dayOfWeek: Value(dayOfWeek),
            specificDate: Value(specificDate),
            windowStartMinutes: windowStartMinutes,
            windowEndMinutes: windowEndMinutes,
            isRecurring: isRecurring,
          ),
        );
  }

  Future<List<Availability>> readForStudent(String studentId) =>
      (_db.select(_db.availabilities)
            ..where((t) => t.studentId.equals(studentId)))
          .get();
}
