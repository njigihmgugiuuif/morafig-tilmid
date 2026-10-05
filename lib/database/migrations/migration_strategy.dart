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
      if (from < 3) {
        // v3: Weekly Timeline needs the student's recurring weekly template
        // (school timetable, sleep window...). Purely additive: a new table,
        // no existing row is touched. See DEVIATIONS.md, DEVIATION-16.
        await m.createTable(db.weeklyTemplateEntries);
      }
      if (from < 4) {
        // v4: Phase 1 data model. Phase 1 was planned as "v3" but v3 was
        // already used by WeeklyTemplateEntries (Phase 2), so it is v4 —
        // the chain stays v1 -> v2 -> v3 -> v4 with one branch per step.
        // Purely additive: 4 new tables, 3 new NULLABLE columns. No existing
        // row is touched and no value is invented for old rows (NULL =
        // unknown). See DEVIATIONS.md, DEVIATION-17.
        await m.createTable(db.energyFocusLogs);
        await m.createTable(db.academicTerms);
        await m.createTable(db.holidays);
        await m.createTable(db.goals);
        await m.addColumn(db.masteryStates, db.masteryStates.confidence);
        await m.addColumn(db.masteryStates, db.masteryStates.observationCount);
        await m.addColumn(db.subjects, db.subjects.curriculumVersionId);
      }
      if (from < 5) {
        // v5: Curriculum phase. A curriculum edition gets the country it
        // describes and its source-given label. Purely additive: 2 NULLABLE
        // columns on curriculum_versions, no new table, no existing row is
        // touched and no value is invented for old rows (NULL = unknown).
        // See DEVIATIONS.md, DEVIATION-18.
        await m.addColumn(
            db.curriculumVersions, db.curriculumVersions.countryCode);
        await m.addColumn(
            db.curriculumVersions, db.curriculumVersions.versionLabel);
      }
      if (from < 6) {
        // v6: Student Integration. The student gets the level, stream and
        // curriculum version they follow. Purely additive: 3 NULLABLE
        // columns on students, no new table, no existing row is touched and
        // no value is invented for old rows (NULL = unknown). See
        // DEVIATIONS.md, DEVIATION-19.
        await m.addColumn(db.students, db.students.educationLevelId);
        await m.addColumn(db.students, db.students.streamId);
        await m.addColumn(db.students, db.students.curriculumVersionId);
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
