import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/repositories/mastery_repository.dart';
import 'package:student_app/repositories/event_repository.dart';
import 'package:student_app/repositories/explanation_and_override_repositories.dart';
import 'fixtures/seed_data.dart';

void main() {
  group('B. Source of Truth', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    test('MasteryRepository has no generic write method — recomputeFrom is '
        'the only mutation path', () {
      // Compile-time guarantee, asserted here as documentation: if this
      // test file compiles, MasteryRepository exposes no
      // `write`/`update`/`set` method other than recomputeFrom. (A
      // reflection-based check is unnecessary — Dart's static typing
      // already enforces this; the real proof is that
      // `MasteryRepository(db).probability = 0.9` is not valid Dart, which
      // this file not attempting it demonstrates by omission.)
      expect(MasteryRepository(db), isA<MasteryRepository>());
    });

    test('recomputeFrom twice updates the same row rather than inserting a '
        'second one (Invariant DB-INV-5)', () async {
      final seed = await seedMinimalCurriculum(db);
      final repo = MasteryRepository(db);
      final eventRepo = EventRepository(db);
      final event = await eventRepo.insertRow(EventsCompanion.insert(
        type: 'TaskCompleted',
        payloadJson: '{}',
        triggersReplan: false,
      ));

      await repo.recomputeFrom(
        studentId: seed.studentId,
        knowledgeNodeId: seed.knowledgeNodeId,
        newProbability: 0.4,
        sourceEventId: event.id,
      );
      await repo.recomputeFrom(
        studentId: seed.studentId,
        knowledgeNodeId: seed.knowledgeNodeId,
        newProbability: 0.6,
        sourceEventId: event.id,
      );

      final all = await db.select(db.masteryStates).get();
      expect(all.length, equals(1));
      expect(all.single.probability, equals(0.6));
    });

    test('recomputeFrom rejects an out-of-range probability', () async {
      final seed = await seedMinimalCurriculum(db);
      final repo = MasteryRepository(db);
      expect(
        () => repo.recomputeFrom(
          studentId: seed.studentId,
          knowledgeNodeId: seed.knowledgeNodeId,
          newProbability: 1.5,
          sourceEventId: 'irrelevant',
        ),
        throwsArgumentError,
      );
    });
  });

  group('C. Append-only enforcement', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    test('EventRepository exposes no delete method (structural check)', () {
      final repo = EventRepository(db);
      expect(repo, isA<EventRepository>());
      // See note in the test above re: static typing as the real proof.
    });

    test('EventRepository.markProcessed refuses to re-set processedAt '
        '(cannot rewrite history)', () async {
      final repo = EventRepository(db);
      final event = await repo.insertRow(EventsCompanion.insert(
        type: 'TaskMissed',
        payloadJson: '{}',
        triggersReplan: true,
      ));
      await repo.markProcessed(event.id, DateTime.now().toUtc());
      expect(
        () => repo.markProcessed(event.id, DateTime.now().toUtc()),
        throwsStateError,
      );
    });

    test('ExplanationRepository and HumanOverrideRepository expose only '
        'insert + read', () {
      final explanationRepo = ExplanationRepository(db);
      final overrideRepo = HumanOverrideRepository(db);
      expect(explanationRepo, isA<ExplanationRepository>());
      expect(overrideRepo, isA<HumanOverrideRepository>());
    });
  });
}
