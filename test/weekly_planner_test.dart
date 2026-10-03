import 'package:test/test.dart';

import 'package:student_app/engines/scheduling_engine.dart';
import 'package:student_app/engines/weekly_planner.dart';
import 'package:student_app/engines/weekly_timeline_engine.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Central scenario: "math 60 / physics 45 / language 30 minutes, then less
/// time becomes available" -> the plan is recomputed, not kept.
void main() {
  final sunday = DateTime(2026, 9, 27);
  DateTime at(int dayOffset, int h, [int m = 0]) =>
      DateTime(2026, 9, 27 + dayOffset, h, m);

  SchedulableItem atomic(String id, int minutes, double score) =>
      SchedulableItem(
        taskId: id,
        priorityScore: score,
        totalDurationMinutes: minutes,
        isSplittable: false,
        prerequisiteSatisfied: true,
      );

  final items = [
    atomic('math', 60, 0.9),
    atomic('physics', 45, 0.7),
    atomic('language', 30, 0.5),
  ];

  const planner = WeeklyPlanner();

  group('plan', () {
    test('places all three tasks when 135 minutes are available', () {
      final p = planner.plan(
        weekStart: sunday,
        studyWindows: [TimeSlot(start: at(0, 16), end: at(0, 18, 15))],
        fixedBlocks: [],
        orderedItems: items,
      );
      expect(p.scheduling.unscheduledQueue, isEmpty);
      expect(p.scheduling.chunksFor('math').single.start, at(0, 16));
      expect(p.scheduling.chunksFor('physics').single.start, at(0, 17));
      expect(p.scheduling.chunksFor('language').single.start, at(0, 17, 45));
      expect(p.timeline.scheduledStudyMinutes, 135);
      expect(p.timeline.days.first.scheduledStudyMinutes, 135);
    });

    test('never places study time inside a hard fixed block', () {
      final school = TimelineBlock(
          kind: TimelineBlockKind.school, start: at(0, 16, 30), end: at(0, 17));
      final p = planner.plan(
        weekStart: sunday,
        studyWindows: [TimeSlot(start: at(0, 16), end: at(0, 18, 15))],
        fixedBlocks: [school],
        orderedItems: items,
      );
      for (final c in p.scheduling.scheduledChunks) {
        final overlaps =
            c.start.isBefore(school.end) && c.end.isAfter(school.start);
        expect(overlaps, isFalse, reason: '${c.taskId} overlaps school');
      }
      expect(p.timeline.conflicts, isEmpty);
    });

    test('nothing is placed before notBefore', () {
      final p = planner.plan(
        weekStart: sunday,
        studyWindows: [TimeSlot(start: at(0, 16), end: at(0, 18, 15))],
        fixedBlocks: [],
        orderedItems: items,
        notBefore: at(0, 17, 30),
      );
      for (final c in p.scheduling.scheduledChunks) {
        expect(c.start.isBefore(at(0, 17, 30)), isFalse);
      }
    });

    test('windows outside the week are ignored', () {
      final p = planner.plan(
        weekStart: sunday,
        studyWindows: [TimeSlot(start: at(8, 16), end: at(8, 18))],
        fixedBlocks: [],
        orderedItems: items,
      );
      expect(p.scheduling.scheduledChunks, isEmpty);
      expect(p.scheduling.unscheduledQueue, hasLength(3));
    });

    test('is deterministic: same inputs give the same plan', () {
      List<ScheduledChunk> run() => planner
          .plan(
            weekStart: sunday,
            studyWindows: [TimeSlot(start: at(0, 16), end: at(0, 18, 15))],
            fixedBlocks: [],
            orderedItems: items,
          )
          .scheduling
          .scheduledChunks;
      final a = run();
      final b = run();
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].taskId, b[i].taskId);
        expect(a[i].start, b[i].start);
        expect(a[i].end, b[i].end);
      }
    });

    test('a template-built week flows end to end', () {
      final fixed = WeekTimelineEngine.expandTemplate(
        weekStart: sunday,
        slots: [
          WeeklyTemplateSlot(
              dayOfWeek: 7,
              startMinutes: 8 * 60,
              endMinutes: 15 * 60,
              kind: TimelineBlockKind.school),
          WeeklyTemplateSlot(
              dayOfWeek: 7,
              startMinutes: 22 * 60,
              endMinutes: 30 * 60,
              kind: TimelineBlockKind.sleep),
        ],
      );
      final p = planner.plan(
        weekStart: sunday,
        studyWindows: [TimeSlot(start: at(0, 7), end: at(0, 22))],
        fixedBlocks: fixed,
        orderedItems: [atomic('math', 60, 0.9)],
      );
      final c = p.scheduling.chunksFor('math').single;
      // 07:00-08:00 is the first free run (school starts at 08:00).
      expect(c.start, at(0, 7));
      expect(p.timeline.days.first.blocks.map((b) => b.kind).toList(), [
        TimelineBlockKind.study,
        TimelineBlockKind.school,
        TimelineBlockKind.sleep,
      ]);
    });
  });

  group('replan: less available time (60 / 45 / 30 minutes)', () {
    final before = planner.plan(
      weekStart: sunday,
      studyWindows: [TimeSlot(start: at(0, 16), end: at(0, 18, 15))],
      fixedBlocks: [],
      orderedItems: items,
    );

    final result = planner.replan(
      previous: before,
      reason: ReplanReason.availabilityChanged,
      detail: 'available 135 -> 50 minutes',
      studyWindows: [TimeSlot(start: at(0, 16), end: at(0, 16, 50))],
      fixedBlocks: [],
      orderedItems: items,
    );

    test('the old plan is not kept: the new one differs', () {
      expect(result.explanation.changedAnything, isTrue);
      expect(result.plan.timeline.scheduledStudyMinutes, lessThan(135));
    });

    test('the reason and detail are carried into the explanation', () {
      expect(result.explanation.reason, ReplanReason.availabilityChanged);
      expect(result.explanation.detail, 'available 135 -> 50 minutes');
    });

    test('exactly what changed is listed per task', () {
      final byTask = {for (final c in result.explanation.changes) c.taskId: c};
      // 50 minutes: math (60, atomic) no longer fits; physics (45) fits and
      // moves earlier; language (30) has no room left.
      expect(byTask['math']!.kind, PlanChangeKind.removed);
      expect(byTask['math']!.minutesBefore, 60);
      expect(byTask['physics']!.kind, PlanChangeKind.moved);
      expect(byTask['physics']!.firstStartAfter, at(0, 16));
      expect(byTask['language']!.kind, PlanChangeKind.removed);
    });

    test('the new plan stays inside the 50 available minutes', () {
      for (final c in result.plan.scheduling.scheduledChunks) {
        expect(c.end.isAfter(at(0, 16, 50)), isFalse);
      }
    });

    test('the shortage is surfaced as gap findings', () {
      final codes =
          result.explanation.remainingGaps.map((g) => g.code).toSet();
      expect(codes, contains('unplaced_no_slot'));
      expect(codes, contains('insufficient_time'));
      final missing = result.explanation.remainingGaps
          .firstWhere((g) => g.code == 'insufficient_time');
      expect(missing.minutes, 90); // math 60 + language 30
    });
  });

  group('replan: new work, a past that must not change, a closer exam', () {
    test('adding a task places it only in the future and leaves the past out',
        () {
      final before = planner.plan(
        weekStart: sunday,
        studyWindows: [TimeSlot(start: at(0, 16), end: at(0, 20))],
        fixedBlocks: [],
        orderedItems: [atomic('math', 60, 0.9)], // placed 16:00-17:00
      );
      final r = planner.replan(
        previous: before,
        reason: ReplanReason.taskAdded,
        detail: 'new assignment',
        studyWindows: [TimeSlot(start: at(0, 16), end: at(0, 20))],
        fixedBlocks: [],
        // math is done (16:00-17:00 is in the past): only the new task is
        // still to be placed.
        orderedItems: [atomic('hw', 45, 0.8)],
        notBefore: at(0, 17),
      );
      final hw = r.plan.scheduling.chunksFor('hw').single;
      expect(hw.start, at(0, 17));
      expect(r.plan.scheduling.chunksFor('math'), isEmpty);
      final kinds = {for (final c in r.explanation.changes) c.taskId: c.kind};
      expect(kinds.keys.toSet(), {'hw'}); // the past (math) is not a change
      expect(kinds['hw'], PlanChangeKind.added);
    });

    test('an exam moving closer shows up as a deadline risk', () {
      final before = planner.plan(
        weekStart: sunday,
        studyWindows: [TimeSlot(start: at(0, 16), end: at(0, 17))],
        fixedBlocks: [],
        orderedItems: [atomic('review', 60, 0.9)],
        markers: [TimelineMarker(at: at(5, 9), refId: 'review')],
        now: at(0, 12),
      );
      expect(before.gaps.where((g) => g.code == 'deadline_near_unplaced'),
          isEmpty);

      final r = planner.replan(
        previous: before,
        reason: ReplanReason.examChanged,
        detail: 'exam moved to Monday 08:00',
        studyWindows: [TimeSlot(start: at(0, 16), end: at(0, 16, 30))],
        fixedBlocks: [],
        orderedItems: [atomic('review', 60, 0.9)],
        markers: [TimelineMarker(at: at(1, 8), refId: 'review')],
        now: at(0, 12),
      );
      final codes = r.explanation.remainingGaps.map((g) => g.code).toSet();
      expect(codes, contains('deadline_near_unplaced'));
      expect(r.explanation.reason, ReplanReason.examChanged);
    });
  });
}
