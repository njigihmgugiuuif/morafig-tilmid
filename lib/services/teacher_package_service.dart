import 'dart:convert';
import 'dart:typed_data';

import '../domain/sha256.dart';
import '../domain/teacher_content_domain.dart';
import '../repositories/teacher_content_repository.dart';

/// The "Teacher Package": the TEMPORARY way teacher content travels from a
/// teacher's device to a student's device in this version (no server). It is
/// a transport for this version only; the final teacher product is not
/// reduced to it (decision of 2026-10-05, D-2 X03, open points O-1 / O-7).
///
/// Format (all of it is a TEMPORARY decision, recorded as O-3 / O-7):
///   one JSON text, `format` = "marafiq.teacher-lesson", `formatVersion` = 1,
///   page images as base64 inside the JSON, and a SHA-256 `fingerprint` of
///   the canonical content. The fingerprint detects corruption and exact
///   duplicates. It does NOT prove who made the package (there is no
///   signature and no server).
///
/// A package carries lesson content only: never tasks, mastery, memory,
/// errors, plans, student identity or any curriculum value.
const String kPackageFormat = 'marafiq.teacher-lesson';
const int kPackageFormatVersion = 1;

class PackagePage {
  const PackagePage(this.bytes, this.mimeType, this.quarterTurns);
  final Uint8List bytes;
  final String mimeType;
  final int quarterTurns;
}

class PackageContent {
  const PackageContent({
    required this.originLessonId,
    required this.versionNumber,
    required this.title,
    required this.subjectName,
    required this.internalLevel,
    required this.teacherName,
    required this.pages,
    required this.nodes,
    required this.attachments,
    this.sectionLabel,
    this.trackLabel,
    this.unitLabel,
    this.notes,
  });

  final String originLessonId;
  final int versionNumber;
  final String title;
  final String subjectName;
  final int internalLevel;
  final String? sectionLabel;
  final String? trackLabel;
  final String? unitLabel;
  final String teacherName;
  final String? notes;
  final List<PackagePage> pages;
  final List<NodeDraft> nodes;
  final List<AttachmentInput> attachments;

  int get totalBytes =>
      pages.fold<int>(0, (s, p) => s + p.bytes.length) +
      attachments.fold<int>(0, (s, a) => s + a.bytes.length);
}

/// What importing a package WOULD do (shown before the student confirms).
enum PackageKind {
  /// Not seen before: will be added.
  fresh,

  /// Same fingerprint already imported: nothing will be added.
  duplicate,

  /// Same lesson, higher version: content will be replaced.
  newerVersion,

  /// Same lesson, the student already has a higher version: refused.
  olderVersion,

  /// Same lesson and version number but different content: refused.
  sameVersionConflict,

  /// Could not be read, or its fingerprint does not match its content.
  corrupt,

  /// A package format this build does not know.
  unsupported,
}

class PackagePreview {
  const PackagePreview({
    required this.kind,
    required this.message,
    this.content,
    this.fingerprint,
    this.existingVersion,
    this.existingLessonId,
  });
  final PackageKind kind;
  final String message;
  final PackageContent? content;
  final String? fingerprint;
  final int? existingVersion;
  final String? existingLessonId;

  bool get canImport =>
      kind == PackageKind.fresh || kind == PackageKind.newerVersion;
}

class PackageImportResult {
  const PackageImportResult(this.preview, this.lessonId);
  final PackagePreview preview;

  /// Set only when something was written.
  final String? lessonId;
  bool get written => lessonId != null;
}

class TeacherPackageService {
  TeacherPackageService(this._repo);
  final TeacherContentRepository _repo;

  // --------------------------------------------------------------- export

  /// Builds the package text of a PUBLISHED, AUTHORED lesson and records the
  /// export. Drafts and lessons in review are never exported.
  Future<({String json, String fileName})> exportLesson(
      String lessonId) async {
    final agg = await _repo.read(lessonId);
    if (agg == null) {
      throw TeacherContentException.single(
          'lesson_missing', 'الدرس غير موجود.');
    }
    final l = agg.lesson;
    if (l.origin != LessonOrigin.authored.toDb) {
      throw TeacherContentException.single(
          'imported_not_exportable', 'لا يُصدَّر إلا درس كتبتَه أنت.');
    }
    if (LessonStatus.fromDb(l.status) != LessonStatus.published) {
      throw TeacherContentException.single('not_published',
          'لا تُصدَّر إلا الدروس «المنشورة». أرسل الدرس إلى المراجعة ثم اعتمده.');
    }
    final content = PackageContent(
      originLessonId: l.id,
      versionNumber: l.versionNumber,
      title: l.title,
      subjectName: l.subjectName,
      internalLevel: l.internalLevel,
      sectionLabel: l.sectionLabel,
      trackLabel: l.trackLabel,
      unitLabel: l.unitLabel,
      teacherName: l.teacherName,
      notes: l.notes,
      pages: agg.pages
          .map((p) => PackagePage(p.bytes, p.mimeType, p.quarterTurns))
          .toList(),
      nodes: agg.nodes
          .map((n) => NodeDraft(
                key: n.id,
                name: n.name,
                pageFrom: n.pageFrom,
                pageTo: n.pageTo,
                requiresKey: n.requiresNodeId,
              ))
          .toList(),
      attachments: agg.attachments
          .map((a) => AttachmentInput(
              name: a.name, mimeType: a.mimeType, bytes: a.bytes))
          .toList(),
    );
    final json = encode(content);
    await _repo.markExported(lessonId);
    final safeTitle =
        l.title.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '-').trim();
    return (
      json: json,
      fileName: '$safeTitle-v${l.versionNumber}.marafiq-lesson.json',
    );
  }

  /// Canonical text the fingerprint is computed over. Insertion order of the
  /// maps is the contract; do not reorder without bumping the format version.
  static String canonicalString(PackageContent c) {
    final canonical = <String, dynamic>{
      'format': kPackageFormat,
      'formatVersion': kPackageFormatVersion,
      'lesson': <String, dynamic>{
        'originLessonId': c.originLessonId,
        'versionNumber': c.versionNumber,
        'title': c.title,
        'subjectName': c.subjectName,
        'internalLevel': c.internalLevel,
        'sectionLabel': c.sectionLabel,
        'trackLabel': c.trackLabel,
        'unitLabel': c.unitLabel,
        'teacherName': c.teacherName,
        'notes': c.notes,
      },
      'pages': c.pages
          .map((p) => <String, dynamic>{
                'mimeType': p.mimeType,
                'quarterTurns': p.quarterTurns,
                'sha256': Sha256.hex(p.bytes),
              })
          .toList(),
      'nodes': c.nodes
          .map((n) => <String, dynamic>{
                'key': n.key,
                'name': n.name,
                'pageFrom': n.pageFrom,
                'pageTo': n.pageTo,
                'requiresKey': n.requiresKey,
              })
          .toList(),
      'attachments': c.attachments
          .map((a) => <String, dynamic>{
                'name': a.name,
                'mimeType': a.mimeType,
                'sha256': Sha256.hex(a.bytes),
              })
          .toList(),
    };
    return jsonEncode(canonical);
  }

  static String fingerprintOf(PackageContent c) =>
      Sha256.hexOfString(canonicalString(c));

  static String encode(PackageContent c) {
    return jsonEncode(<String, dynamic>{
      'format': kPackageFormat,
      'formatVersion': kPackageFormatVersion,
      'fingerprint': fingerprintOf(c),
      'lesson': <String, dynamic>{
        'originLessonId': c.originLessonId,
        'versionNumber': c.versionNumber,
        'title': c.title,
        'subjectName': c.subjectName,
        'internalLevel': c.internalLevel,
        'sectionLabel': c.sectionLabel,
        'trackLabel': c.trackLabel,
        'unitLabel': c.unitLabel,
        'teacherName': c.teacherName,
        'notes': c.notes,
      },
      'pages': c.pages
          .map((p) => <String, dynamic>{
                'mimeType': p.mimeType,
                'quarterTurns': p.quarterTurns,
                'data': base64Encode(p.bytes),
              })
          .toList(),
      'nodes': c.nodes
          .map((n) => <String, dynamic>{
                'key': n.key,
                'name': n.name,
                'pageFrom': n.pageFrom,
                'pageTo': n.pageTo,
                'requiresKey': n.requiresKey,
              })
          .toList(),
      'attachments': c.attachments
          .map((a) => <String, dynamic>{
                'name': a.name,
                'mimeType': a.mimeType,
                'data': base64Encode(a.bytes),
              })
          .toList(),
    });
  }

  // --------------------------------------------------------------- import

  /// Reads and checks a package WITHOUT writing anything and says what
  /// importing it would do. Never throws: a bad file becomes
  /// [PackageKind.corrupt] / [PackageKind.unsupported].
  Future<PackagePreview> inspect(String text) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return const PackagePreview(
          kind: PackageKind.corrupt,
          message: 'تعذّرت قراءة الملف. بياناتك لم تُمَس.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != kPackageFormat) {
      return const PackagePreview(
          kind: PackageKind.corrupt,
          message: 'هذا الملف ليس حزمة درس من أستاذ. بياناتك لم تُمَس.');
    }
    final version = decoded['formatVersion'];
    if (version is! int || version != kPackageFormatVersion) {
      return PackagePreview(
          kind: PackageKind.unsupported,
          message: 'صيغة الحزمة ($version) غير مدعومة في هذه النسخة.');
    }

    final PackageContent content;
    try {
      content = _parseContent(decoded);
    } on FormatException catch (e) {
      return PackagePreview(
          kind: PackageKind.corrupt,
          message: 'الحزمة تالفة: ${e.message}. بياناتك لم تُمَس.');
    }

    final fingerprint = fingerprintOf(content);
    final stated = decoded['fingerprint'];
    if (stated is! String || stated != fingerprint) {
      return const PackagePreview(
          kind: PackageKind.corrupt,
          message: 'بصمة الحزمة لا تطابق محتواها: الملف تالف أو عُدّل. '
              'بياناتك لم تُمَس.');
    }

    final dup = await _repo.findImportedByFingerprint(fingerprint);
    if (dup != null) {
      return PackagePreview(
        kind: PackageKind.duplicate,
        message: 'هذه الحزمة موجودة بنفس البصمة، فلن تُضاف مرتين.',
        content: content,
        fingerprint: fingerprint,
        existingVersion: dup.versionNumber,
        existingLessonId: dup.id,
      );
    }

    final same = await _repo.findImportedByOrigin(content.originLessonId);
    if (same != null) {
      if (content.versionNumber > same.versionNumber) {
        return PackagePreview(
          kind: PackageKind.newerVersion,
          message: 'عندك الإصدار ${same.versionNumber}، وهذه الحزمة الإصدار '
              '${content.versionNumber}. تحديثها يستبدل محتوى الدرس فقط.',
          content: content,
          fingerprint: fingerprint,
          existingVersion: same.versionNumber,
          existingLessonId: same.id,
        );
      }
      if (content.versionNumber < same.versionNumber) {
        return PackagePreview(
          kind: PackageKind.olderVersion,
          message: 'عندك الإصدار ${same.versionNumber} وهو أحدث من هذه '
              'الحزمة (${content.versionNumber}). لم يُغيَّر شيء.',
          content: content,
          fingerprint: fingerprint,
          existingVersion: same.versionNumber,
          existingLessonId: same.id,
        );
      }
      return PackagePreview(
        kind: PackageKind.sameVersionConflict,
        message: 'عندك الدرس نفسه بالإصدار نفسه لكن بمحتوى مختلف. '
            'رُفضت الحزمة ولم يُغيَّر شيء.',
        content: content,
        fingerprint: fingerprint,
        existingVersion: same.versionNumber,
        existingLessonId: same.id,
      );
    }

    return PackagePreview(
      kind: PackageKind.fresh,
      message: 'حزمة جديدة: ستُضاف إلى مكتبتك.',
      content: content,
      fingerprint: fingerprint,
    );
  }

  /// Inspects [text] and, when it can be imported, writes it in one
  /// transaction. Anything else writes nothing and returns the reason.
  Future<PackageImportResult> importPackage(String text) async {
    final preview = await inspect(text);
    if (!preview.canImport) return PackageImportResult(preview, null);
    final c = preview.content!;
    final id = await _repo.writeImported(
      originLessonId: c.originLessonId,
      versionNumber: c.versionNumber,
      fingerprint: preview.fingerprint!,
      title: c.title,
      subjectName: c.subjectName,
      internalLevel: c.internalLevel,
      teacherName: c.teacherName,
      sectionLabel: c.sectionLabel,
      trackLabel: c.trackLabel,
      unitLabel: c.unitLabel,
      notes: c.notes,
      pages: c.pages
          .map((p) => (
                bytes: p.bytes,
                mimeType: p.mimeType,
                quarterTurns: p.quarterTurns
              ))
          .toList(),
      nodes: c.nodes,
      attachments: c.attachments,
      replaceLessonId: preview.kind == PackageKind.newerVersion
          ? preview.existingLessonId
          : null,
    );
    return PackageImportResult(preview, id);
  }

  // -------------------------------------------------------------- parsing

  static PackageContent _parseContent(Map<String, dynamic> m) {
    final lesson = m['lesson'];
    if (lesson is! Map<String, dynamic>) {
      throw const FormatException('بيانات الدرس مفقودة');
    }
    String req(String key) {
      final v = lesson[key];
      if (v is! String || v.trim().isEmpty) {
        throw FormatException('الحقل $key مفقود');
      }
      return v;
    }

    String? opt(Map<String, dynamic> from, String key) {
      final v = from[key];
      if (v == null) return null;
      if (v is! String) throw FormatException('الحقل $key غير صالح');
      return v;
    }

    final level = lesson['internalLevel'];
    if (level is! int || !isValidInternalLevel(level)) {
      throw const FormatException('مستوى الدرس غير صالح');
    }
    final versionNumber = lesson['versionNumber'];
    if (versionNumber is! int || versionNumber < 1) {
      throw const FormatException('رقم الإصدار غير صالح');
    }

    final rawPages = m['pages'];
    if (rawPages is! List || rawPages.isEmpty) {
      throw const FormatException('لا صفحات في الحزمة');
    }
    final pages = <PackagePage>[];
    for (var i = 0; i < rawPages.length; i++) {
      final p = rawPages[i];
      if (p is! Map<String, dynamic>) {
        throw FormatException('الصفحة ${i + 1} غير صالحة');
      }
      final data = p['data'];
      if (data is! String) throw FormatException('الصفحة ${i + 1} بلا بيانات');
      final Uint8List bytes;
      try {
        bytes = base64Decode(data);
      } on FormatException {
        throw FormatException('الصفحة ${i + 1} غير مقروءة');
      }
      final mime = sniffImageMime(bytes);
      if (mime == null) {
        throw FormatException('الصفحة ${i + 1} ليست صورة مدعومة');
      }
      final turns = p['quarterTurns'];
      if (turns is! int || turns < 0 || turns > 3) {
        throw FormatException('دوران الصفحة ${i + 1} غير صالح');
      }
      pages.add(PackagePage(bytes, mime, turns));
    }

    final rawNodes = m['nodes'];
    if (rawNodes is! List) throw const FormatException('العقد مفقودة');
    final nodes = <NodeDraft>[];
    for (final n in rawNodes) {
      if (n is! Map<String, dynamic>) {
        throw const FormatException('عقدة غير صالحة');
      }
      final key = n['key'];
      final name = n['name'];
      if (key is! String || key.isEmpty || name is! String) {
        throw const FormatException('عقدة غير صالحة');
      }
      final from = n['pageFrom'];
      final to = n['pageTo'];
      if ((from != null && from is! int) || (to != null && to is! int)) {
        throw const FormatException('نطاق عقدة غير صالح');
      }
      nodes.add(NodeDraft(
        key: key,
        name: name,
        pageFrom: from as int?,
        pageTo: to as int?,
        requiresKey: opt(n, 'requiresKey'),
      ));
    }
    final nodeIssues = validateNodes(nodes, pages.length);
    if (nodeIssues.isNotEmpty) {
      throw FormatException(nodeIssues.first.message);
    }

    final rawAtts = m['attachments'];
    if (rawAtts is! List) throw const FormatException('المرفقات مفقودة');
    final atts = <AttachmentInput>[];
    for (final a in rawAtts) {
      if (a is! Map<String, dynamic>) {
        throw const FormatException('مرفق غير صالح');
      }
      final name = a['name'];
      final mime = a['mimeType'];
      final data = a['data'];
      if (name is! String || mime is! String || data is! String) {
        throw const FormatException('مرفق غير صالح');
      }
      final Uint8List bytes;
      try {
        bytes = base64Decode(data);
      } on FormatException {
        throw const FormatException('مرفق غير مقروء');
      }
      atts.add(AttachmentInput(name: name, mimeType: mime, bytes: bytes));
    }

    return PackageContent(
      originLessonId: req('originLessonId'),
      versionNumber: versionNumber,
      title: req('title'),
      subjectName: req('subjectName'),
      internalLevel: level,
      sectionLabel: opt(lesson, 'sectionLabel'),
      trackLabel: opt(lesson, 'trackLabel'),
      unitLabel: opt(lesson, 'unitLabel'),
      teacherName: req('teacherName'),
      notes: opt(lesson, 'notes'),
      pages: pages,
      nodes: nodes,
      attachments: atts,
    );
  }
}
