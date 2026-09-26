import 'package:test/test.dart';

import 'package:student_app/engines/scheduling_engine.dart';

/// STATUS: UNVERIFIED — not run through a real Dart test runner (no
/// Flutter/Dart SDK in this environment).
void main() {
  const engine = SchedulingEngine();
  final day = DateTime(2026, 9, 25, 8, 0);

  group('atomic tasks', () {
    test('an atomic task fits into a single slot large enough for it', () {
      final result = engine.schedule(
        orderedItems: [
          SchedulableItem(
            taskId: 't1',
            priorityScore: 0.9,
            totalDurationMinutes: 60,
            isSplittable: false,
            prerequisiteSatisfied: true,
          ),
        ],
        availableSlots: [
          TimeSlot(start: day, end: day.add(const Duration(minutes: 90))),
        ],
      );
      expect(result.unscheduledQueue, isEmpty);
      expect(result.chunksFor('t1').single.minutesAllocated, 60);
    });

    test('an atomic task that does not fit anywhere goes to '
        'unscheduledQueue with noSlotAvailable, never silently dropped',
        () {
      final result = engine.schedule(
        orderedItems: [
          SchedulableItem(
            taskId: 't1',
            priorityScore: 0.99,
            totalDurationMinutes: 120,
            isSplittable: false,
            prerequisiteSatisfied: true,
          ),
        ],
        availableSlots: [
          TimeSlot(start: day, end: day.add(const Duration(minutes: 30))),
        ],
      );
      expect(result.chunksFor('t1'), isEmpty);
      expect(result.unscheduledQueue.single.reason,
          UnscheduledReason.noSlotAvailable);
    });

    test('an atomic task never gets split across two slots, even when '
        'their combined capacity would fit it', () {
      final result = engine.schedule(
        orderedItems: [
          SchedulableItem(
            taskId: 't1',
            priorityScore: 0.9,
            totalDurationMinutes: 60,
            isSplittable: false,
            prerequisiteSatisfied: true,
          ),
        ],
        availableSlots: [
          TimeSlot(start: day, end: day.add(const Duration(minutes: 40))),
          TimeSlot(
              start: day.add(const Duration(hours: 2)),
              end: day.add(const Duration(hours: 2, minutes: 40))),
        ],
      );
      // 40 + 40 = 80 >= 60, but neither slot alone fits it, and it is
      // atomic, so it must be unscheduled rather than fragmented.
      expect(result.chunksFor('t1'), isEmpty);
      expect(result.unscheduledQueue.single.reason,
          UnscheduledReason.noSlotAvailable);
    });
  });

  group('splittable tasks', () {
    test('a splittable task can be spread across multiple slots', () {
      final result = engine.schedule(
        orderedItems: [
          SchedulableItem(
            taskId: 't1',
            priorityScore: 0.9,
            totalDurationMinutes: 60,
            isSplittable: true,
            minimumChunkDurationMinutes: 15,
            prerequisiteSatisfied: true,
          ),
        ],
        availableSlots: [
          TimeSlot(start: day, end: day.add(const Duration(minutes: 30))),
          TimeSlot(
              start: day.add(const Duration(hours: 2)),
              end: day.add(const Duration(hours: 2, minutes: 30))),
        ],
      );
      expect(result.unscheduledQueue, isEmpty);
      expect(result.chunksFor('t1'), hasLength(2));
      final total = result
          .chunksFor('t1')
          .fold<int>(0, (a, c) => a + c.minutesAllocated);
      expect(total, 60);
    });

    test('a splittable task that cannot be fully placed is reported '
        'partiallyScheduled with the exact remaining minutes', () {
      final result = engine.schedule(
        orderedItems: [
          SchedulableItem(
            taskId: 't1',
            priorityScore: 0.9,
            totalDurationMinutes: 100,
            isSplittable: true,
            minimumChunkDurationMinutes: 15,
            prerequisiteSatisfied: true,
          ),
        ],
        availableSlots: [
          TimeSlot(start: day, end: day.add(const Duration(minutes: 30))),
        ],
      );
      expect(result.chunksFor('t1').single.minutesAllocated, 30);
      final entry = result.unscheduledQueue.single;
      expect(entry.reason, UnscheduledReason.partiallyScheduled);
      expect(entry.minutesRemaining, 70);
    });

    test('a splittable task never allocates a chunk smaller than its '
        'minimumChunkDurationMinutes', () {
      final result = engine.schedule(
        orderedItems: [
          SchedulableItem(
            taskId: 't1',
            priorityScore: 0.9,
            totalDurationMinutes: 50,
            isSplittable: true,
            minimumChunkDurationMinutes: 30,
            prerequisiteSatisfied: true,
          ),
        ],
        availableSlots: [
          TimeSlot(start: day, end: day.add(const Duration(minutes: 35))),
          // Too small for a 30-min minimum chunk — must be skipped, not
          // given a tiny 10-minute sliver.
          TimeSlot(
              start: day.add(const Duration(hours: 2)),
              end: day.add(const Duration(hours: 2, minutes: 10))),
        ],
      );
      for (final c in result.chunksFor('t1')) {
        expect(c.minutesAllocated, greaterThanOrEqualTo(30));
      }
    });
  });

  group('prerequisite ordering', () {
    test('a task with prerequisiteSatisfied false is never scheduled, '
        'regardless of priority or slot availability', () {
      final result = engine.schedule(
        orderedItems: [
          SchedulableItem(
            taskId: 't1',
            priorityScore: 1.0,
            totalDurationMinutes: 10,
            isSplittable: false,
            prerequisiteSatisfied: false,
          ),
        ],
        availableSlots: [
          TimeSlot(start: day, end: day.add(const Duration(hours: 4))),
        ],
      );
      expect(result.chunksFor('t1'), isEmpty);
      expect(result.unscheduledQueue.single.reason,
          UnscheduledReason.prerequisiteNotSatisfied);
    });
  });

  group('ordering respects caller-supplied priority order', () {
    test('given two atomic tasks that together do not both fit, the '
        'FIRST item in orderedItems wins the available slot', () {
      final result = engine.schedule(
        orderedItems: [
          SchedulableItem(
            taskId: 'high',
            priorityScore: 0.9,
            totalDurationMinutes: 60,
            isSplittable: false,
            prerequisiteSatisfied: true,
          ),
          SchedulableItem(
            taskId: 'low',
            priorityScore: 0.1,
            totalDurationMinutes: 60,
            isSplittable: false,
            prerequisiteSatisfied: true,
          ),
        ],
        availableSlots: [
          TimeSlot(start: day, end: day.add(const Duration(minutes: 60))),
        ],
      );
      expect(result.chunksFor('high'), isNotEmpty);
      expect(result.chunksFor('low'), isEmpty);
      expect(
          result.unscheduledQueue.any((e) =>
              e.taskId == 'low' && e.reason == UnscheduledReason.noSlotAvailable),
          isTrue);
    });
  });
}
