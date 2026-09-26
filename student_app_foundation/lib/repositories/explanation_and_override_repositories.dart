import '../database/app_database.dart';
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
