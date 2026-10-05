import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

// Students.curriculumVersionId references CurriculumVersions (schema v6,
// DEVIATION-19). curriculum_tables.dart already imports this file, so the two
// table files import each other; Dart allows that, and only the table classes
// (types) are referenced, never evaluated at import time.
import 'curriculum_tables.dart';

const uuidGen = Uuid();

/// Every table in this Foundation shares these four columns. Drift has no
/// "abstract table with inherited columns" shortcut across files without a
/// mixin, so we use a mixin instead of copy-pasting four lines 36 times.
mixin AuditColumns on Table {
  TextColumn get id => text().clientDefault(() => uuidGen.v4())();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
  IntColumn get syncVersion => integer().withDefault(const Constant(0))();
}

/// Single student per local database (single-user, offline-first).
/// DB-level enforcement of "only one Student row" lives in
/// StudentRepository (Drift has no native single-row table constraint).
class Students extends Table with AuditColumns {
  TextColumn get fullNameOrNickname => text()();
  TextColumn get currentAcademicYearId =>
      text().references(AcademicYears, #id)();
  IntColumn get sleepFloorMinMinutes =>
      integer().withDefault(const Constant(420))(); // 7h default, Registry-owned
  // Added in schema v6 (DEVIATION-19). All three are NULLABLE: NULL means
  // "the student has not said / not known", never a guessed value. Only
  // StudentRepository writes them, and it validates them (the stream must
  // belong to the level; the curriculum version must be ACTIVE and belong
  // to the student's current academic year).
  TextColumn get educationLevelId =>
      text().nullable().references(EducationLevels, #id)();
  TextColumn get streamId => text().nullable().references(Streams, #id)();
  TextColumn get curriculumVersionId =>
      text().nullable().references(CurriculumVersions, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

class AcademicYears extends Table with AuditColumns {
  TextColumn get label => text()(); // e.g. "2026-2027"
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {label},
      ];
}

class EducationLevels extends Table with AuditColumns {
  TextColumn get name => text()(); // جذع مشترك / سنة ثانية / سنة ثالثة
  IntColumn get order => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StudyStream')
class Streams extends Table with AuditColumns {
  TextColumn get name => text()();
  TextColumn get educationLevelId => text().references(EducationLevels, #id)();

  @override
  Set<Column> get primaryKey => {id};
}
