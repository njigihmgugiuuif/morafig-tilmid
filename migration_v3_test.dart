import 'dart:io';

import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'fixtures/legacy_shapes.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Exercises the real v2 -> v3 (-> v4) `onUpgrade` branches: a database file
/// that has every v2 table but NOT weekly_template_entries (nor the v4
/// additions) and reports user_version = 2 must gain the template table on
/// open, keep its existing rows, and end at the CURRENT schema version.
/// (Before v4 existed this test asserted 3; the chain now continues to the
/// current version, which is the correct end state for a v2 file.)
void main() {
  test('a v2 database upgrades through v3, gains the template table and '
      'keeps data', () async {
    final dir = await Directory.systemTemp.createTemp('migration_v3_');
    final file = File('${dir.path}/app.sqlite');
    try {
      // 1. Create a fresh database, then make it look like a v2 file.
      var db = AppDatabase(NativeDatabase(file));
      final year = await db.into(db.academicYears).insertReturning(
            AcademicYearsCompanion.insert(
              label: 'MIGRATION-TEST',
              startDate: DateTime.utc(2000, 9, 1),
              endDate: DateTime.utc(2001, 6, 30),
            ),
          );
      await makeLookLikeV2(db);
      await db.close();

      // 2. Reopen with the current code: onUpgrade(2 -> current) must run.
      db = AppDatabase(NativeDatabase(file));
      final templateRows = await db.select(db.weeklyTemplateEntries).get();
      expect(templateRows, isEmpty);

      final version = await db.customSelect('PRAGMA user_version;').getSingle();
      expect(version.data['user_version'], equals(db.schemaVersion));

      // 3. Existing data survived the upgrade.
      final years = await db.select(db.academicYears).get();
      expect(years.map((y) => y.id), contains(year.id));
      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
