import 'package:drift/drift.dart';

import 'core_tables.dart' show AuditColumns;

/// Teacher content (phase C, DEVIATION-23). These tables belong to the
/// SEPARATE `TeacherContentDatabase` (schemaVersion 1 of its own), never to
/// AppDatabase, whose schemaVersion stays 6.
///
/// A lesson written by a teacher, or a copy of one imported by a student.
/// It lives ENTIRELY outside the official curriculum: no table here has a
/// coefficient, an hour count or any official value, and no engine reads
/// these tables. The student-facing label «أستاذ · غير رسمي» is a constant
/// of the domain layer, not a column, so it can never be switched off per row.
class TeacherLessons extends Table with AuditColumns {
  TextColumn get title => text()();
  TextColumn get subjectName => text()();

  /// The ONLY level concept of teacher content: 1, 2 or 3 (validated in
  /// TeacherContentRules and by the repository). A teacher's «2 ثانوي» is
  /// stored as 2 and the lesson's page images belong to slot 2 only.
  IntColumn get internalLevel => integer()();

  /// «القسم» (e.g. «2 علوم تجريبية»): free descriptive text. It decides
  /// nothing: not the level, not the slot, not any access (O-5 / O-6).
  TextColumn get sectionLabel => text().nullable()();

  /// «الشعبة / المسار»: free text, no official list is assumed (O-6).
  TextColumn get trackLabel => text().nullable()();

  /// «الوحدة / الفصل»: free text.
  TextColumn get unitLabel => text().nullable()();

  /// Unverified label typed by the teacher; never an identity.
  TextColumn get teacherName => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get reviewNotes => text().nullable()();

  /// LessonStatus: draft | inReview | published.
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// LessonOrigin: authored | imported.
  TextColumn get origin => text().withDefault(const Constant('authored'))();

  /// Incremented when a PUBLISHED lesson is edited (it goes back to draft and
  /// becomes a new version).
  IntColumn get versionNumber => integer().withDefault(const Constant(1))();

  /// For an imported lesson: the id the lesson had on the teacher's device.
  TextColumn get originLessonId => text().nullable()();

  /// For an imported lesson: the package fingerprint (SHA-256 hex).
  TextColumn get packageFingerprint => text().nullable()();
  DateTimeColumn get importedAt => dateTime().nullable()();

  /// Optional link to a KNOWN curriculum version (an id of the MAIN
  /// database). This is a plain text id, NOT a foreign key: teacher content
  /// lives in its own database. Only an ACTIVE version can be linked
  /// (repository-enforced at link time). NULL = not linked, the normal
  /// state: the lesson then stays «أستاذ · غير رسمي» and nothing official
  /// changes either way.
  TextColumn get linkedCurriculumVersionId => text().nullable()();

  DateTimeColumn get lastExportedAt => dateTime().nullable()();
  IntColumn get exportCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One photographed / picked page image of a lesson.
class TeacherLessonPages extends Table with AuditColumns {
  TextColumn get lessonId => text().references(TeacherLessons, #id)();

  /// 1-based position inside the lesson.
  IntColumn get pageOrder => integer()();
  BlobColumn get bytes => blob()();

  /// Detected from the file's own bytes (jpeg / png / webp), not trusted
  /// from a file name. Format list is a TEMPORARY decision (O-3).
  TextColumn get mimeType => text()();
  IntColumn get byteSize => integer()();

  /// 0..3 quarter turns clockwise, applied when the page is shown. The
  /// stored bytes are never re-encoded.
  IntColumn get quarterTurns => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A knowledge node typed by the teacher inside one lesson (manual input).
class TeacherLessonNodes extends Table with AuditColumns {
  TextColumn get lessonId => text().references(TeacherLessons, #id)();
  TextColumn get name => text()();
  IntColumn get nodeOrder => integer()();
  IntColumn get pageFrom => integer().nullable()();
  IntColumn get pageTo => integer().nullable()();

  /// Another node of the SAME lesson this one requires (validated, acyclic).
  TextColumn get requiresNodeId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TeacherLessonAttachments extends Table with AuditColumns {
  TextColumn get lessonId => text().references(TeacherLessons, #id)();
  TextColumn get name => text()();
  TextColumn get mimeType => text()();
  BlobColumn get bytes => blob()();
  IntColumn get byteSize => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
