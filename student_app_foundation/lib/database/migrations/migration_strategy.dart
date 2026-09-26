import 'package:drift/drift.dart';
import '../app_database.dart';

/// Migration Strategy for the Data Foundation.
///
/// v1 = initial schema (this file). There is no migration FROM anything
/// yet, because there is no released version before this one — this is a
/// new project, not a legacy one being reshaped.
///
/// Forward policy for all FUTURE versions (documented now so it is not
/// improvised later under time pressure):
///   1. Every schema change gets its own `schemaVersion` bump and its own
///      `onUpgrade` branch below (`if (from < N) { ... }`), never a single
///      "upgrade to latest" branch that skips intermediate steps.
///   2. A migration that only ADDS a nullable column or a new table is
///      "safe": `m.addColumn(...)` / `m.createTable(...)`, no data
///      transform needed.
///   3. A migration that changes the MEANING of existing data (renames a
///      status value, splits a column, changes a unit) MUST ship with an
///      explicit data-transform step in the same `onUpgrade` branch, and
///      MUST be covered by a migration test that seeds v(N-1)-shaped data
///      and asserts the v(N) result (see test/migration_test.dart).
///   4. No migration may silently drop a user's data. If a column is
///      genuinely being removed, its data is archived into a
///      `_deprecated_<table>_<version>` table first, not deleted outright,
///      for at least one migration cycle.
MigrationStrategy buildMigrationStrategy(AppDatabase db) {
  return MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // v2: Memory Engine implementation found that FSRS needs
        // Difficulty to persist across reviews, and that MemoryStates
        // should track lastUpdatedFromEventId like MasteryStates already
        // does. Both are additive/nullable — no data transform needed,
        // no existing rows to touch (schema is pre-release, v1 was never
        // shipped). See DEVIATIONS.md.
        await m.addColumn(db.memoryStates, db.memoryStates.difficulty);
        await m.addColumn(
            db.memoryStates, db.memoryStates.lastUpdatedFromEventId);
      }
    },
    beforeOpen: (details) async {
      await db.customStatement('PRAGMA foreign_keys = ON;');
      if (details.wasCreated) {
        // Hook point for seeding ThresholdRegistryEntries with v1 defaults
        // at first-ever launch. Left to the app wiring layer (not the
        // database itself) so that test databases can opt out and supply
        // their own fixtures instead — see test/fixtures/seed_data.dart.
      }
    },
  );
}
