import 'package:drift/drift.dart';
import 'core_tables.dart';

/// Source-of-record for any official document backing a curriculum/policy
/// value (decree number, ministry bulletin, etc). See Phase 1/2-B/2-C
/// research reports for the traceability model this mirrors.
class PolicyDocuments extends Table with AuditColumns {
  TextColumn get documentNumber => text()();
  TextColumn get documentType => text()(); // قرار / منشور / مرسوم ...
  TextColumn get issuingAuthority => text()();
  DateTimeColumn get publicationDate => dateTime().nullable()();
  DateTimeColumn get effectiveDate => dateTime().nullable()();
  TextColumn get officialUrl => text().nullable()();
  // DocumentVerificationStatus enum, stored as text — see domain/enums.dart
  TextColumn get verificationStatus => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One curriculum "edition" for one academic year. status here is the
/// DEFAULT status a SubjectLoad inherits, but a SubjectLoad row MAY override
/// it (a single subject can be individually FROZEN/CONFLICT even while the
/// rest of the curriculum is ACTIVE — this mirrors Phase 2-C's finding that
/// legal status is sometimes subject-specific, not year-wide).
class CurriculumVersions extends Table with AuditColumns {
  TextColumn get academicYearId => text().references(AcademicYears, #id)();
  // PolicyStatus enum as text: active|unknown|conflict|frozen|repealed
  TextColumn get status => text()();
  TextColumn get sourcePolicyDocumentId =>
      text().references(PolicyDocuments, #id)();
  DateTimeColumn get effectiveFrom => dateTime().nullable()();
  DateTimeColumn get effectiveTo => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Subjects extends Table with AuditColumns {
  TextColumn get name => text()();
  TextColumn get educationLevelId => text().references(EducationLevels, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

/// The ONLY table that may ever hold a coefficient / weekly-hours number.
/// This is the single choke point Guard #1 (ingestion) and Guard #2
/// (consumption) are built around — see repositories/curriculum_repository.dart.
class SubjectLoads extends Table with AuditColumns {
  TextColumn get curriculumVersionId =>
      text().references(CurriculumVersions, #id)();
  TextColumn get subjectId => text().references(Subjects, #id)();
  TextColumn get streamId => text().nullable().references(Streams, #id)();
  RealColumn get coefficient => real().nullable()(); // nullable: may be UNKNOWN
  RealColumn get weeklyHours => real().nullable()();
  // Overrides CurriculumVersions.status for this specific subject when set;
  // required (not nullable) — Guard #1 refuses ingestion without an explicit
  // status, on principle: "no status" must never silently mean ACTIVE.
  TextColumn get status => text()();
  TextColumn get fallbackApplied =>
      text().withDefault(const Constant('false'))();
  TextColumn get fallbackReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Units extends Table with AuditColumns {
  TextColumn get subjectId => text().references(Subjects, #id)();
  TextColumn get name => text()();
  IntColumn get order => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Lessons extends Table with AuditColumns {
  TextColumn get unitId => text().references(Units, #id)();
  TextColumn get name => text()();
  IntColumn get order => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class KnowledgeNodes extends Table with AuditColumns {
  TextColumn get lessonId => text().references(Lessons, #id)();
  TextColumn get name => text()();
  BoolColumn get isExaminable => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

class Prerequisites extends Table with AuditColumns {
  TextColumn get knowledgeNodeId => text().references(KnowledgeNodes, #id)();
  TextColumn get requiresNodeId => text().references(KnowledgeNodes, #id)();
  BoolColumn get isHard => boolean()();
  // PrerequisiteRelationType: official|derived|proposed
  TextColumn get relationType => text()();

  @override
  Set<Column> get primaryKey => {id};
  // Cycle prevention (knowledgeNodeId -> ... -> knowledgeNodeId) is NOT
  // expressible as a SQL constraint; enforced in
  // repositories/prerequisite_repository.dart via a DFS check before insert.
  // Documented here so the limitation isn't silently lost.
}
