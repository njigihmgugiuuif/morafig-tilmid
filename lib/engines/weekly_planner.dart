/// Weekly Planner — the pure orchestration step that makes the Weekly
/// Timeline a LIVE plan instead of a static table:
///
///   study windows (student-declared)
///     - hard fixed blocks (school, commute, sleep, commitments, exams...)
///     = free study slots
///   -> SchedulingEngine.schedule(priority-ordered items, free slots)
///   -> WeekTimelineEngine.build(...)          (the 7-day timeline)
///   -> GapDetectionEngine.detect(...)         (what is wrong or wasted)
///
/// and, when reality changes (less time, a new task, a missed task, a moved
/// exam...), [WeeklyPlanner.replan] runs the same pipeline on the new inputs
/// and returns the new plan together with a [ReplanExplanation]: the cause,
/// the exact changes per task, and the findings that remain. Nothing is
/// re-planned "randomly": same inputs always give the same plan.
///
/// What it deliberately does NOT do (kept for later phases so no layer is
/// faked): read the database (a service will feed it from the repositories),
/// compute priorities (priority_engine.dart does, upstream), or apply
/// Recovery / Emergency policies (those engines will wrap this planner).
///
/// The past is never rewritten: when [notBefore] is given, nothing is placed
/// before it, and the "before" side of the explanation only includes chunks
/// that start at or after it. Callers pass only the REMAINING items.
///
/// STATUS: UNVERIFIED locally — not compiled or run in the authoring
/// environment. Verified only by GitHub Actions.
/// See test/weekly_planner_test.dart.
import 'gap_detection_engine.dart';
import 'scheduling_engine.dart';
import 'weekly_timeline_engine.dart';

/// Why a replan happened. Stored/explained by the caller; the planner only
/// carries it through so every new plan has a cause.
enum ReplanReason {
  availabilityChanged,
  taskAdded,
  taskRemoved,
  taskNotCompleted,
  taskFinishedEarly,
  taskFinishedLate,
  examChanged,
  scheduleChanged,
  fatigue,
  emergency,
  manual,
}

class WeekPlan {
  const WeekPlan({
    required this.weekStart,
    required this.freeSlots,
    required this.scheduling,
    required this.timeline,
    required this.gaps,
  });

  final DateTime weekStart;

  /// Study slots that were offered to the scheduler (after subtracting
  /// hard fixed blocks and anything before `notBefore`).
  final List<TimeSlot> freeSlots;
  final SchedulingResult scheduling;
  final WeekTimeline timeline;
  final List<GapFinding> gaps;
}

class ReplanExplanation {
  const ReplanExplanation({
    required this.reason,
    required this.detail,
    required this.changes,
    required this.remainingGaps,
  });

  final ReplanReason reason;

  /// Free text or code from the caller (e.g. `available 135 -> 50 minutes`).
  final String detail;
  final List<PlanChange> changes;
  final List<GapFinding> remainingGaps;

  bool get changedAnything => changes.isNotEmpty;
}

class ReplanResult {
  const ReplanResult({required this.plan, required this.explanation});
  final WeekPlan plan;
  final ReplanExplanation explanation;
}

class WeeklyPlanner {
  const WeeklyPlanner({
    this.scheduler = const SchedulingEngine(),
    this.timelineEngine = const WeekTimelineEngine(),
    this.gapEngine = const GapDetectionEngine(),
  });

  final SchedulingEngine scheduler;
  final WeekTimelineEngine timelineEngine;
  final GapDetectionEngine gapEngine;

  WeekPlan plan({
    required DateTime weekStart,
    required List<TimeSlot> studyWindows,
    required List<TimelineBlock> fixedBlocks,
    required List<SchedulableItem> orderedItems,
    DateTime? notBefore,
    DateTime? now,
    Map<String, String> taskLabels = const {},
    List<TimelineMarker> markers = const [],
    GapDetectionConfig gapConfig = const GapDetectionConfig(),
  }) {
    final start = WeekCalendar.startOfWeek(weekStart);
    final end = WeekCalendar.endOfWeek(start);
    final floor =
        (notBefore != null && notBefore.isAfter(start)) ? notBefore : start;

    // 1. Free study slots = windows clipped to [floor, end) minus hard blocks.
    final freeSlots = <TimeSlot>[];
    for (final w in studyWindows) {
      final s = w.start.isAfter(floor) ? w.start : floor;
      final e = w.end.isBefore(end) ? w.end : end;
      if (!e.isAfter(s)) continue;
      freeSlots.addAll(WeekTimelineEngine.subtractHardBlocks(
        TimeSlot(start: s, end: e),
        fixedBlocks,
      ));
    }
    freeSlots.sort((a, b) => a.start.compareTo(b.start));

    // 2. Schedule in the caller's priority order.
    final scheduling = scheduler.schedule(
      orderedItems: orderedItems,
      availableSlots: freeSlots,
    );

    // 3. Build the 7-day timeline.
    final timeline = timelineEngine.build(
      weekStart: start,
      fixedBlocks: fixedBlocks,
      chunks: scheduling.scheduledChunks,
      studySlots: freeSlots,
      taskLabels: taskLabels,
      markers: markers,
    );

    // 4. Detect gaps.
    final gaps = gapEngine.detect(
      timeline: timeline,
      scheduling: scheduling,
      items: orderedItems,
      now: now ?? floor,
      config: gapConfig,
    );

    return WeekPlan(
      weekStart: start,
      freeSlots: freeSlots,
      scheduling: scheduling,
      timeline: timeline,
      gaps: gaps,
    );
  }

  /// Re-runs the pipeline on the changed inputs and explains the effect.
  /// The new inputs are passed in full (not patched) so the result is a pure
  /// function of them.
  ReplanResult replan({
    required WeekPlan previous,
    required ReplanReason reason,
    required String detail,
    required List<TimeSlot> studyWindows,
    required List<TimelineBlock> fixedBlocks,
    required List<SchedulableItem> orderedItems,
    DateTime? notBefore,
    DateTime? now,
    Map<String, String> taskLabels = const {},
    List<TimelineMarker> markers = const [],
    GapDetectionConfig gapConfig = const GapDetectionConfig(),
  }) {
    final next = plan(
      weekStart: previous.weekStart,
      studyWindows: studyWindows,
      fixedBlocks: fixedBlocks,
      orderedItems: orderedItems,
      notBefore: notBefore,
      now: now,
      taskLabels: taskLabels,
      markers: markers,
      gapConfig: gapConfig,
    );

    // Only compare the part of the old plan that is still in the future:
    // the past is not part of the change.
    final floor = notBefore;
    final List<ScheduledChunk> before;
    if (floor == null) {
      before = previous.scheduling.scheduledChunks;
    } else {
      before = previous.scheduling.scheduledChunks
          .where((c) => !c.start.isBefore(floor))
          .toList();
    }

    final changes = WeekTimelineEngine.diffChunks(
      before,
      next.scheduling.scheduledChunks,
    );

    return ReplanResult(
      plan: next,
      explanation: ReplanExplanation(
        reason: reason,
        detail: detail,
        changes: changes,
        remainingGaps: next.gaps,
      ),
    );
  }
}
