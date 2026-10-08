import 'package:drift/drift.dart';

import 'connection/connection.dart';
import 'tables/teacher_content_tables.dart';

part 'teacher_content_database.g.dart';

/// Teacher content lives in its OWN local database (phase C, DEVIATION-23).
///
/// Why separate: the main AppDatabase stays at schemaVersion 6 (the approved
/// baseline of phases A, B and D-2). Teacher lessons need tables that the
/// main schema does not have, and adding them there would have required a
/// main-schema bump. A second, independent database with its own version
/// (starting at 1) adds the content storage without touching any table,
/// engine, migration or test of the main schema.
///
/// It holds lesson content only (pages, nodes, attachments). It has no
/// foreign key into the main database and no engine reads it.
@DriftDatabase(
  tables: [
    TeacherLessons,
    TeacherLessonPages,
    TeacherLessonNodes,
    TeacherLessonAttachments,
  ],
)
class TeacherContentDatabase extends _$TeacherContentDatabase {
  TeacherContentDatabase(super.e);

  /// Production entry point: a real persistent database, offline.
  factory TeacherContentDatabase.open() =>
      TeacherContentDatabase(openTeacherConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // No upgrade branch exists yet: version 1 is the first. Every future
        // change must add `if (from < N)` here, one branch per version.
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
        },
      );

  /// "Reset all data": removes every teacher lesson, page, node and
  /// attachment in one transaction.
  Future<void> wipeAll() => transaction(() async {
        for (final table in allTables) {
          await delete(table).go();
        }
      });
}
