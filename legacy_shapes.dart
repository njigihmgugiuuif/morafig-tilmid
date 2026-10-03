import 'package:student_app/database/app_database.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Test helpers that make a FRESH (current-schema) database look like an
/// older shipped one, so the real `onUpgrade` branches can be exercised on a
/// real SQLite file. This is an EMULATION of an old file, not a file that was
/// ever shipped: it removes what the later versions added (tables dropped,
/// added columns removed by rebuilding the table with only its old columns)
/// and sets `user_version`. Rows already in the kept columns are preserved.
///
/// The rebuilt tables lose their constraints (CREATE TABLE ... AS SELECT),
/// which is irrelevant to what the upgrade branches do (they add tables and
/// nullable columns) but means this is NOT a byte-exact old schema.

Future<void> _rebuildWithColumns(
    AppDatabase db, String table, List<String> keepColumns) async {
  final cols = keepColumns.join(', ');
  await db.customStatement('CREATE TABLE ${table}_legacy AS '
      'SELECT $cols FROM $table');
  await db.customStatement('DROP TABLE $table');
  await db.customStatement('ALTER TABLE ${table}_legacy RENAME TO $table');
}

/// Makes [db] look like a schema-v3 file (before Phase 1 v4).
Future<void> makeLookLikeV3(AppDatabase db) async {
  await db.customStatement('PRAGMA foreign_keys = OFF');
  for (final t in const [
    'energy_focus_logs',
    'academic_terms',
    'holidays',
    'goals',
  ]) {
    await db.customStatement('DROP TABLE $t');
  }
  await _rebuildWithColumns(db, 'mastery_states', const [
    'id',
    'created_at',
    'updated_at',
    'sync_version',
    'student_id',
    'knowledge_node_id',
    'probability',
    'last_updated_from_event_id',
  ]);
  await _rebuildWithColumns(db, 'subjects', const [
    'id',
    'created_at',
    'updated_at',
    'sync_version',
    'name',
    'education_level_id',
  ]);
  await db.customStatement('PRAGMA user_version = 3');
}

/// Makes [db] look like a schema-v2 file (before the weekly template table
/// and before v4).
Future<void> makeLookLikeV2(AppDatabase db) async {
  await makeLookLikeV3(db);
  await db.customStatement('DROP TABLE weekly_template_entries');
  await db.customStatement('PRAGMA user_version = 2');
}
