import 'package:drift/drift.dart' show Value;

import '../database/app_database.dart';
import '../database/tables/audit_tables.dart';
import 'append_only_repository.dart';

class ExplanationRepository
    extends AppendOnlyRepository<Explanations, Explanation> {
  ExplanationRepository(AppDatabase db) : super(db, db.explanations);

  AppDatabase get _db => db as AppDatabase;

  Future<Explanation?> readById(String id) =>
      (_db.select(_db.explanations)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  // No mutation methods at all — an Explanation, once written, is a fixed
  // historical record of "what the system believed at decision time"
  // (Invariant #7 / INV-7 in the final intelligence spec). Not even a
  // processedAt-style field exists here.
}

class HumanOverrideRepository
    extends AppendOnlyRepository<HumanOverrides, HumanOverride> {
  HumanOverrideRepository(AppDatabase db) : super(db, db.humanOverrides);

  AppDatabase get _db => db as AppDatabase;

  /// Records what the student did with a suggestion (append-only). The
  /// snapshot is the Explanation the system showed at that moment, so the
  /// override always points at «what the system believed». Writing this row
  /// changes nothing else: no priority, no plan.
  Future<HumanOverride> record({
    required String taskId,
    required String action,
    required String explanationId,
    String? reportedReason,
  }) {
    return insertRow(HumanOverridesCompanion.insert(
      taskId: taskId,
      action: action,
      systemStateSnapshotId: explanationId,
      reportedReason: Value(reportedReason),
    ));
  }

  Future<List<HumanOverride>> readByTask(String taskId) =>
      (_db.select(_db.humanOverrides)..where((t) => t.taskId.equals(taskId)))
          .get();

  /// Used by the (future) calibration logic — counts consecutive rejections
  /// of the same dominant factor, read-only, never mutates history.
  Future<int> countRecentRejections(String taskId) async {
    final rows = await readByTask(taskId);
    return rows.where((r) => r.action == 'reject').length;
  }
}
