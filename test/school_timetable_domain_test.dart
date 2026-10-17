import 'package:test/test.dart';

import 'package:student_app/domain/school_timetable_domain.dart';
import 'package:student_app/engines/weekly_timeline_engine.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Pure logic of the school timetable grid. The data below is SYNTHETIC; the
/// «photo model» is only a blank shape (no subjects) the student may choose.
void main() {
  SchoolEntry entry(String id, int dayIndex, int start, int end,
          [String label = 'x']) =>
      SchoolEntry(
        id: id,
        dayStored: WeekCalendar.storedDayFromIndex(dayIndex),
        startMinutes: start,
        endMinutes: end,
        label: label,
      );

  group('photo model (blank shape)', () {
    final m = SchoolTimetableLayout.photoModel();

    test('is Sunday..Thursday, 08:00..17:00 with a 12:00..13:00 break', () {
      expect(m.days, [0, 1, 2, 3, 4]);
      expect(m.slots.first.startMinutes, 8 * 60);
      expect(m.slots.last.endMinutes, 17 * 60);
      final breaks = m.slots.where((s) => s.isBreak).toList();
      expect(breaks, hasLength(1));
      expect(breaks.single.startMinutes, 12 * 60);
      expect(breaks.single.endMinutes, 13 * 60);
      expect(m.periods, hasLength(8));
    });

    test('is a valid layout and carries no subject at all', () {
      expect(SchoolTimetableLayout.validate(m.days, m.slots), isNull);
      expect(m.isConfigured, isTrue);
      // The layout type has no label field: nothing to pre-fill.
      expect(m.encode().contains('label'), isFalse);
    });

    test('the empty layout is not configured (nothing is assumed)', () {
      expect(SchoolTimetableLayout.empty.isConfigured, isFalse);
      expect(SchoolTimetableLayout.empty.days, isEmpty);
      expect(SchoolTimetableLayout.empty.slots, isEmpty);
    });

    test('day 0 is Sunday and is stored as 7', () {
      expect(WeekCalendar.storedDayFromIndex(m.days.first), 7);
    });
  });

  group('validate', () {
    const s1 = SchoolSlot(id: 1, startMinutes: 480, endMinutes: 540);

    test('needs a day', () {
      expect(SchoolTimetableLayout.validate(const <int>[], const [s1]),
          'اختر يومًا واحدًا على الأقل.');
    });

    test('needs a lesson slot (a break alone is not enough)', () {
      expect(
          SchoolTimetableLayout.validate(const [0], const [
            SchoolSlot(id: 1, startMinutes: 480, endMinutes: 540, isBreak: true)
          ]),
          'أضف حصة واحدة على الأقل.');
    });

    test('rejects end before start, overlap and duplicated ids', () {
      expect(
          SchoolTimetableLayout.validate(const [0], const [
            SchoolSlot(id: 1, startMinutes: 540, endMinutes: 540)
          ]),
          'نهاية الحصة يجب أن تكون بعد بدايتها.');
      expect(
          SchoolTimetableLayout.validate(const [0], const [
            s1,
            SchoolSlot(id: 2, startMinutes: 520, endMinutes: 600)
          ]),
          contains('متداخلتان'));
      expect(
          SchoolTimetableLayout.validate(const [0], const [
            s1,
            SchoolSlot(id: 1, startMinutes: 600, endMinutes: 660)
          ]),
          isNotNull);
    });

    test('touching slots are fine; crossing midnight is not', () {
      expect(
          SchoolTimetableLayout.validate(const [0], const [
            s1,
            SchoolSlot(id: 2, startMinutes: 540, endMinutes: 600)
          ]),
          isNull);
      expect(
          SchoolTimetableLayout.validate(const [0], const [
            SchoolSlot(id: 1, startMinutes: 1400, endMinutes: 1500)
          ]),
          isNotNull);
    });

    test('limits the number of rows', () {
      final many = [
        for (var i = 0; i < kSchoolMaxSlots + 1; i++)
          SchoolSlot(id: i + 1, startMinutes: i * 60, endMinutes: i * 60 + 30)
      ];
      expect(SchoolTimetableLayout.validate(const [0], many), isNotNull);
    });

    test('label rules', () {
      expect(SchoolTimetableLayout.validateLabel('  '), isNotNull);
      expect(SchoolTimetableLayout.validateLabel('رياضيات'), isNull);
      expect(SchoolTimetableLayout.validateLabel('م' * (kSchoolMaxLabel + 1)),
          isNotNull);
    });
  });

  group('storage format', () {
    test('round trip keeps days and slots', () {
      final m = SchoolTimetableLayout.photoModel();
      final back = SchoolTimetableLayout.decode(m.encode())!;
      expect(back.days, m.days);
      expect(back.slots, m.slots);
    });

    test('damaged or invalid values give null, never a guess', () {
      expect(SchoolTimetableLayout.decode(null), isNull);
      expect(SchoolTimetableLayout.decode(''), isNull);
      expect(SchoolTimetableLayout.decode('not json'), isNull);
      expect(SchoolTimetableLayout.decode('[1,2]'), isNull);
      expect(SchoolTimetableLayout.decode('{"days":[0],"slots":[]}'), isNull);
      expect(
          SchoolTimetableLayout.decode(
              '{"days":[0],"slots":[{"id":1,"start":480,"end":600},'
              '{"id":2,"start":540,"end":660}]}'),
          isNull);
    });
  });

  group('cells', () {
    final layout = SchoolTimetableLayout.photoModel();
    final slot = layout.slots.first; // 08:00..09:00

    test('cellAt finds the cell of a day and a slot', () {
      final e = entry('a', 0, 480, 540, 'رياضيات');
      expect(SchoolTimetableLayout.cellAt([e], 0, slot), same(e));
      expect(SchoolTimetableLayout.cellAt([e], 1, slot), isNull);
    });

    test('usedLabels: most used first, then alphabetical', () {
      final names = SchoolTimetableLayout.usedLabels([
        entry('1', 0, 480, 540, 'ب'),
        entry('2', 1, 480, 540, 'أ'),
        entry('3', 2, 480, 540, 'ب'),
        entry('4', 3, 480, 540, ' '),
      ]);
      expect(names, ['ب', 'أ']);
    });

    test('fits: only cells on a day and a slot of the grid', () {
      expect(layout.fits(entry('a', 0, 480, 540)), isTrue);
      expect(layout.fits(entry('b', 5, 480, 540)), isFalse); // Friday
      expect(layout.fits(entry('c', 0, 481, 540)), isFalse);
      expect(layout.fits(entry('d', 0, 720, 780)), isFalse); // the break
    });
  });

  group('layout changes move or delete only what they must', () {
    final old = SchoolTimetableLayout.photoModel();
    final slot1 = old.slots[0]; // id 1, 08:00
    final entries = [
      entry('a', 0, 480, 540, 'رياضيات'),
      entry('b', 4, 480, 540, 'فيزياء'),
      entry('c', 0, 540, 600, 'عربية'),
      entry('out', 0, 1100, 1160, 'خارج الشبكة'), // not part of the grid
    ];

    test('unchanged layout: nothing happens', () {
      final plan = SchoolTimetableLayout.planChange(
          oldLayout: old, next: old, entries: entries);
      expect(plan.isEmpty, isTrue);
    });

    test('removing a day deletes that day\'s cells only', () {
      final next = SchoolTimetableLayout.normalized(
          old.days.where((d) => d != 4), old.slots);
      final plan = SchoolTimetableLayout.planChange(
          oldLayout: old, next: next, entries: entries);
      expect(plan.removed.map((e) => e.id), ['b']);
      expect(plan.retimed, isEmpty);
    });

    test('changing the times of a slot moves its cells with it', () {
      final next = SchoolTimetableLayout.normalized(old.days, [
        slot1.copyWith(startMinutes: 490, endMinutes: 550),
        ...old.slots.skip(1),
      ]);
      final plan = SchoolTimetableLayout.planChange(
          oldLayout: old, next: next, entries: entries);
      expect(plan.removed, isEmpty);
      expect(plan.retimed.map((r) => r.entry.id).toSet(), {'a', 'b'});
      expect(plan.retimed.first.to.startMinutes, 490);
      expect(plan.retimed.first.to.endMinutes, 550);
    });

    test('deleting a slot or turning it into a break deletes its cells', () {
      final without = SchoolTimetableLayout.normalized(
          old.days, old.slots.where((s) => s.id != 1));
      expect(
          SchoolTimetableLayout.planChange(
                  oldLayout: old, next: without, entries: entries)
              .removed
              .map((e) => e.id)
              .toSet(),
          {'a', 'b'});

      final asBreak = SchoolTimetableLayout.normalized(old.days, [
        slot1.copyWith(isBreak: true),
        ...old.slots.skip(1),
      ]);
      expect(
          SchoolTimetableLayout.planChange(
                  oldLayout: old, next: asBreak, entries: entries)
              .removed
              .map((e) => e.id)
              .toSet(),
          {'a', 'b'});
    });

    test('a cell outside the grid is never touched', () {
      final next = SchoolTimetableLayout.normalized(const [0], [
        const SchoolSlot(id: 1, startMinutes: 480, endMinutes: 540),
      ]);
      final plan = SchoolTimetableLayout.planChange(
          oldLayout: old, next: next, entries: entries);
      expect(plan.removed.map((e) => e.id), isNot(contains('out')));
      expect(plan.retimed.map((r) => r.entry.id), isNot(contains('out')));
    });
  });

  group('mergedWith (layout lost, cells kept)', () {
    test('rebuilds days and slots from stored cells, nothing more', () {
      final merged = SchoolTimetableLayout.empty.mergedWith([
        entry('a', 0, 480, 540),
        entry('b', 2, 540, 600),
        entry('c', 2, 480, 540),
      ]);
      expect(merged.days, [0, 2]);
      expect(merged.periods.map((s) => s.startMinutes), [480, 540]);
      expect(merged.isConfigured, isTrue);
      expect(merged.outsideGridCount([entry('a', 0, 480, 540)]), 0);
    });

    test('a cell that overlaps a slot partly is kept but counted outside', () {
      final base = SchoolTimetableLayout.photoModel();
      final odd = entry('odd', 0, 500, 560);
      final merged = base.mergedWith([odd]);
      expect(merged.slots.length, base.slots.length);
      expect(merged.outsideGridCount([odd]), 1);
    });
  });
}
