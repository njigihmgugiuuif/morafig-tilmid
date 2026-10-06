import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/enums.dart';
import 'package:student_app/repositories/event_repository.dart';
import 'package:student_app/repositories/exam_repository.dart';
import 'package:student_app/repositories/mastery_repository.dart';
import 'package:student_app/repositories/memory_repository.dart';
import 'package:student_app/repositories/priority_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'package:student_app/services/intelligence_service.dart';
import 'fixtures/seed_data.dart';

/// Track D: proves the engines are really driven by events, end to end,
/// against a real (in-memory) database. All data is synthetic.
void main() {
  late AppDatabase db;
  late MinimalCurriculumSeed seed;
  final fixedNow = DateTime.utc(2026, 10, 1, 12);

  setUp(() async {
    db = createInMemoryTestDatabase();
    seed = await seedMinimalCurriculum(db);
  });
  tearDown(() => db.close());

  IntelligenceService service() =>
      IntelligenceService(db, clock: () => fixedNow);

  Future<Task> newTask() => TaskRepository(db).createTask(
        knowledgeNodeId: seed.knowledgeNodeId,
        estimatedDurationMinutes: 30,
        isSplittable: false,
      );

  group('D. Intelligence integration', () {
    test('good understanding raises mastery (BKT) and creates a memory '
        'state (FSRS); the event is marked processed', () async {
      final done = await newTask();
      await TaskRepository(db).markComplete(done,
          understanding: Understanding.good);

      final result = await service().processPendingEvents();
      expect(result.errors, isEmpty);

      final mastery =
          await MasteryRepository(db).read(seed.studentId, seed.knowledgeNodeId);
      expect(mastery, isNotNull);
      // BKT defaults: P(L0)=0.3, slip=0.1, guess=0.2, transition=0.1
      // posterior = 0.27/0.41 = 0.6585; after transition = 0.6927.
      expect(mastery!.probability, closeTo(0.6927, 0.005));

      final memory =
          await MemoryRepository(db).read(seed.studentId, seed.knowledgeNodeId);
      expect(memory, isNotNull);
      expect(memory!.stability, greaterThan(0));

      expect(await EventRepository(db).readUnprocessed(), isEmpty);
    });

    test('not understood lowers mastery below the initial prior', () async {
      final done = await newTask();
      await TaskRepository(db).markComplete(done,
          understanding: Understanding.notUnderstood);

      final result = await service().processPendingEvents();
      expect(result.errors, isEmpty);

      final mastery =
          await MasteryRepository(db).read(seed.studentId, seed.knowledgeNodeId);
      expect(mastery, isNotNull);
      // posterior = 0.03/0.59 = 0.0508; after transition = 0.1458.
      expect(mastery!.probability, closeTo(0.1458, 0.005));
      expect(mastery.probability, lessThan(0.3));
    });

    test('skipped feedback creates NO mastery/memory (nothing is guessed)',
        () async {
      final done = await newTask();
      await TaskRepository(db).markComplete(done); // understanding unknown

      final result = await service().processPendingEvents();
      expect(result.errors, isEmpty);

      expect(
          await MasteryRepository(db)
              .read(seed.studentId, seed.knowledgeNodeId),
          isNull);
      expect(
          await MemoryRepository(db)
              .read(seed.studentId, seed.knowledgeNodeId),
          isNull);
      expect(await EventRepository(db).readUnprocessed(), isEmpty);
    });

    test('an open task gets a priority with a real explanation after a '
        'weak result on the same node', () async {
      final done = await newTask();
      final open = await newTask();
      await TaskRepository(db).markComplete(done,
          understanding: Understanding.notUnderstood);

      final result = await service().processPendingEvents();
      expect(result.errors, isEmpty);

      final priority = await PriorityRepository(db).read(open.id);
      expect(priority, isNotNull);
      expect(priority!.score, inInclusiveRange(0.0, 1.0));
      // Completed task is not ranked.
      expect(await PriorityRepository(db).read(done.id), isNull);

      final explanation = await (db.select(db.explanations)
            ..where((t) => t.id.equals(priority.explanationId)))
          .getSingle();
      expect(explanation.factorsJson, contains('masteryGap'));
      // The pre-A-0 name is no longer written (old rows keep it, read via
      // canonicalPrioritySignalName).
      expect(explanation.factorsJson, isNot(contains('personalWeakness')));
      // Unknown signals are listed as excluded, never invented.
      expect(explanation.excludedFactorsJson, contains('officialCoefficient'));
    });

    test('with no signal at all, an open task gets no priority yet',
        () async {
      final open = await newTask();
      await service().refreshPriorities();
      expect(await PriorityRepository(db).read(open.id), isNull);
    });

    test('a near exam alone produces an exam-driven priority', () async {
      final open = await newTask();
      await ExamRepository(db).insert(
        subjectId: seed.subjectId,
        examDate: DateTime.utc(2026, 10, 6, 12), // exactly 5 days later
        examType: ExamType.summative,
      );

      await service().refreshPriorities();

      final priority = await PriorityRepository(db).read(open.id);
      expect(priority, isNotNull);
      // Only one signal available -> weights renormalise to 1:
      // examProximity(5 days, 21-day horizon) = 1 - 5/21 = 0.7619.
      expect(priority!.score, closeTo(0.7619, 0.005));
    });
  });
}
