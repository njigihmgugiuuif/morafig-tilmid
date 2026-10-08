import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../database/app_database.dart' show AppDatabase;
import '../database/teacher_content_database.dart';
import '../database/tables/core_tables.dart' show uuidGen;
import '../domain/teacher_content_domain.dart';

/// Thrown when a teacher-content write is refused. [issues] carry the Arabic
/// messages the UI shows; nothing is written when this is thrown.
class TeacherContentException implements Exception {
  TeacherContentException(this.issues);
  TeacherContentException.single(String code, String message)
      : issues = [LessonIssue(code, message)];
  final List<LessonIssue> issues;
  String get message => issues.map((i) => i.message).join('\n');
  @override
  String toString() => 'TeacherContentException: ${issues.join(', ')}';
}

class PageInput {
  const PageInput({
    required this.bytes,
    this.id,
    this.quarterTurns = 0,
  });
  final String? id;
  final Uint8List bytes;
  final int quarterTurns;
}

class AttachmentInput {
  const AttachmentInput({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });
  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// Everything the 4-step lesson path collects. [nodes] keys are the node ids
/// that will be stored (the UI generates a UUID per new node).
class LessonInput {
  const LessonInput({
    required this.title,
    required this.subjectName,
    required this.internalLevel,
    required this.teacherName,
    this.id,
    this.sectionLabel,
    this.trackLabel,
    this.unitLabel,
    this.notes,
    this.linkedCurriculumVersionId,
    this.pages = const [],
    this.nodes = const [],
    this.attachments = const [],
  });

  final String? id;
  final String title;
  final String subjectName;
  final int? internalLevel;
  final String? sectionLabel;
  final String? trackLabel;
  final String? unitLabel;
  final String teacherName;
  final String? notes;
  final String? linkedCurriculumVersionId;
  final List<PageInput> pages;
  final List<NodeDraft> nodes;
  final List<AttachmentInput> attachments;
}

class LessonAggregate {
  const LessonAggregate({
    required this.lesson,
    required this.pages,
    required this.nodes,
    required this.attachments,
  });
  final TeacherLesson lesson;
  final List<TeacherLessonPage> pages;
  final List<TeacherLessonNode> nodes;
  final List<TeacherLessonAttachment> attachments;

  int get totalBytes =>
      pages.fold<int>(0, (s, p) => s + p.byteSize) +
      attachments.fold<int>(0, (s, a) => s + a.byteSize);
}

class LessonListItem {
  const LessonListItem(this.lesson, this.pageCount, this.nodeCount, this.bytes);
  final TeacherLesson lesson;
  final int pageCount;
  final int nodeCount;
  final int bytes;
}

class LinkableVersion {
  const LinkableVersion(this.id, this.label);
  final String id;
  final String label;
}

/// All reads and writes of teacher content (phase C).
///
/// Rules enforced HERE (not only in the UI):
///  - the internal level is 1, 2 or 3; «القسم» never influences it;
///  - only AUTHORED lessons are edited; an imported lesson is read-only and
///    can only be deleted (or replaced by a newer package version);
///  - a lesson reaches «قيد المراجعة» only when ready (fields, ≥ 1 page,
///    valid nodes) and «منشور» only from «قيد المراجعة»;
///  - editing a PUBLISHED lesson sends it back to draft as a new version;
///  - page bytes must be a recognised image; the stored mime comes from the
///    bytes, never from a name;
///  - a curriculum link may only point at an ACTIVE version, and linking
///    changes nothing in the curriculum;
///  - the student's own data (tasks, mastery, memory, …) is never touched.
class TeacherContentRepository {
  TeacherContentRepository(this._db, {AppDatabase? mainDb}) : _main = mainDb;

  /// The SEPARATE teacher-content database (DEVIATION-23).
  final TeacherContentDatabase _db;

  /// The main database, used READ-ONLY and only to check that a curriculum
  /// version offered for linking exists and is ACTIVE. Null in contexts that
  /// never link (then no version is linkable).
  final AppDatabase? _main;

  // ---------------------------------------------------------------- write

  /// Creates (id == null) or updates an AUTHORED lesson with all its pages,
  /// nodes and attachments in ONE transaction. Returns the lesson id.
  Future<String> saveLesson(LessonInput input) async {
    final issues = validateLessonFields(
      title: input.title,
      subjectName: input.subjectName,
      internalLevel: input.internalLevel,
      teacherName: input.teacherName,
    );
    issues.addAll(validateNodes(input.nodes, input.pages.length));
    final mimes = <String>[];
    for (var i = 0; i < input.pages.length; i++) {
      final mime = sniffImageMime(input.pages[i].bytes);
      if (mime == null) {
        issues.add(LessonIssue('page_format_unsupported',
            'الصفحة ${i + 1} ليست صورة مدعومة (JPEG أو PNG أو WebP).'));
      }
      mimes.add(mime ?? '');
      final turns = input.pages[i].quarterTurns;
      if (turns < 0 || turns > 3) {
        issues.add(LessonIssue(
            'page_turns_invalid', 'زاوية دوران الصفحة ${i + 1} غير صالحة.'));
      }
    }
    for (final n in input.nodes) {
      if (n.key.isEmpty) {
        issues.add(const LessonIssue('node_key_required', 'عقدة بلا معرّف.'));
      }
    }
    if (issues.isNotEmpty) throw TeacherContentException(issues);

    return _db.transaction(() async {
      await _requireLinkable(input.linkedCurriculumVersionId);
      final now = DateTime.now().toUtc();
      String lessonId;
      if (input.id == null) {
        final row = await _db.into(_db.teacherLessons).insertReturning(
              TeacherLessonsCompanion.insert(
                title: input.title.trim(),
                subjectName: input.subjectName.trim(),
                internalLevel: input.internalLevel!,
                teacherName: input.teacherName.trim(),
                sectionLabel: Value(_blankToNull(input.sectionLabel)),
                trackLabel: Value(_blankToNull(input.trackLabel)),
                unitLabel: Value(_blankToNull(input.unitLabel)),
                notes: Value(_blankToNull(input.notes)),
                linkedCurriculumVersionId:
                    Value(input.linkedCurriculumVersionId),
              ),
            );
        lessonId = row.id;
      } else {
        lessonId = input.id!;
        final existing = await _requireLesson(lessonId);
        if (existing.origin != LessonOrigin.authored.toDb) {
          throw TeacherContentException.single('imported_read_only',
              'الدرس المستورد للقراءة فقط ولا يُعدَّل.');
        }
        final status = LessonStatus.fromDb(existing.status);
        // Editing a published lesson is a NEW version; editing a lesson that
        // is in review sends it back to draft (it changed after being sent).
        final nextStatus = LessonStatus.draft;
        final nextVersion = status == LessonStatus.published
            ? existing.versionNumber + 1
            : existing.versionNumber;
        await (_db.update(_db.teacherLessons)
              ..where((t) => t.id.equals(lessonId)))
            .write(TeacherLessonsCompanion(
          title: Value(input.title.trim()),
          subjectName: Value(input.subjectName.trim()),
          internalLevel: Value(input.internalLevel!),
          teacherName: Value(input.teacherName.trim()),
          sectionLabel: Value(_blankToNull(input.sectionLabel)),
          trackLabel: Value(_blankToNull(input.trackLabel)),
          unitLabel: Value(_blankToNull(input.unitLabel)),
          notes: Value(_blankToNull(input.notes)),
          linkedCurriculumVersionId: Value(input.linkedCurriculumVersionId),
          status: Value(nextStatus.toDb),
          versionNumber: Value(nextVersion),
          updatedAt: Value(now),
        ));
        await _deleteChildren(lessonId);
      }

      for (var i = 0; i < input.pages.length; i++) {
        final p = input.pages[i];
        await _db.into(_db.teacherLessonPages).insert(
              TeacherLessonPagesCompanion.insert(
                lessonId: lessonId,
                pageOrder: i + 1,
                bytes: p.bytes,
                mimeType: mimes[i],
                byteSize: p.bytes.length,
                quarterTurns: Value(p.quarterTurns),
              ),
            );
      }
      for (var i = 0; i < input.nodes.length; i++) {
        final n = input.nodes[i];
        await _db.into(_db.teacherLessonNodes).insert(
              TeacherLessonNodesCompanion.insert(
                id: Value(n.key),
                lessonId: lessonId,
                name: n.name.trim(),
                nodeOrder: i + 1,
                pageFrom: Value(n.pageFrom),
                pageTo: Value(n.pageTo),
                requiresNodeId: Value(n.requiresKey),
              ),
            );
      }
      for (final a in input.attachments) {
        await _db.into(_db.teacherLessonAttachments).insert(
              TeacherLessonAttachmentsCompanion.insert(
                lessonId: lessonId,
                name: a.name.trim().isEmpty ? 'مرفق' : a.name.trim(),
                mimeType: a.mimeType,
                bytes: a.bytes,
                byteSize: a.bytes.length,
              ),
            );
      }
      return lessonId;
    });
  }

  /// Moves an AUTHORED lesson along draft → inReview → published, or back to
  /// draft. Throws [TeacherContentException] when the move is not allowed or
  /// the lesson is not ready for review.
  Future<void> transition(String lessonId, LessonStatus to) async {
    await _db.transaction(() async {
      final agg = await read(lessonId);
      if (agg == null) {
        throw TeacherContentException.single(
            'lesson_missing', 'الدرس غير موجود.');
      }
      final lesson = agg.lesson;
      if (lesson.origin != LessonOrigin.authored.toDb) {
        throw TeacherContentException.single('imported_read_only',
            'حالة الدرس المستورد لا تتغير.');
      }
      final from = LessonStatus.fromDb(lesson.status);
      if (!canTransition(from, to)) {
        throw TeacherContentException.single('transition_not_allowed',
            'لا يمكن نقل الدرس من «${from.label}» إلى «${to.label}».');
      }
      if (to == LessonStatus.inReview) {
        final issues = readinessForReview(
          title: lesson.title,
          subjectName: lesson.subjectName,
          internalLevel: lesson.internalLevel,
          teacherName: lesson.teacherName,
          pageCount: agg.pages.length,
          nodes: agg.nodes
              .map((n) => NodeDraft(
                    key: n.id,
                    name: n.name,
                    pageFrom: n.pageFrom,
                    pageTo: n.pageTo,
                    requiresKey: n.requiresNodeId,
                  ))
              .toList(),
        );
        if (issues.isNotEmpty) throw TeacherContentException(issues);
      }
      await (_db.update(_db.teacherLessons)
            ..where((t) => t.id.equals(lessonId)))
          .write(TeacherLessonsCompanion(
        status: Value(to.toDb),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
    });
  }

  Future<void> setReviewNotes(String lessonId, String? notes) async {
    final lesson = await _requireLesson(lessonId);
    if (lesson.origin != LessonOrigin.authored.toDb) {
      throw TeacherContentException.single(
          'imported_read_only', 'الدرس المستورد للقراءة فقط.');
    }
    await (_db.update(_db.teacherLessons)..where((t) => t.id.equals(lessonId)))
        .write(TeacherLessonsCompanion(
      reviewNotes: Value(_blankToNull(notes)),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  /// Records that a package of this lesson was handed out (for the account
  /// screen's «الحزم المصدّرة»). Does not change status or content.
  Future<void> markExported(String lessonId) async {
    final lesson = await _requireLesson(lessonId);
    await (_db.update(_db.teacherLessons)..where((t) => t.id.equals(lessonId)))
        .write(TeacherLessonsCompanion(
      lastExportedAt: Value(DateTime.now().toUtc()),
      exportCount: Value(lesson.exportCount + 1),
    ));
  }

  /// Deletes a lesson with its pages, nodes and attachments. Touches no
  /// other table: tasks, mastery, memory and plans are unaffected.
  Future<void> deleteLesson(String lessonId) async {
    await _db.transaction(() async {
      await _deleteChildren(lessonId);
      await (_db.delete(_db.teacherLessons)
            ..where((t) => t.id.equals(lessonId)))
          .go();
    });
  }

  // ----------------------------------------------------------------- read

  Future<LessonAggregate?> read(String lessonId) async {
    final lesson = await (_db.select(_db.teacherLessons)
          ..where((t) => t.id.equals(lessonId)))
        .getSingleOrNull();
    if (lesson == null) return null;
    final pages = await (_db.select(_db.teacherLessonPages)
          ..where((t) => t.lessonId.equals(lessonId))
          ..orderBy([(t) => OrderingTerm(expression: t.pageOrder)]))
        .get();
    final nodes = await (_db.select(_db.teacherLessonNodes)
          ..where((t) => t.lessonId.equals(lessonId))
          ..orderBy([(t) => OrderingTerm(expression: t.nodeOrder)]))
        .get();
    final atts = await (_db.select(_db.teacherLessonAttachments)
          ..where((t) => t.lessonId.equals(lessonId)))
        .get();
    return LessonAggregate(
        lesson: lesson, pages: pages, nodes: nodes, attachments: atts);
  }

  Future<List<LessonListItem>> listAuthored({
    int? level,
    LessonStatus? status,
    String query = '',
  }) =>
      _list(LessonOrigin.authored, level: level, status: status, query: query);

  Future<List<LessonListItem>> listImported({
    int? level,
    String query = '',
  }) =>
      _list(LessonOrigin.imported, level: level, query: query);

  Future<List<LessonListItem>> _list(
    LessonOrigin origin, {
    int? level,
    LessonStatus? status,
    String query = '',
  }) async {
    final rows = await (_db.select(_db.teacherLessons)
          ..where((t) => t.origin.equals(origin.toDb))
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .get();
    final q = query.trim();
    final out = <LessonListItem>[];
    for (final l in rows) {
      if (level != null && l.internalLevel != level) continue;
      if (status != null && l.status != status.toDb) continue;
      if (q.isNotEmpty &&
          !l.title.contains(q) &&
          !l.subjectName.contains(q) &&
          !(l.sectionLabel ?? '').contains(q)) {
        continue;
      }
      final stats = await _stats(l.id);
      out.add(LessonListItem(l, stats.$1, stats.$2, stats.$3));
    }
    return out;
  }

  Future<(int, int, int)> _stats(String lessonId) async {
    final pages = await (_db.select(_db.teacherLessonPages)
          ..where((t) => t.lessonId.equals(lessonId)))
        .get();
    final nodes = await (_db.select(_db.teacherLessonNodes)
          ..where((t) => t.lessonId.equals(lessonId)))
        .get();
    final atts = await (_db.select(_db.teacherLessonAttachments)
          ..where((t) => t.lessonId.equals(lessonId)))
        .get();
    final bytes = pages.fold<int>(0, (s, p) => s + p.byteSize) +
        atts.fold<int>(0, (s, a) => s + a.byteSize);
    return (pages.length, nodes.length, bytes);
  }

  Future<Map<LessonStatus, int>> authoredStatusCounts() async {
    final rows = await (_db.select(_db.teacherLessons)
          ..where((t) => t.origin.equals(LessonOrigin.authored.toDb)))
        .get();
    final counts = {for (final s in LessonStatus.values) s: 0};
    for (final r in rows) {
      final s = LessonStatus.fromDb(r.status);
      counts[s] = counts[s]! + 1;
    }
    return counts;
  }

  /// Total stored size of the imported content (L05 «المساحة المستعملة»).
  Future<int> importedBytes() async {
    final items = await listImported();
    return items.fold<int>(0, (s, i) => s + i.bytes);
  }

  /// Export statistics for the account screen.
  Future<({int packages, DateTime? last})> exportSummary() async {
    final rows = await (_db.select(_db.teacherLessons)
          ..where((t) => t.origin.equals(LessonOrigin.authored.toDb)))
        .get();
    var packages = 0;
    DateTime? last;
    for (final r in rows) {
      packages += r.exportCount;
      final l = r.lastExportedAt;
      if (l != null && (last == null || l.isAfter(last))) last = l;
    }
    return (packages: packages, last: last);
  }

  /// Curriculum versions a lesson may be linked to: ACTIVE ones only. When
  /// the list is empty the UI says the link is unavailable (nothing is
  /// invented, and no curriculum data is seeded by the app).
  Future<List<LinkableVersion>> linkableVersions() async {
    final main = _main;
    if (main == null) return const [];
    final rows = await (main.select(main.curriculumVersions)
          ..where((t) => t.status.equals('active')))
        .get();
    return rows
        .map((v) => LinkableVersion(
            v.id, v.versionLabel ?? 'نسخة منهج ${v.id.substring(0, 6)}'))
        .toList();
  }

  // -------------------------------------------------------------- imports

  Future<TeacherLesson?> findImportedByFingerprint(String fingerprint) =>
      (_db.select(_db.teacherLessons)
            ..where((t) =>
                t.origin.equals(LessonOrigin.imported.toDb) &
                t.packageFingerprint.equals(fingerprint)))
          .getSingleOrNull();

  Future<TeacherLesson?> findImportedByOrigin(String originLessonId) =>
      (_db.select(_db.teacherLessons)
            ..where((t) =>
                t.origin.equals(LessonOrigin.imported.toDb) &
                t.originLessonId.equals(originLessonId)))
          .getSingleOrNull();

  /// Writes an imported lesson. With [replaceLessonId] the existing imported
  /// lesson's content is replaced in place (same local id, newer version);
  /// otherwise a new lesson is added. Only the four teacher tables are
  /// touched. The lesson is stored as `published` + `imported` (read-only).
  Future<String> writeImported({
    required String originLessonId,
    required int versionNumber,
    required String fingerprint,
    required String title,
    required String subjectName,
    required int internalLevel,
    required String teacherName,
    String? sectionLabel,
    String? trackLabel,
    String? unitLabel,
    String? notes,
    required List<({Uint8List bytes, String mimeType, int quarterTurns})> pages,
    required List<NodeDraft> nodes,
    required List<AttachmentInput> attachments,
    String? replaceLessonId,
  }) async {
    if (!isValidInternalLevel(internalLevel)) {
      throw TeacherContentException.single(
          'level_invalid', 'مستوى الدرس في الحزمة غير صالح.');
    }
    return _db.transaction(() async {
      final now = DateTime.now().toUtc();
      String lessonId;
      if (replaceLessonId == null) {
        final row = await _db.into(_db.teacherLessons).insertReturning(
              TeacherLessonsCompanion.insert(
                title: title.trim(),
                subjectName: subjectName.trim(),
                internalLevel: internalLevel,
                teacherName: teacherName.trim(),
                sectionLabel: Value(_blankToNull(sectionLabel)),
                trackLabel: Value(_blankToNull(trackLabel)),
                unitLabel: Value(_blankToNull(unitLabel)),
                notes: Value(_blankToNull(notes)),
                status: Value(LessonStatus.published.toDb),
                origin: Value(LessonOrigin.imported.toDb),
                versionNumber: Value(versionNumber),
                originLessonId: Value(originLessonId),
                packageFingerprint: Value(fingerprint),
                importedAt: Value(now),
              ),
            );
        lessonId = row.id;
      } else {
        lessonId = replaceLessonId;
        await (_db.update(_db.teacherLessons)
              ..where((t) => t.id.equals(lessonId)))
            .write(TeacherLessonsCompanion(
          title: Value(title.trim()),
          subjectName: Value(subjectName.trim()),
          internalLevel: Value(internalLevel),
          teacherName: Value(teacherName.trim()),
          sectionLabel: Value(_blankToNull(sectionLabel)),
          trackLabel: Value(_blankToNull(trackLabel)),
          unitLabel: Value(_blankToNull(unitLabel)),
          notes: Value(_blankToNull(notes)),
          versionNumber: Value(versionNumber),
          packageFingerprint: Value(fingerprint),
          importedAt: Value(now),
          updatedAt: Value(now),
        ));
        await _deleteChildren(lessonId);
      }

      for (var i = 0; i < pages.length; i++) {
        final p = pages[i];
        await _db.into(_db.teacherLessonPages).insert(
              TeacherLessonPagesCompanion.insert(
                lessonId: lessonId,
                pageOrder: i + 1,
                bytes: p.bytes,
                mimeType: p.mimeType,
                byteSize: p.bytes.length,
                quarterTurns: Value(p.quarterTurns),
              ),
            );
      }
      // Node ids from the package are re-generated locally so two imports of
      // different lessons can never collide on a primary key.
      final newIds = {for (final n in nodes) n.key: uuidGen.v4()};
      for (var i = 0; i < nodes.length; i++) {
        final n = nodes[i];
        await _db.into(_db.teacherLessonNodes).insert(
              TeacherLessonNodesCompanion.insert(
                id: Value(newIds[n.key]!),
                lessonId: lessonId,
                name: n.name.trim(),
                nodeOrder: i + 1,
                pageFrom: Value(n.pageFrom),
                pageTo: Value(n.pageTo),
                requiresNodeId: Value(
                    n.requiresKey == null ? null : newIds[n.requiresKey!]),
              ),
            );
      }
      for (final a in attachments) {
        await _db.into(_db.teacherLessonAttachments).insert(
              TeacherLessonAttachmentsCompanion.insert(
                lessonId: lessonId,
                name: a.name,
                mimeType: a.mimeType,
                bytes: a.bytes,
                byteSize: a.bytes.length,
              ),
            );
      }
      return lessonId;
    });
  }

  // ------------------------------------------------------------- internal

  Future<TeacherLesson> _requireLesson(String id) async {
    final row = await (_db.select(_db.teacherLessons)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw TeacherContentException.single(
          'lesson_missing', 'الدرس غير موجود.');
    }
    return row;
  }

  Future<void> _requireLinkable(String? versionId) async {
    if (versionId == null) return;
    final main = _main;
    final v = main == null
        ? null
        : await (main.select(main.curriculumVersions)
              ..where((t) => t.id.equals(versionId)))
            .getSingleOrNull();
    if (v == null || v.status != 'active') {
      throw TeacherContentException.single('link_invalid',
          'لا يُربط الدرس إلا بنسخة منهج معروفة ومتحقَّق منها (فعّالة).');
    }
  }

  Future<void> _deleteChildren(String lessonId) async {
    await (_db.delete(_db.teacherLessonPages)
          ..where((t) => t.lessonId.equals(lessonId)))
        .go();
    await (_db.delete(_db.teacherLessonNodes)
          ..where((t) => t.lessonId.equals(lessonId)))
        .go();
    await (_db.delete(_db.teacherLessonAttachments)
          ..where((t) => t.lessonId.equals(lessonId)))
        .go();
  }

  static String? _blankToNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
