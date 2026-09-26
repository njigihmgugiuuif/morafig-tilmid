import '../repositories/exam_repository.dart';

/// Long-Term / Baccalaureate domain layer — Track C, Cycle 2.
///
/// Deliberately structural only. This cycle's rule is explicit: when a
/// layer would need verified official Algerian curriculum/Bac data this
/// session does not have confirmed (e.g. which subjects carry more
/// long-term weight, official Bac coefficient tables, stream-specific
/// requirements), build schema/domain SUPPORT for it, never bake in an
/// unconfirmed number or rule as if it were fact. Everything below reads
/// only structural, already-in-schema data (ExamType, examDate) — nothing
/// here asserts a subject-specific Bac fact.
library long_term_domain;

/// A purely time-based bucket — NOT a judgment about a subject's Bac
/// importance, only about how far away a given exam date is from `now`.
enum AcademicHorizon { immediate, thisMonth, thisTerm, fullYear }

class LongTermDomainService {
  const LongTermDomainService(this._exams);
  final ExamRepository _exams;

  /// INITIAL HEURISTIC day-count boundaries, same status as every other
  /// cross-cutting constant in this codebase — not derived from an
  /// official Algerian academic-calendar document. `static` (no `this`
  /// dependency) so it is unit-testable without a database — see
  /// test/long_term_domain_test.dart.
  static AcademicHorizon classifyHorizon({
    required DateTime now,
    required DateTime examDate,
  }) {
    final days = examDate.difference(now).inDays;
    if (days <= 7) return AcademicHorizon.immediate;
    if (days <= 30) return AcademicHorizon.thisMonth;
    if (days <= 120) return AcademicHorizon.thisTerm;
    return AcademicHorizon.fullYear;
  }

  /// Whether `subjectId` has ANY upcoming exam whose examType is 'bac' —
  /// a structural (schema-enum) check only. Does NOT attempt to say
  /// anything about how much that exam should matter relative to others;
  /// that would require the unverified official weighting data this layer
  /// explicitly does not embed.
  Future<bool> hasUpcomingBacExam({
    required String subjectId,
    required DateTime now,
  }) async {
    final upcoming =
        await _exams.readUpcoming(now: now, subjectId: subjectId);
    return upcoming.any((e) => e.examType == 'bac');
  }
}
