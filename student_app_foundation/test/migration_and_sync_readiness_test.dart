import 'package:test/test.dart';
import 'package:drift/drift.dart';

import 'package:student_app/database/app_database.dart';

void main() {
  group('F. Migration', () {
    test('a brand-new in-memory database opens at schemaVersion 1 without '
        'error', () async {
      final db = AppDatabase.forTesting();
      final version =
          await db.customSelect('PRAGMA user_version;').getSingle();
      expect(version.data['user_version'], equals(1));
      await db.close();
    });

    test('onCreate builds every table (no table left out of createAll())',
        () async {
      final db = AppDatabase.forTesting();
      for (final table in db.allTables) {
        await db.select(table).get(); // throws if the table wasn't created
      }
      await db.close();
    });

    // NOTE — genuine test debt, documented rather than hidden:
    // A real "old data survives a schema bump" migration test requires an
    // actual v1 -> v2 transition to exist, which it does not yet (this IS
    // v1, per migration_strategy.dart). This test is a placeholder that
    // documents the exact shape the real test must take once v2 exists,
    // rather than a fabricated pass. See FOUNDATION_IMPLEMENTATION_REPORT.md.
    test('[PLACEHOLDER] v1 -> v2 migration preserves existing rows', () {
      // When v2 is introduced:
      //   1. Build a v1 database file with seed data.
      //   2. Open it with the v2 AppDatabase (triggers onUpgrade).
      //   3. Assert the seeded rows are still present and correctly shaped.
    }, skip: 'No v2 exists yet — this phase only defines v1.');
  });

  group('G. Sync readiness (fields only, no network sync implemented)', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    test('every table has id (UUID-shaped text), createdAt, updatedAt, '
        'syncVersion columns', () {
      for (final table in db.allTables) {
        final columnNames = table.$columns.map((c) => c.name.name).toSet();
        expect(columnNames, contains('id'));
        expect(columnNames, contains('created_at'));
        expect(columnNames, contains('updated_at'));
        expect(columnNames, contains('sync_version'));
      }
    });

    test('inserted ids look like UUIDs (36 chars, hyphenated), not '
        'sequential integers', () async {
      final year = await db.into(db.academicYears).insertReturning(
            AcademicYearsCompanion.insert(
              label: 'SYNC-TEST',
              startDate: DateTime.utc(2000, 1, 1),
              endDate: DateTime.utc(2001, 1, 1),
            ),
          );
      expect(year.id.length, equals(36));
      expect(year.id.split('-').length, equals(5));
    });

    test('SyncMetadataEntries table exists and is ready to receive rows '
        'once a real sync engine is built (not implemented in this phase)',
        () async {
      final rows = await db.select(db.syncMetadataEntries).get();
      expect(rows, isEmpty); // table exists, unused — exactly as designed
    });
  });
}
