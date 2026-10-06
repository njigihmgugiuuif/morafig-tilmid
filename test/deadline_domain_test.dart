import 'package:drift/drift.dart' as drift;
import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/deadline_domain.dart';
import 'package:student_app/repositories/deadline_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// A-1 (DEVIATION-21): deadline pressure. The 21-day horizon is an INITIAL
/// HEURISTIC approved by the owner, not an official rule. All data is
/// SYNTHETIC.
void main() {
  group('deadlinePressureSignal() — pure', () {
    test('no due date -> null (unknown), never 0', () {
      expect(DeadlineDomainService.deadlinePressureSignal(null), isNull);
    });

    test('a due date that has passed (open task) -> 1.0', () {
      expect(DeadlineDomainService.deadlinePressureSignal(const Duration(days: -3)),
          1.0);
      expect(DeadlineDomainService.deadlinePressureSignal(Duration.zero), 1.0);
    });

    test('at or beyond the horizon -> 0.0', () {
      expect(DeadlineDomainService.defaultHorizonDays, 21.0);
      expect(DeadlineDomainService.deadlinePressureSignal(const Duration(days: 21)),
          0.0);
      expect(DeadlineDomainService.deadlinePressureSignal(const Duration(days: 90)),
          0.0);
    });

    test('linear ramp inside the horizon: 1 - days / 21', () {
      expect(
        DeadlineDomainService.deadlinePressureSignal(const Duration(days: 7)),
        closeTo(1.0 - 7.0 / 21.0, 1e-9),
      );
      expect(
        DeadlineDomainService.deadlinePressureSignal(
            const Duration(days: 10, hours: 12)),
        closeTo(0.5, 1e-9),
      );
    });

    test('pressure never decreases as the due date gets closer', () {
      double? previous;
      for (var d = 25; d >= -2; d--) {
        final p = DeadlineDomainService.deadlinePressureSignal(Duration(days: d))!;
        expect(p, inInclusiveRange(0.0, 1.0));
        if (previous != null) expect(p, greaterThanOrEqualTo(previous));
        previous = p;
      }
    });

    test('a custom horizon is honoured', () {
      expect(
        DeadlineDomainService.deadlinePressureSignal(const Duration(days: 5),
            horizonDays: 10),
        closeTo(0.5, 1e-9),
      );
    });
  });

  group('pressureForTask() — with a database', () {
    late AppDatabase db;
    late MinimalCurriculumSeed seed;
    late DeadlineDomainService service;
    final now = DateTime.utc(2026, 10, 1, 12);

    setUp(() async {
      db = createInMemoryTestDatabase();
      seed = await seedMinimalCurriculum(db);
      service = DeadlineDomainService(DeadlineRepository(db));
    });
    tearDown(() => db.close());

    Future<Task> newTask() => TaskRepository(db).createTask(
          knowledgeNodeId: seed.knowledgeNodeId,
          estimatedDurationMinutes: 30,
          isSplittable: false,
        );

    Future<void> addDeadline(String entityId, String type, DateTime due,
        {bool hard = true}) {
      return db.into(db.deadlines).insert(DeadlinesCompanion.insert(
            relatedEntityId: entityId,
            relatedEntityType: type,
            dueDateTime: due,
            isHard: hard,
          ));
    }

    test('a task with no due date at all -> null', () async {
      final t = await newTask();
      expect(await service.pressureForTask(taskId: t.id, now: now), isNull);
    });

    test('a Task deadline gives the ramp value', () async {
      final t = await newTask();
      await addDeadline(t.id, 'Task', now.add(const Duration(days: 7)));
      expect(await service.pressureForTask(taskId: t.id, now: now),
          closeTo(1.0 - 7.0 / 21.0, 1e-9));
    });

    test('an overdue deadline on an open task -> 1.0', () async {
      final t = await newTask();
      await addDeadline(t.id, 'Task', now.subtract(const Duration(days: 2)));
      expect(await service.pressureForTask(taskId: t.id, now: now), 1.0);
    });

    test('with several deadlines the most pressing one decides', () async {
      final t = await newTask();
      await addDeadline(t.id, 'Task', now.add(const Duration(days: 15)));
      await addDeadline(t.id, 'Task', now.add(const Duration(days: 3)),
          hard: false);
      expect(await service.pressureForTask(taskId: t.id, now: now),
          closeTo(1.0 - 3.0 / 21.0, 1e-9));
    });

    test('an Exam deadline is NOT read here (examProximity owns it)',
        () async {
      final t = await newTask();
      await addDeadline(t.id, 'Exam', now.add(const Duration(days: 1)));
      expect(await service.pressureForTask(taskId: t.id, now: now), isNull);
    });

    test('a deadline of another task is not used', () async {
      final mine = await newTask();
      final other = await newTask();
      await addDeadline(other.id, 'Task', now.add(const Duration(days: 1)));
      expect(await service.pressureForTask(taskId: mine.id, now: now), isNull);
    });

    test('the linked assignment\'s due date and its Deadline rows are read',
        () async {
      final assignment = await db.into(db.assignments).insertReturning(
            AssignmentsCompanion.insert(
              subjectId: seed.subjectId,
              description: 'TEST-ASSIGNMENT',
              dueDate: now.add(const Duration(days: 14)),
            ),
          );
      final t = await db.into(db.tasks).insertReturning(TasksCompanion.insert(
            knowledgeNodeId: seed.knowledgeNodeId,
            estimatedDurationMinutes: 30,
            remainingDurationMinutes: 30,
            sourceType: 'assignment',
            sourceAssignmentId: drift.Value(assignment.id),
          ));

      // Only Assignments.dueDate exists: 14 days away.
      expect(
          await service.pressureForTask(
              taskId: t.id, sourceAssignmentId: assignment.id, now: now),
          closeTo(1.0 - 14.0 / 21.0, 1e-9));

      // A nearer Deadline row on the assignment takes over.
      await addDeadline(
          assignment.id, 'Assignment', now.add(const Duration(days: 2)));
      expect(
          await service.pressureForTask(
              taskId: t.id, sourceAssignmentId: assignment.id, now: now),
          closeTo(1.0 - 2.0 / 21.0, 1e-9));

      // Without passing the link, the assignment is not consulted.
      expect(await service.pressureForTask(taskId: t.id, now: now), isNull);
    });
  });
}
