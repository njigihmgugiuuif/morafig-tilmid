import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/repositories/explanation_and_override_repositories.dart';
import 'package:student_app/repositories/priority_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'package:student_app/services/intelligence_service.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// «ليست مناسبة الآن»: the answer is stored as a fact (append-only) pointing
/// at the explanation the student saw, and nothing else changes.
void main() {
  late AppDatabase db;
  late MinimalCurriculumSeed seed;

  setUp(() async {
    db = createInMemoryTestDatabase();
    seed = await seedMinimalCurriculum(db);
  });
  tearDown(() => db.close());

  test('records a postponement and leaves the priority unchanged', () async {
    final repo = TaskRepository(db);
    final done = await repo.createTask(
        knowledgeNodeId: seed.knowledgeNodeId,
        estimatedDurationMinutes: 30,
        isSplittable: false);
    final open = await repo.createTask(
        knowledgeNodeId: seed.knowledgeNodeId,
        estimatedDurationMinutes: 30,
        isSplittable: false);
    await repo.markComplete(done, understanding: Understanding.notUnderstood);
    await IntelligenceService(db).processPendingEvents();

    final before = await PriorityRepository(db).read(open.id);
    expect(before, isNotNull);

    await HumanOverrideRepository(db).record(
        taskId: open.id,
        action: 'postpone',
        explanationId: before!.explanationId,
        reportedReason: 'تعب');

    final rows = await HumanOverrideRepository(db).readByTask(open.id);
    expect(rows.length, 1);
    expect(rows.single.action, 'postpone');
    expect(rows.single.systemStateSnapshotId, before.explanationId);

    final after = await PriorityRepository(db).read(open.id);
    expect(after!.score, before.score);
  });
}
