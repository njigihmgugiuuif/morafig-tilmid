import 'package:drift/drift.dart';

import '../database/app_database.dart';

class InvalidCalendarEntry implements Exception {
  InvalidCalendarEntry(this.reason);
  final String reason;
  @override
  String toString() => 'InvalidCalendarEntry: $reason';
}

/// Terms and holidays of an academic year (B, DEVIATION-22).
///
/// Nothing is seeded and nothing is inferred: every row is typed in by the
/// student. There is deliberately no parameter for `source` (the column
/// defaults to USER_INPUT), exactly like the reality repositories; an
/// official calendar may only be recorded later from a documented source.
///
/// Dates are CALENDAR days. Callers pass local midnight dates; a range is
/// inclusive of its start day and inclusive of its end day (see the table
/// comment), applied by [coversDay] below.
class AcademicCalendarRepository {
  AcademicCalendarRepository(this._db);
  final AppDatabase _db;

  Future<AcademicTerm> insertTerm({
    required String academicYearId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    _validate(name, startDate, endDate);
    return _db.into(_db.academicTerms).insertReturning(
          AcademicTermsCompanion.insert(
            academicYearId: academicYearId,
            name: name.trim(),
            startDate: startDate,
            endDate: endDate,
          ),
        );
  }

  Future<Holiday> insertHolidayFromUser({
    required String academicYearId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    _validate(name, startDate, endDate);
    return _db.into(_db.holidays).insertReturning(
          HolidaysCompanion.insert(
            academicYearId: academicYearId,
            name: name.trim(),
            startDate: startDate,
            endDate: endDate,
          ),
        );
  }

  Future<List<AcademicTerm>> readTerms(String academicYearId) =>
      (_db.select(_db.academicTerms)
            ..where((t) => t.academicYearId.equals(academicYearId))
            ..orderBy([(t) => OrderingTerm.asc(t.startDate)]))
          .get();

  Future<List<Holiday>> readHolidays(String academicYearId) =>
      (_db.select(_db.holidays)
            ..where((t) => t.academicYearId.equals(academicYearId))
            ..orderBy([(t) => OrderingTerm.asc(t.startDate)]))
          .get();

  /// The term whose day range contains [date], or null (no term entered, or
  /// the date is between terms). If entered terms overlap, the first by
  /// start date is returned.
  Future<AcademicTerm?> termContaining(
    String academicYearId,
    DateTime date,
  ) async {
    for (final t in await readTerms(academicYearId)) {
      if (coversDay(t.startDate, t.endDate, date)) return t;
    }
    return null;
  }

  /// Holidays whose day range contains [date].
  Future<List<Holiday>> holidaysCovering(
    String academicYearId,
    DateTime date,
  ) async {
    return (await readHolidays(academicYearId))
        .where((h) => coversDay(h.startDate, h.endDate, date))
        .toList();
  }

  /// True when the calendar day of [date] lies within [start]..[end], both
  /// days included (compared by year/month/day only).
  static bool coversDay(DateTime start, DateTime end, DateTime date) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  void _validate(String name, DateTime start, DateTime end) {
    if (name.trim().isEmpty) {
      throw InvalidCalendarEntry('name must not be empty');
    }
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    if (e.isBefore(s)) {
      throw InvalidCalendarEntry('endDate must not be before startDate');
    }
  }
}
