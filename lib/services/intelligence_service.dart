import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../domain/examination_domain.dart';
import '../engines/mastery_engine.dart';
import '../engines/memory_engine.dart';
import '../engines/priority_engine.dart';
import '../repositories/event_repository.dart';
import '../repositories/exam_repository.dart';
import '../repositories/explanation_and_override_repositories.dart';
import '../repositories/mastery_repository.dart';
import '../repositories/memory_repository.dart';
import '../repositories/priority_repository.dart';

/// Self-assessed understanding captured when the student completes a task.
/// Stored in the TaskCompleted event payload as one of these strings.
class Understanding {
  static const good = 'good';
  static const partial = 'partial';
  static const notUnderstood = 'notUnderstood';

  /// The student skipped the question: NO learning evidence exists, so
  /// no Mastery/Memory update is made (nothing is guessed).
  static const unknown = 'unknown';
}

class IntelligenceRunResult {
  const IntelligenceRunResult({required this.processed, required this.errors});

  final int processed;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
}

/// Track D integration: the single place where Events drive the engines.
///
/// Flow (event-sourced, as in the approved design):
///   TaskCompleted event (carries the student's self-assessment)
///     -> Mastery (BKT)  : only for good / notUnderstood evidence
///     -> Memory (FSRS)  : good -> good, partial -> hard, notUnderstood -> forgot
///     -> mark event processed
///   then, once per run, recompute Priority for every open task using ONLY
///   the signals that really exist:
///     personalWeakness = 1 - mastery probability
///     forgettingRisk   = 1 - FSRS retrievability now
///     examPriority     = ramp over days to the nearest exam of the subject
///   officialCoefficient / learningPriority / urgencyImportance stay null
///   (unknown, never invented) and the Priority Engine renormalises weights
///   over the available signals. Every priority gets a real Explanation row.
class IntelligenceService {
  IntelligenceService(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Processes every unprocessed event in creation order. A failing event
  /// is NOT marked processed (it will be retried next run) and its error is
  /// reported in the result, never swallowed.
  Future<IntelligenceRunResult> processPendingEvents() async {
    final events = EventRepository(_db);
    final pending = await events.readUnprocessed();
    pending.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    var processed = 0;
    final errors = <String>[];
    for (final e in pending) {
      try {
        await _db.transaction(() async {
          if (e.type == 'TaskCompleted') {
            await _applyTaskCompleted(e);
          }
          await events.markProcessed(e.id, _clock().toUtc());
        });
        processed++;
      } catch (err) {
        errors.add('${e.type}: $err');
      }
    }

    if (processed > 0) {
      try {
        await refreshPriorities();
      } catch (err) {
        errors.add('priorities: $err');
      }
    }
    return IntelligenceRunResult(processed: processed, errors: errors);
  }

  Future<void> _applyTaskCompleted(Event e) async {
    final payload = jsonDecode(e.payloadJson) as Map<String, dynamic>;
    final taskId = payload['taskId'] as String;
    final understanding = payload['understanding'] as String?;
    if (understanding == null || understanding == Understanding.unknown) {
      return; // no evidence -> no learning update
    }

    final task = await (_db.select(_db.tasks)
          ..where((t) => t.id.equals(taskId)))
        .getSingleOrNull();
    final student = await _db.select(_db.students).getSingleOrNull();
    if (task == null || student == null) return;
    final nodeId = task.knowledgeNodeId;

    // Mastery (BKT) — binary evidence only. 'partial' is deliberately not
    // forced into correct/incorrect; it informs Memory only.
    if (understanding == Understanding.good ||
        understanding == Understanding.notUnderstood) {
      final mastery = MasteryRepository(_db);
      final prior = await mastery.read(student.id, nodeId);
      final params = BktParameters.defaults();
      final result = const MasteryEngine().compute(
        priorProbability: prior?.probability ?? params.initialProbability,
        correct: understanding == Understanding.good,
        params: params,
        // Observation count is not persisted (only the probability is),
        // so confidence is not stored; the probability does not depend
        // on it.
        priorObservationCount: 0,
      );
      await mastery.recomputeFrom(
        studentId: student.id,
        knowledgeNodeId: nodeId,
        newProbability: result.probability,
        sourceEventId: e.id,
      );
    }

    // Memory (FSRS) — a real, auditable review event.
    final grade = understanding == Understanding.good
        ? 'good'
        : understanding == Understanding.partial
            ? 'hard'
            : 'forgot';
    final now = _clock().toUtc();
    final reviewEvent = await EventRepository(_db).insertRow(
      EventsCompanion.insert(
        type: 'MemoryReviewCompleted',
        payloadJson: jsonEncode({
          'studentId': student.id,
          'knowledgeNodeId': nodeId,
          'grade': grade,
          'reviewedAt': now.toIso8601String(),
          'sourceEventId': e.id,
        }),
        triggersReplan: false,
        processedAt: Value(now),
      ),
    );
    await MemoryRepository(_db).recomputeFrom(reviewEvent);
  }

  /// Recomputes the Priority of every open task from real signals.
  /// Tasks with no available signal at all get no priority yet.
  Future<void> refreshPriorities() async {
    final student = await _db.select(_db.students).getSingleOrNull();
    if (student == null) return;

    final now = _clock().toUtc();
    final tasks = await (_db.select(_db.tasks)
          ..where((t) => t.completionStatus.equals('complete').not()))
        .get();

    final mastery = MasteryRepository(_db);
    final memory = MemoryRepository(_db);
    final exams = ExaminationDomainService(ExamRepository(_db));
    const memoryEngine = MemoryEngine();
    const priorityEngine = PriorityEngine();

    for (final task in tasks) {
      final m = await mastery.read(student.id, task.knowledgeNodeId);
      final mem = await memory.read(student.id, task.knowledgeNodeId);

      double? forgetting;
      if (mem != null) {
        var elapsedDays =
            now.difference(mem.updatedAt).inMilliseconds /
                Duration.millisecondsPerDay;
        if (elapsedDays < 0) elapsedDays = 0;
        final r = memoryEngine.retrievability(elapsedDays, mem.stability);
        forgetting = (1.0 - r).clamp(0.0, 1.0);
      }

      final subjectId = await _subjectIdForNode(task.knowledgeNodeId);
      final days = await exams.daysUntilNearestExam(
        now: now,
        subjectId: subjectId,
      );

      final signals = PrioritySignals(
        officialCoefficient: null,
        learningPriority: null,
        examPriority: ExaminationDomainService.examPrioritySignal(days),
        personalWeakness: m == null ? null : (1.0 - m.probability),
        forgettingRisk: forgetting,
        urgencyImportance: null,
      );
      if (signals.asMap().values.every((v) => v == null)) continue;

      final result = priorityEngine.compute(signals: signals);

      final factors = <String, Map<String, double>>{};
      var dominant = '';
      var best = -1.0;
      final excluded = <String>[];
      for (final entry in signals.asMap().entries) {
        final value = entry.value;
        if (value == null) {
          excluded.add(entry.key.name);
          continue;
        }
        final w = result.weightsUsed[entry.key] ?? 0.0;
        factors[entry.key.name] = {
          'value': value,
          'weight': w,
          'contribution': value * w,
        };
        if (value * w > best) {
          best = value * w;
          dominant = entry.key.name;
        }
      }

      final version = await _db.into(_db.dataStateVersions).insertReturning(
            DataStateVersionsCompanion.insert(
              snapshotTimestamp: now,
              relatedEventId: 'priority-refresh',
            ),
          );
      final explanation = await ExplanationRepository(_db).insertRow(
        ExplanationsCompanion.insert(
          factorsJson: jsonEncode(factors),
          excludedFactorsJson: jsonEncode(excluded),
          dominantFactor: dominant,
          hardConstraintsCheckedJson: '[]',
          versionBundleId: version.id,
        ),
      );
      await PriorityRepository(_db).recomputeFrom(
        taskId: task.id,
        result: result,
        explanationId: explanation.id,
      );
    }
  }

  Future<String?> _subjectIdForNode(String knowledgeNodeId) async {
    final node = await (_db.select(_db.knowledgeNodes)
          ..where((t) => t.id.equals(knowledgeNodeId)))
        .getSingleOrNull();
    if (node == null) return null;
    final lesson = await (_db.select(_db.lessons)
          ..where((t) => t.id.equals(node.lessonId)))
        .getSingleOrNull();
    if (lesson == null) return null;
    final unit = await (_db.select(_db.units)
          ..where((t) => t.id.equals(lesson.unitId)))
        .getSingleOrNull();
    return unit?.subjectId;
  }
}
