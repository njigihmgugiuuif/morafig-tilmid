/// Gap Detection Engine — pure decision logic, no UI, no database.
///
/// Reads a [WeekTimeline] plus the [SchedulingResult] that produced it and
/// reports what is wrong or wasted, each finding carrying a stable `code`,
/// a severity, and machine-readable `details` so the UI can explain it and
/// the Replanning layer can react to it:
///
///   - freeSlot            : usable study time left unused (information)
///   - unusedWhileBacklog  : free study minutes exist AND tasks are unplaced
///                           (fragmentation or an atomic task too long)
///   - overload            : a day is filled beyond a safe share of capacity
///   - conflict            : two hard blocks overlap
///   - insufficientTime    : not enough study time for what must be done
///   - unplacedTask        : a task has no (or only partial) place, with the
///                           scheduler's own reason
///   - backlog             : many tasks pile up unplaced
///   - deadlineRisk        : deadline close/passed and task not fully placed
///   - lateRisk            : task is placed, but ends after its deadline
///
/// It does not decide what to do about a finding — that is replanning.
/// All thresholds are INITIAL HEURISTICS in [GapDetectionConfig], meant to
/// move into the Threshold Registry once real data exists.
///
/// SCOPE NOTE: this is the TIME-side half of Gap Detection (the agreed
/// engine also covers knowledge gaps: unstudied/unmastered lessons, weak
/// prerequisites, overdue reviews, repeated errors, neglected subjects).
/// Those need Mastery/Memory/Error/KnowledgeGraph data and belong to the
/// integration phase; they are NOT implemented here and are not claimed.
///
/// STATUS: UNVERIFIED locally — not compiled or run in the authoring
/// environment. Verified only by GitHub Actions.
/// See test/gap_detection_engine_test.dart.
import 'scheduling_engine.dart';
import 'weekly_timeline_engine.dart';

enum GapKind {
  freeSlot,
  unusedWhileBacklog,
  overload,
  conflict,
  insufficientTime,
  unplacedTask,
  backlog,
  deadlineRisk,
  lateRisk,
}

enum GapSeverity { info, warning, critical }

class GapFinding {
  const GapFinding({
    required this.kind,
    required this.severity,
    required this.code,
    this.taskId,
    this.date,
    this.minutes,
    this.details = const {},
  });

  final GapKind kind;
  final GapSeverity severity;

  /// Stable machine code, e.g. `unplaced_no_slot`.
  final String code;
  final String? taskId;
  final DateTime? date;
  final int? minutes;
  final Map<String, Object> details;
}

class GapDetectionConfig {
  const GapDetectionConfig({
    this.minFreeSlotMinutes = 30,
    this.overloadRatio = 0.9,
    this.dailyStudyLimitMinutes,
    this.backlogThreshold = 3,
    this.deadlineHorizon = const Duration(hours: 48),
  });

  /// Free study slots shorter than this are not reported.
  final int minFreeSlotMinutes;

  /// scheduled / capacity at or above this ratio is an overload warning.
  final double overloadRatio;

  /// Absolute daily ceiling (from Workload Engine once wired). Null = none.
  final int? dailyStudyLimitMinutes;

  /// Unplaced (time-related) tasks at or above this count is a backlog.
  final int backlogThreshold;

  /// Deadlines further away than this are not flagged as at risk yet.
  final Duration deadlineHorizon;
}

class GapDetectionEngine {
  const GapDetectionEngine();

  List<GapFinding> detect({
    required WeekTimeline timeline,
    required SchedulingResult scheduling,
    required List<SchedulableItem> items,
    required DateTime now,
    GapDetectionConfig config = const GapDetectionConfig(),
  }) {
    final findings = <GapFinding>[];
    final itemById = {for (final i in items) i.taskId: i};

    // --- conflicts -------------------------------------------------------
    for (final day in timeline.days) {
      for (final c in day.conflicts) {
        findings.add(GapFinding(
          kind: GapKind.conflict,
          severity: GapSeverity.critical,
          code: 'conflict_hard_blocks',
          date: day.date,
          minutes: c.overlapMinutes,
          taskId: c.a.kind == TimelineBlockKind.study
              ? c.a.refId
              : (c.b.kind == TimelineBlockKind.study ? c.b.refId : null),
          details: {
            'a': c.a.kind.name,
            'b': c.b.kind.name,
          },
        ));
      }
    }

    // --- unplaced tasks, time shortage, backlog --------------------------
    var missingMinutes = 0;
    var timeRelatedUnplaced = 0;
    for (final u in scheduling.unscheduledQueue) {
      final item = itemById[u.taskId];
      switch (u.reason) {
        case UnscheduledReason.prerequisiteNotSatisfied:
          findings.add(GapFinding(
            kind: GapKind.unplacedTask,
            severity: GapSeverity.info,
            code: 'unplaced_prerequisite',
            taskId: u.taskId,
          ));
          break;
        case UnscheduledReason.noSlotAvailable:
          final m = item?.totalDurationMinutes ?? 0;
          missingMinutes += m;
          timeRelatedUnplaced++;
          findings.add(GapFinding(
            kind: GapKind.unplacedTask,
            severity: GapSeverity.warning,
            code: 'unplaced_no_slot',
            taskId: u.taskId,
            minutes: m,
          ));
          break;
        case UnscheduledReason.partiallyScheduled:
          final m = u.minutesRemaining ?? 0;
          missingMinutes += m;
          timeRelatedUnplaced++;
          findings.add(GapFinding(
            kind: GapKind.unplacedTask,
            severity: GapSeverity.warning,
            code: 'unplaced_partial',
            taskId: u.taskId,
            minutes: m,
          ));
          break;
      }
    }

    if (missingMinutes > 0) {
      findings.add(GapFinding(
        kind: GapKind.insufficientTime,
        severity: GapSeverity.warning,
        code: 'insufficient_time',
        minutes: missingMinutes,
        details: {
          'freeStudyMinutes': timeline.freeStudyMinutes,
          'studyCapacityMinutes': timeline.studyCapacityMinutes,
        },
      ));
    }

    if (timeRelatedUnplaced >= config.backlogThreshold) {
      findings.add(GapFinding(
        kind: GapKind.backlog,
        severity: GapSeverity.warning,
        code: 'backlog',
        minutes: missingMinutes,
        details: {'unplacedCount': timeRelatedUnplaced},
      ));
    }

    if (timeRelatedUnplaced > 0 &&
        timeline.freeStudyMinutes >= config.minFreeSlotMinutes) {
      findings.add(GapFinding(
        kind: GapKind.unusedWhileBacklog,
        severity: GapSeverity.warning,
        code: 'unused_while_backlog',
        minutes: timeline.freeStudyMinutes,
        details: {'unplacedCount': timeRelatedUnplaced},
      ));
    }

    // --- per-day load and idle time --------------------------------------
    for (final day in timeline.days) {
      final cap = day.studyCapacityMinutes;
      final used = day.scheduledStudyMinutes;

      final limit = config.dailyStudyLimitMinutes;
      if (limit != null && used > limit) {
        findings.add(GapFinding(
          kind: GapKind.overload,
          severity: GapSeverity.critical,
          code: 'overload_over_limit',
          date: day.date,
          minutes: used - limit,
          details: {'scheduled': used, 'limit': limit},
        ));
      } else if (cap > 0 && used / cap >= config.overloadRatio) {
        findings.add(GapFinding(
          kind: GapKind.overload,
          severity: GapSeverity.warning,
          code: 'overload_near_capacity',
          date: day.date,
          minutes: used,
          details: {'scheduled': used, 'capacity': cap},
        ));
      }

      for (final slot in day.freeStudySlots) {
        if (slot.durationMinutes >= config.minFreeSlotMinutes) {
          findings.add(GapFinding(
            kind: GapKind.freeSlot,
            severity: GapSeverity.info,
            code: 'free_slot',
            date: day.date,
            minutes: slot.durationMinutes,
          ));
        }
      }
    }

    // --- deadlines -------------------------------------------------------
    final unscheduledIds = {
      for (final u in scheduling.unscheduledQueue)
        if (u.reason != UnscheduledReason.prerequisiteNotSatisfied) u.taskId
    };
    for (final marker in timeline.markers) {
      final severity =
          marker.isHard ? GapSeverity.critical : GapSeverity.warning;

      if (unscheduledIds.contains(marker.refId)) {
        final untilDeadline = marker.at.difference(now);
        if (untilDeadline <= config.deadlineHorizon) {
          findings.add(GapFinding(
            kind: GapKind.deadlineRisk,
            severity: severity,
            code: untilDeadline.isNegative
                ? 'deadline_passed_unplaced'
                : 'deadline_near_unplaced',
            taskId: marker.refId,
            date: marker.at,
            minutes: untilDeadline.inMinutes,
          ));
        }
        continue;
      }

      final chunks = scheduling.chunksFor(marker.refId);
      if (chunks.isEmpty) continue;
      var lastEnd = chunks.first.end;
      for (final c in chunks) {
        if (c.end.isAfter(lastEnd)) lastEnd = c.end;
      }
      if (lastEnd.isAfter(marker.at)) {
        findings.add(GapFinding(
          kind: GapKind.lateRisk,
          severity: severity,
          code: 'placed_after_deadline',
          taskId: marker.refId,
          date: marker.at,
          minutes: lastEnd.difference(marker.at).inMinutes,
        ));
      }
    }

    findings.sort((a, b) {
      final s = b.severity.index.compareTo(a.severity.index);
      if (s != 0) return s;
      return a.kind.index.compareTo(b.kind.index);
    });
    return findings;
  }

  /// Arabic description of a finding for display. Pure formatting — no
  /// decisions. Unknown codes fall back to the code itself so nothing is
  /// ever silently hidden.
  static String describeAr(GapFinding f) {
    switch (f.code) {
      case 'conflict_hard_blocks':
        return 'تعارض: كتلتان ثابتتان تتداخلان لمدة ${f.minutes ?? 0} دقيقة.';
      case 'unplaced_prerequisite':
        return 'مهمة لا يمكن بدؤها قبل إتقان متطلبها السابق.';
      case 'unplaced_no_slot':
        return 'لا يوجد مكان لهذه المهمة (${f.minutes ?? 0} دقيقة) هذا الأسبوع.';
      case 'unplaced_partial':
        return 'وُضع جزء من المهمة فقط، وبقي ${f.minutes ?? 0} دقيقة بلا مكان.';
      case 'insufficient_time':
        return 'نقص في الوقت: ${f.minutes ?? 0} دقيقة مطلوبة بلا مكان.';
      case 'backlog':
        return 'تراكم: ${f.details['unplacedCount']} مهام بلا مكان.';
      case 'unused_while_backlog':
        return 'يوجد وقت دراسة غير مستغل (${f.minutes ?? 0} دقيقة) مع بقاء مهام بلا مكان؛ '
            'قد يكون مجزّأً أو أقصر من مهمة غير قابلة للتقسيم.';
      case 'overload_over_limit':
        return 'حمل اليوم يتجاوز الحد المسموح بـ ${f.minutes ?? 0} دقيقة.';
      case 'overload_near_capacity':
        return 'اليوم ممتلئ تقريبًا (${f.details['scheduled']} من ${f.details['capacity']} دقيقة).';
      case 'free_slot':
        return 'وقت دراسة متاح غير مستغل: ${f.minutes ?? 0} دقيقة.';
      case 'deadline_near_unplaced':
        return 'موعد نهائي قريب ومهمته بلا مكان كامل.';
      case 'deadline_passed_unplaced':
        return 'فات الموعد النهائي ومهمته لم توضع كاملة.';
      case 'placed_after_deadline':
        return 'المهمة موضوعة بعد موعدها النهائي بـ ${f.minutes ?? 0} دقيقة.';
      default:
        return f.code;
    }
  }
}
