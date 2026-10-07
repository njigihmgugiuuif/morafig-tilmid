import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Storage for the saved weekly plan (B, DEVIATION-22): `StudySessions` (one
/// row per planned block of time) and `TaskSegments` (one row per chunk of a
/// splittable task).
///
/// A session is a PLANNED fact until `recordActual` stores what really
/// happened. Planned-but-unexecuted sessions in the future are DERIVED data:
/// a replan may delete and recreate them. A session that has an actual, or
/// that lies in the past, is history and is never deleted by this class.
class StudySessionRepository {
  StudySessionRepository(this._db);
  final AppDatabase _db;

  Future<StudySession> insertPlanned({
    required String taskId,
    String? taskSegmentId,
    required DateTime plannedStart,
    required DateTime plannedEnd,
  }) {
    if (!plannedEnd.isAfter(plannedStart)) {
      throw ArgumentError('plannedEnd must be after plannedStart.');
    }
    return _db.into(_db.studySessions).insertReturning(
          StudySessionsCompanion.insert(
            taskId: taskId,
            taskSegmentId: Value(taskSegmentId),
            plannedStart: plannedStart,
            plannedEnd: plannedEnd,
          ),
        );
  }

  Future<TaskSegment> insertSegment({
    required String parentTaskId,
    required int segmentDurationMinutes,
    required int segmentOrder,
  }) {
    if (segmentDurationMinutes <= 0) {
      throw ArgumentError('segmentDurationMinutes must be > 0.');
    }
    return _db.into(_db.taskSegments).insertReturning(
          TaskSegmentsCompanion.insert(
            parentTaskId: parentTaskId,
            segmentDurationMinutes: segmentDurationMinutes,
            segmentOrder: segmentOrder,
          ),
        );
  }

  Future<List<TaskSegment>> readSegmentsForTask(String taskId) =>
      (_db.select(_db.taskSegments)
            ..where((t) => t.parentTaskId.equals(taskId))
            ..orderBy([(t) => OrderingTerm.asc(t.segmentOrder)]))
          .get();

  Future<StudySession?> readById(String id) =>
      (_db.select(_db.studySessions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<List<StudySession>> readForTask(String taskId) =>
      (_db.select(_db.studySessions)
            ..where((t) => t.taskId.equals(taskId))
            ..orderBy([(t) => OrderingTerm.asc(t.plannedStart)]))
          .get();

  /// Sessions that overlap [from, to): plannedStart < to AND plannedEnd > from.
  Future<List<StudySession>> readOverlapping(DateTime from, DateTime to) =>
      (_db.select(_db.studySessions)
            ..where((t) =>
                t.plannedStart.isSmallerThanValue(to) &
                t.plannedEnd.isBiggerThanValue(from))
            ..orderBy([(t) => OrderingTerm.asc(t.plannedStart)]))
          .get();

  /// Planned sessions with no actual recorded whose planned end is at or
  /// before [now]: the candidates for "missed".
  Future<List<StudySession>> readUnexecutedEndedBy(DateTime now) =>
      (_db.select(_db.studySessions)
            ..where((t) =>
                t.actualStart.isNull() & t.plannedEnd.isSmallerOrEqualValue(now))
            ..orderBy([(t) => OrderingTerm.asc(t.plannedStart)]))
          .get();

  /// Planned sessions with no actual that are running at [instant]
  /// (plannedStart < instant < plannedEnd).
  Future<List<StudySession>> readUnexecutedStraddling(DateTime instant) =>
      (_db.select(_db.studySessions)
            ..where((t) =>
                t.actualStart.isNull() &
                t.plannedStart.isSmallerThanValue(instant) &
                t.plannedEnd.isBiggerThanValue(instant)))
          .get();

  /// Stores what really happened. Refuses a second actual for the same
  /// session (an actual is a fact, not a draft). Also marks the segment
  /// executed.
  Future<StudySession> recordActual({
    required String sessionId,
    required DateTime actualStart,
    required DateTime actualEnd,
  }) async {
    if (!actualEnd.isAfter(actualStart)) {
      throw ArgumentError('actualEnd must be after actualStart.');
    }
    return _db.transaction(() async {
      final existing = await readById(sessionId);
      if (existing == null) {
        throw StateError('Unknown StudySession $sessionId.');
      }
      if (existing.actualStart != null) {
        throw StateError(
            'StudySession $sessionId already has an actual recorded.');
      }
      final minutes = actualEnd.difference(actualStart).inMinutes;
      await (_db.update(_db.studySessions)
            ..where((t) => t.id.equals(sessionId)))
          .write(StudySessionsCompanion(
        actualStart: Value(actualStart),
        actualEnd: Value(actualEnd),
        observedDurationMinutes: Value(minutes),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
      final segmentId = existing.taskSegmentId;
      if (segmentId != null) {
        await (_db.update(_db.taskSegments)
              ..where((t) => t.id.equals(segmentId)))
            .write(TaskSegmentsCompanion(
          executedAt: Value(actualEnd),
          updatedAt: Value(DateTime.now().toUtc()),
        ));
      }
      return (await readById(sessionId))!;
    });
  }

  /// Deletes the FUTURE, UNEXECUTED part of a saved plan:
  /// sessions with no actual and `from <= plannedStart < to`, together with
  /// their segments when those segments were never executed. Returns the
  /// number of sessions deleted. Sessions that have an actual, or that start
  /// before [from], are never touched (the past is not rewritten).
  Future<int> deleteUnexecutedStartingIn(DateTime from, DateTime to) async {
    final rows = await (_db.select(_db.studySessions)
          ..where((t) =>
              t.actualStart.isNull() &
              t.plannedStart.isBiggerOrEqualValue(from) &
              t.plannedStart.isSmallerThanValue(to)))
        .get();
    if (rows.isEmpty) return 0;
    final ids = rows.map((r) => r.id).toList();
    final segmentIds = rows
        .map((r) => r.taskSegmentId)
        .whereType<String>()
        .toList();
    await (_db.delete(_db.studySessions)..where((t) => t.id.isIn(ids))).go();
    if (segmentIds.isNotEmpty) {
      await (_db.delete(_db.taskSegments)
            ..where((t) => t.id.isIn(segmentIds) & t.executedAt.isNull()))
          .go();
    }
    return rows.length;
  }
}
