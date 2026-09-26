import '../repositories/curriculum_repository.dart';

/// Curriculum domain layer — Track C, Cycle 2.
///
/// This does NOT duplicate CurriculumRepository (which already is the
/// single choke point for SubjectLoads/coefficients — see its own doc
/// comment). It adds exactly one piece of logic CurriculumRepository
/// correctly does not own: turning a raw official coefficient (whatever
/// numeric scale Algerian curriculum documents actually use — 1 to 7 for
/// some streams, potentially different elsewhere) into the [0,1]
/// `officialCoefficient` signal priority_engine.dart expects. That scale
/// is NOT hardcoded here as an assumed fact — see `maxPlausibleCoefficient`
/// below — per this cycle's explicit rule: create domain/schema support
/// for unverified official data, never bake in an unverified number as if
/// it were confirmed.
class CurriculumDomainService {
  const CurriculumDomainService(this._repo);
  final CurriculumRepository _repo;

  /// Returns null when the SubjectLoad's status is not
  /// usableForCalculation (UNKNOWN/CONFLICT/FROZEN) — passed straight
  /// through from Guard #2, meaning "exclude this signal," never "treat
  /// as 0." Throws (propagated from the repository) if the SubjectLoad is
  /// REPEALED or does not exist — those are bugs in the caller, not data
  /// conditions a signal computation should silently absorb.
  ///
  /// `maxPlausibleCoefficient` is REQUIRED, with no default: this layer
  /// will not embed an assumed Algerian coefficient ceiling as if it were
  /// verified fact. The caller (Track D integration) must supply it,
  /// ideally sourced from a verified PolicyDocument.
  Future<double?> officialCoefficientSignal({
    required String subjectLoadId,
    required double maxPlausibleCoefficient,
  }) async {
    final coefficient = await _repo.getUsableCoefficient(subjectLoadId);
    if (coefficient == null) return null;
    return normalizeCoefficient(coefficient, maxPlausibleCoefficient);
  }

  /// The pure normalization step, pulled out as `static` (no `this`/no
  /// database) so it is unit-testable on its own — see
  /// test/curriculum_domain_test.dart.
  static double normalizeCoefficient(double coefficient, double maxPlausibleCoefficient) {
    if (maxPlausibleCoefficient <= 0) {
      throw ArgumentError.value(
          maxPlausibleCoefficient,
          'maxPlausibleCoefficient',
          'must be > 0 — this is a caller-supplied normalization ceiling, '
              'not a value this layer invents.');
    }
    return (coefficient / maxPlausibleCoefficient).clamp(0.0, 1.0);
  }
}
