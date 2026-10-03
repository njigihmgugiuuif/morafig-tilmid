import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/repositories/mastery_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'package:student_app/services/intelligence_service.dart';
import 'fixtures/legacy_shapes.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Exercises the real v3 -> v4 `onUpgrade` branch on a real SQLite FILE that
/// has been made to look like a v3 file (see fixtures/legacy_shapes.dart for
/// exactly what that emulation does and does not cover):
///   - the four new tables appear (empty and usable),
///   - mastery_states gains confidence/observation_count as NULL (never an
///     invented 0),
///   - subjects gains curriculum_version_id as NULL,
///   - every pre-existing row survives with its values,
///   - user_version ends at the current schema version.
void main() {
  test('a v3 database upgrades to v4 without losing data and without '
      'inventing values', () async {
    final dir = await Directory.systemTemp.createTemp('migration_v4_');
    final file = File('${dir.path}/app.sqlite');
    try {
      // 1. Build realistic data on a fresh database.
      var db = AppDatabase(NativeDatabase(file));
      final seed = await seedMinimalCurriculum(db);
      final task = await TaskRepository(db).createTask(
        knowledgeNodeId: seed.knowledgeNodeId,
        estimatedDurationMinutes: 30,
        isSplittable: false,
      );
      await TaskRepository(db)
          .markComplete(task, understanding: Understanding.good);
      final run = await IntelligenceService(db,
              clock: () => DateTime.utc(2026, 10, 1, 12))
          .processPendingEvents();
      expect(run.errors, isEmpty);
      final masteryBefore = await MasteryRepository(db)
          .read(seed.studentId, seed.knowledgeNodeId);
      expect(masteryBefore, isNotNull);
      final subjectBefore = await (db.select(db.subjects)
            ..where((t) => t.id.equals(seed.subjectId)))
          .getSingle();

      // 2. Make it look like a v3 file and close.
      await makeLookLikeV3(db);
      await db.close();

      // 3. Reopen with the current code: onUpgrade(3 -> 4) must run.
      db = AppDatabase(NativeDatabase(file));

      final version = await db.customSelect('PRAGMA user_version;').getSingle();
      expect(version.data['user_version'], equals(db.schemaVersion));
      expect(db.schemaVersion, equals(4));

      // New tables exist, are empty and accept rows.
      expect(await db.select(db.energyFocusLogs).get(), isEmpty);
      expect(await db.select(db.academicTerms).get(), isEmpty);
      expect(await db.select(db.holidays).get(), isEmpty);
      expect(await db.select(db.goals).get(), isEmpty);
      await db.into(db.goals).insert(GoalsCompanion.insert(
            studentId: seed.studentId,
            title: 'MIGRATION-TEST-GOAL',
          ));
      expect(await db.select(db.goals).get(), hasLength(1));

      // Old mastery row survived; new columns are NULL (unknown).
      final masteryAfter = await MasteryRepository(db)
          .read(seed.studentId, seed.knowledgeNodeId);
      expect(masteryAfter, isNotNull);
      expect(masteryAfter!.id, equals(masteryBefore!.id));
      expect(masteryAfter.probability, equals(masteryBefore.probability));
      expect(masteryAfter.confidence, isNull);
      expect(masteryAfter.observationCount, isNull);

      // Old subject row survived; the new link is NULL, and can be set.
      final subjectAfter = await (db.select(db.subjects)
            ..where((t) => t.id.equals(seed.subjectId)))
          .getSingle();
      expect(subjectAfter.name, equals(subjectBefore.name));
      expect(subjectAfter.curriculumVersionId, isNull);
      await (db.update(db.subjects)..where((t) => t.id.equals(seed.subjectId)))
          .write(SubjectsCompanion(
        curriculumVersionId: drift.Value(seed.curriculumVersionId),
      ));
      final linked = await (db.select(db.subjects)
            ..where((t) => t.id.equals(seed.subjectId)))
          .getSingle();
      expect(linked.curriculumVersionId, equals(seed.curriculumVersionId));

      // Other data untouched.
      expect(await db.select(db.students).get(), hasLength(1));
      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
