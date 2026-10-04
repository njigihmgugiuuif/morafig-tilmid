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
/// The rebuilt tables are re-created from an EXPLICIT old-shape DDL that keeps
/// PRIMARY KEY, UNIQUE and FOREIGN KEY constraints. This matters: a rebuild
/// with `CREATE TABLE ... AS SELECT` drops the primary key, and once
/// `PRAGMA foreign_keys = ON` (set by the app's `beforeOpen`) any statement
/// touching a table that references the rebuilt one fails with
/// "foreign key mismatch" (SQLite requires the parent key to be a PK/UNIQUE).
/// Types/defaults follow what Drift generates; it is still an emulation, not a
/// byte-exact copy of a file that was ever shipped.

Future<void> _rebuildWithDdl(AppDatabase db, String table, String createSql,
    List<String> keepColumns) async {
  final cols = keepColumns.join(', ');
  await db.customStatement(createSql.replaceFirst(
      'CREATE TABLE $table ', 'CREATE TABLE ${table}_legacy '));
  await db.customStatement('INSERT INTO ${table}_legacy ($cols) '
      'SELECT $cols FROM $table');
  await db.customStatement('DROP TABLE $table');
  await db.customStatement('ALTER TABLE ${table}_legacy RENAME TO $table');
}

/// Makes [db] look like a schema-v4 file (before the Curriculum phase, v5):
/// curriculum_versions without country_code / version_label.
Future<void> makeLookLikeV4(AppDatabase db) async {
  await db.customStatement('PRAGMA foreign_keys = OFF');
  await _rebuildWithDdl(
      db,
      'curriculum_versions',
      'CREATE TABLE curriculum_versions ('
      'id TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, '
      'updated_at INTEGER NOT NULL, '
      'sync_version INTEGER NOT NULL DEFAULT 0, '
      'academic_year_id TEXT NOT NULL REFERENCES academic_years (id), '
      'status TEXT NOT NULL, '
      'source_policy_document_id TEXT NOT NULL REFERENCES policy_documents (id), '
      'effective_from INTEGER NULL, '
      'effective_to INTEGER NULL, '
      'PRIMARY KEY (id))',
      const [
        'id',
        'created_at',
        'updated_at',
        'sync_version',
        'academic_year_id',
        'status',
        'source_policy_document_id',
        'effective_from',
        'effective_to',
      ]);
  await db.customStatement('PRAGMA user_version = 4');
}

/// Makes [db] look like a schema-v3 file (before Phase 1 v4).
Future<void> makeLookLikeV3(AppDatabase db) async {
  await makeLookLikeV4(db);
  await db.customStatement('PRAGMA foreign_keys = OFF');
  for (final t in const [
    'energy_focus_logs',
    'academic_terms',
    'holidays',
    'goals',
  ]) {
    await db.customStatement('DROP TABLE $t');
  }
  await _rebuildWithDdl(
      db,
      'mastery_states',
      'CREATE TABLE mastery_states ('
      'id TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, '
      'updated_at INTEGER NOT NULL, '
      'sync_version INTEGER NOT NULL DEFAULT 0, '
      'student_id TEXT NOT NULL REFERENCES students (id), '
      'knowledge_node_id TEXT NOT NULL REFERENCES knowledge_nodes (id), '
      'probability REAL NOT NULL, '
      'last_updated_from_event_id TEXT NOT NULL REFERENCES events (id), '
      'PRIMARY KEY (id), '
      'UNIQUE (student_id, knowledge_node_id))',
      const [
        'id',
        'created_at',
        'updated_at',
        'sync_version',
        'student_id',
        'knowledge_node_id',
        'probability',
        'last_updated_from_event_id',
      ]);
  await _rebuildWithDdl(
      db,
      'subjects',
      'CREATE TABLE subjects ('
      'id TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, '
      'updated_at INTEGER NOT NULL, '
      'sync_version INTEGER NOT NULL DEFAULT 0, '
      'name TEXT NOT NULL, '
      'education_level_id TEXT NOT NULL REFERENCES education_levels (id), '
      'PRIMARY KEY (id))',
      const [
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
