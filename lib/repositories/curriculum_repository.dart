import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../domain/enums.dart';

/// Thrown when Guard #1 (ingestion) or Guard #2 (consumption) refuses an
/// operation. Deliberately its own type (not a generic StateError) so
/// calling code — and tests — can catch this specifically.
class PolicyDataGuardViolation implements Exception {
  PolicyDataGuardViolation(this.message);
  final String message;
  @override
  String toString() => 'PolicyDataGuardViolation: $message';
}

/// The single choke point for every read/write of curriculum/policy
/// numbers (coefficients, hours). This is the ONLY place in the whole app
/// permitted to touch the SubjectLoads/CurriculumVersions tables — the
/// Priority Engine (built in a later phase) will depend on this
/// repository's `getUsableCoefficient` method and MUST NOT query
/// SubjectLoads directly (enforced organizationally via
/// analysis_options.yaml, same pattern as the append-only tables).
///
/// Implements all three guards from the Data Foundation Schema (Section H):
///   Guard #1 — ingestion:   refuses to insert a SubjectLoad without an
///                            explicit status. No silent default to ACTIVE.
///   Guard #2 — consumption: getUsableCoefficient() refuses to return a
///                            value for anything other than ACTIVE, and
///                            throws (does not silently return null) for
///                            REPEALED specifically, to make a bypass
///                            attempt loud rather than quietly wrong.
///   Guard #3 — DB access:   readRawStatus() is the only way to peek at a
///                            REPEALED row's status for audit/UI display
///                            purposes; it is a clearly separate method
///                            from getUsableCoefficient(), so a caller
///                            cannot arrive at a REPEALED coefficient by
///                            accident while writing calculation code.
class CurriculumRepository {
  CurriculumRepository(this._db);
  final AppDatabase _db;

  /// Guard #1 — Ingestion.
  Future<SubjectLoad> ingestSubjectLoad({
    required String curriculumVersionId,
    required String subjectId,
    String? streamId,
    double? coefficient,
    double? weeklyHours,
    required PolicyStatus status,
    String? fallbackReason,
  }) async {
    // No default parameter value for `status` above, and no fallback here:
    // callers MUST pass a PolicyStatus explicitly. This is the structural
    // half of Guard #1; the other half is that PolicyStatus itself has no
    // "unset"/null-like member (see domain/enums.dart).
    return _db.into(_db.subjectLoads).insertReturning(
          SubjectLoadsCompanion.insert(
            curriculumVersionId: curriculumVersionId,
            subjectId: subjectId,
            streamId: Value(streamId),
            coefficient: Value(coefficient),
            weeklyHours: Value(weeklyHours),
            status: status.toDb,
            fallbackApplied: Value(fallbackReason != null ? 'true' : 'false'),
            fallbackReason: Value(fallbackReason),
          ),
        );
  }

  /// Guard #2 — Consumption. This is what the Priority Engine will call.
  /// Returns null for UNKNOWN/CONFLICT/FROZEN (a legitimate "not usable
  /// right now" outcome the caller must handle via signal exclusion —
  /// see the Intelligence spec's dataCompleteness handling). Throws for
  /// REPEALED specifically, because returning null there would look
  /// identical to "we don't have data" when the true situation is "we
  /// have data and it is legally void" — those must never be
  /// indistinguishable to a caller.
  Future<double?> getUsableCoefficient(String subjectLoadId) async {
    final row = await (_db.select(_db.subjectLoads)
          ..where((t) => t.id.equals(subjectLoadId)))
        .getSingleOrNull();

    if (row == null) {
      throw PolicyDataGuardViolation(
          'SubjectLoad $subjectLoadId does not exist.');
    }

    final status = PolicyStatus.fromDb(row.status);

    if (status == PolicyStatus.repealed) {
      throw PolicyDataGuardViolation(
          'SubjectLoad $subjectLoadId is REPEALED and must never be '
          'consumed by any calculation. This is Guard #2 firing — if you '
          'reached this from engine code, that code has a bug.');
    }

    if (!status.usableForCalculation) {
      // UNKNOWN / CONFLICT / FROZEN: legitimate exclusion, not an error.
      return null;
    }

    return row.coefficient;
  }

  /// Guard #3 — DB access. Separate, clearly-named method for anything that
  /// needs to SHOW a REPEALED row (e.g. an audit screen listing "why is
  /// this subject's old coefficient not being used") without risking that
  /// value being fed into a calculation by mistake. Returns the raw status
  /// string, never the numeric coefficient.
  Future<PolicyStatus> readRawStatus(String subjectLoadId) async {
    final row = await (_db.select(_db.subjectLoads)
          ..where((t) => t.id.equals(subjectLoadId)))
        .getSingleOrNull();
    if (row == null) {
      throw PolicyDataGuardViolation(
          'SubjectLoad $subjectLoadId does not exist.');
    }
    return PolicyStatus.fromDb(row.status);
  }

  Future<CurriculumVersion?> readCurriculumVersion(String id) =>
      (_db.select(_db.curriculumVersions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
}
