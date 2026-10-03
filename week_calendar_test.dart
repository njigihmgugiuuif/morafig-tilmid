import 'package:test/test.dart';

import 'package:student_app/engines/weekly_timeline_engine.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// WeekCalendar is the official conversion layer between the stored day
/// number (Dart weekday: 1 = Monday ... 7 = Sunday) and the Sunday-first
/// week index (0 = Sunday ... 6 = Saturday). Dates used below:
/// 2026-09-27 is a Sunday, 2026-10-03 a Saturday.
void main() {
  group('WeekCalendar — stored day <-> Sunday-first index', () {
    test('Sunday is index 0 and stored day 7; Monday is 1/1; Saturday 6/6',
        () {
      expect(WeekCalendar.indexFromStoredDay(7), 0); // Sunday
      expect(WeekCalendar.indexFromStoredDay(1), 1); // Monday
      expect(WeekCalendar.indexFromStoredDay(2), 2);
      expect(WeekCalendar.indexFromStoredDay(5), 5); // Friday
      expect(WeekCalendar.indexFromStoredDay(6), 6); // Saturday
      expect(WeekCalendar.storedDayFromIndex(0), 7);
      expect(WeekCalendar.storedDayFromIndex(1), 1);
      expect(WeekCalendar.storedDayFromIndex(6), 6);
    });

    test('the two conversions are exact inverses for every valid value', () {
      for (var stored = 1; stored <= 7; stored++) {
        expect(
          WeekCalendar.storedDayFromIndex(WeekCalendar.indexFromStoredDay(stored)),
          stored,
        );
      }
      for (var index = 0; index <= 6; index++) {
        expect(
          WeekCalendar.indexFromStoredDay(WeekCalendar.storedDayFromIndex(index)),
          index,
        );
      }
    });

    test('out-of-range values are rejected, not silently wrapped', () {
      expect(() => WeekCalendar.indexFromStoredDay(0), throwsRangeError);
      expect(() => WeekCalendar.indexFromStoredDay(8), throwsRangeError);
      expect(() => WeekCalendar.storedDayFromIndex(-1), throwsRangeError);
      expect(() => WeekCalendar.storedDayFromIndex(7), throwsRangeError);
      expect(WeekCalendar.isValidStoredDay(0), isFalse);
      expect(WeekCalendar.isValidStoredDay(7), isTrue);
    });

    test('storedDayOf(date) equals Dart weekday for every day of a week', () {
      for (var i = 0; i < 7; i++) {
        final d = DateTime(2026, 9, 27 + i);
        expect(WeekCalendar.storedDayOf(d), d.weekday);
        expect(WeekCalendar.indexInWeek(d), i); // Sunday-first order
      }
    });

    test('storedDayMatches: null and invalid never match; valid compares the '
        'weekday', () {
      final sunday = DateTime(2026, 9, 27);
      final monday = DateTime(2026, 9, 28);
      expect(WeekCalendar.storedDayMatches(7, sunday), isTrue);
      expect(WeekCalendar.storedDayMatches(7, monday), isFalse);
      expect(WeekCalendar.storedDayMatches(1, monday), isTrue);
      expect(WeekCalendar.storedDayMatches(1, sunday), isFalse);
      expect(WeekCalendar.storedDayMatches(null, sunday), isFalse);
      expect(WeekCalendar.storedDayMatches(0, sunday), isFalse);
      expect(WeekCalendar.storedDayMatches(8, sunday), isFalse);
    });
  });

  group('WeekCalendar — week boundaries and day arithmetic', () {
    test('a Sunday starts its own week; a Saturday belongs to the previous '
        'Sunday', () {
      expect(WeekCalendar.startOfWeek(DateTime(2026, 9, 27, 15, 30)),
          DateTime(2026, 9, 27));
      expect(WeekCalendar.startOfWeek(DateTime(2026, 10, 3, 23, 59)),
          DateTime(2026, 9, 27));
      expect(WeekCalendar.startOfWeek(DateTime(2026, 9, 28)),
          DateTime(2026, 9, 27)); // Monday
    });

    test('endOfWeek is the next Sunday midnight and daysOf lists Sunday '
        'first', () {
      final start = DateTime(2026, 9, 27);
      expect(WeekCalendar.endOfWeek(start), DateTime(2026, 10, 4));
      final days = WeekCalendar.daysOf(start);
      expect(days, hasLength(7));
      expect(days.first, DateTime(2026, 9, 27));
      expect(days.last, DateTime(2026, 10, 3));
      expect(WeekCalendar.arabicDayNames.first, 'الأحد');
    });

    test('addDays crosses month and year boundaries', () {
      expect(WeekCalendar.addDays(DateTime(2026, 9, 30), 1),
          DateTime(2026, 10, 1));
      expect(WeekCalendar.addDays(DateTime(2026, 12, 31), 1),
          DateTime(2027, 1, 1));
      expect(WeekCalendar.addDays(DateTime(2026, 10, 1), -1),
          DateTime(2026, 9, 30));
    });
  });

  group('expandTemplate uses the official conversion', () {
    test('a stored Sunday (7) lands on index 0 and a stored Monday (1) on '
        'index 1 of the same Sunday-first week', () {
      final sunday = DateTime(2026, 9, 27);
      final blocks = WeekTimelineEngine.expandTemplate(
        weekStart: sunday,
        slots: [
          WeeklyTemplateSlot(
              dayOfWeek: 7,
              startMinutes: 8 * 60,
              endMinutes: 9 * 60,
              kind: TimelineBlockKind.school),
          WeeklyTemplateSlot(
              dayOfWeek: 1,
              startMinutes: 8 * 60,
              endMinutes: 9 * 60,
              kind: TimelineBlockKind.school),
        ],
      );
      expect(blocks[0].start, DateTime(2026, 9, 27, 8)); // Sunday
      expect(blocks[1].start, DateTime(2026, 9, 28, 8)); // Monday
    });
  });
}
