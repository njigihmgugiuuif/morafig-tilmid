import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/repositories/curriculum_repository.dart';
import 'fixtures/legacy_shapes.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Exercises the real v4 -> v5 `onUpgrade` branch on a real SQLite FILE made
/// to look like a v4 file (see fixtures/legacy_shapes.dart):
///   - curriculum_versions gains countryCode / versionLabel as NULL (never an
///     invented value),
///   - the existing version row and its subject load survive and stay
///     readable, and the Guard #2 result on the old data is unchanged,
///   - the new columns can then be written,
///   - user_version ends at 5.
void main() {
  test('a v4 database upgrades to v5 without losing data and without '
      'inventing values', () async {
    final dir = await Directory.systemTemp.createTemp('migration_v5_');
    final file = File('${dir.path}/app.sqlite');
    try {
      var db = AppDatabase(NativeDatabase(file));
      final seed = await seedMinimalCurriculum(db);
      final before = await CurriculumRepository(db)
          .readCurriculumVersion(seed.curriculumVersionId);
      expect(before, isNotNull);

      await makeLookLikeV4(db);
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      final repo = CurriculumRepository(db);

      final version = await db.customSelect('PRAGMA user_version;').getSingle();
      // The file is upgraded all the way to the current schema (v6 added
      // the Student Integration columns, DEVIATION-19); this test is about
      // the v4 -> v5 step, so it only requires >= 5.
      expect(version.data['user_version'], equals(db.schemaVersion));
      expect(db.schemaVersion, greaterThanOrEqualTo(5));

      final after = await repo.readCurriculumVersion(seed.curriculumVersionId);
      expect(after, isNotNull);
      expect(after!.id, equals(before!.id));
      expect(after.status, equals(before.status));
      expect(after.sourcePolicyDocumentId, equals(before.sourcePolicyDocumentId));
      expect(after.countryCode, isNull);
      expect(after.versionLabel, isNull);

      // Old data is still readable and Guard #2 still answers as before.
      expect(await repo.getUsableCoefficient(seed.subjectLoadId), equals(5.0));

      // The new columns are usable after the upgrade.
      await (db.update(db.curriculumVersions)
            ..where((t) => t.id.equals(seed.curriculumVersionId)))
          .write(CurriculumVersionsCompanion(
        countryCode: const drift.Value('ZZ'),
        versionLabel: const drift.Value('TEST-LABEL'),
      ));
      final written =
          await repo.readCurriculumVersion(seed.curriculumVersionId);
      expect(written!.countryCode, equals('ZZ'));
      expect(written.versionLabel, equals('TEST-LABEL'));

      expect(await db.select(db.students).get(), hasLength(1));
      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
