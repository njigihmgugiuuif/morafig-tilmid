import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Tables considered "append-only" for import-merge purposes: on conflict
/// (same id already present), the existing row wins unconditionally — an
/// append-only row is never overwritten by an import, only added if new.
/// This is intentionally a different policy from mutable-state tables
/// (see kMutableStateTables below) and the split is enforced by which
/// branch of `_mergeRow` a table's name routes through, not left as an
/// unwritten convention.
const Set<String> kAppendOnlyTables = {'events', 'explanations', 'human_overrides'};

/// Everything else with an `updated_at` column is "mutable state": import
/// uses Last-Write-Wins on `updatedAt` — a row in the import file only
/// overwrites the local row if its `updatedAt` is strictly newer.
const Set<String> kMutableStateTables = {
  'students', 'academic_years', 'education_levels', 'streams',
  'policy_documents', 'curriculum_versions', 'subject_loads',
  'subjects', 'units', 'lessons', 'knowledge_nodes', 'prerequisites',
  'tasks', 'task_segments', 'assignments', 'exams', 'deadlines',
  'study_sessions', 'availabilities', 'reality_constraints',
  'mastery_states', 'memory_states', 'error_records', 'time_estimates',
  'workload_states', 'priority_states', 'recovery_records', 'emergency_states',
  'algorithm_versions', 'configuration_versions', 'threshold_registry_entries',
  'data_state_versions', 'sync_metadata_entries',
};

class ImportValidationException implements Exception {
  ImportValidationException(this.reason);
  final String reason;
  @override
  String toString() => 'ImportValidationException: $reason';
}

class ExportImportService {
  ExportImportService(this._db);
  final AppDatabase _db;

  static const int schemaVersion = 1;

  /// Full local export. No network access anywhere in this method — it
  /// reads exclusively from the local SQLite connection already open on
  /// `_db`.
  Future<String> exportAll() async {
    final bundle = <String, dynamic>{
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'schemaVersion': schemaVersion,
      'tables': <String, List<Map<String, dynamic>>>{},
    };

    final tables = bundle['tables'] as Map<String, List<Map<String, dynamic>>>;

    for (final table in _db.allTables) {
      final rows = await _db.select(table).get();
      tables[table.actualTableName] =
          rows.map((r) => (r as dynamic).toJson()).toList().cast<Map<String, dynamic>>();
    }

    return jsonEncode(bundle);
  }

  /// Import with:
  ///   - pre-import structural validation (schemaVersion check, shape check)
  ///   - a single transaction wrapping the whole import
  ///   - automatic rollback if ANY row fails (no half-imported database)
  ///   - append-only tables merged by union-on-id (never overwritten)
  ///   - mutable-state tables merged by Last-Write-Wins on updatedAt
  Future<void> importAll(String jsonString) async {
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(jsonString) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw ImportValidationException('Not valid JSON: $e');
    }

    _validateShape(parsed);

    final tables = (parsed['tables'] as Map).cast<String, dynamic>();

    await _db.transaction(() async {
      for (final table in _db.allTables) {
        final name = table.actualTableName;
        final incomingRows = (tables[name] as List?)?.cast<Map<String, dynamic>>();
        if (incomingRows == null) continue;

        for (final row in incomingRows) {
          if (kAppendOnlyTables.contains(name)) {
            await _mergeAppendOnlyRow(table, row);
          } else {
            await _mergeMutableRow(table, row);
          }
        }
      }
      // If anything above throws, Drift's transaction() rolls back
      // everything executed so far in this block — there is no explicit
      // rollback call needed, and no code path that commits partially.
    });
  }

  void _validateShape(Map<String, dynamic> parsed) {
    if (parsed['schemaVersion'] == null) {
      throw ImportValidationException('Missing schemaVersion.');
    }
    if (parsed['schemaVersion'] != schemaVersion) {
      throw ImportValidationException(
          'schemaVersion mismatch: file has ${parsed['schemaVersion']}, '
          'this database is $schemaVersion. Cross-version import is not '
          'supported yet — migrate the file first (see Migration Strategy).');
    }
    if (parsed['tables'] is! Map) {
      throw ImportValidationException('Missing or malformed "tables" object.');
    }
  }

  Future<void> _mergeAppendOnlyRow(TableInfo table, Map<String, dynamic> row) async {
    final id = row['id'] as String?;
    if (id == null) {
      throw ImportValidationException(
          'Row in append-only table ${table.actualTableName} has no id.');
    }
    final existing = await _db
        .customSelect('SELECT id FROM ${table.actualTableName} WHERE id = ?',
            variables: [Variable.withString(id)])
        .getSingleOrNull();
    if (existing != null) {
      // Union semantics: existing append-only row always wins, never
      // overwritten by an import — this is the policy documented in
      // SOURCE_OF_TRUTH.md for Event/Explanation/HumanOverride.
      return;
    }
    await _db.into(table).insert(
          table.map(row) as Insertable,
          mode: InsertMode.insertOrFail,
        );
  }

  Future<void> _mergeMutableRow(TableInfo table, Map<String, dynamic> row) async {
    final id = row['id'] as String?;
    final incomingUpdatedAt = row['updated_at'] as String?;
    if (id == null || incomingUpdatedAt == null) {
      throw ImportValidationException(
          'Row in ${table.actualTableName} is missing id or updated_at.');
    }

    final existing = await _db
        .customSelect(
            'SELECT updated_at FROM ${table.actualTableName} WHERE id = ?',
            variables: [Variable.withString(id)])
        .getSingleOrNull();

    if (existing == null) {
      await _db
          .into(table)
          .insert(table.map(row) as Insertable, mode: InsertMode.insertOrFail);
      return;
    }

    final existingUpdatedAt =
        DateTime.parse(existing.data['updated_at'] as String);
    final incoming = DateTime.parse(incomingUpdatedAt);

    if (incoming.isAfter(existingUpdatedAt)) {
      await _db.into(table).insertOnConflictUpdate(table.map(row) as Insertable);
    }
    // else: local row is newer or equal — Last-Write-Wins keeps it, import
    // row is discarded for this entity.
  }
}
