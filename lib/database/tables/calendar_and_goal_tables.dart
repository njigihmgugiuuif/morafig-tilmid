import 'package:drift/drift.dart';
import 'core_tables.dart';
import 'curriculum_tables.dart';

// Phase 1 data model additions (schema v4). See DEVIATIONS.md, DEVIATION-17.
//
// Every row in these four tables is typed in by the student (or, for
// Holidays, entered from a documented official calendar); nothing here is
// ever pre-filled with invented data. Dates are stored as Drift DateTime
// values (UTC instants like every other table); a Holiday/Term range is
// inclusive of its start day and inclusive of its end day, which is applied
// by the consumer (Academic Year phase), not by the schema.

/// One self-reported reading of the student's energy and focus at a moment
/// in time. Feeds the Workload + Energy phase.
///
/// Scale (DEVIATION-17, a documented decision, not an official number):
/// both levels are integers 1 (lowest) .. 5 (highest). The range is
/// validated by the repository that will write this table (Workload +
/// Energy phase), not by a SQL CHECK, following DEVIATION-2.
class EnergyFocusLogs extends Table with AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  DateTimeColumn get loggedAt => dateTime()();
  IntColumn get energyLevel => integer()();
  IntColumn get focusLevel => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A term/semester/trimester inside an academic year (the name is whatever
/// the student or the documented source calls it; the schema assumes no
/// number of terms).
class AcademicTerms extends Table with AuditColumns {
  TextColumn get academicYearId => text().references(AcademicYears, #id)();
  TextColumn get name => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A holiday / break inside an academic year. `source` records where the
/// dates came from (USER_INPUT by default; a documented official calendar
/// may be recorded by its own label) — never inferred.
class Holidays extends Table with AuditColumns {
  TextColumn get academicYearId => text().references(AcademicYears, #id)();
  TextColumn get name => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get source =>
      text().withDefault(const Constant('USER_INPUT'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A goal the student sets (optionally for one subject, optionally with a
/// target date). `status` is text: active | achieved | dropped (default
/// active); enforced in Dart per DEVIATION-2, not as a SQL CHECK.
class Goals extends Table with AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  TextColumn get title => text()();
  TextColumn get subjectId => text().nullable().references(Subjects, #id)();
  DateTimeColumn get targetDate => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();

  @override
  Set<Column> get primaryKey => {id};
}
