import 'dart:math' as math;

import '../../database/app_database.dart';
import '../../domain/reality_layer_domain.dart';
import '../../engines/scheduling_engine.dart' show TimeSlot;
import '../../engines/weekly_timeline_engine.dart';
import '../../repositories/availability_repository.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/exam_repository.dart';
import '../../repositories/reality_and_prerequisite_repositories.dart';
import '../../repositories/weekly_template_repository.dart';
import 'progress_insights.dart' show calendarDaysBetween, formatMinutes;

/// «الحمل قبل كل امتحان»: for each coming exam, the time the open tasks of
/// that subject still need next to the free study time left before the exam.
///
/// Only arithmetic on what the student entered and the planner already uses:
///  - needed = sum of `remainingDurationMinutes` of the subject's open tasks
///    (the estimates recorded on the tasks);
///  - available = the student's declared free windows (واقعي ← فراغي) from
///    now until the exam, minus hard constraints and the weekly template's
///    hard blocks (school, sleep, commitments).
/// No threshold decides "enough" or "not enough": the view only states which
/// number is larger and by how much. The free time is the same time for every
/// exam (it is not split between them), so rows must not be added together.
///
/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
class ExamLoadRow {
  const ExamLoadRow({
    required this.subjectName,
    required this.date,
    required this.daysAway,
    required this.neededMinutes,
    required this.availableMinutes,
    required this.openTasks,
  });

  final String subjectName;
  final DateTime date;
  final int daysAway;
  final int neededMinutes;
  final int availableMinutes;
  final int openTasks;

  /// Positive when the free time is larger than the needed time.
  int get gapMinutes => availableMinutes - neededMinutes;
}

class ExamLoadData {
  const ExamLoadData({required this.rows, required this.hasAvailability});
  final List<ExamLoadRow> rows;

  /// False when the student has not entered any free window at all.
  final bool hasAvailability;
}

class ExamLoadMath {
  const ExamLoadMath._();

  /// Free study minutes in [from, to): the windows (clipped, overlaps merged
  /// so no minute counts twice) minus every HARD block.
  static int freeMinutes({
    required List<TimeSlot> windows,
    required List<TimelineBlock> blocks,
    required DateTime from,
    required DateTime to,
  }) {
    if (!to.isAfter(from)) return 0;
    final clipped = <TimeSlot>[];
    for (final w in windows) {
      final s = w.start.isAfter(from) ? w.start : from;
      final e = w.end.isBefore(to) ? w.end : to;
      if (e.isAfter(s)) clipped.add(TimeSlot(start: s, end: e));
    }
    clipped.sort((a, b) => a.start.compareTo(b.start));
    final merged = <TimeSlot>[];
    for (final c in clipped) {
      if (merged.isNotEmpty && !c.start.isAfter(merged.last.end)) {
        final last = merged.removeLast();
        merged.add(TimeSlot(
            start: last.start,
            end: c.end.isAfter(last.end) ? c.end : last.end));
      } else {
        merged.add(c);
      }
    }
    var total = 0;
    for (final m in merged) {
      for (final piece in WeekTimelineEngine.subtractHardBlocks(m, blocks)) {
        total += piece.durationMinutes;
      }
    }
    return total;
  }

  /// One plain Arabic sentence that only states the two numbers and which is
  /// larger.
  static String summaryFor({
    required int needed,
    required int available,
    required bool hasAvailability,
    required int openTasks,
  }) {
    if (openTasks == 0 || needed <= 0) {
      return 'لا مهام مفتوحة لهذه المادة.';
    }
    if (!hasAvailability) {
      return 'المطلوب ${formatMinutes(needed)}. لم تُدخل أوقات فراغك بعد، فلا نعرف المتاح.';
    }
    if (available <= 0) {
      return 'المطلوب ${formatMinutes(needed)} ولا وقت فراغ متاح قبل الامتحان.';
    }
    final gap = available - needed;
    if (gap >= 0) {
      return 'المتاح ${formatMinutes(available)} والمطلوب ${formatMinutes(needed)}: '
          'يزيد المتاح بـ ${formatMinutes(gap)}.';
    }
    return 'المتاح ${formatMinutes(available)} والمطلوب ${formatMinutes(needed)}: '
        'ينقص المتاح ${formatMinutes(-gap)}.';
  }
}

class ExamLoadReader {
  ExamLoadReader(this._db);
  final AppDatabase _db;

  Future<ExamLoadData> read(String studentId, DateTime now,
      {int maxExams = 6}) async {
    final exams = (await ExamRepository(_db).readUpcoming(now: now.toUtc()))
        .take(maxExams)
        .toList();
    final availabilities =
        await AvailabilityRepository(_db).readForStudent(studentId);
    final hasAvailability = availabilities.isNotEmpty;
    if (exams.isEmpty) {
      return ExamLoadData(rows: const [], hasAvailability: hasAvailability);
    }

    // What the open tasks of each subject still need.
    final tasks = await _db.select(_db.tasks).get();
    final content = ContentRepository(_db);
    final needed = <String, int>{};
    final open = <String, int>{};
    for (final t in tasks) {
      if (t.completionStatus == 'complete') continue;
      final id = await content.subjectIdForNode(t.knowledgeNodeId);
      if (id == null) continue;
      needed[id] = (needed[id] ?? 0) + math.max(0, t.remainingDurationMinutes);
      open[id] = (open[id] ?? 0) + 1;
    }

    // Free windows and fixed blocks up to the last exam shown.
    final local = now.toLocal();
    var last = exams.last.examDate.toLocal();
    if (!last.isAfter(local)) last = local.add(const Duration(minutes: 1));
    final windows = hasAvailability
        ? await RealityLayerDomainService(
            AvailabilityRepository(_db),
            RealityConstraintRepository(_db),
          ).computeFreeSlots(
            studentId: studentId, rangeStart: local, rangeEnd: last)
        : <TimeSlot>[];
    final templates =
        await WeeklyTemplateRepository(_db).readSlotsForStudent(studentId);
    final blocks = <TimelineBlock>[];
    for (var w = WeekCalendar.startOfWeek(local);
        w.isBefore(last);
        w = WeekCalendar.addDays(w, 7)) {
      blocks.addAll(
          WeekTimelineEngine.expandTemplate(weekStart: w, slots: templates));
    }

    final today = DateTime(local.year, local.month, local.day);
    final rows = <ExamLoadRow>[];
    for (final e in exams) {
      final subject = await (_db.select(_db.subjects)
            ..where((t) => t.id.equals(e.subjectId)))
          .getSingleOrNull();
      final when = e.examDate.toLocal();
      final day = DateTime(when.year, when.month, when.day);
      rows.add(ExamLoadRow(
        subjectName: subject?.name ?? 'مادة',
        date: when,
        daysAway: calendarDaysBetween(today, day),
        neededMinutes: needed[e.subjectId] ?? 0,
        availableMinutes: hasAvailability
            ? ExamLoadMath.freeMinutes(
                windows: windows, blocks: blocks, from: local, to: when)
            : 0,
        openTasks: open[e.subjectId] ?? 0,
      ));
    }
    return ExamLoadData(rows: rows, hasAvailability: hasAvailability);
  }
}
