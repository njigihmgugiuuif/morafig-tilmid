/// Scheduling Engine — FOUNDATION LAYER.
///
/// Pure, dependency-free decision logic, no UI and no database access —
/// same status as priority_engine.dart's foundation layer. Takes a
/// priority-ordered list of items and a list of already-free time slots,
/// and fits items into slots. It does NOT compute priority (Priority ≠
/// Schedule — priority is an input, produced upstream by
/// priority_engine.dart) and it does NOT compute which windows are free
/// (that is reality_layer_domain.dart's job, this same cycle — it turns
/// Availabilities + RealityConstraints, including sleep/school/commute,
/// into the free `TimeSlot`s this engine receives).
///
/// CONTRACT for the two hard invariants this cycle calls out explicitly:
///   - "never break minimum sleep": this engine never allocates time
///     outside a slot it was given. It trusts that the caller's slots
///     already exclude sleep/school/commute/fixed-commitment windows.
///     Re-deriving that exclusion here would just be trusting the same
///     input twice under a different name — the actual enforcement lives
///     one layer down, in reality_layer_domain.dart.
///   - "never break prerequisite ordering": THIS is checked directly, in
///     code, right here — any item whose `prerequisiteSatisfied` is false
///     is refused a slot outright and reported as
///     UnscheduledReason.prerequisiteNotSatisfied, regardless of its
///     priority score. `prerequisiteSatisfied` is computed upstream by
///     knowledge_graph_domain.dart (this same cycle) from Prerequisites
///     edges; this engine does not walk the graph itself.
///
/// STATUS: UNVERIFIED — not run through a real Dart compiler/test runner
/// (no Flutter/Dart SDK in this environment). See
/// test/scheduling_engine_test.dart.
library scheduling_engine;

enum UnscheduledReason {
  /// No slot (or combination of slots, for a splittable item) had enough
  /// room anywhere in the horizon the caller supplied.
  noSlotAvailable,

  /// A splittable item was placed into some slots but not all of its
  /// duration could be fit — distinct from noSlotAvailable because SOME
  /// scheduling did happen (see SchedulingResult.chunksFor).
  partiallyScheduled,

  /// prerequisiteSatisfied was false. The item is high-priority-eligible
  /// but structurally cannot go first — this is exactly the "high
  /// priority but stays in the queue, with a clear reason" case the
  /// cycle's rules call out, just for a different root cause than "no
  /// time."
  prerequisiteNotSatisfied,
}

class SchedulableItem {
  const SchedulableItem({
    required this.taskId,
    required this.priorityScore,
    required this.totalDurationMinutes,
    required this.isSplittable,
    this.minimumChunkDurationMinutes,
    this.maximumChunkDurationMinutes,
    required this.prerequisiteSatisfied,
  })  : assert(priorityScore >= 0 && priorityScore <= 1),
        assert(totalDurationMinutes > 0);

  final String taskId;

  /// [0, 1], from priority_engine.dart. Determines placement ORDER only
  /// — it never overrides the prerequisite check or slot availability.
  final double priorityScore;
  final int totalDurationMinutes;

  /// Mirrors Tasks.isSplittable — atomic and splittable tasks are kept
  /// structurally distinct throughout this engine (this cycle's explicit
  /// requirement), never silently coerced into one another.
  final bool isSplittable;

  /// Only meaningful when isSplittable is true. Mirrors
  /// Tasks.minimumChunkDurationMinutes / maximumChunkDurationMinutes.
  final int? minimumChunkDurationMinutes;
  final int? maximumChunkDurationMinutes;

  final bool prerequisiteSatisfied;
}

class TimeSlot {
  TimeSlot({required this.start, required this.end})
      : assert(end.isAfter(start), 'A TimeSlot must have end after start.');

  final DateTime start;
  final DateTime end;

  int get durationMinutes => end.difference(start).inMinutes;
}

class ScheduledChunk {
  const ScheduledChunk({
    required this.taskId,
    required this.start,
    required this.end,
  });

  final String taskId;
  final DateTime start;
  final DateTime end;

  int get minutesAllocated => end.difference(start).inMinutes;
}

class UnscheduledEntry {
  const UnscheduledEntry({
    required this.taskId,
    required this.reason,
    this.minutesRemaining,
  });

  final String taskId;
  final UnscheduledReason reason;

  /// For partiallyScheduled only: how many of totalDurationMinutes are
  /// still unplaced.
  final int? minutesRemaining;
}

class SchedulingResult {
  const SchedulingResult({
    required this.scheduledChunks,
    required this.unscheduledQueue,
  });

  final List<ScheduledChunk> scheduledChunks;

  /// Every item that did not get its full duration placed, each with an
  /// explicit reason — nothing is ever silently dropped. This IS the
  /// "stays in unscheduledQueue with a clear reason" behavior the cycle's
  /// rules require for high-priority-but-no-time items.
  final List<UnscheduledEntry> unscheduledQueue;

  List<ScheduledChunk> chunksFor(String taskId) =>
      scheduledChunks.where((c) => c.taskId == taskId).toList();
}

class SchedulingEngine {
  const SchedulingEngine({this.defaultMinimumChunkMinutes = 15});

  /// Used only when a splittable item's own minimumChunkDurationMinutes
  /// is null. INITIAL HEURISTIC, same status as every other constant in
  /// this codebase.
  final int defaultMinimumChunkMinutes;

  /// Items are placed in the order given — the caller (Track D) is
  /// responsible for sorting by priorityScore descending (and for any
  /// tie-breaking policy); this engine does not re-sort, so its behavior
  /// is fully deterministic and traceable from the input order alone.
  SchedulingResult schedule({
    required List<SchedulableItem> orderedItems,
    required List<TimeSlot> availableSlots,
  }) {
    // Work on a mutable copy of slots, sorted chronologically, each
    // tracked as a shrinkable window from a cursor (inclusive) to the
    // slot's end (exclusive).
    final slots = [...availableSlots]..sort((a, b) => a.start.compareTo(b.start));
    final cursors = slots.map((s) => s.start).toList(growable: false);

    final chunks = <ScheduledChunk>[];
    final unscheduled = <UnscheduledEntry>[];

    for (final item in orderedItems) {
      if (!item.prerequisiteSatisfied) {
        unscheduled.add(UnscheduledEntry(
          taskId: item.taskId,
          reason: UnscheduledReason.prerequisiteNotSatisfied,
        ));
        continue;
      }

      if (!item.isSplittable) {
        final placed = _placeAtomic(item, slots, cursors, chunks);
        if (!placed) {
          unscheduled.add(UnscheduledEntry(
            taskId: item.taskId,
            reason: UnscheduledReason.noSlotAvailable,
          ));
        }
        continue;
      }

      final remaining = _placeSplittable(item, slots, cursors, chunks);
      if (remaining == item.totalDurationMinutes) {
        unscheduled.add(UnscheduledEntry(
          taskId: item.taskId,
          reason: UnscheduledReason.noSlotAvailable,
        ));
      } else if (remaining > 0) {
        unscheduled.add(UnscheduledEntry(
          taskId: item.taskId,
          reason: UnscheduledReason.partiallyScheduled,
          minutesRemaining: remaining,
        ));
      }
    }

    return SchedulingResult(
      scheduledChunks: chunks,
      unscheduledQueue: unscheduled,
    );
  }

  bool _placeAtomic(
    SchedulableItem item,
    List<TimeSlot> slots,
    List<DateTime> cursors,
    List<ScheduledChunk> chunks,
  ) {
    for (var i = 0; i < slots.length; i++) {
      final remainingMinutes = slots[i].end.difference(cursors[i]).inMinutes;
      if (remainingMinutes >= item.totalDurationMinutes) {
        final start = cursors[i];
        final end = start.add(Duration(minutes: item.totalDurationMinutes));
        chunks.add(ScheduledChunk(taskId: item.taskId, start: start, end: end));
        cursors[i] = end;
        return true;
      }
    }
    return false;
  }

  /// Returns minutes still unplaced (0 if the whole item fit).
  int _placeSplittable(
    SchedulableItem item,
    List<TimeSlot> slots,
    List<DateTime> cursors,
    List<ScheduledChunk> chunks,
  ) {
    final minChunk =
        item.minimumChunkDurationMinutes ?? defaultMinimumChunkMinutes;
    var remaining = item.totalDurationMinutes;

    for (var i = 0; i < slots.length && remaining > 0; i++) {
      final availableInSlot = slots[i].end.difference(cursors[i]).inMinutes;
      if (availableInSlot < minChunk) continue;

      var allocation = availableInSlot < remaining ? availableInSlot : remaining;
      if (item.maximumChunkDurationMinutes != null &&
          allocation > item.maximumChunkDurationMinutes!) {
        allocation = item.maximumChunkDurationMinutes!;
      }
      if (allocation < minChunk) continue;

      final start = cursors[i];
      final end = start.add(Duration(minutes: allocation));
      chunks.add(ScheduledChunk(taskId: item.taskId, start: start, end: end));
      cursors[i] = end;
      remaining -= allocation;
    }

    return remaining;
  }
}
