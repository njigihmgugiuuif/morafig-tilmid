import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/repositories/study_session_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'package:student_app/services/planning_service.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Recording what really happened must teach the time estimate of the
/// subject (Time Estimation engine), without touching the task or the plan.
void main() {
  late AppDatabase db;
  late MinimalCurriculumSeed seed;

  setUp(() async {
    db = createInMemoryTestDatabase();
    seed = await seedMinimalCurriculum(db);
  });
  tearDown(() => db.close());

  test('a recorded session creates a time estimate for its subject',
      () async {
    final task = await TaskRepository(db).createTask(
      knowledgeNodeId: seed.knowledgeNodeId,
      estimatedDurationMinutes: 30,
      isSplittable: false,
    );
    final start = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final s = await StudySessionRepository(db).insertPlanned(
        taskId: task.id,
        plannedStart: start,
        plannedEnd: start.add(const Duration(minutes: 30)));

    await PlanningService(db).recordSessionActual(
        sessionId: s.id,
        actualStart: start,
        actualEnd: start.add(const Duration(minutes: 45)));

    final estimates = await db.select(db.timeEstimates).get();
    expect(estimates.length, 1);
    expect(estimates.single.subjectId, seed.subjectId);
    expect(estimates.single.estimatedDurationMinutes, 45);
    expect(estimates.single.basis, isNotEmpty);

    // The task itself is untouched: the plan keeps using its own duration.
    final again = await (db.select(db.tasks)
          ..where((t) => t.id.equals(task.id)))
        .getSingle();
    expect(again.estimatedDurationMinutes, 30);
  });

  test('an actual can be recorded only once for a session', () async {
    final task = await TaskRepository(db).createTask(
      knowledgeNodeId: seed.knowledgeNodeId,
      estimatedDurationMinutes: 30,
      isSplittable: false,
    );
    final start = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final s = await StudySessionRepository(db).insertPlanned(
        taskId: task.id,
        plannedStart: start,
        plannedEnd: start.add(const Duration(minutes: 30)));
    final svc = PlanningService(db);
    await svc.recordSessionActual(
        sessionId: s.id,
        actualStart: start,
        actualEnd: start.add(const Duration(minutes: 30)));
    expect(
        () => svc.recordSessionActual(
            sessionId: s.id,
            actualStart: start,
            actualEnd: start.add(const Duration(minutes: 20))),
        throwsStateError);
  });
}
