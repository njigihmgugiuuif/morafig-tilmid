import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'event_repository.dart';

/// Plain CRUD for Tasks — the raw planning-input table that the
/// Scheduling/Priority engines read from. Unlike MasteryStates/
/// MemoryStates (derived, recompute-only), a Task is entered directly by
/// the student, so ordinary insert/update is correct here, not a guarded
/// recompute method.
///
/// Every state-changing method also writes a real, append-only Event row
/// (TaskCreated / TaskCompleted), matching the event-sourcing model the
/// rest of the engines are built around. NOTE (explicitly not silently
/// skipped): writing the Event does NOT itself trigger a Mastery/Memory/
/// Priority recomputation pipeline yet — that cross-engine wiring is
/// Track D integration and is not part of this UI pass. The Event is
/// real and durable, so nothing is lost; a future Track D pass can read
/// these same unprocessed Events and react to them.
class TaskRepository {
  TaskRepository(this._db);
  final AppDatabase _db;

  Stream<List<Task>> watchActive(String studentIdUnused) {
    // Tasks are not currently student-scoped in the schema (single
    // student per local database — see Students table doc comment), so
    // this simply watches all non-complete tasks.
    return (_db.select(_db.tasks)
          ..where((t) => t.completionStatus.equals('complete').not())
          ..orderBy([(t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)]))
        .watch();
  }

  Stream<List<Task>> watchCompleted() {
    return (_db.select(_db.tasks)
          ..where((t) => t.completionStatus.equals('complete'))
          ..orderBy([(t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)])
          ..limit(50))
        .watch();
  }

  Future<Task> createTask({
    required String knowledgeNodeId,
    required int estimatedDurationMinutes,
    required bool isSplittable,
    int? minimumChunkDurationMinutes,
  }) async {
    return _db.transaction(() async {
      final task = await _db.into(_db.tasks).insertReturning(
            TasksCompanion.insert(
              knowledgeNodeId: knowledgeNodeId,
              estimatedDurationMinutes: estimatedDurationMinutes,
              isSplittable: Value(isSplittable),
              minimumChunkDurationMinutes:
                  Value(minimumChunkDurationMinutes),
              remainingDurationMinutes: estimatedDurationMinutes,
              completionStatus: const Value('notStarted'),
              sourceType: 'regular',
            ),
          );
      await EventRepository(_db).insertRow(
        EventsCompanion.insert(
          type: 'TaskCreated',
          payloadJson: '{"taskId":"${task.id}"}',
          triggersReplan: false,
        ),
      );
      return task;
    });
  }

  Future<void> markComplete(Task task) async {
    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id)))
          .write(const TasksCompanion(
        completionStatus: Value('complete'),
        remainingDurationMinutes: Value(0),
      ));
      await EventRepository(_db).insertRow(
        EventsCompanion.insert(
          type: 'TaskCompleted',
          payloadJson: '{"taskId":"${task.id}"}',
          triggersReplan: true,
        ),
      );
    });
  }

  Future<void> delete(Task task) {
    return (_db.delete(_db.tasks)..where((t) => t.id.equals(task.id))).go();
  }
}
