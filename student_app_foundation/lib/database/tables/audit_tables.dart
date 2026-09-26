import 'package:drift/drift.dart';
import 'core_tables.dart';
import 'planning_tables.dart';
import 'config_tables.dart';

/// APPEND-ONLY. See repositories/append_only_repository.dart — the base
/// class these three repositories extend physically has no update()/
/// delete() method, so it is impossible for any calling code (UI, import,
/// a future sync engine, or an engine) to mutate a row after insert without
/// bypassing the repository layer entirely (which is only possible by
/// importing drift's generated DAO directly, which the lint rule in
/// analysis_options.yaml forbids outside lib/repositories/).
class Events extends Table with AuditColumns {
  TextColumn get type => text()(); // see domain/event_types.dart for the 17 values
  TextColumn get payloadJson => text()();
  BoolColumn get triggersReplan => boolean()();
  DateTimeColumn get processedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Explanations extends Table with AuditColumns {
  TextColumn get factorsJson => text()();
  TextColumn get excludedFactorsJson => text()();
  TextColumn get dominantFactor => text()();
  TextColumn get hardConstraintsCheckedJson => text()();
  TextColumn get versionBundleId =>
      text().references(DataStateVersions, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

class HumanOverrides extends Table with AuditColumns {
  TextColumn get taskId => text().references(Tasks, #id)();
  // OverrideAction: accept|postpone|reject|reschedule|markEasier|markHarder|reportReason
  TextColumn get action => text()();
  TextColumn get systemStateSnapshotId =>
      text().references(Explanations, #id)();
  TextColumn get reportedReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
