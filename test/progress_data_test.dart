import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/repositories/mastery_repository.dart';
import 'package:student_app/repositories/memory_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'package:student_app/services/intelligence_service.dart';
import 'package:student_app/ui/state/progress_data.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// The progress charts must show what the engines really computed from
/// recorded evidence. All data is SYNTHETIC.
void main() {
  late AppDatabase db;
  late MinimalCurriculumSeed seed;

  setUp(() async {
    db = createInMemoryTestDatabase();
    seed = await seedMinimalCurriculum(db);
  });
  tearDown(() => db.close());

  Future<Task> newTask() => TaskRepository(db).createTask(
        knowledgeNodeId: seed.knowledgeNodeId,
        estimatedDurationMinutes: 30,
        isSplittable: false,
      );

  Future<void> complete(String understanding) async {
    final t = await newTask();
    await TaskRepository(db).markComplete(t, understanding: understanding);
    final r = await IntelligenceService(db).processPendingEvents();
    expect(r.errors, isEmpty);
  }

  group('mastery trajectory', () {
    test('is empty when there is no recorded answer', () async {
      await newTask();
      expect(await ProgressData(db).masteryTrajectory(seed.knowledgeNodeId),
          isEmpty);
    });

    test('replaying the answers ends on the mastery the engine stored',
        () async {
      await complete(Understanding.good);
      await complete(Understanding.good);
      await complete(Understanding.good);

      final steps =
          await ProgressData(db).masteryTrajectory(seed.knowledgeNodeId);
      expect(steps.length, 3);
      // Three good answers can only push mastery upward.
      expect(steps[1].probability, greaterThan(steps[0].probability));
      expect(steps[2].probability, greaterThan(steps[1].probability));

      final stored = await MasteryRepository(db)
          .read(seed.studentId, seed.knowledgeNodeId);
      expect(steps.last.probability, closeTo(stored!.probability, 1e-9));
    });

    test('skipped and partly-understood answers add no point', () async {
      await complete(Understanding.partial);
      await complete(Understanding.unknown);
      expect(await ProgressData(db).masteryTrajectory(seed.knowledgeNodeId),
          isEmpty);
    });
  });

  group('forgetting curve', () {
    test('starts at full recall and never rises', () async {
      await complete(Understanding.good);
      final memory = await MemoryRepository(db)
          .read(seed.studentId, seed.knowledgeNodeId);
      expect(memory, isNotNull);

      final curve = ProgressData(db)
          .forgettingCurve(memory!, DateTime.now().toUtc())!;
      expect(curve.points.first.day, 0);
      expect(curve.points.first.recall, closeTo(1.0, 1e-9));
      for (var i = 1; i < curve.points.length; i++) {
        expect(curve.points[i].recall,
            lessThanOrEqualTo(curve.points[i - 1].recall));
      }
      expect(curve.recallNow, inInclusiveRange(0.0, 1.0));
      expect(curve.points.last.day, greaterThanOrEqualTo(30));
    });
  });

  group('overview counts', () {
    test('counts finished and open tasks per subject', () async {
      await complete(Understanding.good);
      await newTask();
      final rows = await ProgressData(db).subjectProgress();
      expect(rows.length, 1);
      expect(rows.single.done, 1);
      expect(rows.single.open, 1);
    });

    test('weekly counts add up to the completions of the last weeks',
        () async {
      await complete(Understanding.good);
      await complete(Understanding.notUnderstood);
      final weeks =
          await ProgressData(db).weeklyCompletions(DateTime.now().toUtc());
      expect(weeks.length, 8);
      expect(weeks.fold<int>(0, (a, w) => a + w.count), 2);
    });
  });
}
