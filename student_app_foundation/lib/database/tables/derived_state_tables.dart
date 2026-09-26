import 'package:drift/drift.dart';
import 'core_tables.dart';
import 'curriculum_tables.dart';
import 'planning_tables.dart';
import 'audit_tables.dart';

/// Every table in this file is DERIVED STATE: its source of truth is other
/// raw tables, not this table itself. The Repository layer for each of
/// these (repositories/*_repository.dart) exposes ONLY a
/// `recomputeFrom(...)` write path — there is no generic `update()` method
/// on these repositories, so no code path in the app can hand-edit a
/// derived value without going through its owning engine's recomputation
/// logic. See SOURCE_OF_TRUTH.md.

class MasteryStates extends Table with AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get knowledgeNodeId => text().references(KnowledgeNodes, #id)();
  RealColumn get probability => real()();
  TextColumn get lastUpdatedFromEventId => text().references(Events, #id)();

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {studentId, knowledgeNodeId}, // DB-INV-5: one row per pair
      ];
}

class MemoryStates extends Table with AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get knowledgeNodeId => text().references(KnowledgeNodes, #id)();
  RealColumn get stability => real()();
  RealColumn get retrievability => real()();
  DateTimeColumn get nextReviewDate => dateTime()();
  // Added in schema v2 (see migrations/migration_strategy.dart): FSRS's
  // DSR model needs Difficulty (D ∈ [1,10]) to persist across reviews —
  // it's not derivable from stability/retrievability alone. Nullable
  // because rows written before v2 (none exist yet — schema is
  // pre-release) have no value. See DEVIATIONS.md for how this gap was
  // found (during Memory Engine implementation, not before).
  RealColumn get difficulty => real().nullable()();
  // Added in schema v2, same migration: mirrors
  // MasteryStates.lastUpdatedFromEventId — the Memory Engine recomputation
  // pattern should be traceable to the triggering Event exactly like the
  // Mastery Engine's is, for the same audit/reconstruction reason.
  TextColumn get lastUpdatedFromEventId =>
      text().nullable().references(Events, #id)();

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {studentId, knowledgeNodeId},
      ];
}

class ErrorRecords extends Table with AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get knowledgeNodeId => text().references(KnowledgeNodes, #id)();
  TextColumn get taskSegmentId =>
      text().nullable().references(TaskSegments, #id)();
  // ErrorType: careless|conceptual|missingPrerequisite
  TextColumn get errorType => text()();
  DateTimeColumn get timestamp => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class TimeEstimates extends Table with AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get subjectId => text().references(Subjects, #id)();
  TextColumn get sessionType => text()();
  IntColumn get estimatedDurationMinutes => integer()();
  TextColumn get confidenceLevel => text()(); // low|medium|high
  RealColumn get confidenceValue => real()();
  TextColumn get basis => text()(); // curriculum_default|observed_history|hybrid
  TextColumn get observedSamplesJson =>
      text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {studentId, subjectId, sessionType},
      ];
}

/// DB-INV-6: one active snapshot per student — enforced by uniqueKeys on
/// studentId AND by the repository always UPDATEing the single row rather
/// than INSERTing a new one.
class WorkloadStates extends Table with AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  IntColumn get totalEstimatedTimeNeededMinutes => integer()();
  IntColumn get totalAvailableTimeMinutes => integer()();
  TextColumn get status => text()(); // underload|balanced|overload|impossible

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {studentId},
      ];
}

class PriorityStates extends Table with AuditColumns {
  TextColumn get taskId => text().references(Tasks, #id)();
  RealColumn get score => real()();
  TextColumn get confidenceLevel => text()();
  RealColumn get confidenceValue => real()();
  TextColumn get weightsUsedJson => text()(); // must sum to 1.0 — enforced
  // in PriorityRepository.write(), not at the DB layer (SQLite can't sum a
  // JSON blob in a CHECK constraint portably).
  TextColumn get explanationId => text().references(Explanations, #id)();

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {taskId},
      ];
}

class RecoveryRecords extends Table with AuditColumns {
  TextColumn get triggerEventId => text().references(Events, #id)();
  TextColumn get affectedTaskId => text().references(Tasks, #id)();
  // RecoveryDecision: keep|move|merge|defer|dropTemporarily|replan
  TextColumn get decision => text()();
  TextColumn get reasoning => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class EmergencyStates extends Table with AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get triggerReason => text()(); // examProximity|workloadImpossible
  DateTimeColumn get enteredAt => dateTime()();
  DateTimeColumn get exitedAt => dateTime().nullable()();
  TextColumn get originalWeightsSnapshotJson => text()();

  @override
  Set<Column> get primaryKey => {id};
  // "at most one ACTIVE (exitedAt IS NULL) row per student" is enforced in
  // EmergencyRepository.enter(), not as a SQL constraint (SQLite has no
  // native partial-unique-index across all drift-supported targets used
  // here without raw SQL — flagged as acceptable for v1, see DEVIATIONS.md).
}
