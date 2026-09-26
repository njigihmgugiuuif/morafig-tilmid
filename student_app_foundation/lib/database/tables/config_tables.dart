import 'package:drift/drift.dart';
import 'core_tables.dart';

class AlgorithmVersions extends Table with AuditColumns {
  TextColumn get versionLabel => text()();
  DateTimeColumn get releasedAt => dateTime()();
  TextColumn get changeDescription => text()();

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {versionLabel},
      ];
}

class ConfigurationVersions extends Table with AuditColumns {
  TextColumn get versionLabel => text()();
  DateTimeColumn get releasedAt => dateTime()();
  TextColumn get changeDescription => text()();

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {versionLabel},
      ];
}

/// The single source for every tunable number in the Intelligence Engine
/// (epsilon, deltaMin, weight bounds, backlog thresholds, sleep floor...).
/// No threshold may be a literal constant inside engine code — this table
/// is the only place they may be defined. See
/// algeria-intelligence-final-spec.md Section H for the full initial set.
class ThresholdRegistryEntries extends Table with AuditColumns {
  TextColumn get name => text()();
  RealColumn get value => real()();
  TextColumn get unit => text()();
  RealColumn get minBound => real().nullable()();
  RealColumn get maxBound => real().nullable()();
  TextColumn get configurationVersionId =>
      text().references(ConfigurationVersions, #id)();

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {name, configurationVersionId},
      ];
}

/// A reference point in time, tied to the Event that produced it, used to
/// reconstruct "what did the system believe at decision time" for audit and
/// for the Determinism invariant. This is a pointer/marker, not a full
/// serialized state copy (see SOURCE_OF_TRUTH.md — full-state copies would
/// duplicate the source of truth, which the Schema explicitly forbids).
class DataStateVersions extends Table with AuditColumns {
  DateTimeColumn get snapshotTimestamp => dateTime()();
  TextColumn get relatedEventId => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncMetadataEntries extends Table with AuditColumns {
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  IntColumn get entitySyncVersion => integer()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {entityType, entityId, deviceId},
      ];
}
