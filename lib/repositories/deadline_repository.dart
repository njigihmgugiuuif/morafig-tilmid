import '../database/app_database.dart';

/// READ-ONLY access to the due dates that already exist in the schema
/// (A-1, DEVIATION-21). It never writes: nothing in the app creates
/// Deadlines or Assignments yet, so for real users this returns an empty list
/// until a later phase adds a writer. It does not invent a date.
///
/// Sources, and only these:
///   - `Deadlines` rows whose `relatedEntityType` is 'Task' and whose
///     `relatedEntityId` is the task;
///   - `Deadlines` rows whose `relatedEntityType` is 'Assignment' and whose
///     `relatedEntityId` is the task's `sourceAssignmentId`;
///   - `Assignments.dueDate` of that same linked assignment.
/// 'Exam' deadlines are deliberately NOT read here: exam proximity is
/// already its own signal (examProximity), and reading it again would count
/// the same fact twice.
class DeadlineRepository {
  DeadlineRepository(this._db);
  final AppDatabase _db;

  /// Every known due date for one task (hard and soft alike), in no
  /// particular order. Empty when the task has none.
  Future<List<DateTime>> readDueDatesForTask({
    required String taskId,
    String? sourceAssignmentId,
  }) async {
    final dates = <DateTime>[];

    final own = await (_db.select(_db.deadlines)
          ..where((t) =>
              t.relatedEntityType.equals('Task') &
              t.relatedEntityId.equals(taskId)))
        .get();
    dates.addAll(own.map((d) => d.dueDateTime));

    if (sourceAssignmentId != null) {
      final viaAssignment = await (_db.select(_db.deadlines)
            ..where((t) =>
                t.relatedEntityType.equals('Assignment') &
                t.relatedEntityId.equals(sourceAssignmentId)))
          .get();
      dates.addAll(viaAssignment.map((d) => d.dueDateTime));

      final assignment = await (_db.select(_db.assignments)
            ..where((t) => t.id.equals(sourceAssignmentId)))
          .getSingleOrNull();
      if (assignment != null) dates.add(assignment.dueDate);
    }

    return dates;
  }
}
