import 'package:drift/drift.dart';
import 'core_tables.dart';
import 'curriculum_tables.dart';

class Tasks extends Table with AuditColumns {
  TextColumn get knowledgeNodeId => text().references(KnowledgeNodes, #id)();
  IntColumn get estimatedDurationMinutes => integer()();
  BoolColumn get isSplittable => boolean().withDefault(const Constant(false))();
  IntColumn get minimumChunkDurationMinutes => integer().nullable()();
  IntColumn get maximumChunkDurationMinutes => integer().nullable()();
  BoolColumn get crossSessionTypeAllowed =>
      boolean().withDefault(const Constant(false))();
  IntColumn get remainingDurationMinutes => integer()();
  // TaskCompletionStatus: notStarted|partial|complete
  TextColumn get completionStatus =>
      text().withDefault(const Constant('notStarted'))();
  // TaskSourceType: regular|assignment|examPrep
  TextColumn get sourceType => text()();
  TextColumn get sourceAssignmentId =>
      text().nullable().references(Assignments, #id)();
  TextColumn get sourceExamId => text().nullable().references(Exams, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskSegments extends Table with AuditColumns {
  TextColumn get parentTaskId => text().references(Tasks, #id)();
  IntColumn get segmentDurationMinutes => integer()();
  IntColumn get segmentOrder => integer()();
  DateTimeColumn get executedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Assignments extends Table with AuditColumns {
  TextColumn get subjectId => text().references(Subjects, #id)();
  TextColumn get description => text()();
  DateTimeColumn get dueDate => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Exams extends Table with AuditColumns {
  TextColumn get subjectId => text().references(Subjects, #id)();
  DateTimeColumn get examDate => dateTime()();
  // ExamType: formative|summative|bac
  TextColumn get examType => text()();
  RealColumn get officialWeight => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Deadlines extends Table with AuditColumns {
  TextColumn get relatedEntityId => text()();
  TextColumn get relatedEntityType => text()(); // 'Task' | 'Assignment' | 'Exam'
  DateTimeColumn get dueDateTime => dateTime()();
  BoolColumn get isHard => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Unifies the original spec's "ScheduleEntry" and this phase's requested
/// "StudySession" — documented as a deliberate naming decision in
/// DEVIATIONS.md, not a dropped entity.
class StudySessions extends Table with AuditColumns {
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get taskSegmentId =>
      text().nullable().references(TaskSegments, #id)();
  DateTimeColumn get plannedStart => dateTime()();
  DateTimeColumn get plannedEnd => dateTime()();
  DateTimeColumn get actualStart => dateTime().nullable()();
  DateTimeColumn get actualEnd => dateTime().nullable()();
  IntColumn get observedDurationMinutes => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Availabilities extends Table with AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  IntColumn get dayOfWeek => integer().nullable()(); // 1-7, null if specificDate used
  DateTimeColumn get specificDate => dateTime().nullable()();
  // Stored as minutes-from-midnight to avoid timezone ambiguity on a Time type.
  IntColumn get windowStartMinutes => integer()();
  IntColumn get windowEndMinutes => integer()();
  BoolColumn get isRecurring => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

class RealityConstraints extends Table with AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  // RealityConstraintType: school|commute|fixedCommitment|rest|sleep|activity|unexpectedEvent
  TextColumn get type => text()();
  DateTimeColumn get windowStart => dateTime()();
  DateTimeColumn get windowEnd => dateTime()();
  BoolColumn get isHard => boolean()();
  // Invariant: this column exists ONLY to make the "manual input only" rule
  // auditable in the data itself — the repository layer additionally
  // refuses to accept any other value at the API boundary (see
  // RealityConstraintRepository — there is no path that lets an engine
  // write this table directly).
  TextColumn get source =>
      text().withDefault(const Constant('USER_INPUT'))();

  @override
  Set<Column> get primaryKey => {id};
}
