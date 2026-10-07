import '../database/app_database.dart' show Exam, Goal, AcademicTerm, Holiday;
import '../repositories/academic_calendar_repository.dart';
import '../repositories/exam_repository.dart';
import '../repositories/goal_repository.dart';

/// Everything the data already says about ONE exam (B, DEVIATION-22):
/// its subject, the education level of that subject, the active goals on
/// that subject, the term it falls in and any holiday covering its day.
///
/// This is READ-ONLY linking over existing columns (no schema change). It
/// never moves an exam, never decides anything and never invents a value: a
/// missing term/level simply stays null, and a suspicious situation is
/// reported as a warning code, not corrected.
class ExamContext {
  const ExamContext({
    required this.exam,
    required this.educationLevelId,
    required this.activeGoals,
    required this.term,
    required this.holidays,
    required this.warnings,
  });

  final Exam exam;

  /// Level of the exam's subject; null if the subject row is missing.
  final String? educationLevelId;
  final List<Goal> activeGoals;
  final AcademicTerm? term;
  final List<Holiday> holidays;

  /// Stable codes: `exam_on_holiday`, `exam_outside_terms` (terms exist but
  /// none contains the date), `exam_level_differs_from_student`.
  final List<String> warnings;

  bool get onHoliday => holidays.isNotEmpty;
}

class ExamLinkService {
  const ExamLinkService(this._exams, this._goals, this._calendar);

  final ExamRepository _exams;
  final GoalRepository _goals;
  final AcademicCalendarRepository _calendar;

  Future<ExamContext> contextFor(
    Exam exam, {
    required String studentId,
    required String academicYearId,
    String? studentLevelId,
  }) async {
    final levelId = await _exams.levelIdForSubject(exam.subjectId);
    final goals = await _goals.readActiveForSubject(studentId, exam.subjectId);
    final terms = await _calendar.readTerms(academicYearId);
    AcademicTerm? term;
    for (final t in terms) {
      if (AcademicCalendarRepository.coversDay(
          t.startDate, t.endDate, exam.examDate)) {
        term = t;
        break;
      }
    }
    final holidays = await _calendar.holidaysCovering(
      academicYearId,
      exam.examDate,
    );

    final warnings = <String>[];
    if (holidays.isNotEmpty) warnings.add('exam_on_holiday');
    if (terms.isNotEmpty && term == null) warnings.add('exam_outside_terms');
    if (studentLevelId != null &&
        levelId != null &&
        levelId != studentLevelId) {
      warnings.add('exam_level_differs_from_student');
    }

    return ExamContext(
      exam: exam,
      educationLevelId: levelId,
      activeGoals: goals,
      term: term,
      holidays: holidays,
      warnings: warnings,
    );
  }

  /// Contexts for every exam from [now] on, soonest first.
  Future<List<ExamContext>> upcomingContexts({
    required DateTime now,
    required String studentId,
    required String academicYearId,
    String? studentLevelId,
  }) async {
    final upcoming = await _exams.readUpcoming(now: now);
    return [
      for (final e in upcoming)
        await contextFor(
          e,
          studentId: studentId,
          academicYearId: academicYearId,
          studentLevelId: studentLevelId,
        ),
    ];
  }
}
