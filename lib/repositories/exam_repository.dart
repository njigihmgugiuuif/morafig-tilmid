import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../domain/enums.dart';

/// Thin repository over Exams — no per-student scoping (Students is a
/// single-row table in this offline-first design; see core_tables.dart's
/// doc comment on Students), so every Exam row belongs to "the" student.
class ExamRepository {
  ExamRepository(this._db);
  final AppDatabase _db;

  Future<Exam> insert({
    required String subjectId,
    required DateTime examDate,
    required ExamType examType,
    double? officialWeight,
  }) {
    return _db.into(_db.exams).insertReturning(
          ExamsCompanion.insert(
            subjectId: subjectId,
            examDate: examDate,
            examType: examType.name,
            officialWeight: Value(officialWeight),
          ),
        );
  }

  /// All exams with examDate >= `now`, soonest first — the direct input
  /// examination_domain.dart needs for "days until nearest exam".
  Future<List<Exam>> readUpcoming({required DateTime now, String? subjectId}) {
    final query = _db.select(_db.exams)
      ..where((t) => t.examDate.isBiggerOrEqualValue(now));
    if (subjectId != null) {
      query.where((t) => t.subjectId.equals(subjectId));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.examDate)]);
    return query.get();
  }

  Future<Exam?> readById(String id) =>
      (_db.select(_db.exams)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// Exams with `from <= examDate < to`, soonest first (B: the plan's week).
  Future<List<Exam>> readInRange({
    required DateTime from,
    required DateTime to,
  }) {
    final query = _db.select(_db.exams)
      ..where((t) =>
          t.examDate.isBiggerOrEqualValue(from) &
          t.examDate.isSmallerThanValue(to))
      ..orderBy([(t) => OrderingTerm.asc(t.examDate)]);
    return query.get();
  }

  /// The education level a subject belongs to (Subjects.educationLevelId),
  /// or null when the subject does not exist. Read-only (B: exam linking).
  Future<String?> levelIdForSubject(String subjectId) async {
    final row = await (_db.select(_db.subjects)
          ..where((t) => t.id.equals(subjectId)))
        .getSingleOrNull();
    return row?.educationLevelId;
  }
}
