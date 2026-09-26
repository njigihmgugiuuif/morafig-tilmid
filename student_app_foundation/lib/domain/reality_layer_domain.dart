import '../database/app_database.dart' show RealityConstraint;
import '../engines/scheduling_engine.dart' show TimeSlot;
import '../repositories/availability_repository.dart';
import '../repositories/reality_and_prerequisite_repositories.dart';

/// Reality Layer domain — Track C, Cycle 2.
///
/// THIS is where the "never break minimum sleep" invariant actually lives
/// for the whole pipeline (see scheduling_engine.dart's file-level doc
/// comment, which explicitly defers to this file): it resolves
/// Availabilities into concrete per-day windows, then subtracts every
/// HARD RealityConstraint (sleep, school, commute, fixedCommitment, and
/// any hard rest/activity/unexpectedEvent) from those windows before a
/// single TimeSlot is ever handed to scheduling_engine.dart. A sleep
/// RealityConstraint row is not treated as special-cased here — it is
/// simply one of the RealityConstraintType values, subtracted exactly
/// like every other hard constraint, which is what makes the invariant
/// hold by construction rather than by a type-specific carve-out that
/// could be forgotten later.
///
/// Soft (isHard == false) constraints are deliberately NOT subtracted —
/// see [computeFreeSlots]'s doc comment for why.
///
/// STATUS: UNVERIFIED — not run through a real Dart compiler/test runner
/// (no Flutter/Dart SDK in this environment). See
/// test/reality_layer_domain_test.dart.
class RealityLayerDomainService {
  const RealityLayerDomainService(this._availabilities, this._constraints);

  final AvailabilityRepository _availabilities;
  final RealityConstraintRepository _constraints;

  /// Half-open range: rangeStart inclusive, rangeEnd exclusive. Iterates
  /// day-by-day internally so a
  /// multi-day range resolves each day's Availability independently (a
  /// Tuesday-only recurring Availability row must not leak into
  /// Wednesday, for example).
  ///
  /// Soft constraints are not subtracted: subtracting them would silently
  /// turn "the student would rather not" into "the student structurally
  /// cannot" — the same distinction this cycle draws for Emergency Mode
  /// ("changes weights/thresholds only, never cancels a base constraint"),
  /// mirrored here on the reality-data side: only HARD constraints are
  /// allowed to remove time from what looks free.
  Future<List<TimeSlot>> computeFreeSlots({
    required String studentId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    if (!rangeEnd.isAfter(rangeStart)) {
      throw ArgumentError('rangeEnd must be after rangeStart.');
    }

    final availabilities = await _availabilities.readForStudent(studentId);
    final hardConstraints = (await _constraints.readForStudent(studentId))
        .where((c) => c.isHard)
        .toList();

    final freeSlots = <TimeSlot>[];
    var day = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    while (day.isBefore(rangeEnd)) {
      for (final window in resolveAvailabilityForDay(availabilities, day)) {
        freeSlots.addAll(subtractConstraints(window, hardConstraints));
      }
      day = day.add(const Duration(days: 1));
    }
    return freeSlots;
  }

  /// A specificDate Availability row for a given day OVERRIDES every
  /// recurring (dayOfWeek) row for that same day — never merged with it.
  /// This mirrors CurriculumVersions/SubjectLoads' own
  /// year-wide-default-vs-per-subject-override pattern (curriculum_tables
  /// .dart), applied here to schedule data instead of policy data: a more
  /// specific record always wins over a general one, it is never additive.
  /// Public + `static` (no `this`) so this resolution logic is
  /// unit-testable without a database — see
  /// test/reality_layer_domain_test.dart.
  static List<TimeSlot> resolveAvailabilityForDay(
    List<Availability> all,
    DateTime day,
  ) {
    final specific = all
        .where((a) => a.specificDate != null && isSameDate(a.specificDate!, day))
        .toList();
    // Dart's DateTime.weekday is 1=Monday..7=Sunday. Availabilities
    // .dayOfWeek is documented in planning_tables.dart only as "1-7,"
    // with no convention specified there — this file adopts Dart's
    // native weekday numbering as that convention, since introducing a
    // different one would need its own translation layer for no stated
    // reason. Flagged here explicitly so a future DEVIATION can correct
    // it cheaply if the intended convention turns out to differ (e.g. a
    // 1=Sunday convention some regional calendars use).
    final source = specific.isNotEmpty
        ? specific
        : all.where((a) => a.dayOfWeek == day.weekday).toList();

    return source
        .map((a) => TimeSlot(
              start: day.add(Duration(minutes: a.windowStartMinutes)),
              end: day.add(Duration(minutes: a.windowEndMinutes)),
            ))
        .toList();
  }

  static bool isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static List<TimeSlot> subtractConstraints(
    TimeSlot window,
    List<RealityConstraint> constraints,
  ) {
    var pieces = <TimeSlot>[window];
    for (final c in constraints) {
      final next = <TimeSlot>[];
      for (final p in pieces) {
        next.addAll(subtractOne(p, c.windowStart, c.windowEnd));
      }
      pieces = next;
    }
    return pieces;
  }

  /// Standard interval subtraction: slot minus the half-open interval
  /// from cutStart (inclusive) to cutEnd (exclusive) yields
  /// 0, 1, or 2 resulting TimeSlots. Only ever constructs a TimeSlot when
  /// it is genuinely non-empty (end strictly after start) — TimeSlot's
  /// own constructor asserts that, so this never risks tripping it.
  static List<TimeSlot> subtractOne(
    TimeSlot slot,
    DateTime cutStart,
    DateTime cutEnd,
  ) {
    if (!cutEnd.isAfter(slot.start) || !slot.end.isAfter(cutStart)) {
      return [slot]; // No overlap at all.
    }
    final result = <TimeSlot>[];
    final leftEnd = cutStart.isBefore(slot.end) ? cutStart : slot.end;
    if (leftEnd.isAfter(slot.start)) {
      result.add(TimeSlot(start: slot.start, end: leftEnd));
    }
    final rightStart = cutEnd.isAfter(slot.start) ? cutEnd : slot.start;
    if (slot.end.isAfter(rightStart)) {
      result.add(TimeSlot(start: rightStart, end: slot.end));
    }
    return result;
  }
}
