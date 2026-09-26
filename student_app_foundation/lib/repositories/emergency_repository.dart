import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../engines/emergency_engine.dart';

/// EmergencyStates' own table comment (derived_state_tables.dart) already
/// documents that "at most one ACTIVE (exitedAt IS NULL) row per student"
/// is enforced here, not at the SQL layer — this repository is that
/// enforcement, implemented for the first time this cycle.
class EmergencyRepository {
  EmergencyRepository(this._db);
  final AppDatabase _db;

  Future<EmergencyState?> readActive(String studentId) =>
      (_db.select(_db.emergencyStates)
            ..where((t) =>
                t.studentId.equals(studentId) & t.exitedAt.isNull()))
          .getSingleOrNull();

  /// Refuses to open a second active emergency window for the same
  /// student — callers must `exit()` the existing one first (or this
  /// throws), which is what keeps "at most one active" true without a DB
  /// constraint.
  Future<EmergencyState> enter({
    required String studentId,
    required EmergencyTriggerKind trigger,
    required DateTime enteredAt,
    required Map<String, double> originalWeightsSnapshot,
  }) async {
    final existing = await readActive(studentId);
    if (existing != null) {
      throw StateError(
          'Student $studentId already has an active EmergencyState '
          '(id: ${existing.id}) — exit() it before entering a new one. '
          'This is the "at most one active" invariant firing, not a bug.');
    }

    return _db.into(_db.emergencyStates).insertReturning(
          EmergencyStatesCompanion.insert(
            studentId: studentId,
            triggerReason: trigger.name,
            enteredAt: enteredAt,
            originalWeightsSnapshotJson: jsonEncode(originalWeightsSnapshot),
          ),
        );
  }

  Future<void> exit({required String id, required DateTime exitedAt}) async {
    await (_db.update(_db.emergencyStates)..where((t) => t.id.equals(id)))
        .write(EmergencyStatesCompanion(
      exitedAt: Value(exitedAt),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }
}
