import '../database/app_database.dart';

/// "Reset all data": deletes every row of every table in ONE transaction
/// (all-or-nothing). Foreign keys are deferred to commit time so the order
/// of deletion does not matter. The schema is kept; the next launch shows
/// first-run onboarding again.
class ResetRepository {
  ResetRepository(this._db);
  final AppDatabase _db;

  Future<void> wipeAllData() async {
    await _db.transaction(() async {
      await _db.customStatement('PRAGMA defer_foreign_keys = ON;');
      for (final table in _db.allTables) {
        await _db.delete(table).go();
      }
    });
  }
}
