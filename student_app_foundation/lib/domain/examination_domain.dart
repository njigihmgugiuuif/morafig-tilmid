import 'dart:math' as math;

import '../repositories/exam_repository.dart';

/// Examination domain layer — Track C, Cycle 2.
///
/// Two things, both feeding existing engines rather than duplicating
/// them: `daysUntilNearestExam` (raw input emergency_engine.dart's
/// evaluate() needs) and `examPrioritySignal` (a [0,1] value derived from
/// exam proximity, feeding priority_engine.dart's examPriority signal).
class ExaminationDomainService {
  const ExaminationDomainService(this._exams, {this.urgencyHorizonDays = 21});

  final ExamRepository _exams;

  /// Days out at which exam proximity stops contributing to
  /// examPrioritySignal at all (signal reaches 0). INITIAL HEURISTIC, same
  /// status as every other cross-cutting constant in this codebase.
  final int urgencyHorizonDays;

  /// Null when there is no upcoming exam at all for the given subject (or
  /// any subject, if subjectId is omitted) — this is a real "no data",
  /// not a 0, and emergency_engine.dart's evaluate() already treats a null
  /// daysUntilNearestExam as "exam proximity cannot trigger," correctly.
  Future<int?> daysUntilNearestExam({
    required DateTime now,
    String? subjectId,
  }) async {
    final upcoming = await _exams.readUpcoming(now: now, subjectId: subjectId);
    if (upcoming.isEmpty) return null;
    final nearest = upcoming.first; // readUpcoming is already sorted asc.
    return nearest.examDate.difference(now).inHours ~/ 24;
  }

  /// [0,1], linearly ramping from 0 at `horizonDays` out to 1 on the exam
  /// day itself, 0 when there is no known upcoming exam (a missing exam
  /// date must never silently read as "very urgent" via some
  /// default-to-0-days mistake — it is null in, null out).
  ///
  /// Deliberately `static` (does not depend on `this`/the ExamRepository)
  /// so this pure calculation can be unit-tested with no database at all
  /// — see test/examination_domain_test.dart.
  static double? examPrioritySignal(
    int? daysUntilExam, {
    int horizonDays = 21,
  }) {
    if (daysUntilExam == null) return null;
    if (daysUntilExam <= 0) return 1.0;
    if (daysUntilExam >= horizonDays) return 0.0;
    final ramped = 1.0 - (daysUntilExam / horizonDays);
    return math.min(1.0, math.max(0.0, ramped));
  }

  /// Instance convenience that applies this service's own
  /// `urgencyHorizonDays` — thin wrapper over the static version above.
  double? examPrioritySignalForInstance(int? daysUntilExam) =>
      examPrioritySignal(daysUntilExam, horizonDays: urgencyHorizonDays);
}
