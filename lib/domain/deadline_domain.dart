import '../repositories/deadline_repository.dart';

/// Deadline domain layer (A-1, DEVIATION-21): turns a task's own due dates
/// into the [0,1] `deadlinePressure` Priority signal.
///
/// Honest limits, stated here so they are not mistaken for facts:
///   - There is no official formula for deadline pressure. The linear ramp
///     below (the same shape as the examination ramp) and its 21-day horizon
///     are an INITIAL HEURISTIC, not an official rule, and are expected to be
///     calibrated.
///   - No task has a due date unless a Deadline / Assignment row exists. The
///     app has no writer for those yet, so for real users the signal is
///     usually null (unknown), never 0.
class DeadlineDomainService {
  const DeadlineDomainService(
    this._deadlines, {
    this.horizonDays = defaultHorizonDays,
  }) : assert(horizonDays > 0);

  final DeadlineRepository _deadlines;

  /// INITIAL HEURISTIC (approved by the owner, 2026-10-06): a due date this
  /// many days away or more exerts no pressure yet.
  static const double defaultHorizonDays = 21.0;

  final double horizonDays;

  /// PURE (no database). [untilDue] is `dueDate - now`.
  ///   - null  -> null (no due date: unknown, excluded, never 0);
  ///   - zero or negative (the date has passed) -> 1.0. This function is only
  ///     asked about OPEN tasks, so "passed and not complete" is maximal
  ///     pressure;
  ///   - [horizonDays] or more away -> 0.0;
  ///   - otherwise a linear ramp: 1 - days / horizon.
  static double? deadlinePressureSignal(
    Duration? untilDue, {
    double horizonDays = defaultHorizonDays,
  }) {
    if (untilDue == null) return null;
    if (untilDue.inMicroseconds <= 0) return 1.0;
    final days = untilDue.inMicroseconds / Duration.microsecondsPerDay;
    if (days >= horizonDays) return 0.0;
    return (1.0 - days / horizonDays).clamp(0.0, 1.0);
  }

  /// The signal for one OPEN task, or null when it has no due date at all.
  /// With several due dates the most pressing one decides (the highest
  /// pressure, which is the nearest or an overdue one).
  Future<double?> pressureForTask({
    required String taskId,
    String? sourceAssignmentId,
    required DateTime now,
  }) async {
    final dates = await _deadlines.readDueDatesForTask(
      taskId: taskId,
      sourceAssignmentId: sourceAssignmentId,
    );
    double? best;
    for (final due in dates) {
      final p = deadlinePressureSignal(due.difference(now),
          horizonDays: horizonDays);
      if (p != null && (best == null || p > best)) best = p;
    }
    return best;
  }
}
