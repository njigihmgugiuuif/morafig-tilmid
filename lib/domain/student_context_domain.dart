import '../repositories/curriculum_repository.dart';
import '../repositories/student_repository.dart';
import 'enums.dart';

/// Student Integration domain layer (DEVIATION-19).
///
/// The one place the Core asks "which curriculum may be consumed for THIS
/// student right now?". It reads the student only through
/// [StudentRepository] and the version only through [CurriculumRepository],
/// never from the database directly.
///
/// A curriculum that merely EXISTS in the database or is merely LINKED to the
/// student is not usable. It is usable only when the linked version
///   - exists,
///   - belongs to the student's current academic year,
///   - has status ACTIVE, and
///   - (when a date is supplied) is inside its effective dates.
/// Anything else is reported with a reason, and nothing is invented: a
/// student with no linked version has UNKNOWN curriculum, not a default one.
class StudentCurriculumContext {
  const StudentCurriculumContext({
    required this.profile,
    required this.status,
    required this.linkedToVersion,
    required this.reason,
    this.curriculumVersionId,
    this.windowState,
  });

  final StudentProfile profile;

  /// Effective curriculum status for this student. UNKNOWN when nothing
  /// trustworthy is linked (no link, missing version, or a version from
  /// another academic year).
  final PolicyStatus status;

  final bool linkedToVersion;
  final String? curriculumVersionId;

  /// Null when no date was supplied (effective dates not checked).
  final VersionWindowState? windowState;

  final String reason;

  bool get curriculumUsable =>
      status.usableForCalculation &&
      windowState != VersionWindowState.notYetEffective &&
      windowState != VersionWindowState.ended;
}

class StudentContextService {
  const StudentContextService(this._students, this._curriculum);

  final StudentRepository _students;
  final CurriculumRepository _curriculum;

  /// The current student with the state of their curriculum, or null when no
  /// student exists yet.
  Future<StudentCurriculumContext?> current({DateTime? asOf}) async {
    final profile = await _students.readProfile();
    if (profile == null) return null;

    final versionId = profile.curriculumVersionId;
    if (versionId == null) {
      return StudentCurriculumContext(
        profile: profile,
        status: PolicyStatus.unknown,
        linkedToVersion: false,
        reason: 'The student is not linked to any curriculum version: the '
            'curriculum is UNKNOWN, never assumed ACTIVE.',
      );
    }

    final version = await _curriculum.readCurriculumVersion(versionId);
    if (version == null) {
      return StudentCurriculumContext(
        profile: profile,
        status: PolicyStatus.unknown,
        linkedToVersion: true,
        curriculumVersionId: versionId,
        reason: 'The linked curriculum version $versionId no longer exists.',
      );
    }
    if (version.academicYearId != profile.student.currentAcademicYearId) {
      return StudentCurriculumContext(
        profile: profile,
        status: PolicyStatus.unknown,
        linkedToVersion: true,
        curriculumVersionId: versionId,
        reason: 'The linked curriculum version $versionId belongs to a '
            'different academic year than the student\'s current one '
            '(stale link).',
      );
    }

    final status = PolicyStatus.fromDb(version.status);
    VersionWindowState? window;
    if (asOf != null) {
      window = CurriculumRepository.windowStateOf(
        effectiveFrom: version.effectiveFrom,
        effectiveTo: version.effectiveTo,
        asOf: asOf,
      );
    }
    return StudentCurriculumContext(
      profile: profile,
      status: status,
      linkedToVersion: true,
      curriculumVersionId: versionId,
      windowState: window,
      reason: 'The linked curriculum version $versionId has status '
          '${status.name}.',
    );
  }

  /// The id of the curriculum version the Core may consume for this student,
  /// or null when none may be used (no student, no link, UNKNOWN, CONFLICT,
  /// FROZEN, stale or outside its dates). A REPEALED version throws, loudly,
  /// exactly like Guard #2 for coefficients: returning null there would look
  /// the same as "no data" when the truth is "legally void".
  Future<String?> usableCurriculumVersionId({DateTime? asOf}) async {
    final ctx = await current(asOf: asOf);
    if (ctx == null) return null;
    if (ctx.status == PolicyStatus.repealed) {
      throw PolicyDataGuardViolation(
          'The student\'s curriculum version ${ctx.curriculumVersionId} is '
          'REPEALED and must never be consumed. (${ctx.reason})');
    }
    return ctx.curriculumUsable ? ctx.curriculumVersionId : null;
  }
}
