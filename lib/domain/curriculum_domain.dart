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
    DateTime? asOf,
  }) async {
    final coefficient =
        await _repo.getUsableCoefficient(subjectLoadId, asOf: asOf);
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

  // ---------------------------------------------------------------------
  // A-1 (DEVIATION-21): the official-coefficient signal for ONE subject of
  // the student's stream, normalised against the highest usable coefficient
  // of the same stream and the same curriculum version.
  //
  // This normalisation is an ENGINEERING DESIGN decision, not an official
  // rule. Nothing here embeds a coefficient value or a ceiling: the ceiling
  // is derived from the stored, guard-approved loads themselves.
  // ---------------------------------------------------------------------

  /// A stream needs at least this many usable loads before the signal is
  /// meaningful: with a single load, "coefficient / highest" is trivially
  /// 1.0 and would fabricate importance.
  static const int minimumUsableLoads = 2;

  /// PURE (no database). [coefficient] is the subject's own usable
  /// coefficient; [usableCoefficients] are the usable coefficients of every
  /// load of the same stream and version (the subject's own included).
  /// Returns null (never 0) when the signal cannot be trusted:
  ///   - the subject's coefficient is null or <= 0;
  ///   - fewer than [minimumUsableLoads] usable (> 0) coefficients exist.
  static double? normalizeAgainstStreamMax({
    required double? coefficient,
    required List<double> usableCoefficients,
  }) {
    if (coefficient == null || coefficient <= 0) return null;
    final positives = usableCoefficients.where((c) => c > 0).toList();
    if (positives.length < minimumUsableLoads) return null;
    var highest = positives.first;
    for (final c in positives) {
      if (c > highest) highest = c;
    }
    return (coefficient / highest).clamp(0.0, 1.0);
  }

  /// The [0,1] `officialCoefficient` signal for [subjectId], or null.
  ///
  /// The caller passes the student's USABLE curriculum version and stream
  /// (obtained through StudentContextService, which already refuses
  /// UNKNOWN / CONFLICT / FROZEN / REPEALED / stale versions). Null is
  /// returned (meaning "exclude this signal", never "treat as 0") when:
  ///   - no load, or MORE THAN ONE load, matches the subject in this
  ///     version and stream (no match = no data; several = ambiguous);
  ///   - the matching load is not usable (Guard #2 returns null), or is
  ///     REPEALED (the guard's exception is caught HERE, per load, so one
  ///     withdrawn row cannot stop the priority refresh of every task);
  ///   - [normalizeAgainstStreamMax] returns null.
  /// Loads without a stream never take part (see
  /// CurriculumRepository.readLoadsForVersionAndStream). Guard #1/#2/#3 are
  /// untouched: every coefficient is read through getUsableCoefficient.
  Future<double?> officialCoefficientSignalForSubject({
    required String subjectId,
    required String curriculumVersionId,
    required String streamId,
    DateTime? asOf,
  }) async {
    final loads = await _repo.readLoadsForVersionAndStream(
      curriculumVersionId: curriculumVersionId,
      streamId: streamId,
    );

    final matching = loads.where((l) => l.subjectId == subjectId).toList();
    if (matching.length != 1) return null;

    double? ownCoefficient;
    final usable = <double>[];
    for (final load in loads) {
      double? value;
      try {
        value = await _repo.getUsableCoefficient(load.id, asOf: asOf);
      } on PolicyDataGuardViolation {
        value = null; // REPEALED: excluded for this signal only.
      }
      if (load.id == matching.single.id) ownCoefficient = value;
      if (value != null) usable.add(value);
    }

    return normalizeAgainstStreamMax(
      coefficient: ownCoefficient,
      usableCoefficients: usable,
    );
  }
}
