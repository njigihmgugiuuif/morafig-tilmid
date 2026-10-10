import 'package:drift/drift.dart';

import '../database/app_database.dart';

class InvalidEnergyFocusEntry implements Exception {
  InvalidEnergyFocusEntry(this.message);
  final String message;
  @override
  String toString() => 'InvalidEnergyFocusEntry: $message';
}

/// Thin read/write layer over EnergyFocusLogs (D-2 A04). The student records
/// how energetic and focused they felt, on a 1..5 scale, at a moment they
/// choose. Nothing here computes anything, and no engine reads these rows
/// yet: it is a log, shown back to the student as entered.
class EnergyFocusRepository {
  EnergyFocusRepository(this._db);
  final AppDatabase _db;

  static const int minLevel = 1;
  static const int maxLevel = 5;

  Future<EnergyFocusLog> insertFromUser({
    required String studentId,
    required DateTime loggedAt,
    required int energyLevel,
    required int focusLevel,
  }) {
    for (final v in [energyLevel, focusLevel]) {
      if (v < minLevel || v > maxLevel) {
        throw InvalidEnergyFocusEntry(
            'القيمة يجب أن تكون بين $minLevel و$maxLevel.');
      }
    }
    return _db.into(_db.energyFocusLogs).insertReturning(
          EnergyFocusLogsCompanion.insert(
            studentId: studentId,
            loggedAt: loggedAt,
            energyLevel: energyLevel,
            focusLevel: focusLevel,
          ),
        );
  }

  /// Newest first.
  Future<List<EnergyFocusLog>> readForStudent(String studentId,
          {int limit = 60}) =>
      (_db.select(_db.energyFocusLogs)
            ..where((t) => t.studentId.equals(studentId))
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.loggedAt, mode: OrderingMode.desc)
            ])
            ..limit(limit))
          .get();
}
