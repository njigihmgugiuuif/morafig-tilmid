import '../../database/app_database.dart';
import '../../engines/weekly_timeline_engine.dart' show WeekCalendar;
import '../../repositories/content_repository.dart';
import '../../repositories/event_repository.dart';
import '../../repositories/exam_repository.dart';
import '../../repositories/goal_repository.dart';
import '../../repositories/study_session_repository.dart';
import 'home_data.dart';
import 'progress_data.dart';

/// Read-only views for the progress pages (Batch 4).
///
/// RULES: everything here is READ from what the app stored (mastery and
/// memory states written by their engines, planned/actual sessions, completion
/// events, goals, exams, the stored priority and workload). The only
/// arithmetic is adding up and averaging stored numbers so they can be drawn.
/// No mastery, forgetting, priority or scheduling rule is re-implemented, no
/// threshold is invented, and an empty source gives an empty result with the
/// reason, never a made-up value.

// ------------------------------------------------------------- formatting

/// Whole calendar days from [from] to [to] (negative when [to] is earlier).
/// Computed on the calendar dates alone, so a daylight-saving change can
/// never make a day short.
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = from.toLocal();
  final b = to.toLocal();
  return DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
}

/// «45 د» / «2 س» / «2 س و 15 د».
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes د';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h س' : '$h س و $m د';
}

/// Three-letter day names that stay different from each other (the first two
/// letters of «الأحد» and «الاثنين» are the same), indexed 0 = Sunday.
const List<String> kDayShortAr = [
  'أحد', 'إثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت'
];

const List<String> kMonthNamesAr = [
  'جانفي', 'فيفري', 'مارس', 'أفريل', 'ماي', 'جوان',
  'جويلية', 'أوت', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
];

// ------------------------------------------------------------ mastery

class SubjectMastery {
  const SubjectMastery({
    required this.subjectId,
    required this.name,
    required this.average,
    required this.topics,
    required this.weakestName,
    required this.weakestValue,
  });
  final String subjectId;
  final String name;

  /// Mean of the stored mastery of the topics the student has been
  /// evaluated on in this subject (0..1).
  final double average;
  final int topics;
  final String weakestName;
  final double weakestValue;
}

// ------------------------------------------------------------- memory

class ReviewForecast {
  const ReviewForecast({
    required this.total,
    required this.overdue,
    required this.perDay,
    required this.later,
    required this.averageRecallNow,
  });

  /// Topics that have a memory state.
  final int total;

  /// Reviews already due (the same rule the memory page uses).
  final int overdue;

  /// Reviews that fall due on each of the next 7 calendar days, starting
  /// with today (a review due later today counts under today).
  final List<int> perDay;

  /// Due after the next 7 days.
  final int later;

  /// Mean of the memory engine's recall for each topic right now; null when
  /// no topic has a usable stored stability.
  final double? averageRecallNow;

  String get summary {
    if (total == 0) {
      return 'لا مراجعات بعد. تظهر هنا بعد أن تنجز مهامك الأولى.';
    }
    final soon = perDay.fold<int>(0, (a, b) => a + b);
    final parts = <String>[
      overdue == 0 ? 'لا مراجعات متأخرة' : 'عندك $overdue مراجعة مستحقة الآن',
      if (soon > 0) 'و$soon أخرى خلال 7 أيام',
    ];
    final r = averageRecallNow;
    return '${parts.join(' ')}.'
        '${r == null ? '' : ' متوسط ما تتذكره الآن ${(r * 100).round()}% بحسب محرّك الذاكرة.'}';
  }
}

// -------------------------------------------------------- time periods

enum TimePeriod { week, month, year }

class TimeBucket {
  const TimeBucket({
    required this.label,
    required this.shortLabel,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.completedTasks,
    required this.missedSessions,
  });
  final String label;

  /// Fits under a column of a small-screen chart.
  final String shortLabel;
  final int plannedMinutes;
  final int actualMinutes;
  final int completedTasks;
  final int missedSessions;
}

class PeriodReport {
  const PeriodReport({
    required this.period,
    required this.from,
    required this.to,
    required this.title,
    required this.buckets,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.endedPlannedMinutes,
    required this.sessions,
    required this.endedSessions,
    required this.recordedSessions,
    required this.completedTasks,
    required this.missedSessions,
  });

  final TimePeriod period;
  final DateTime from;
  final DateTime to;
  final String title;
  final List<TimeBucket> buckets;
  final int plannedMinutes;
  final int actualMinutes;

  /// Planned minutes of sessions whose planned end has already passed: the
  /// only part that can honestly be compared with what was recorded.
  final int endedPlannedMinutes;
  final int sessions;
  final int endedSessions;
  final int recordedSessions;
  final int completedTasks;
  final int missedSessions;

  bool get hasAnything => sessions > 0 || completedTasks > 0;
  bool get canCompare => endedSessions > 0 && recordedSessions > 0;

  /// One short sentence saying what the student is looking at.
  String get summary => summarizePeriod(
        sessions: sessions,
        plannedMinutes: plannedMinutes,
        endedSessions: endedSessions,
        recordedSessions: recordedSessions,
        endedPlannedMinutes: endedPlannedMinutes,
        actualMinutes: actualMinutes,
        completedTasks: completedTasks,
        missedSessions: missedSessions,
      );
}

String summarizePeriod({
  required int sessions,
  required int plannedMinutes,
  required int endedSessions,
  required int recordedSessions,
  required int endedPlannedMinutes,
  required int actualMinutes,
  required int completedTasks,
  required int missedSessions,
}) {
  if (sessions == 0 && completedTasks == 0) {
    return 'لا جلسات مخطَّطة ولا مهام منجزة في هذه الفترة.';
  }
  final out = <String>[];
  if (sessions > 0) {
    out.add('خُطِّط لك ${formatMinutes(plannedMinutes)} في $sessions جلسة.');
    if (endedSessions == 0) {
      out.add('لم تنتهِ أي جلسة بعد، فلا مقارنة الآن.');
    } else if (recordedSessions == 0) {
      out.add('ستظهر المقارنة بعد تسجيل جلسات الدراسة.');
    } else {
      final pct = endedPlannedMinutes <= 0
          ? null
          : (actualMinutes * 100 / endedPlannedMinutes).round();
      out.add('سجّلتَ فعليًا ${formatMinutes(actualMinutes)}'
          '${pct == null ? '' : ' (حوالي $pct% مما خُطِّط للجلسات المنتهية)'}.');
    }
    if (missedSessions > 0) {
      out.add('فاتتك $missedSessions جلسة انتهت دون تسجيل.');
    }
  }
  if (completedTasks > 0) {
    out.add('أنجزتَ $completedTasks مهمة.');
  }
  return out.join(' ');
}

// ----------------------------------------------------------- workload

class WorkloadView {
  const WorkloadView({
    required this.neededMinutes,
    required this.availableMinutes,
    required this.status,
  });
  final int neededMinutes;
  final int availableMinutes;
  final String status;

  bool get hasAvailability => availableMinutes > 0;

  String get statusLabel => workloadStatusLabel(status);

  String get summary {
    if (!hasAvailability) {
      return 'لم تُدخل أوقات فراغك بعد، فلا نحسب العبء. أضفها من «المزيد ← واقعي».';
    }
    return 'المطلوب ${formatMinutes(neededMinutes)} والمتاح ${formatMinutes(availableMinutes)}: $statusLabel.';
  }
}

String workloadStatusLabel(String status) {
  switch (status) {
    case 'underload':
      return 'عبء خفيف';
    case 'balanced':
      return 'عبء متوازن';
    case 'overload':
      return 'عبء زائد';
    case 'impossible':
      return 'غير قابل للتحقيق بالوقت الحالي';
    default:
      return 'عبء غير معروف';
  }
}

// ----------------------------------------------- exams, goals, gaps

class ExamOutlook {
  const ExamOutlook({
    required this.subjectName,
    required this.date,
    required this.daysAway,
    required this.masteryAverage,
    required this.topics,
    required this.openTasks,
  });
  final String subjectName;
  final DateTime date;
  final int daysAway;

  /// Mean stored mastery of the subject's evaluated topics; null when none.
  final double? masteryAverage;
  final int topics;
  final int openTasks;

  String get summary {
    final when = daysAway <= 0 ? 'اليوم' : 'بعد $daysAway يومًا';
    final m = masteryAverage;
    final prep = m == null
        ? 'لا تقييمات لمواضيع هذه المادة بعد.'
        : 'متوسط إتقانك لما قيّمتَه فيها ${(m * 100).round()}% ($topics موضوعًا).';
    return '$when · $prep';
  }
}

class GoalView {
  const GoalView({
    required this.goal,
    required this.subjectName,
    required this.daysLeft,
    required this.masteryAverage,
    required this.topics,
    required this.doneTasks,
    required this.openTasks,
  });
  final Goal goal;
  final String? subjectName;
  final int? daysLeft;
  final double? masteryAverage;
  final int topics;
  final int doneTasks;
  final int openTasks;
}

class GapTopic {
  const GapTopic({
    required this.nodeName,
    required this.subjectName,
    required this.probability,
    required this.reviewOverdueDays,
  });
  final String nodeName;
  final String subjectName;
  final double probability;

  /// Days a review has been due, or null when none is due.
  final int? reviewOverdueDays;
}

class PriorityPageData {
  const PriorityPageData({required this.ranked, required this.exams});
  final List<PrioritizedTask> ranked;
  final List<ExamOutlook> exams;
}

class GoalsPageData {
  const GoalsPageData({required this.goals, required this.weakest});
  final List<GoalView> goals;
  final List<GapTopic> weakest;
}

class ProgressInsights {
  ProgressInsights(this._db);
  final AppDatabase _db;

  // -------------------------------------------------------- mastery

  Future<List<SubjectMastery>> subjectMastery(String studentId) async {
    final states = await (_db.select(_db.masteryStates)
          ..where((t) => t.studentId.equals(studentId)))
        .get();
    final content = ContentRepository(_db);
    final sums = <String, double>{};
    final counts = <String, int>{};
    final weakest = <String, MasteryState>{};
    final names = <String, String>{};
    for (final s in states) {
      final id = await content.subjectIdForNode(s.knowledgeNodeId) ?? '';
      sums[id] = (sums[id] ?? 0) + s.probability;
      counts[id] = (counts[id] ?? 0) + 1;
      final w = weakest[id];
      if (w == null || s.probability < w.probability) weakest[id] = s;
      if (!names.containsKey(id)) {
        names[id] = await content.subjectNameForNode(s.knowledgeNodeId);
      }
    }
    final out = <SubjectMastery>[];
    for (final id in sums.keys) {
      final w = weakest[id]!;
      final name = (names[id] ?? '').isEmpty ? 'بدون مادة' : names[id]!;
      out.add(SubjectMastery(
        subjectId: id,
        name: name,
        average: sums[id]! / counts[id]!,
        topics: counts[id]!,
        weakestName: await content.nameForNode(w.knowledgeNodeId),
        weakestValue: w.probability,
      ));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  // --------------------------------------------------------- memory

  Future<ReviewForecast> reviewForecast(String studentId, DateTime now) async {
    final states = await (_db.select(_db.memoryStates)
          ..where((t) => t.studentId.equals(studentId)))
        .get();
    final nowUtc = now.toUtc();
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);
    final perDay = List<int>.filled(7, 0);
    var overdue = 0;
    var later = 0;
    final data = ProgressData(_db);
    var recallSum = 0.0;
    var recallN = 0;
    for (final m in states) {
      final curve = data.forgettingCurve(m, nowUtc);
      if (curve != null) {
        recallSum += curve.recallNow;
        recallN++;
      }
      if (!m.nextReviewDate.isAfter(nowUtc)) {
        overdue++;
        continue;
      }
      final diff = calendarDaysBetween(today, m.nextReviewDate);
      if (diff < 7) {
        perDay[diff < 0 ? 0 : diff]++;
      } else {
        later++;
      }
    }
    return ReviewForecast(
      total: states.length,
      overdue: overdue,
      perDay: perDay,
      later: later,
      averageRecallNow: recallN == 0 ? null : recallSum / recallN,
    );
  }

  // ----------------------------------------------------------- time

  /// Planned vs recorded study time and finished tasks for a week, a month
  /// or a year (Sunday-first weeks, local time). [anchor] is any date inside
  /// the wanted period.
  Future<PeriodReport> periodReport(
      TimePeriod period, DateTime anchor, DateTime now) async {
    final a = DateTime(anchor.year, anchor.month, anchor.day);
    late DateTime from;
    late DateTime to;
    late String title;
    late int count;
    late List<String> labels;
    late List<String> shorts;
    late int Function(DateTime) bucketOf;

    switch (period) {
      case TimePeriod.week:
        from = DateTime(a.year, a.month, a.day - WeekCalendar.indexInWeek(a));
        to = DateTime(from.year, from.month, from.day + 7);
        count = 7;
        labels = List<String>.of(WeekCalendar.arabicDayNames);
        shorts = List<String>.of(kDayShortAr);
        bucketOf = (d) => calendarDaysBetween(from, d);
        title = '${from.day}/${from.month} – '
            '${to.subtract(const Duration(days: 1)).day}/'
            '${to.subtract(const Duration(days: 1)).month}';
        break;
      case TimePeriod.month:
        from = DateTime(a.year, a.month);
        to = DateTime(a.year, a.month + 1);
        final days = to.difference(from).inDays;
        final lead = WeekCalendar.indexInWeek(from);
        count = (lead + days + 6) ~/ 7;
        labels = [for (var i = 1; i <= count; i++) 'أسبوع $i'];
        shorts = [for (var i = 1; i <= count; i++) '$i'];
        bucketOf = (d) => (d.day - 1 + lead) ~/ 7;
        title = '${kMonthNamesAr[a.month - 1]} ${a.year}';
        break;
      case TimePeriod.year:
        from = DateTime(a.year);
        to = DateTime(a.year + 1);
        count = 12;
        labels = List<String>.of(kMonthNamesAr);
        shorts = [for (var i = 1; i <= 12; i++) '$i'];
        bucketOf = (d) => d.month - 1;
        title = '${a.year}';
        break;
    }

    final planned = List<int>.filled(count, 0);
    final actual = List<int>.filled(count, 0);
    final done = List<int>.filled(count, 0);
    final missed = List<int>.filled(count, 0);
    var sessions = 0, ended = 0, recorded = 0;
    var endedPlanned = 0;

    final rows = await StudySessionRepository(_db).readOverlapping(from, to);
    final nowUtc = now.toUtc();
    for (final s in rows) {
      final start = s.plannedStart.toLocal();
      if (start.isBefore(from) || !start.isBefore(to)) continue;
      final i = bucketOf(DateTime(start.year, start.month, start.day));
      if (i < 0 || i >= count) continue;
      final p = s.plannedEnd.difference(s.plannedStart).inMinutes;
      sessions++;
      planned[i] += p;
      final isEnded = !s.plannedEnd.isAfter(nowUtc);
      if (isEnded) {
        ended++;
        endedPlanned += p;
      }
      if (s.actualStart != null) {
        recorded++;
        actual[i] += s.observedDurationMinutes ??
            (s.actualEnd == null
                ? 0
                : s.actualEnd!.difference(s.actualStart!).inMinutes);
      } else if (isEnded) {
        missed[i]++;
      }
    }

    var completed = 0;
    final events = await EventRepository(_db).readByType('TaskCompleted');
    for (final e in events) {
      final d = e.createdAt.toLocal();
      if (d.isBefore(from) || !d.isBefore(to)) continue;
      final i = bucketOf(DateTime(d.year, d.month, d.day));
      if (i < 0 || i >= count) continue;
      done[i]++;
      completed++;
    }

    return PeriodReport(
      period: period,
      from: from,
      to: to,
      title: title,
      buckets: [
        for (var i = 0; i < count; i++)
          TimeBucket(
            label: labels[i],
            shortLabel: shorts[i],
            plannedMinutes: planned[i],
            actualMinutes: actual[i],
            completedTasks: done[i],
            missedSessions: missed[i],
          ),
      ],
      plannedMinutes: planned.fold(0, (x, y) => x + y),
      actualMinutes: actual.fold(0, (x, y) => x + y),
      endedPlannedMinutes: endedPlanned,
      sessions: sessions,
      endedSessions: ended,
      recordedSessions: recorded,
      completedTasks: completed,
      missedSessions: missed.fold(0, (x, y) => x + y),
    );
  }

  Future<WorkloadView?> workload(String studentId) async {
    final rows = await (_db.select(_db.workloadStates)
          ..where((t) => t.studentId.equals(studentId)))
        .get();
    if (rows.isEmpty) return null;
    rows.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final w = rows.first;
    return WorkloadView(
      neededMinutes: w.totalEstimatedTimeNeededMinutes,
      availableMinutes: w.totalAvailableTimeMinutes,
      status: w.status,
    );
  }

  // ------------------------------------------- priorities and exams

  Future<PriorityPageData> priorities(String studentId, DateTime now) async {
    final ranked = await HomeData(_db).readRanked(limit: 8);
    final subjects = await subjectMastery(studentId);
    final bySubject = {for (final s in subjects) s.subjectId: s};
    final tasks = await _db.select(_db.tasks).get();
    final content = ContentRepository(_db);
    final openBySubject = <String, int>{};
    for (final t in tasks) {
      if (t.completionStatus == 'complete') continue;
      final id = await content.subjectIdForNode(t.knowledgeNodeId);
      if (id != null) openBySubject[id] = (openBySubject[id] ?? 0) + 1;
    }
    final exams = await ExamRepository(_db).readUpcoming(now: now.toUtc());
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);
    final out = <ExamOutlook>[];
    for (final e in exams.take(6)) {
      final subject = await (_db.select(_db.subjects)
            ..where((t) => t.id.equals(e.subjectId)))
          .getSingleOrNull();
      final l = e.examDate.toLocal();
      final sm = bySubject[e.subjectId];
      out.add(ExamOutlook(
        subjectName: subject?.name ?? 'مادة',
        date: l,
        daysAway: calendarDaysBetween(today, l),
        masteryAverage: sm?.average,
        topics: sm?.topics ?? 0,
        openTasks: openBySubject[e.subjectId] ?? 0,
      ));
    }
    return PriorityPageData(ranked: ranked, exams: out);
  }

  // --------------------------------------------------- goals and gaps

  Future<GoalsPageData> goalsAndGaps(String studentId, DateTime now) async {
    final goals = await GoalRepository(_db).readForStudent(studentId);
    goals.sort((a, b) {
      final ra = a.status == GoalRepository.statusActive ? 0 : 1;
      final rb = b.status == GoalRepository.statusActive ? 0 : 1;
      if (ra != rb) return ra - rb;
      final da = a.targetDate, db_ = b.targetDate;
      if (da == null && db_ == null) return 0;
      if (da == null) return 1;
      if (db_ == null) return -1;
      return da.compareTo(db_);
    });
    final subjects = await subjectMastery(studentId);
    final bySubject = {for (final s in subjects) s.subjectId: s};
    final progress = await _taskCountsBySubject();
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);
    final views = <GoalView>[];
    for (final g in goals) {
      String? name;
      if (g.subjectId != null) {
        final s = await (_db.select(_db.subjects)
              ..where((t) => t.id.equals(g.subjectId!)))
            .getSingleOrNull();
        name = s?.name;
      }
      final t = g.targetDate?.toLocal();
      final sm = g.subjectId == null ? null : bySubject[g.subjectId!];
      final c = g.subjectId == null ? null : progress[g.subjectId!];
      views.add(GoalView(
        goal: g,
        subjectName: name,
        daysLeft: t == null ? null : calendarDaysBetween(today, t),
        masteryAverage: sm?.average,
        topics: sm?.topics ?? 0,
        doneTasks: c?.$1 ?? 0,
        openTasks: c?.$2 ?? 0,
      ));
    }

    // Weakest topics: only a ranking of what the engines stored. No
    // threshold decides who is "weak" (that threshold is not approved).
    final mastery = await (_db.select(_db.masteryStates)
          ..where((t) => t.studentId.equals(studentId)))
        .get();
    mastery.sort((a, b) => a.probability.compareTo(b.probability));
    final memory = await (_db.select(_db.memoryStates)
          ..where((t) => t.studentId.equals(studentId)))
        .get();
    final dueSince = {
      for (final m in memory)
        if (!m.nextReviewDate.isAfter(now.toUtc()))
          m.knowledgeNodeId: now.toUtc().difference(m.nextReviewDate).inDays
    };
    final content = ContentRepository(_db);
    final weakest = <GapTopic>[];
    for (final m in mastery.take(5)) {
      weakest.add(GapTopic(
        nodeName: await content.nameForNode(m.knowledgeNodeId),
        subjectName: await content.subjectNameForNode(m.knowledgeNodeId),
        probability: m.probability,
        reviewOverdueDays: dueSince[m.knowledgeNodeId],
      ));
    }
    return GoalsPageData(goals: views, weakest: weakest);
  }

  /// (done, open) task counts per subject id.
  Future<Map<String, (int, int)>> _taskCountsBySubject() async {
    final tasks = await _db.select(_db.tasks).get();
    final content = ContentRepository(_db);
    final done = <String, int>{};
    final open = <String, int>{};
    for (final t in tasks) {
      final id = await content.subjectIdForNode(t.knowledgeNodeId);
      if (id == null) continue;
      if (t.completionStatus == 'complete') {
        done[id] = (done[id] ?? 0) + 1;
      } else {
        open[id] = (open[id] ?? 0) + 1;
      }
    }
    return {
      for (final id in {...done.keys, ...open.keys})
        id: (done[id] ?? 0, open[id] ?? 0)
    };
  }
}
