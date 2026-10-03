import 'package:test/test.dart';

import 'package:student_app/engines/scheduling_engine.dart';
import 'package:student_app/engines/weekly_timeline_engine.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Reference calendar: Sunday 2026-09-27 starts the week used below
/// (2026-10-02 is a Friday).
void main() {
  final sunday = DateTime(2026, 9, 27);
  DateTime at(int dayOffset, int h, [int m = 0]) =>
      DateTime(2026, 9, 27 + dayOffset, h, m);

  group('WeekCalendar — the week starts on Sunday', () {
    test('Sunday is index 0 and maps to itself', () {
      expect(WeekCalendar.indexInWeek(sunday), 0);
      expect(WeekCalendar.startOfWeek(sunday), sunday);
    });

    test('Monday is index 1, Saturday is index 6', () {
      expect(WeekCalendar.indexInWeek(DateTime(2026, 9, 28)), 1);
      expect(WeekCalendar.indexInWeek(DateTime(2026, 10, 3)), 6);
    });

    test('a Friday and a Saturday belong to the week of the previous Sunday',
        () {
      expect(WeekCalendar.startOfWeek(DateTime(2026, 10, 2, 15, 30)), sunday);
      expect(WeekCalendar.startOfWeek(DateTime(2026, 10, 3)), sunday);
    });

    test('the next Sunday starts a new week (not the same one)', () {
      expect(WeekCalendar.startOfWeek(DateTime(2026, 10, 4)),
          DateTime(2026, 10, 4));
    });

    test('crossing a month boundary still lands on the right Sunday', () {
      expect(WeekCalendar.startOfWeek(DateTime(2026, 10, 1)), sunday);
    });

    test('daysOf returns 7 midnights, Sunday first, and the exclusive end',
        () {
      final days = WeekCalendar.daysOf(DateTime(2026, 10, 2));
      expect(days, hasLength(7));
      expect(days.first, sunday);
      expect(days.last, DateTime(2026, 10, 3));
      expect(WeekCalendar.endOfWeek(sunday), DateTime(2026, 10, 4));
    });

    test('Arabic day names are Sunday-first', () {
      expect(WeekCalendar.arabicDayNames.first, 'الأحد');
      expect(WeekCalendar.arabicDayNames.last, 'السبت');
      expect(WeekCalendar.arabicDayNames, hasLength(7));
    });
  });

  group('expandTemplate', () {
    test('Dart weekday numbers map onto the Sunday-first week', () {
      final blocks = WeekTimelineEngine.expandTemplate(
        weekStart: sunday,
        slots: [
          WeeklyTemplateSlot(
              dayOfWeek: 7, // Sunday
              startMinutes: 8 * 60,
              endMinutes: 10 * 60,
              kind: TimelineBlockKind.school),
          WeeklyTemplateSlot(
              dayOfWeek: 1, // Monday
              startMinutes: 8 * 60,
              endMinutes: 12 * 60,
              kind: TimelineBlockKind.school),
          WeeklyTemplateSlot(
              dayOfWeek: 6, // Saturday
              startMinutes: 9 * 60,
              endMinutes: 10 * 60,
              kind: TimelineBlockKind.extraClass),
        ],
      );
      expect(blocks[0].start, at(0, 8));
      expect(blocks[0].end, at(0, 10));
      expect(blocks[1].start, at(1, 8));
      expect(blocks[1].end, at(1, 12));
      expect(blocks[2].start, at(6, 9));
    });

    test('a sleep block can run past midnight', () {
      final blocks = WeekTimelineEngine.expandTemplate(
        weekStart: sunday,
        slots: [
          WeeklyTemplateSlot(
              dayOfWeek: 7,
              startMinutes: 22 * 60,
              endMinutes: 30 * 60, // 06:00 next day
              kind: TimelineBlockKind.sleep),
        ],
      );
      expect(blocks.single.start, at(0, 22));
      expect(blocks.single.end, at(1, 6));
    });

    test('a Saturday sleep crossing midnight also fills Sunday morning of '
        'the same week (carry-in from the previous week)', () {
      final blocks = WeekTimelineEngine.expandTemplate(
        weekStart: sunday,
        slots: [
          WeeklyTemplateSlot(
              dayOfWeek: 6, // Saturday
              startMinutes: 22 * 60,
              endMinutes: 30 * 60,
              kind: TimelineBlockKind.sleep),
        ],
      );
      expect(blocks.length, 2);
      final sat = blocks.firstWhere((b) => b.start == at(6, 22));
      expect(sat.end, at(7, 6)); // next week's Sunday 06:00
      final carry = blocks.firstWhere((b) => b.start == at(-1, 22));
      expect(carry.end, at(0, 6)); // this week's Sunday 06:00
      final t = const WeekTimelineEngine().build(
        weekStart: sunday,
        fixedBlocks: blocks,
        chunks: [],
      );
      expect(t.days[0].blocks.single.start, at(0, 0));
      expect(t.days[0].blocks.single.end, at(0, 6));
    });
  });

  group('WeekTimelineEngine.build', () {
    const engine = WeekTimelineEngine();

    test('always yields 7 days, Sunday first', () {
      final t = engine.build(
          weekStart: DateTime(2026, 10, 1), fixedBlocks: [], chunks: []);
      expect(t.days, hasLength(7));
      expect(t.weekStart, sunday);
      expect(t.days.first.date, sunday);
      expect(t.days.first.dayNameAr, 'الأحد');
      expect(t.days.last.dayNameAr, 'السبت');
    });

    test('an empty day is one free gap of 24 hours', () {
      final t = engine.build(weekStart: sunday, fixedBlocks: [], chunks: []);
      expect(t.days.first.freeGaps, hasLength(1));
      expect(t.days.first.freeMinutes, 1440);
    });

    test('a block crossing midnight is clipped into both days', () {
      final t = engine.build(
        weekStart: sunday,
        fixedBlocks: [
          TimelineBlock(
              kind: TimelineBlockKind.sleep, start: at(0, 22), end: at(1, 6)),
        ],
        chunks: [],
      );
      expect(t.days[0].blocks.single.start, at(0, 22));
      expect(t.days[0].blocks.single.end, at(1, 0));
      expect(t.days[1].blocks.single.start, at(1, 0));
      expect(t.days[1].blocks.single.end, at(1, 6));
      expect(t.days[0].freeMinutes, 22 * 60);
      expect(t.days[1].freeMinutes, 18 * 60);
    });

    test('gaps are the minutes covered by no block', () {
      final t = engine.build(
        weekStart: sunday,
        fixedBlocks: [
          TimelineBlock(
              kind: TimelineBlockKind.school, start: at(0, 8), end: at(0, 12)),
        ],
        chunks: [],
      );
      final gaps = t.days.first.freeGaps;
      expect(gaps, hasLength(2));
      expect(gaps[0].start, at(0, 0));
      expect(gaps[0].end, at(0, 8));
      expect(gaps[1].start, at(0, 12));
      expect(gaps[1].end, at(1, 0));
    });

    test('blocks within a day are sorted by start time', () {
      final t = engine.build(
        weekStart: sunday,
        fixedBlocks: [
          TimelineBlock(
              kind: TimelineBlockKind.meal, start: at(0, 13), end: at(0, 14)),
          TimelineBlock(
              kind: TimelineBlockKind.school, start: at(0, 8), end: at(0, 12)),
        ],
        chunks: [],
      );
      expect(t.days.first.blocks.map((b) => b.kind).toList(),
          [TimelineBlockKind.school, TimelineBlockKind.meal]);
    });

    test('two overlapping HARD blocks are a conflict with the right overlap',
        () {
      final t = engine.build(
        weekStart: sunday,
        fixedBlocks: [
          TimelineBlock(
              kind: TimelineBlockKind.school, start: at(0, 10), end: at(0, 12)),
          TimelineBlock(
              kind: TimelineBlockKind.commitment,
              start: at(0, 11),
              end: at(0, 13)),
        ],
        chunks: [],
      );
      expect(t.conflicts, hasLength(1));
      expect(t.conflicts.single.overlapMinutes, 60);
    });

    test('a SOFT block never creates a conflict', () {
      final t = engine.build(
        weekStart: sunday,
        fixedBlocks: [
          TimelineBlock(
              kind: TimelineBlockKind.school, start: at(0, 10), end: at(0, 12)),
          TimelineBlock(
              kind: TimelineBlockKind.rest,
              start: at(0, 11),
              end: at(0, 13),
              isHard: false),
        ],
        chunks: [],
      );
      expect(t.conflicts, isEmpty);
    });

    test('study chunks become study blocks and use up study capacity', () {
      final t = engine.build(
        weekStart: sunday,
        fixedBlocks: [],
        studySlots: [TimeSlot(start: at(0, 16), end: at(0, 18))],
        chunks: [
          ScheduledChunk(taskId: 'math', start: at(0, 16), end: at(0, 17)),
        ],
        taskLabels: {'math': 'رياضيات'},
      );
      final day = t.days.first;
      expect(day.studyCapacityMinutes, 120);
      expect(day.scheduledStudyMinutes, 60);
      expect(day.freeStudyMinutes, 60);
      expect(day.blocks.single.kind, TimelineBlockKind.study);
      expect(day.blocks.single.label, 'رياضيات');
      expect(t.scheduledStudyMinutes, 60);
      expect(t.studyCapacityMinutes, 120);
    });

    test('dayFor finds the right day and rejects a date outside the week', () {
      final t = engine.build(weekStart: sunday, fixedBlocks: [], chunks: []);
      expect(t.dayFor(at(3, 10)).date, at(3, 0));
      expect(() => t.dayFor(DateTime(2026, 10, 5)), throwsArgumentError);
    });
  });

  group('subtractHardBlocks', () {
    test('subtracts hard blocks and ignores soft ones', () {
      final window = TimeSlot(start: at(0, 16), end: at(0, 20));
      final pieces = WeekTimelineEngine.subtractHardBlocks(window, [
        TimelineBlock(
            kind: TimelineBlockKind.commitment,
            start: at(0, 17),
            end: at(0, 18)),
        TimelineBlock(
            kind: TimelineBlockKind.rest,
            start: at(0, 19),
            end: at(0, 20),
            isHard: false),
      ]);
      expect(pieces, hasLength(2));
      expect(pieces[0].end, at(0, 17));
      expect(pieces[1].start, at(0, 18));
      expect(pieces[1].end, at(0, 20));
    });
  });

  group('compareWithActual', () {
    const engine = WeekTimelineEngine();
    final planned = [
      ScheduledChunk(taskId: 'on', start: at(0, 16), end: at(0, 17)),
      ScheduledChunk(taskId: 'over', start: at(0, 17), end: at(0, 18)),
      ScheduledChunk(taskId: 'short', start: at(0, 18), end: at(0, 19)),
      ScheduledChunk(taskId: 'miss', start: at(0, 19), end: at(0, 20)),
    ];
    final actual = [
      ActualSession(taskId: 'on', start: at(0, 16), end: at(0, 17, 3)),
      ActualSession(taskId: 'over', start: at(0, 17), end: at(0, 18, 30)),
      ActualSession(taskId: 'short', start: at(0, 18), end: at(0, 18, 20)),
      ActualSession(taskId: 'extra', start: at(0, 21), end: at(0, 21, 30)),
    ];

    test('classifies each task', () {
      final r = {
        for (final x
            in engine.compareWithActual(planned: planned, actual: actual))
          x.taskId: x
      };
      expect(r['on']!.status, RealityStatus.onTrack);
      expect(r['over']!.status, RealityStatus.overran);
      expect(r['over']!.deltaMinutes, 30);
      expect(r['short']!.status, RealityStatus.shortened);
      expect(r['short']!.deltaMinutes, -40);
      expect(r['miss']!.status, RealityStatus.missed);
      expect(r['miss']!.actualMinutes, 0);
      expect(r['extra']!.status, RealityStatus.unplanned);
      expect(r['extra']!.plannedMinutes, 0);
    });
  });

  group('diffChunks', () {
    test('reports added, removed, moved and resized tasks only', () {
      final before = [
        ScheduledChunk(taskId: 'same', start: at(0, 16), end: at(0, 17)),
        ScheduledChunk(taskId: 'gone', start: at(0, 17), end: at(0, 18)),
        ScheduledChunk(taskId: 'moved', start: at(0, 18), end: at(0, 19)),
        ScheduledChunk(taskId: 'size', start: at(0, 19), end: at(0, 20)),
      ];
      final after = [
        ScheduledChunk(taskId: 'same', start: at(0, 16), end: at(0, 17)),
        ScheduledChunk(taskId: 'moved', start: at(1, 16), end: at(1, 17)),
        ScheduledChunk(taskId: 'size', start: at(0, 19), end: at(0, 19, 30)),
        ScheduledChunk(taskId: 'new', start: at(0, 20), end: at(0, 21)),
      ];
      final changes = {
        for (final c in WeekTimelineEngine.diffChunks(before, after))
          c.taskId: c
      };
      expect(changes.keys.toSet(), {'gone', 'moved', 'size', 'new'});
      expect(changes['gone']!.kind, PlanChangeKind.removed);
      expect(changes['new']!.kind, PlanChangeKind.added);
      expect(changes['moved']!.kind, PlanChangeKind.moved);
      expect(changes['size']!.kind, PlanChangeKind.resized);
      expect(changes['size']!.minutesBefore, 60);
      expect(changes['size']!.minutesAfter, 30);
    });

    test('identical plans produce no changes', () {
      final p = [
        ScheduledChunk(taskId: 'a', start: at(0, 16), end: at(0, 17)),
      ];
      expect(WeekTimelineEngine.diffChunks(p, p), isEmpty);
    });
  });
}
