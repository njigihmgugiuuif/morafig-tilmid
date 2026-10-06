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

/// Where a date sits relative to a curriculum version's effective dates.
/// `unbounded` = the version has NO dates at all (both NULL): the window is
/// unknown, which is NOT the same as "always in effect" — callers must not
/// infer an expiry from it, and must not invent one.
enum VersionWindowState { unbounded, notYetEffective, inEffect, ended }

/// The status that actually governs a curriculum value, and why. `status`
/// is the MOST RESTRICTIVE of every status that applies to it. A value that
/// is not linked to any curriculum version has no official provenance, so
/// it is UNKNOWN (never silently ACTIVE).
class EffectiveCurriculumStatus {
  const EffectiveCurriculumStatus({
    required this.status,
    required this.linkedToVersion,
    required this.reason,
    this.curriculumVersionId,
  });

  final PolicyStatus status;
  final bool linkedToVersion;
  final String? curriculumVersionId;
  final String reason;

  bool get usableForCalculation => status.usableForCalculation;
}

/// Read models for the curriculum hierarchy (version → subject → unit →
/// lesson → knowledge node, with each node's direct prerequisite edges).
class CurriculumNodeView {
  const CurriculumNodeView({required this.node, required this.prerequisites});
  final KnowledgeNode node;
  final List<Prerequisite> prerequisites;
}

class CurriculumLessonView {
  const CurriculumLessonView({required this.lesson, required this.nodes});
  final Lesson lesson;
  final List<CurriculumNodeView> nodes;
}

class CurriculumUnitView {
  const CurriculumUnitView({required this.unit, required this.lessons});
  final Unit unit;
  final List<CurriculumLessonView> lessons;
}

class CurriculumSubjectView {
  const CurriculumSubjectView({required this.subject, required this.units});
  final Subject subject;
  final List<CurriculumUnitView> units;
}

class CurriculumTree {
  const CurriculumTree({required this.version, required this.subjects});
  final CurriculumVersion version;
  final List<CurriculumSubjectView> subjects;
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
///                            A curriculum version can only be ACTIVE when
///                            its source document is verified.
///   Guard #2 — consumption: getUsableCoefficient() refuses to return a
///                            value for anything other than ACTIVE, and
///                            throws (does not silently return null) for
///                            REPEALED specifically, to make a bypass
///                            attempt loud rather than quietly wrong. The
///                            status that counts is the MOST RESTRICTIVE of
///                            the SubjectLoad's own status and its
///                            curriculum version's status (DEVIATION-18).
///   Guard #3 — DB access:   readRawStatus() is the only way to peek at a
///                            REPEALED row's status for audit/UI display
///                            purposes; it is a clearly separate method
///                            from getUsableCoefficient(), so a caller
///                            cannot arrive at a REPEALED coefficient by
///                            accident while writing calculation code.
class CurriculumRepository {
  CurriculumRepository(this._db);
  final AppDatabase _db;

  // ---------------------------------------------------------------------
  // Versions (Guard #1 for the version layer)
  // ---------------------------------------------------------------------

  /// Creates a curriculum edition. Nothing is defaulted or invented:
  /// `status` is required, country and label stay NULL unless the caller
  /// supplies them from a source, and an ACTIVE edition is refused when its
  /// source document is not verified.
  Future<CurriculumVersion> createVersion({
    required String academicYearId,
    required PolicyStatus status,
    required String sourcePolicyDocumentId,
    String? countryCode,
    String? versionLabel,
    DateTime? effectiveFrom,
    DateTime? effectiveTo,
  }) async {
    if (effectiveFrom != null &&
        effectiveTo != null &&
        effectiveTo.isBefore(effectiveFrom)) {
      throw PolicyDataGuardViolation(
          'effectiveTo ($effectiveTo) is before effectiveFrom '
          '($effectiveFrom).');
    }
    final doc = await _requireDocument(sourcePolicyDocumentId);
    _requireTrustedSourceForActive(status, doc);

    return _db.into(_db.curriculumVersions).insertReturning(
          CurriculumVersionsCompanion.insert(
            academicYearId: academicYearId,
            status: status.toDb,
            sourcePolicyDocumentId: sourcePolicyDocumentId,
            effectiveFrom: Value(effectiveFrom),
            effectiveTo: Value(effectiveTo),
            countryCode: Value(normalizeCountryCode(countryCode)),
            versionLabel: Value(normalizeLabel(versionLabel)),
          ),
        );
  }

  /// Moves a version to a new status. REPEALED is terminal: a repealed
  /// edition can never be brought back (a new edition must be created
  /// instead), and ACTIVE still requires a verified source document.
  Future<CurriculumVersion> changeVersionStatus({
    required String curriculumVersionId,
    required PolicyStatus newStatus,
  }) async {
    final version = await readCurriculumVersion(curriculumVersionId);
    if (version == null) {
      throw PolicyDataGuardViolation(
          'CurriculumVersion $curriculumVersionId does not exist.');
    }
    final current = PolicyStatus.fromDb(version.status);
    if (current == newStatus) return version;
    if (current == PolicyStatus.repealed) {
      throw PolicyDataGuardViolation(
          'CurriculumVersion $curriculumVersionId is REPEALED, which is '
          'terminal: it cannot become ${newStatus.name}. Create a new '
          'version instead.');
    }
    final doc = await _requireDocument(version.sourcePolicyDocumentId);
    _requireTrustedSourceForActive(newStatus, doc);

    await (_db.update(_db.curriculumVersions)
          ..where((t) => t.id.equals(curriculumVersionId)))
        .write(CurriculumVersionsCompanion(
      status: Value(newStatus.toDb),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
    final updated = await readCurriculumVersion(curriculumVersionId);
    return updated!;
  }

  Future<PolicyDocument> _requireDocument(String id) async {
    final doc = await (_db.select(_db.policyDocuments)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (doc == null) {
      throw PolicyDataGuardViolation('PolicyDocument $id does not exist.');
    }
    return doc;
  }

  void _requireTrustedSourceForActive(PolicyStatus status, PolicyDocument doc) {
    if (status != PolicyStatus.active) return;
    final trusted =
        doc.verificationStatus == DocumentVerificationStatus.primaryVerified.name ||
            doc.verificationStatus ==
                DocumentVerificationStatus.secondaryConfirmed.name;
    if (!trusted) {
      throw PolicyDataGuardViolation(
          'A curriculum version cannot be ACTIVE when its source document '
          '${doc.id} is not verified (verificationStatus='
          '"${doc.verificationStatus}"). Use UNKNOWN until the source is '
          'verified.');
    }
  }

  /// 2-letter country code, upper-cased; null/blank = unknown (NULL).
  static String? normalizeCountryCode(String? raw) {
    if (raw == null) return null;
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(v)) {
      throw ArgumentError.value(raw, 'countryCode',
          'must be a 2-letter country code, or null when unknown.');
    }
    return v.toUpperCase();
  }

  /// Trimmed label; null/blank = unknown (NULL).
  static String? normalizeLabel(String? raw) {
    if (raw == null) return null;
    final v = raw.trim();
    return v.isEmpty ? null : v;
  }

  // ---------------------------------------------------------------------
  // Subject loads (coefficients / hours)
  // ---------------------------------------------------------------------

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
  ///
  /// The status that decides is the most restrictive of the SubjectLoad's
  /// own status and its curriculum version's status, so an ACTIVE load
  /// inside a REPEALED/FROZEN version is NOT usable.
  ///
  /// When [asOf] is given, a version that is not yet effective, or whose
  /// effective period has ended, also yields null. A version with no dates
  /// is never expired by inference.
  Future<double?> getUsableCoefficient(
    String subjectLoadId, {
    DateTime? asOf,
  }) async {
    final row = await _requireLoad(subjectLoadId);
    final effective = await _effectiveForLoadRow(row);

    if (effective.status == PolicyStatus.repealed) {
      throw PolicyDataGuardViolation(
          'SubjectLoad $subjectLoadId is REPEALED and must never be '
          'consumed by any calculation. This is Guard #2 firing — if you '
          'reached this from engine code, that code has a bug. '
          '(${effective.reason})');
    }

    if (!effective.usableForCalculation) {
      // UNKNOWN / CONFLICT / FROZEN: legitimate exclusion, not an error.
      return null;
    }

    if (asOf != null) {
      final version = await readCurriculumVersion(row.curriculumVersionId);
      final window = windowStateOf(
        effectiveFrom: version?.effectiveFrom,
        effectiveTo: version?.effectiveTo,
        asOf: asOf,
      );
      if (window == VersionWindowState.notYetEffective ||
          window == VersionWindowState.ended) {
        return null;
      }
    }

    return row.coefficient;
  }

  /// Pure date logic (no database), exposed for tests.
  static VersionWindowState windowStateOf({
    DateTime? effectiveFrom,
    DateTime? effectiveTo,
    required DateTime asOf,
  }) {
    if (effectiveFrom == null && effectiveTo == null) {
      return VersionWindowState.unbounded;
    }
    if (effectiveFrom != null && asOf.isBefore(effectiveFrom)) {
      return VersionWindowState.notYetEffective;
    }
    if (effectiveTo != null && asOf.isAfter(effectiveTo)) {
      return VersionWindowState.ended;
    }
    return VersionWindowState.inEffect;
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

  /// READ-ONLY (A-1, DEVIATION-21). Every SubjectLoad of one curriculum
  /// version that belongs to exactly this stream. Loads with NO stream
  /// (`streamId` NULL) never match here, so they can never enter a
  /// comparison between subjects of a stream. The rows are returned raw:
  /// their coefficients must still go through [getUsableCoefficient] (Guard
  /// #2) before anything consumes them. Nothing is written or changed.
  Future<List<SubjectLoad>> readLoadsForVersionAndStream({
    required String curriculumVersionId,
    required String streamId,
  }) {
    return (_db.select(_db.subjectLoads)
          ..where((t) =>
              t.curriculumVersionId.equals(curriculumVersionId) &
              t.streamId.equals(streamId)))
        .get();
  }

  Future<CurriculumVersion?> readCurriculumVersion(String id) =>
      (_db.select(_db.curriculumVersions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<SubjectLoad> _requireLoad(String subjectLoadId) async {
    final row = await (_db.select(_db.subjectLoads)
          ..where((t) => t.id.equals(subjectLoadId)))
        .getSingleOrNull();
    if (row == null) {
      throw PolicyDataGuardViolation(
          'SubjectLoad $subjectLoadId does not exist.');
    }
    return row;
  }

  // ---------------------------------------------------------------------
  // Effective status (what actually governs a value)
  // ---------------------------------------------------------------------

  Future<EffectiveCurriculumStatus> effectiveStatusForSubjectLoad(
      String subjectLoadId) async {
    final row = await _requireLoad(subjectLoadId);
    return _effectiveForLoadRow(row);
  }

  Future<EffectiveCurriculumStatus> _effectiveForLoadRow(
      SubjectLoad row) async {
    final loadStatus = PolicyStatus.fromDb(row.status);
    final fromVersion = await _fromVersionId(
        row.curriculumVersionId, 'SubjectLoad ${row.id}');
    final combined =
        PolicyStatus.mostRestrictive(loadStatus, fromVersion.status);
    return EffectiveCurriculumStatus(
      status: combined,
      linkedToVersion: true,
      curriculumVersionId: row.curriculumVersionId,
      reason: 'SubjectLoad status is ${loadStatus.name} and its version '
          'status is ${fromVersion.status.name}; the more restrictive '
          'applies: ${combined.name}.',
    );
  }

  /// A subject's status is its curriculum version's status. A subject that
  /// is not linked to any version (e.g. one the student typed in) has no
  /// official provenance, so it is UNKNOWN — never ACTIVE.
  Future<EffectiveCurriculumStatus> effectiveStatusForSubject(
      String subjectId) async {
    final subject = await _requireSubject(subjectId);
    return _fromVersionId(subject.curriculumVersionId, 'Subject $subjectId');
  }

  /// A knowledge node inherits the status of its subject (via lesson and
  /// unit). A broken chain is a data bug and throws.
  Future<EffectiveCurriculumStatus> effectiveStatusForNode(
      String knowledgeNodeId) async {
    final node = await (_db.select(_db.knowledgeNodes)
          ..where((t) => t.id.equals(knowledgeNodeId)))
        .getSingleOrNull();
    if (node == null) {
      throw PolicyDataGuardViolation(
          'KnowledgeNode $knowledgeNodeId does not exist.');
    }
    final lesson = await (_db.select(_db.lessons)
          ..where((t) => t.id.equals(node.lessonId)))
        .getSingleOrNull();
    if (lesson == null) {
      throw PolicyDataGuardViolation(
          'Lesson ${node.lessonId} of node $knowledgeNodeId does not exist.');
    }
    final unit = await (_db.select(_db.units)
          ..where((t) => t.id.equals(lesson.unitId)))
        .getSingleOrNull();
    if (unit == null) {
      throw PolicyDataGuardViolation(
          'Unit ${lesson.unitId} of lesson ${lesson.id} does not exist.');
    }
    final subject = await _requireSubject(unit.subjectId);
    return _fromVersionId(
        subject.curriculumVersionId, 'KnowledgeNode $knowledgeNodeId');
  }

  Future<EffectiveCurriculumStatus> _fromVersionId(
      String? versionId, String what) async {
    if (versionId == null) {
      return EffectiveCurriculumStatus(
        status: PolicyStatus.unknown,
        linkedToVersion: false,
        reason: '$what is not linked to any curriculum version: its '
            'provenance is unknown, so it is never treated as ACTIVE.',
      );
    }
    final version = await readCurriculumVersion(versionId);
    if (version == null) {
      throw PolicyDataGuardViolation(
          'CurriculumVersion $versionId does not exist.');
    }
    final status = PolicyStatus.fromDb(version.status);
    return EffectiveCurriculumStatus(
      status: status,
      linkedToVersion: true,
      curriculumVersionId: versionId,
      reason: '$what belongs to curriculum version $versionId whose status '
          'is ${status.name}.',
    );
  }

  Future<Subject> _requireSubject(String subjectId) async {
    final subject = await (_db.select(_db.subjects)
          ..where((t) => t.id.equals(subjectId)))
        .getSingleOrNull();
    if (subject == null) {
      throw PolicyDataGuardViolation('Subject $subjectId does not exist.');
    }
    return subject;
  }

  // ---------------------------------------------------------------------
  // Official content (links subjects to a version)
  // ---------------------------------------------------------------------

  /// Adds (or returns the existing) subject of a curriculum version. The
  /// version must exist; nothing is invented about the subject.
  Future<Subject> ingestSubject({
    required String curriculumVersionId,
    required String educationLevelId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty.');
    }
    final version = await readCurriculumVersion(curriculumVersionId);
    if (version == null) {
      throw PolicyDataGuardViolation(
          'CurriculumVersion $curriculumVersionId does not exist.');
    }
    final existing = await (_db.select(_db.subjects)
          ..where((t) =>
              t.curriculumVersionId.equals(curriculumVersionId) &
              t.educationLevelId.equals(educationLevelId) &
              t.name.equals(trimmed)))
        .getSingleOrNull();
    if (existing != null) return existing;
    return _db.into(_db.subjects).insertReturning(
          SubjectsCompanion.insert(
            name: trimmed,
            educationLevelId: educationLevelId,
            curriculumVersionId: Value(curriculumVersionId),
          ),
        );
  }

  /// Links an existing subject to a curriculum version (e.g. when a
  /// student's own subject is matched to a documented edition).
  Future<Subject> linkSubjectToVersion({
    required String subjectId,
    required String curriculumVersionId,
  }) async {
    await _requireSubject(subjectId);
    final version = await readCurriculumVersion(curriculumVersionId);
    if (version == null) {
      throw PolicyDataGuardViolation(
          'CurriculumVersion $curriculumVersionId does not exist.');
    }
    await (_db.update(_db.subjects)..where((t) => t.id.equals(subjectId)))
        .write(SubjectsCompanion(
      curriculumVersionId: Value(curriculumVersionId),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
    return _requireSubject(subjectId);
  }

  // ---------------------------------------------------------------------
  // Hierarchy read model
  // ---------------------------------------------------------------------

  /// The full hierarchy of one version: its subjects, each subject's units
  /// (by `order`), each unit's lessons (by `order`), each lesson's nodes
  /// (by name) and every node's direct prerequisite edges. Read-only.
  Future<CurriculumTree> readTreeForVersion(String curriculumVersionId) async {
    final version = await readCurriculumVersion(curriculumVersionId);
    if (version == null) {
      throw PolicyDataGuardViolation(
          'CurriculumVersion $curriculumVersionId does not exist.');
    }
    final subjects = await (_db.select(_db.subjects)
          ..where((t) => t.curriculumVersionId.equals(curriculumVersionId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();

    final subjectViews = <CurriculumSubjectView>[];
    for (final subject in subjects) {
      final units = await (_db.select(_db.units)
            ..where((t) => t.subjectId.equals(subject.id))
            ..orderBy([(t) => OrderingTerm.asc(t.order)]))
          .get();
      final unitViews = <CurriculumUnitView>[];
      for (final unit in units) {
        final lessons = await (_db.select(_db.lessons)
              ..where((t) => t.unitId.equals(unit.id))
              ..orderBy([(t) => OrderingTerm.asc(t.order)]))
            .get();
        final lessonViews = <CurriculumLessonView>[];
        for (final lesson in lessons) {
          final nodes = await (_db.select(_db.knowledgeNodes)
                ..where((t) => t.lessonId.equals(lesson.id))
                ..orderBy([(t) => OrderingTerm.asc(t.name)]))
              .get();
          final nodeViews = <CurriculumNodeView>[];
          for (final node in nodes) {
            final prereqs = await (_db.select(_db.prerequisites)
                  ..where((t) => t.knowledgeNodeId.equals(node.id)))
                .get();
            nodeViews.add(
                CurriculumNodeView(node: node, prerequisites: prereqs));
          }
          lessonViews
              .add(CurriculumLessonView(lesson: lesson, nodes: nodeViews));
        }
        unitViews.add(CurriculumUnitView(unit: unit, lessons: lessonViews));
      }
      subjectViews
          .add(CurriculumSubjectView(subject: subject, units: unitViews));
    }
    return CurriculumTree(version: version, subjects: subjectViews);
  }
}
