import 'dart:convert';

import 'package:drift/drift.dart'
    show
        BooleanExpressionOperators,
        ComparableExpr,
        OrderingMode,
        OrderingTerm;

import '../../database/app_database.dart';
import '../../engines/priority_engine.dart'
    show canonicalPrioritySignalName;
import '../../repositories/content_repository.dart';
import '../../repositories/exam_repository.dart';
import '../../repositories/explanation_and_override_repositories.dart';
import '../../repositories/study_session_repository.dart';

/// One signal of a stored priority, as the Priority Engine wrote it.
class PriorityFactorView {
  const PriorityFactorView({
    required this.key,
    required this.value,
    required this.weight,
    required this.contribution,
  });

  /// Current signal name (an old stored name is mapped to the current one).
  final String key;
  final double value;
  final double weight;
  final double contribution;
}

/// A task together with the priority and explanation the engine stored for
/// it. Nothing here is computed in the UI: it is read, named and ordered.
class PrioritizedTask {
  const PrioritizedTask({
    required this.task,
    required this.priority,
    required this.nodeName,
    required this.subjectName,
    required this.factors,
    required this.excluded,
    required this.dominantFactor,
  });

  final Task task;
  final PriorityState priority;
  final String nodeName;
  final String subjectName;

  /// Signals that took part, strongest contribution first.
  final List<PriorityFactorView> factors;

  /// Signals that had no data and were left out (never filled with a guess).
  final List<String> excluded;
  final String dominantFactor;
}

class NearestExamView {
  const NearestExamView({
    required this.subjectName,
    required this.date,
    required this.daysAway,
  });
  final String subjectName;
  final DateTime date;

  /// Whole calendar days from today (0 = today).
  final int daysAway;
}

class MasteryHighlight {
  const MasteryHighlight({
    required this.nodeName,
    required this.subjectName,
    required this.probability,
  });
  final String nodeName;
  final String subjectName;
  final double probability;
}

/// Everything the home screen shows, read in one pass.
class HomeSnapshot {
  const HomeSnapshot({
    required this.studentName,
    required this.now,
    required this.alternatives,
    required this.reviewsDue,
    required this.nearestExam,
    required this.todaySessions,
    required this.todayDone,
    required this.openTasks,
    required this.lowestMastery,
  });

  final String studentName;
  final PrioritizedTask? now;
  final List<PrioritizedTask> alternatives;
  final int reviewsDue;
  final NearestExamView? nearestExam;
  final int todaySessions;
  final int todayDone;
  final int openTasks;
  final List<MasteryHighlight> lowestMastery;
}

/// Reads for the home / «now» / task-detail screens.
class HomeData {
  HomeData(this._db);
  final AppDatabase _db;

  /// The tasks that have a stored priority and are not complete, best first.
  Future<List<PrioritizedTask>> readRanked({int limit = 4}) async {
    final states = await (_db.select(_db.priorityStates)
          ..orderBy([
            (t) => OrderingTerm(expression: t.score, mode: OrderingMode.desc),
          ]))
        .get();
    final out = <PrioritizedTask>[];
    for (final s in states) {
      if (out.length >= limit) break;
      final task = await (_db.select(_db.tasks)
            ..where((t) => t.id.equals(s.taskId)))
          .getSingleOrNull();
      if (task == null || task.completionStatus == 'complete') continue;
      out.add(await _build(task, s));
    }
    return out;
  }

  /// The stored priority of one task, if it has one.
  Future<PrioritizedTask?> readForTask(Task task) async {
    final s = await (_db.select(_db.priorityStates)
          ..where((t) => t.taskId.equals(task.id)))
        .getSingleOrNull();
    if (s == null) return null;
    return _build(task, s);
  }

  Future<PrioritizedTask> _build(Task task, PriorityState s) async {
    final content = ContentRepository(_db);
    final explanation = await ExplanationRepository(_db).readById(s.explanationId);
    final factors = <PriorityFactorView>[];
    final excluded = <String>[];
    var dominant = '';
    if (explanation != null) {
      dominant = canonicalPrioritySignalName(explanation.dominantFactor);
      try {
        final decoded = jsonDecode(explanation.factorsJson);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is Map) {
              factors.add(PriorityFactorView(
                key: canonicalPrioritySignalName('$k'),
                value: (v['value'] as num?)?.toDouble() ?? 0,
                weight: (v['weight'] as num?)?.toDouble() ?? 0,
                contribution: (v['contribution'] as num?)?.toDouble() ?? 0,
              ));
            }
          });
        }
        final ex = jsonDecode(explanation.excludedFactorsJson);
        if (ex is List) {
          excluded.addAll(ex.map((e) => canonicalPrioritySignalName('$e')));
        }
      } catch (_) {
        // A malformed stored explanation shows no factors; it never throws
        // into the screen.
      }
      factors.sort((a, b) => b.contribution.compareTo(a.contribution));
    }
    return PrioritizedTask(
      task: task,
      priority: s,
      nodeName: await content.nameForNode(task.knowledgeNodeId),
      subjectName: await content.subjectNameForNode(task.knowledgeNodeId),
      factors: factors,
      excluded: excluded,
      dominantFactor: dominant,
    );
  }

  Future<HomeSnapshot> loadHome({
    required String studentId,
    DateTime? clock,
  }) async {
    final now = clock ?? DateTime.now();

    final student = await (_db.select(_db.students)
          ..where((t) => t.id.equals(studentId)))
        .getSingleOrNull();

    final ranked = await readRanked(limit: 4);

    final due = await (_db.select(_db.memoryStates)
          ..where((t) =>
              t.studentId.equals(studentId) &
              t.nextReviewDate.isSmallerOrEqualValue(now.toUtc())))
        .get();

    NearestExamView? nearest;
    final exams = await ExamRepository(_db).readUpcoming(now: now.toUtc());
    if (exams.isNotEmpty) {
      final e = exams.first;
      final subject = await (_db.select(_db.subjects)
            ..where((t) => t.id.equals(e.subjectId)))
          .getSingleOrNull();
      final local = e.examDate.toLocal();
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(local.year, local.month, local.day);
      nearest = NearestExamView(
        subjectName: subject?.name ?? '',
        date: local,
        daysAway: day.difference(today).inDays,
      );
    }

    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = DateTime(now.year, now.month, now.day + 1);
    final todays = await StudySessionRepository(_db)
        .readOverlapping(dayStart, dayEnd);

    final open = await (_db.select(_db.tasks)
          ..where((t) => t.completionStatus.equals('complete').not()))
        .get();

    final weakest = await (_db.select(_db.masteryStates)
          ..where((t) => t.studentId.equals(studentId))
          ..orderBy([(t) => OrderingTerm(expression: t.probability)])
          ..limit(2))
        .get();
    final content = ContentRepository(_db);
    final highlights = <MasteryHighlight>[];
    for (final m in weakest) {
      highlights.add(MasteryHighlight(
        nodeName: await content.nameForNode(m.knowledgeNodeId),
        subjectName: await content.subjectNameForNode(m.knowledgeNodeId),
        probability: m.probability,
      ));
    }

    return HomeSnapshot(
      studentName: student?.fullNameOrNickname ?? '',
      now: ranked.isEmpty ? null : ranked.first,
      alternatives: ranked.length > 1 ? ranked.sublist(1) : const [],
      reviewsDue: due.length,
      nearestExam: nearest,
      todaySessions: todays.length,
      todayDone: todays.where((s) => s.actualEnd != null).length,
      openTasks: open.length,
      lowestMastery: highlights,
    );
  }
}

/// Plain-language names of the six Priority signals (D-1 S16). The wording
/// states what a signal looks at, not a verdict.
String prioritySignalLabel(String key) {
  switch (canonicalPrioritySignalName(key)) {
    case 'masteryGap':
      return 'فجوة في الإتقان';
    case 'forgettingRisk':
      return 'خطر النسيان';
    case 'officialCoefficient':
      return 'معامل المادة';
    case 'examProximity':
      return 'قرب الامتحان';
    case 'deadlinePressure':
      return 'ضغط الموعد';
    case 'longTermGoalAlignment':
      return 'ارتباط بهدفك';
    default:
      return key;
  }
}

/// One line saying what each signal measures, for the explanation screen.
String prioritySignalHint(String key) {
  switch (canonicalPrioritySignalName(key)) {
    case 'masteryGap':
      return 'كم بقي من الإتقان لهذا الموضوع (من تقديرك عند الإنجاز).';
    case 'forgettingRisk':
      return 'احتمال أن تكون قد بدأت تنسى هذا الموضوع الآن.';
    case 'officialCoefficient':
      return 'وزن المادة مقارنةً بأعلى معامل في شعبتك، من بيانات رسمية موثّقة فقط.';
    case 'examProximity':
      return 'مدى قرب أقرب امتحان في هذه المادة.';
    case 'deadlinePressure':
      return 'مدى قرب موعد التسليم المسجَّل لهذه المهمة.';
    case 'longTermGoalAlignment':
      return 'غير مفعّل بعد: تعريف الارتباط بالهدف لم يُعتمد.';
    default:
      return '';
  }
}
