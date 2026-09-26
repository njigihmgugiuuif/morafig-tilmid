import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'connection/connection_stub.dart';
import 'tables/core_tables.dart';
import 'tables/curriculum_tables.dart';
import 'tables/planning_tables.dart';
import 'tables/derived_state_tables.dart';
import 'tables/audit_tables.dart';
import 'tables/config_tables.dart';
import 'migrations/migration_strategy.dart';

part 'app_database.g.dart';

/// The Data Foundation database. 36 tables total (34 entities from the
/// approved schema + the deliberate StudySession/ScheduleEntry unification
/// already documented, counted as one — see DEVIATIONS.md for the exact
/// reconciliation of the count against the schema document).
@DriftDatabase(
  tables: [
    // Raw/Reference
    Students, AcademicYears, EducationLevels, Streams,
    Subjects, Units, Lessons, KnowledgeNodes, Prerequisites,
    // Policy/Legal (isolated — see curriculum_tables.dart header)
    PolicyDocuments, CurriculumVersions, SubjectLoads,
    // Planning
    Tasks, TaskSegments, Assignments, Exams, Deadlines,
    StudySessions, Availabilities, RealityConstraints,
    // Derived State
    MasteryStates, MemoryStates, ErrorRecords, TimeEstimates,
    WorkloadStates, PriorityStates, RecoveryRecords, EmergencyStates,
    // Audit (append-only)
    Events, Explanations, HumanOverrides,
    // Config/Versioning
    AlgorithmVersions, ConfigurationVersions, ThresholdRegistryEntries,
    DataStateVersions, SyncMetadataEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Production entry point: a real persistent database, offline, no
  /// network path anywhere in this constructor. On native platforms this
  /// is a file under the app's documents directory; on web it is Drift's
  /// WASM/IndexedDB backend (see connection/connection_web.dart —
  /// DEVIATION-8, requires a one-time manual asset setup, UNVERIFIED here).
  factory AppDatabase.open() {
    return AppDatabase(openConnection());
  }

  /// Test entry point: fully in-memory, never touches disk. Used by every
  /// test file in test/ so the test suite has zero filesystem/network
  /// dependency of its own.
  factory AppDatabase.forTesting() {
    return AppDatabase(NativeDatabase.memory(
      setup: (rawDb) => rawDb.execute('PRAGMA foreign_keys = ON;'),
    ));
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => buildMigrationStrategy(this);
}
