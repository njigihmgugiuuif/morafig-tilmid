import 'package:drift/drift.dart';
import 'package:drift/native.dart' if (dart.library.js_interop) 'package:drift/wasm.dart';

import 'connection/connection.dart';
import 'tables/core_tables.dart';
import 'tables/curriculum_tables.dart';
import 'tables/planning_tables.dart';
import 'tables/derived_state_tables.dart';
import 'tables/audit_tables.dart';
import 'tables/config_tables.dart';
import 'migrations/migration_strategy.dart';

part 'app_database.g.dart';

/// The Data Foundation database. 36 tables total.
@DriftDatabase(
  tables: [
    // Raw/Reference
    Students, AcademicYears, EducationLevels, Streams,
    Subjects, Units, Lessons, KnowledgeNodes, Prerequisites,
    // Policy/Legal
    PolicyDocuments, CurriculumVersions, SubjectLoads,
    // Planning
    Tasks, TaskSegments, Assignments, Exams, Deadlines,
    StudySessions, Availabilities, RealityConstraints,
    // Derived State
    MasteryStates, MemoryStates, ErrorRecords, TimeEstimates,
    WorkloadStates, PriorityStates, RecoveryRecords, EmergencyStates,
    // Audit
    Events, Explanations, HumanOverrides,
    // Config/Versioning
    AlgorithmVersions, ConfigurationVersions, ThresholdRegistryEntries,
    DataStateVersions, SyncMetadataEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.open() {
    return AppDatabase(openConnection());
  }

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
