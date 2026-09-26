import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../engines/error_engine.dart';
import 'append_only_repository.dart';

/// ErrorRecords is a raw historical log (one row per occurrence, never
/// updated) — the same append-only contract as Events/Explanations/
/// HumanOverrides, so this repository extends the same base class and
/// exposes no update/delete path. ErrorEngine (engines/error_engine.dart)
/// is the ONLY consumer of readForNode's output; nothing here computes a
/// signal itself — that separation is what keeps the engine unit-testable
/// without a database.
class ErrorRepository extends AppendOnlyRepository<ErrorRecords, ErrorRecord> {
  ErrorRepository(AppDatabase db) : super(db, db.errorRecords);

  AppDatabase get _db => db as AppDatabase;

  Future<ErrorRecord?> readById(String id) =>
      (_db.select(_db.errorRecords)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// All ErrorRecords for a (student, knowledgeNode) pair within the
  /// caller-supplied window, converted to the daysAgo-relative form
  /// ErrorEngine consumes. `now` is a parameter (not DateTime.now()
  /// internally) so this stays deterministic and testable.
  Future<List<ErrorObservation>> readForNode({
    required String studentId,
    required String knowledgeNodeId,
    required DateTime now,
    Duration? window,
  }) async {
    final query = _db.select(_db.errorRecords)
      ..where((t) =>
          t.studentId.equals(studentId) &
          t.knowledgeNodeId.equals(knowledgeNodeId));
    if (window != null) {
      final cutoff = now.subtract(window);
      query.where((t) => t.timestamp.isBiggerOrEqualValue(cutoff));
    }
    final rows = await query.get();

    return rows.map((r) {
      final daysAgo = now.difference(r.timestamp).inMinutes / (60.0 * 24.0);
      return ErrorObservation(
        kind: _kindFromDb(r.errorType),
        daysAgo: daysAgo < 0 ? 0.0 : daysAgo,
      );
    }).toList();
  }

  ErrorKind _kindFromDb(String value) {
    switch (value) {
      case 'careless':
        return ErrorKind.careless;
      case 'conceptual':
        return ErrorKind.conceptual;
      case 'missingPrerequisite':
        return ErrorKind.missingPrerequisite;
      default:
        throw StateError('Unrecognized ErrorType "$value" in ErrorRecords — '
            'refusing to guess a default; fix the data at the source.');
    }
  }

  /// Records one new error occurrence. This is the ONLY write path onto
  /// ErrorRecords — there is deliberately no method that takes an
  /// existing id, matching the append-only contract.
  Future<ErrorRecord> record({
    required String studentId,
    required String knowledgeNodeId,
    String? taskSegmentId,
    required ErrorKind kind,
    required DateTime timestamp,
  }) {
    return insertRow(ErrorRecordsCompanion.insert(
      studentId: studentId,
      knowledgeNodeId: knowledgeNodeId,
      taskSegmentId: Value(taskSegmentId),
      errorType: _kindToDb(kind),
      timestamp: timestamp,
    ));
  }

  String _kindToDb(ErrorKind kind) => kind.name;
}
