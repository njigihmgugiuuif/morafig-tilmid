import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// MasteryState is DERIVED — its source of truth is the sequence of
/// ErrorRecords/answer history for a (student, knowledgeNode) pair, not
/// this table. This repository has no `writeProbability(double value)`
/// method on purpose: the ONLY way to change a MasteryState row is
/// `recomputeFrom`, which takes the BKT computation's own output together
/// with the Event that triggered it — there is no path for UI code, import
/// code, or a future sync engine to poke an arbitrary probability into
/// this table directly.
class MasteryRepository {
  MasteryRepository(this._db);
  final AppDatabase _db;

  Future<MasteryState?> read(String studentId, String knowledgeNodeId) =>
      (_db.select(_db.masteryStates)
            ..where((t) =>
                t.studentId.equals(studentId) &
                t.knowledgeNodeId.equals(knowledgeNodeId)))
          .getSingleOrNull();

  /// Called ONLY by the (future) MasteryEngine, immediately after it
  /// computes a new BKT probability from ErrorRecords. `sourceEventId`
  /// must point at the Event (e.g. TaskCompleted) that caused the
  /// recomputation — this is what lets MasteryState.lastUpdatedFromEventId
  /// support the audit/reconstruction requirement from the schema.
  Future<void> recomputeFrom({
    required String studentId,
    required String knowledgeNodeId,
    required double newProbability,
    required String sourceEventId,
  }) async {
    if (newProbability < 0 || newProbability > 1) {
      throw ArgumentError.value(newProbability, 'newProbability',
          'BKT probability must be in [0,1] — this indicates a bug in the '
          'caller, not a valid edge case to silently clamp.');
    }

    final existing = await read(studentId, knowledgeNodeId);
    if (existing == null) {
      await _db.into(_db.masteryStates).insert(
            MasteryStatesCompanion.insert(
              studentId: studentId,
              knowledgeNodeId: knowledgeNodeId,
              probability: newProbability,
              lastUpdatedFromEventId: sourceEventId,
            ),
          );
    } else {
      await (_db.update(_db.masteryStates)
            ..where((t) => t.id.equals(existing.id)))
          .write(MasteryStatesCompanion(
        probability: Value(newProbability),
        lastUpdatedFromEventId: Value(sourceEventId),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
    }
  }
}
