import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/export_import/export_import_service.dart';
import 'package:student_app/repositories/reset_repository.dart';
import 'package:student_app/repositories/student_repository.dart';
import 'package:student_app/repositories/task_repository.dart';
import 'fixtures/seed_data.dart';

/// Settings screen data layer: profile edit, backup restore, full reset.
/// All data is synthetic.
void main() {
  late AppDatabase db;

  setUp(() => db = createInMemoryTestDatabase());
  tearDown(() => db.close());

  group('Settings: profile, restore, reset', () {
    test('updateProfile persists the new name and sleep floor', () async {
      final repo = StudentRepository(db);
      final s = await repo.createInitialStudent(
          fullNameOrNickname: 'A', sleepFloorMinMinutes: 420);

      await repo.updateProfile(
        studentId: s.id,
        fullNameOrNickname: 'B',
        sleepFloorMinMinutes: 480,
      );

      final r = await repo.readExisting();
      expect(r, isNotNull);
      expect(r!.id, equals(s.id));
      expect(r.fullNameOrNickname, equals('B'));
      expect(r.sleepFloorMinMinutes, equals(480));
    });

    test('wipeAllData empties every table (append-only included) and a new '
        'student can then be created', () async {
      final seed = await seedMinimalCurriculum(db);
      await TaskRepository(db).createTask(
        knowledgeNodeId: seed.knowledgeNodeId,
        estimatedDurationMinutes: 30,
        isSplittable: false,
      );
      expect(await db.select(db.events).get(), isNotEmpty);

      await ResetRepository(db).wipeAllData();

      for (final table in db.allTables) {
        final rows = await db.select(table).get();
        expect(rows, isEmpty,
            reason: 'table ${table.actualTableName} still has rows');
      }

      final again = await StudentRepository(db).createInitialStudent(
          fullNameOrNickname: 'C', sleepFloorMinMinutes: 420);
      expect(again.fullNameOrNickname, equals('C'));
    });

    test('restoreReplacingAll reproduces the backup and replaces other '
        'data', () async {
      final seed = await seedMinimalCurriculum(db);
      final json = await ExportImportService(db).exportAll();

      final target = createInMemoryTestDatabase();
      await StudentRepository(target).createInitialStudent(
          fullNameOrNickname: 'Other', sleepFloorMinMinutes: 420);

      await ExportImportService(target).restoreReplacingAll(json);

      final students = await target.select(target.students).get();
      expect(students, hasLength(1));
      expect(students.single.id, equals(seed.studentId));
      final nodes = await target.select(target.knowledgeNodes).get();
      expect(nodes.map((n) => n.id), contains(seed.knowledgeNodeId));

      await target.close();
    });

    test('a failed restore leaves the existing data untouched', () async {
      await StudentRepository(db).createInitialStudent(
          fullNameOrNickname: 'Keep', sleepFloorMinMinutes: 420);

      const bad = '{"exportedAt":"2026-01-01T00:00:00Z","schemaVersion":1,'
          '"tables":{"students":[{"id":"x"}]}}';
      await expectLater(
        ExportImportService(db).restoreReplacingAll(bad),
        throwsA(isA<ImportValidationException>()),
      );

      final rows = await db.select(db.students).get();
      expect(rows, hasLength(1));
      expect(rows.single.fullNameOrNickname, equals('Keep'));
    });
  });
}
