import 'package:drift/drift.dart';
import 'core_tables.dart';
import 'curriculum_tables.dart';

/// The student's recurring weekly template: school timetable, commute,
/// sleep window, meals, regular commitments, extra classes. Every row is
/// typed in by the student (source is always USER_INPUT — the repository
/// has no way to write anything else); nothing here is ever pre-filled with
/// a default timetable.
///
/// `dayOfWeek` keeps Dart's native numbering (1 = Monday ... 7 = Sunday),
/// the same convention as Availabilities.dayOfWeek, so no stored meaning
/// differs between the two tables. The Sunday-first WEEK is a boundary /
/// ordering rule applied by WeekCalendar (weekly_timeline_engine.dart), not
/// a storage rule. See DEVIATIONS.md, DEVIATION-16.
///
/// Times are minutes from midnight (no Time type, no timezone ambiguity).
/// `endMinutes` may exceed 1440 (up to 2880) for a block that runs past
/// midnight, e.g. sleep 22:00 -> 06:00 is 1320 -> 1800.
class WeeklyTemplateEntries extends Table with AuditColumns {
  TextColumn get studentId => text().references(Students, #id)();
  IntColumn get dayOfWeek => integer()(); // 1 = Monday ... 7 = Sunday
  IntColumn get startMinutes => integer()();
  IntColumn get endMinutes => integer()();
  // TimelineBlockKind name: school|commute|sleep|rest|meal|commitment|
  // activity|extraClass
  TextColumn get kind => text()();
  TextColumn get label => text().nullable()();
  TextColumn get subjectId => text().nullable().references(Subjects, #id)();
  BoolColumn get isHard => boolean().withDefault(const Constant(true))();
  TextColumn get source =>
      text().withDefault(const Constant('USER_INPUT'))();

  @override
  Set<Column> get primaryKey => {id};
}
