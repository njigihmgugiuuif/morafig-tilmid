/// Weekly Timeline Engine — pure decision logic, no UI, no database.
///
/// Turns (a) the student's fixed week (school, commute, sleep, rest, meals,
/// commitments, extra classes, exams — all entered by the student) and
/// (b) the chunks produced by scheduling_engine.dart into a real, day-by-day
/// timeline for the whole week, and can compare that plan against what the
/// student actually did.
///
/// WEEK CONVENTION (mandatory product decision, see DEVIATIONS.md,
/// DEVIATION-16): a week starts on SUNDAY and ends on Saturday. This is a
/// *boundary / ordering* convention only. Stored day numbers elsewhere in
/// the project (Availabilities.dayOfWeek, WeeklyTemplateEntries.dayOfWeek)
/// keep Dart's native numbering (1 = Monday ... 7 = Sunday) so nothing
/// already stored changes meaning. [WeekCalendar] is the single place that
/// translates between the two.
///
/// This file never invents a school timetable: every fixed block comes from
/// the caller (user input or a documented source).
///
/// STATUS: UNVERIFIED locally — not compiled or run in the authoring
/// environment (no Flutter/Dart SDK). Verified only by GitHub Actions.
/// See test/weekly_timeline_engine_test.dart.
import 'scheduling_engine.dart';

/// Sunday-first week arithmetic. Uses calendar-field construction
/// (DateTime(y, m, d + n)) instead of adding Durations so that daylight
/// saving changes cannot shift a day boundary.
class WeekCalendar {
  const WeekCalendar._();

  /// Arabic day names indexed by [indexInWeek] (0 = Sunday ... 6 = Saturday).
  static const List<String> arabicDayNames = [
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
  ];

  /// 0 = Sunday, 1 = Monday ... 6 = Saturday.
  static int indexInWeek(DateTime d) => d.weekday % 7;

  // ---- Stored day number <-> Sunday-first index -------------------------
  // The database stores day-of-week as Dart's native weekday (1 = Monday ...
  // 7 = Sunday; DEVIATION-7/16) so no old row changes meaning. The product
  // week is Sunday-first (index 0 = Sunday ... 6 = Saturday). These three
  // functions are the ONLY official conversion between the two; code that
  // needs a stored day compared with a date must go through them instead of
  // re-deriving `% 7` or `weekday` by hand.

  /// True if [stored] is a valid stored day number (1..7).
  static bool isValidStoredDay(int stored) => stored >= 1 && stored <= 7;

  /// Stored day (1 = Monday ... 7 = Sunday) -> Sunday-first index
  /// (Sunday = 0 ... Saturday = 6). Throws on a value outside 1..7.
  static int indexFromStoredDay(int stored) {
    if (!isValidStoredDay(stored)) {
      throw RangeError.range(stored, 1, 7, 'stored day of week');
    }
    return stored % 7;
  }

  /// Sunday-first index (0..6) -> stored day (1..7). Throws outside 0..6.
  static int storedDayFromIndex(int index) {
    if (index < 0 || index > 6) {
      throw RangeError.range(index, 0, 6, 'week index');
    }
    return index == 0 ? 7 : index;
  }

  /// The stored day number of a date (same as Dart's `weekday`).
  static int storedDayOf(DateTime d) => storedDayFromIndex(indexInWeek(d));

  /// True when a nullable stored day (as found in a database row) falls on
  /// the same weekday as [date]. Null or out-of-range values never match
  /// (they are ignored, not an error, exactly like before this helper).
  static bool storedDayMatches(int? stored, DateTime date) {
    if (stored == null || !isValidStoredDay(stored)) return false;
    return indexFromStoredDay(stored) == indexInWeek(date);
  }

  /// Calendar-field day arithmetic (no Duration, so a DST change cannot
  /// shift a day boundary).
  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// Midnight (local) of the Sunday that starts the week containing [d].
  static DateTime startOfWeek(DateTime d) {
    return DateTime(d.year, d.month, d.day - indexInWeek(d));
  }

  /// The seven midnights of the week that starts at [weekStart]
  /// (normalized to Sunday first).
  static List<DateTime> daysOf(DateTime weekStart) {
    final s = startOfWeek(weekStart);
    return List<DateTime>.generate(
      7,
      (i) => DateTime(s.year, s.month, s.day + i),
      growable: false,
    );
  }

  /// Exclusive end of the week (the next Sunday at midnight).
  static DateTime endOfWeek(DateTime weekStart) {
    final s = startOfWeek(weekStart);
    return DateTime(s.year, s.month, s.day + 7);
  }
}

enum TimelineBlockKind {
  school,
  commute,
  sleep,
  rest,
  meal,
  commitment,
  activity,
  extraClass,
  unexpected,
  exam,

  /// A chunk placed by scheduling_engine.dart.
  study,
}

/// Kinds a student may put in a recurring weekly template. `exam` comes
/// from the Exams table and `study` from the scheduler, never from here.
const Set<TimelineBlockKind> kTemplateKinds = {
  TimelineBlockKind.school,
  TimelineBlockKind.commute,
  TimelineBlockKind.sleep,
  TimelineBlockKind.rest,
  TimelineBlockKind.meal,
  TimelineBlockKind.commitment,
  TimelineBlockKind.activity,
  TimelineBlockKind.extraClass,
};

class TimelineBlock {
  TimelineBlock({
    required this.kind,
    required this.start,
    required this.end,
    this.label,
    this.refId,
    this.isHard = true,
  }) : assert(end.isAfter(start), 'A TimelineBlock must have end after start.');

  final TimelineBlockKind kind;
  final DateTime start;
  final DateTime end;
  final String? label;

  /// Task id for study blocks, source row id for fixed blocks.
  final String? refId;

  /// Hard blocks cannot overlap each other (an overlap is a conflict).
  /// Soft blocks ("would rather not") never create conflicts.
  final bool isHard;

  int get durationMinutes => end.difference(start).inMinutes;

  /// True for everything except scheduler-placed study blocks.
  bool get isFixed => kind != TimelineBlockKind.study;
}

/// A point in time the plan must respect (task/assignment/exam deadline).
class TimelineMarker {
  const TimelineMarker({
    required this.at,
    required this.refId,
    this.label,
    this.isHard = true,
  });

  final DateTime at;
  final String refId;
  final String? label;
  final bool isHard;
}

/// One entry of the recurring weekly template (the student's real school
/// timetable, sleep window, etc.). `dayOfWeek` uses Dart's numbering
/// (1 = Monday ... 7 = Sunday). `endMinutes` may exceed 1440 for a block
/// that runs past midnight (e.g. sleep 22:00 -> 06:00 = 1320 -> 1800).
class WeeklyTemplateSlot {
  WeeklyTemplateSlot({
    required this.dayOfWeek,
    required this.startMinutes,
    required this.endMinutes,
    required this.kind,
    this.label,
    this.refId,
    this.isHard = true,
  })  : assert(dayOfWeek >= 1 && dayOfWeek <= 7),
        assert(startMinutes >= 0 && startMinutes < 1440),
        assert(endMinutes > startMinutes && endMinutes <= 2880);

  final int dayOfWeek;
  final int startMinutes;
  final int endMinutes;
  final TimelineBlockKind kind;
  final String? label;
  final String? refId;
  final bool isHard;
}

class BlockConflict {
  const BlockConflict({required this.a, required this.b});
  final TimelineBlock a;
  final TimelineBlock b;

  /// Minutes the two blocks overlap.
  int get overlapMinutes {
    final s = a.start.isAfter(b.start) ? a.start : b.start;
    final e = a.end.isBefore(b.end) ? a.end : b.end;
    return e.difference(s).inMinutes;
  }
}

class DayTimeline {
  const DayTimeline({
    required this.date,
    required this.blocks,
    required this.freeGaps,
    required this.freeStudySlots,
    required this.studyCapacityMinutes,
    required this.scheduledStudyMinutes,
    required this.conflicts,
  });

  /// Midnight of this day.
  final DateTime date;

  /// Blocks clipped to this day, sorted by start. A block that crosses
  /// midnight appears (clipped) in both days.
  final List<TimelineBlock> blocks;

  /// Minutes of the day covered by no block at all.
  final List<TimeSlot> freeGaps;

  /// Study-capable slots (declared study windows net of hard fixed blocks)
  /// still unused after scheduling.
  final List<TimeSlot> freeStudySlots;

  /// Study-capable minutes before scheduling.
  final int studyCapacityMinutes;
  final int scheduledStudyMinutes;
  final List<BlockConflict> conflicts;

  int get freeMinutes => freeGaps.fold(0, (s, g) => s + g.durationMinutes);
  int get freeStudyMinutes =>
      freeStudySlots.fold(0, (s, g) => s + g.durationMinutes);
  int get dayIndex => WeekCalendar.indexInWeek(date);
  String get dayNameAr => WeekCalendar.arabicDayNames[dayIndex];
}

class WeekTimeline {
  const WeekTimeline({
    required this.weekStart,
    required this.days,
    required this.markers,
  });

  /// Sunday midnight.
  final DateTime weekStart;

  /// Always 7 entries, Sunday first.
  final List<DayTimeline> days;
  final List<TimelineMarker> markers;

  List<BlockConflict> get conflicts =>
      [for (final d in days) ...d.conflicts];

  int get scheduledStudyMinutes =>
      days.fold(0, (s, d) => s + d.scheduledStudyMinutes);
  int get studyCapacityMinutes =>
      days.fold(0, (s, d) => s + d.studyCapacityMinutes);
  int get freeStudyMinutes => days.fold(0, (s, d) => s + d.freeStudyMinutes);

  DayTimeline dayFor(DateTime date) {
    final idx = WeekCalendar.indexInWeek(date);
    final d = days[idx];
    final same = d.date.year == date.year &&
        d.date.month == date.month &&
        d.date.day == date.day;
    if (!same) {
      throw ArgumentError('$date is outside the week starting $weekStart.');
    }
    return d;
  }
}

enum RealityStatus {
  /// Actual time within tolerance of planned time.
  onTrack,

  /// Did noticeably more than planned.
  overran,

  /// Did noticeably less than planned (but not nothing).
  shortened,

  /// Planned but no actual time recorded.
  missed,

  /// Actual time recorded for a task that had no plan.
  unplanned,
}

class ActualSession {
  ActualSession({
    required this.taskId,
    required this.start,
    required this.end,
  }) : assert(end.isAfter(start));
  final String taskId;
  final DateTime start;
  final DateTime end;
  int get minutes => end.difference(start).inMinutes;
}

class TaskReality {
  const TaskReality({
    required this.taskId,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.status,
  });
  final String taskId;
  final int plannedMinutes;
  final int actualMinutes;
  final RealityStatus status;
  int get deltaMinutes => actualMinutes - plannedMinutes;
}

enum PlanChangeKind { added, removed, moved, resized }

class PlanChange {
  const PlanChange({
    required this.taskId,
    required this.kind,
    required this.minutesBefore,
    required this.minutesAfter,
    this.firstStartBefore,
    this.firstStartAfter,
  });
  final String taskId;
  final PlanChangeKind kind;
  final int minutesBefore;
  final int minutesAfter;
  final DateTime? firstStartBefore;
  final DateTime? firstStartAfter;
}

class WeekTimelineEngine {
  const WeekTimelineEngine();

  /// Expands the recurring template into dated blocks for one concrete week.
  static List<TimelineBlock> expandTemplate({
    required DateTime weekStart,
    required List<WeeklyTemplateSlot> slots,
  }) {
    final s = WeekCalendar.startOfWeek(weekStart);
    final out = <TimelineBlock>[];
    for (final slot in slots) {
      final idx = WeekCalendar.indexFromStoredDay(slot.dayOfWeek);
      final y = s.year, m = s.month, d = s.day + idx;
      out.add(TimelineBlock(
        kind: slot.kind,
        // Minutes are passed as the minute field and normalized by DateTime,
        // so 1800 minutes = 06:00 the next day, in wall-clock terms.
        start: DateTime(y, m, d, 0, slot.startMinutes),
        end: DateTime(y, m, d, 0, slot.endMinutes),
        label: slot.label,
        refId: slot.refId,
        isHard: slot.isHard,
      ));
      // A recurring slot that crosses midnight (endMinutes > 1440) also
      // spills into the next day. For a Saturday slot that next day is the
      // NEXT week's Sunday, but the previous week's instance (shifted -7
      // days) spills into THIS week's Sunday morning: emit that carry-in.
      if (slot.endMinutes > 1440) {
        final carryEnd = DateTime(y, m, d - 7, 0, slot.endMinutes);
        if (carryEnd.isAfter(s)) {
          out.add(TimelineBlock(
            kind: slot.kind,
            start: DateTime(y, m, d - 7, 0, slot.startMinutes),
            end: carryEnd,
            label: slot.label,
            refId: slot.refId,
            isHard: slot.isHard,
          ));
        }
      }
    }
    return out;
  }

  /// Removes from [window] every interval covered by a HARD block.
  /// Soft blocks never remove time (same rule as reality_layer_domain.dart).
  static List<TimeSlot> subtractHardBlocks(
    TimeSlot window,
    List<TimelineBlock> blocks,
  ) {
    var pieces = <TimeSlot>[window];
    for (final b in blocks.where((b) => b.isHard)) {
      final next = <TimeSlot>[];
      for (final p in pieces) {
        next.addAll(_subtract(p, b.start, b.end));
      }
      pieces = next;
    }
    return pieces;
  }

  WeekTimeline build({
    required DateTime weekStart,
    required List<TimelineBlock> fixedBlocks,
    required List<ScheduledChunk> chunks,
    List<TimeSlot> studySlots = const [],
    Map<String, String> taskLabels = const {},
    List<TimelineMarker> markers = const [],
  }) {
    final start = WeekCalendar.startOfWeek(weekStart);
    final studyBlocks = [
      for (final c in chunks)
        TimelineBlock(
          kind: TimelineBlockKind.study,
          start: c.start,
          end: c.end,
          label: taskLabels[c.taskId],
          refId: c.taskId,
        ),
    ];
    final all = [...fixedBlocks, ...studyBlocks];

    final days = <DayTimeline>[];
    for (var i = 0; i < 7; i++) {
      final dayStart = DateTime(start.year, start.month, start.day + i);
      final dayEnd = DateTime(start.year, start.month, start.day + i + 1);

      final dayBlocks = <TimelineBlock>[];
      for (final b in all) {
        final clipped = _clipBlock(b, dayStart, dayEnd);
        if (clipped != null) dayBlocks.add(clipped);
      }
      dayBlocks.sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.end.compareTo(b.end);
      });

      final conflicts = <BlockConflict>[];
      for (var x = 0; x < dayBlocks.length; x++) {
        for (var y = x + 1; y < dayBlocks.length; y++) {
          final a = dayBlocks[x];
          final b = dayBlocks[y];
          if (!a.isHard || !b.isHard) continue;
          if (a.end.isAfter(b.start) && b.end.isAfter(a.start)) {
            conflicts.add(BlockConflict(a: a, b: b));
          }
        }
      }

      final gaps = _gapsOf(dayBlocks, dayStart, dayEnd);

      var capacity = 0;
      final remaining = <TimeSlot>[];
      for (final s in studySlots) {
        final clipped = _clipSlot(s, dayStart, dayEnd);
        if (clipped == null) continue;
        capacity += clipped.durationMinutes;
        var pieces = <TimeSlot>[clipped];
        for (final sb
            in dayBlocks.where((b) => b.kind == TimelineBlockKind.study)) {
          final next = <TimeSlot>[];
          for (final p in pieces) {
            next.addAll(_subtract(p, sb.start, sb.end));
          }
          pieces = next;
        }
        remaining.addAll(pieces);
      }
      remaining.sort((a, b) => a.start.compareTo(b.start));

      final scheduled = dayBlocks
          .where((b) => b.kind == TimelineBlockKind.study)
          .fold<int>(0, (s, b) => s + b.durationMinutes);

      days.add(DayTimeline(
        date: dayStart,
        blocks: dayBlocks,
        freeGaps: gaps,
        freeStudySlots: remaining,
        studyCapacityMinutes: capacity,
        scheduledStudyMinutes: scheduled,
        conflicts: conflicts,
      ));
    }

    return WeekTimeline(weekStart: start, days: days, markers: markers);
  }

  /// Compares what was planned with what actually happened, per task.
  /// [tolerance] is the fraction of planned time that still counts as
  /// "on track" (default 10%). INITIAL HEURISTIC like every constant here.
  List<TaskReality> compareWithActual({
    required List<ScheduledChunk> planned,
    required List<ActualSession> actual,
    double tolerance = 0.10,
  }) {
    final plannedBy = <String, int>{};
    for (final c in planned) {
      plannedBy[c.taskId] = (plannedBy[c.taskId] ?? 0) + c.minutesAllocated;
    }
    final actualBy = <String, int>{};
    for (final a in actual) {
      actualBy[a.taskId] = (actualBy[a.taskId] ?? 0) + a.minutes;
    }
    final ids = <String>{...plannedBy.keys, ...actualBy.keys}.toList()..sort();

    final out = <TaskReality>[];
    for (final id in ids) {
      final p = plannedBy[id] ?? 0;
      final a = actualBy[id] ?? 0;
      final RealityStatus status;
      if (p == 0) {
        status = RealityStatus.unplanned;
      } else if (a == 0) {
        status = RealityStatus.missed;
      } else if ((a - p).abs() <= p * tolerance) {
        status = RealityStatus.onTrack;
      } else if (a > p) {
        status = RealityStatus.overran;
      } else {
        status = RealityStatus.shortened;
      }
      out.add(TaskReality(
        taskId: id,
        plannedMinutes: p,
        actualMinutes: a,
        status: status,
      ));
    }
    return out;
  }

  /// Per-task difference between two plans. Returns only tasks that
  /// changed. A task that kept its total minutes but starts elsewhere is
  /// `moved`; one whose total minutes changed is `resized`.
  static List<PlanChange> diffChunks(
    List<ScheduledChunk> before,
    List<ScheduledChunk> after,
  ) {
    Map<String, List<ScheduledChunk>> group(List<ScheduledChunk> l) {
      final m = <String, List<ScheduledChunk>>{};
      for (final c in l) {
        m.putIfAbsent(c.taskId, () => []).add(c);
      }
      for (final v in m.values) {
        v.sort((a, b) => a.start.compareTo(b.start));
      }
      return m;
    }

    int total(List<ScheduledChunk> l) =>
        l.fold(0, (s, c) => s + c.minutesAllocated);

    final b = group(before);
    final a = group(after);
    final ids = <String>{...b.keys, ...a.keys}.toList()..sort();
    final out = <PlanChange>[];

    for (final id in ids) {
      final bl = b[id];
      final al = a[id];
      if (bl == null && al != null) {
        out.add(PlanChange(
          taskId: id,
          kind: PlanChangeKind.added,
          minutesBefore: 0,
          minutesAfter: total(al),
          firstStartAfter: al.first.start,
        ));
      } else if (bl != null && al == null) {
        out.add(PlanChange(
          taskId: id,
          kind: PlanChangeKind.removed,
          minutesBefore: total(bl),
          minutesAfter: 0,
          firstStartBefore: bl.first.start,
        ));
      } else if (bl != null && al != null) {
        final tb = total(bl);
        final ta = total(al);
        if (tb != ta) {
          out.add(PlanChange(
            taskId: id,
            kind: PlanChangeKind.resized,
            minutesBefore: tb,
            minutesAfter: ta,
            firstStartBefore: bl.first.start,
            firstStartAfter: al.first.start,
          ));
        } else {
          var same = bl.length == al.length;
          if (same) {
            for (var i = 0; i < bl.length; i++) {
              if (bl[i].start != al[i].start || bl[i].end != al[i].end) {
                same = false;
                break;
              }
            }
          }
          if (!same) {
            out.add(PlanChange(
              taskId: id,
              kind: PlanChangeKind.moved,
              minutesBefore: tb,
              minutesAfter: ta,
              firstStartBefore: bl.first.start,
              firstStartAfter: al.first.start,
            ));
          }
        }
      }
    }
    return out;
  }

  // ---- private helpers -------------------------------------------------

  static TimelineBlock? _clipBlock(
    TimelineBlock b,
    DateTime dayStart,
    DateTime dayEnd,
  ) {
    final s = b.start.isAfter(dayStart) ? b.start : dayStart;
    final e = b.end.isBefore(dayEnd) ? b.end : dayEnd;
    if (!e.isAfter(s)) return null;
    return TimelineBlock(
      kind: b.kind,
      start: s,
      end: e,
      label: b.label,
      refId: b.refId,
      isHard: b.isHard,
    );
  }

  static TimeSlot? _clipSlot(TimeSlot t, DateTime dayStart, DateTime dayEnd) {
    final s = t.start.isAfter(dayStart) ? t.start : dayStart;
    final e = t.end.isBefore(dayEnd) ? t.end : dayEnd;
    if (!e.isAfter(s)) return null;
    return TimeSlot(start: s, end: e);
  }

  /// Slot minus the half-open interval [cutStart, cutEnd): 0, 1 or 2 pieces.
  static List<TimeSlot> _subtract(
    TimeSlot slot,
    DateTime cutStart,
    DateTime cutEnd,
  ) {
    if (!cutEnd.isAfter(slot.start) || !slot.end.isAfter(cutStart)) {
      return [slot];
    }
    final result = <TimeSlot>[];
    if (cutStart.isAfter(slot.start)) {
      result.add(TimeSlot(start: slot.start, end: cutStart));
    }
    if (slot.end.isAfter(cutEnd)) {
      result.add(TimeSlot(start: cutEnd, end: slot.end));
    }
    return result;
  }

  /// Gaps of [dayStart, dayEnd) not covered by any of the (sorted) blocks.
  static List<TimeSlot> _gapsOf(
    List<TimelineBlock> sortedBlocks,
    DateTime dayStart,
    DateTime dayEnd,
  ) {
    final gaps = <TimeSlot>[];
    var cursor = dayStart;
    for (final b in sortedBlocks) {
      if (b.start.isAfter(cursor)) {
        gaps.add(TimeSlot(start: cursor, end: b.start));
      }
      if (b.end.isAfter(cursor)) cursor = b.end;
    }
    if (dayEnd.isAfter(cursor)) {
      gaps.add(TimeSlot(start: cursor, end: dayEnd));
    }
    return gaps;
  }
}
