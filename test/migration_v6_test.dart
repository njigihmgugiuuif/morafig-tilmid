import 'dart:io';

import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/repositories/student_repository.dart';
import 'fixtures/legacy_shapes.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Exercises the real v5 -> v6 `onUpgrade` branch (Student Integration,
/// DEVIATION-19) on a real SQLite FILE made to look like a v5 file:
///   - students gains education_level_id / stream_id / curriculum_version_id
///     as NULL (never an invented value),
///   - the existing student row survives unchanged,
///   - the new columns are usable through StudentRepository afterwards,
///   - user_version ends at the current schema version.
void main() {
  test('a v5 database upgrades to v6 without losing data and without '
      'inventing values', () async {
    final dir = await Directory.systemTemp.createTemp('migration_v6_');
    final file = File('${dir.path}/app.sqlite');
    try {
      var db = AppDatabase(NativeDatabase(file));
      final seed = await seedMinimalCurriculum(db);
      final before = await StudentRepository(db).readExisting();
      expect(before, isNotNull);

      await makeLookLikeV5(db);
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      final repo = StudentRepository(db);

      final version = await db.customSelect('PRAGMA user_version;').getSingle();
      expect(version.data['user_version'], equals(db.schemaVersion));
      expect(db.schemaVersion, greaterThanOrEqualTo(6));

      final after = await repo.readExisting();
      expect(after, isNotNull);
      expect(after!.id, equals(before!.id));
      expect(after.fullNameOrNickname, equals(before.fullNameOrNickname));
      expect(after.currentAcademicYearId, equals(before.currentAcademicYearId));
      expect(after.educationLevelId, isNull);
      expect(after.streamId, isNull);
      expect(after.curriculumVersionId, isNull);

      // The new columns are usable after the upgrade (FK enforcement is ON).
      final level = await db.select(db.educationLevels).getSingle();
      await repo.setAcademicTrack(
          studentId: seed.studentId, educationLevelId: level.id);
      final linked = await repo.readExisting();
      expect(linked!.educationLevelId, equals(level.id));

      await repo.setCurriculumVersion(
          studentId: seed.studentId,
          curriculumVersionId: seed.curriculumVersionId);
      final withVersion = await repo.readExisting();
      expect(withVersion!.curriculumVersionId, equals(seed.curriculumVersionId));

      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
