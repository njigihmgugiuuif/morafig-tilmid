import 'package:test/test.dart';

import 'package:student_app/engines/gap_detection_engine.dart';
import 'package:student_app/engines/scheduling_engine.dart';
import 'package:student_app/engines/weekly_timeline_engine.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
void main() {
  final sunday = DateTime(2026, 9, 27);
  DateTime at(int dayOffset, int h, [int m = 0]) =>
      DateTime(2026, 9, 27 + dayOffset, h, m);

  const timelineEngine = WeekTimelineEngine();
  const gapEngine = GapDetectionEngine();
  const emptyResult =
      SchedulingResult(scheduledChunks: [], unscheduledQueue: []);

  SchedulableItem item(String id, int minutes,
          {bool splittable = false, bool prereq = true}) =>
      SchedulableItem(
        taskId: id,
        priorityScore: 0.5,
        totalDurationMinutes: minutes,
        isSplittable: splittable,
        prerequisiteSatisfied: prereq,
      );

  List<GapFinding> run({
    required WeekTimeline timeline,
    SchedulingResult scheduling = emptyResult,
    List<SchedulableItem> items = const [],
    DateTime? now,
    GapDetectionConfig config = const GapDetectionConfig(),
  }) =>
      gapEngine.detect(
        timeline: timeline,
        scheduling: scheduling,
        items: items,
        now: now ?? sunday,
        config: config,
      );

  Iterable<GapFinding> only(List<GapFinding> f, String code) =>
      f.where((x) => x.code == code);

  group('free time', () {
    test('a large unused study slot is reported as free_slot', () {
      final t = timelineEngine.build(
        weekStart: sunday,
        fixedBlocks: [],
        chunks: [],
        studySlots: [TimeSlot(start: at(0, 16), end: at(0, 18))],
      );
      final f = only(run(timeline: t), 'free_slot').toList();
      expect(f, hasLength(1));
      expect(f.single.minutes, 120);
      expect(f.single.severity, GapSeverity.info);
    });

    test('a slot shorter than the threshold is not reported', () {
      final t = timelineEngine.build(
        weekStart: sunday,
        fixedBlocks: [],
        chunks: [],
        studySlots: [TimeSlot(start: at(0, 16), end: at(0, 16, 20))],
      );
      expect(only(run(timeline: t), 'free_slot'), isEmpty);
    });
  });

  group('conflicts', () {
    test('overlapping hard blocks produce a critical conflict', () {
      final t = timelineEngine.build(
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
      final f = only(run(timeline: t), 'conflict_hard_blocks').toList();
      expect(f, hasLength(1));
      expect(f.single.severity, GapSeverity.critical);
      expect(f.single.minutes, 60);
    });
  });

  group('overload', () {
    WeekTimeline loaded(int chunkMinutes) => timelineEngine.build(
          weekStart: sunday,
          fixedBlocks: [],
          studySlots: [TimeSlot(start: at(0, 16), end: at(0, 17, 40))],
          chunks: [
            ScheduledChunk(
                taskId: 't',
                start: at(0, 16),
                end: at(0, 16).add(Duration(minutes: chunkMinutes))),
          ],
        );

    test('a day filled to 95% of capacity is flagged near capacity', () {
      final f = run(timeline: loaded(95));
      final o = only(f, 'overload_near_capacity').toList();
      expect(o, hasLength(1));
      expect(o.single.severity, GapSeverity.warning);
    });

    test('a day filled to 50% is not flagged', () {
      final f = run(timeline: loaded(50));
      expect(only(f, 'overload_near_capacity'), isEmpty);
    });

    test('an absolute daily limit is critical when exceeded', () {
      final f = run(
        timeline: loaded(95),
        config: const GapDetectionConfig(dailyStudyLimitMinutes: 60),
      );
      final o = only(f, 'overload_over_limit').toList();
      expect(o, hasLength(1));
      expect(o.single.minutes, 35);
      expect(o.single.severity, GapSeverity.critical);
    });
  });

  group('unplaced tasks and time shortage', () {
    final timeline = timelineEngine.build(
      weekStart: sunday,
      fixedBlocks: [],
      chunks: [],
      studySlots: [TimeSlot(start: at(0, 16), end: at(0, 17))],
    );

    test('noSlotAvailable and partiallyScheduled are reported with minutes',
        () {
      final f = run(
        timeline: timeline,
        items: [item('a', 90), item('b', 60, splittable: true)],
        scheduling: const SchedulingResult(
          scheduledChunks: [],
          unscheduledQueue: [
            UnscheduledEntry(
                taskId: 'a', reason: UnscheduledReason.noSlotAvailable),
            UnscheduledEntry(
                taskId: 'b',
                reason: UnscheduledReason.partiallyScheduled,
                minutesRemaining: 20),
          ],
        ),
      );
      expect(only(f, 'unplaced_no_slot').single.minutes, 90);
      expect(only(f, 'unplaced_partial').single.minutes, 20);
      expect(only(f, 'insufficient_time').single.minutes, 110);
    });

    test('a prerequisite-blocked task is info only and adds no missing time',
        () {
      final f = run(
        timeline: timeline,
        items: [item('p', 60, prereq: false)],
        scheduling: const SchedulingResult(
          scheduledChunks: [],
          unscheduledQueue: [
            UnscheduledEntry(
                taskId: 'p',
                reason: UnscheduledReason.prerequisiteNotSatisfied),
          ],
        ),
      );
      expect(
          only(f, 'unplaced_prerequisite').single.severity, GapSeverity.info);
      expect(only(f, 'insufficient_time'), isEmpty);
      expect(only(f, 'backlog'), isEmpty);
    });

    test('three time-related unplaced tasks make a backlog', () {
      final f = run(
        timeline: timeline,
        items: [item('a', 30), item('b', 30), item('c', 30)],
        scheduling: const SchedulingResult(
          scheduledChunks: [],
          unscheduledQueue: [
            UnscheduledEntry(
                taskId: 'a', reason: UnscheduledReason.noSlotAvailable),
            UnscheduledEntry(
                taskId: 'b', reason: UnscheduledReason.noSlotAvailable),
            UnscheduledEntry(
                taskId: 'c', reason: UnscheduledReason.noSlotAvailable),
          ],
        ),
      );
      expect(only(f, 'backlog'), hasLength(1));
    });

    test('free study time left while tasks are unplaced is called out', () {
      final f = run(
        timeline: timeline, // 60 free study minutes, nothing scheduled
        items: [item('a', 90)],
        scheduling: const SchedulingResult(
          scheduledChunks: [],
          unscheduledQueue: [
            UnscheduledEntry(
                taskId: 'a', reason: UnscheduledReason.noSlotAvailable),
          ],
        ),
      );
      expect(only(f, 'unused_while_backlog').single.minutes, 60);
    });
  });

  group('deadlines', () {
    WeekTimeline withMarker(TimelineMarker m, {List<ScheduledChunk>? chunks}) =>
        timelineEngine.build(
          weekStart: sunday,
          fixedBlocks: [],
          chunks: chunks ?? [],
          markers: [m],
        );

    const unplacedA = SchedulingResult(
      scheduledChunks: [],
      unscheduledQueue: [
        UnscheduledEntry(taskId: 'a', reason: UnscheduledReason.noSlotAvailable),
      ],
    );

    test('an unplaced task with a near hard deadline is critical', () {
      final marker = TimelineMarker(at: at(1, 8), refId: 'a');
      final f = run(
        timeline: withMarker(marker),
        items: [item('a', 60)],
        now: at(0, 20),
        scheduling: unplacedA,
      );
      final d = only(f, 'deadline_near_unplaced').single;
      expect(d.severity, GapSeverity.critical);
      expect(d.taskId, 'a');
    });

    test('a passed deadline with an unplaced task is reported as passed', () {
      final marker = TimelineMarker(at: at(0, 8), refId: 'a');
      final f = run(
        timeline: withMarker(marker),
        items: [item('a', 60)],
        now: at(0, 20),
        scheduling: unplacedA,
      );
      expect(only(f, 'deadline_passed_unplaced'), hasLength(1));
    });

    test('a far deadline is not flagged yet', () {
      final marker = TimelineMarker(at: at(6, 8), refId: 'a');
      final f = run(
        timeline: withMarker(marker),
        items: [item('a', 60)],
        now: at(0, 8),
        scheduling: unplacedA,
      );
      expect(only(f, 'deadline_near_unplaced'), isEmpty);
      expect(only(f, 'deadline_passed_unplaced'), isEmpty);
    });

    test('a task placed after its deadline is a late risk with the overrun',
        () {
      final marker = TimelineMarker(at: at(0, 17), refId: 'a');
      final chunks = [
        ScheduledChunk(taskId: 'a', start: at(0, 17), end: at(0, 18)),
      ];
      final f = run(
        timeline: withMarker(marker, chunks: chunks),
        items: [item('a', 60)],
        scheduling:
            SchedulingResult(scheduledChunks: chunks, unscheduledQueue: const []),
      );
      final l = only(f, 'placed_after_deadline').single;
      expect(l.minutes, 60);
      expect(l.severity, GapSeverity.critical);
    });

    test('a task placed before its deadline is fine', () {
      final marker = TimelineMarker(at: at(0, 20), refId: 'a');
      final chunks = [
        ScheduledChunk(taskId: 'a', start: at(0, 17), end: at(0, 18)),
      ];
      final f = run(
        timeline: withMarker(marker, chunks: chunks),
        items: [item('a', 60)],
        scheduling:
            SchedulingResult(scheduledChunks: chunks, unscheduledQueue: const []),
      );
      expect(only(f, 'placed_after_deadline'), isEmpty);
    });
  });

  group('ordering and descriptions', () {
    test('findings are sorted most severe first', () {
      final t = timelineEngine.build(
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
        studySlots: [TimeSlot(start: at(0, 16), end: at(0, 18))],
      );
      final f = run(timeline: t);
      expect(f.first.severity, GapSeverity.critical);
      expect(f.last.severity, GapSeverity.info);
    });

    test('every code the engine can emit has an Arabic description', () {
      const codes = [
        'conflict_hard_blocks',
        'unplaced_prerequisite',
        'unplaced_no_slot',
        'unplaced_partial',
        'insufficient_time',
        'backlog',
        'unused_while_backlog',
        'overload_over_limit',
        'overload_near_capacity',
        'free_slot',
        'deadline_near_unplaced',
        'deadline_passed_unplaced',
        'placed_after_deadline',
      ];
      for (final code in codes) {
        final text = GapDetectionEngine.describeAr(GapFinding(
          kind: GapKind.freeSlot,
          severity: GapSeverity.info,
          code: code,
          minutes: 5,
          details: const {'unplacedCount': 3, 'scheduled': 1, 'capacity': 2},
        ));
        expect(text, isNot(code), reason: 'no Arabic text for $code');
      }
    });

    test('an unknown code falls back to the code, never hides the finding',
        () {
      expect(
        GapDetectionEngine.describeAr(const GapFinding(
            kind: GapKind.freeSlot, severity: GapSeverity.info, code: 'zzz')),
        'zzz',
      );
    });
  });
}
