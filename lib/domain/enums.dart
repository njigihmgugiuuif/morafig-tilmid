/// Shared enums used across the Data Foundation.
/// These map to TEXT columns in SQLite (Drift TextColumn + check-like
/// enforcement in the Domain layer, since SQLite has no native enum type).
/// Storing as text (not int) is deliberate: it keeps exported JSON and raw
/// SQLite inspection human-readable, which matters for auditability of
/// legal/curriculum data specifically.

/// The 5 legally-tracked statuses for any Curriculum/Policy-sourced value.
/// This is the single vocabulary used everywhere a curriculum/policy value
/// is produced or consumed. See CURRICULUM_GUARDS.md for the enforcement
/// rules attached to each state.
enum PolicyStatus {
  active,
  unknown,
  conflict,
  frozen,
  repealed;

  static PolicyStatus fromDb(String value) => PolicyStatus.values.firstWhere(
        (e) => e.name == value,
        orElse: () => throw StateError(
            'Unrecognized PolicyStatus "$value" — refusing to default to '
            'ACTIVE or UNKNOWN silently. Fix the data at the source.'),
      );

  /// Whether this status is allowed to be read into ANY computation
  /// (priority scoring, scheduling, workload, etc). This is Guard #2
  /// (consumption guard). REPEALED must never return true here.
  bool get usableForCalculation => this == PolicyStatus.active;

  String get toDb => name;

  /// How restrictive a status is when two statuses apply to the same value
  /// (a curriculum version's status and a per-subject override): the MORE
  /// restrictive one always wins, so a looser status can never "rescue"
  /// data that a stricter one has withdrawn. ACTIVE < UNKNOWN < FROZEN <
  /// CONFLICT < REPEALED.
  int get severity {
    switch (this) {
      case PolicyStatus.active:
        return 0;
      case PolicyStatus.unknown:
        return 1;
      case PolicyStatus.frozen:
        return 2;
      case PolicyStatus.conflict:
        return 3;
      case PolicyStatus.repealed:
        return 4;
    }
  }

  static PolicyStatus mostRestrictive(PolicyStatus a, PolicyStatus b) =>
      a.severity >= b.severity ? a : b;
}

enum TaskCompletionStatus { notStarted, partial, complete }

enum TaskSourceType { regular, assignment, examPrep }

enum ErrorType { careless, conceptual, missingPrerequisite }

enum RecoveryDecision { keep, move, merge, defer, dropTemporarily, replan }

enum WorkloadStatus { underload, balanced, overload, impossible }

enum ExamType { formative, summative, bac }

enum RealityConstraintType {
  school,
  commute,
  fixedCommitment,
  rest,
  sleep,
  activity,
  unexpectedEvent
}

enum PrerequisiteRelationType { official, derived, proposed }

enum OverrideAction {
  accept,
  postpone,
  reject,
  reschedule,
  markEasier,
  markHarder,
  reportReason
}

enum EmergencyTrigger { examProximity, workloadImpossible }

enum DocumentVerificationStatus {
  primaryVerified,
  secondaryConfirmed,
  unverified
}
