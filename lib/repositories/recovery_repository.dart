import '../database/app_database.dart';
import '../engines/recovery_engine.dart';
import 'append_only_repository.dart';

/// RecoveryRecords is a raw historical log (one row per decision, never
/// updated) — same append-only contract as ErrorRecords/Events. The only
/// write path is `record`, which takes recovery_engine.dart's own output
/// directly, so a RecoveryRecords row can never disagree with the
/// RecoveryEngine decision that produced it.
class RecoveryRepository extends AppendOnlyRepository<RecoveryRecords, RecoveryRecord> {
  RecoveryRepository(AppDatabase db) : super(db, db.recoveryRecords);

  AppDatabase get _db => db as AppDatabase;

  Future<List<RecoveryRecord>> readForTask(String taskId) =>
      (_db.select(_db.recoveryRecords)
            ..where((t) => t.affectedTaskId.equals(taskId)))
          .get();

  Future<RecoveryRecord> record({
    required String triggerEventId,
    required String affectedTaskId,
    required RecoveryDecisionResult result,
  }) {
    return insertRow(RecoveryRecordsCompanion.insert(
      triggerEventId: triggerEventId,
      affectedTaskId: affectedTaskId,
      decision: result.decision.name,
      reasoning: result.reasoning,
    ));
  }
}
