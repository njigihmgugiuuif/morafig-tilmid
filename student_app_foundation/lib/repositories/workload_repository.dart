import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../engines/workload_engine.dart';

/// WorkloadState is DERIVED, one active snapshot per student (DB-INV-6,
/// documented directly on the WorkloadStates table) — this repository
/// enforces that by always UPDATEing the single existing row rather than
/// INSERTing a new one, the same "recompute, never accumulate" contract
/// as Mastery/TimeEstimate.
class WorkloadRepository {
  WorkloadRepository(this._db);
  final AppDatabase _db;

  Future<WorkloadState?> read(String studentId) =>
      (_db.select(_db.workloadStates)
            ..where((t) => t.studentId.equals(studentId)))
          .getSingleOrNull();

  /// Called by the (future) integration layer after summing pending
  /// Tasks/TimeEstimates into `result.neededMinutes` and Availability/
  /// RealityConstraint rows into `result.availableMinutes`, then running
  /// WorkloadEngine.compute(). `impossible` maps 1:1 onto
  /// WorkloadClassification.impossible — the caller does not decide this,
  /// the engine does.
  Future<void> recomputeFrom({
    required String studentId,
    required WorkloadResult result,
  }) async {
    final existing = await read(studentId);
    final statusDb = _classificationToDb(result.classification);

    if (existing == null) {
      await _db.into(_db.workloadStates).insert(
            WorkloadStatesCompanion.insert(
              studentId: studentId,
              totalEstimatedTimeNeededMinutes: result.neededMinutes,
              totalAvailableTimeMinutes: result.availableMinutes,
              status: statusDb,
            ),
          );
    } else {
      await (_db.update(_db.workloadStates)
            ..where((t) => t.id.equals(existing.id)))
          .write(WorkloadStatesCompanion(
        totalEstimatedTimeNeededMinutes: Value(result.neededMinutes),
        totalAvailableTimeMinutes: Value(result.availableMinutes),
        status: Value(statusDb),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
    }
  }

  String _classificationToDb(WorkloadClassification c) {
    switch (c) {
      case WorkloadClassification.underload:
        return 'underload';
      case WorkloadClassification.balanced:
        return 'balanced';
      case WorkloadClassification.overload:
        return 'overload';
      case WorkloadClassification.impossible:
        return 'impossible';
    }
  }
}
