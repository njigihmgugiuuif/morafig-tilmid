import 'dart:typed_data';

/// Pure rules of teacher content (phase C). No database, no Flutter.
///
/// Everything here is either an agreed requirement (the three internal
/// levels, the «أستاذ · غير رسمي» badge, the draft → review → published
/// path, section ≠ level) or a clearly marked TEMPORARY decision recorded as
/// an open point in DEVIATIONS.md (DEVIATION-23): image formats (O-3), the
/// meaning of «review» (O-2), the fingerprint/duplicate rules (O-7).

/// The badge shown on every piece of teacher content on the student side.
/// A constant, not a setting: it cannot be turned off per lesson.
const String kTeacherBadge = 'أستاذ · غير رسمي';

/// The three internal levels of teacher content, and nothing else.
const List<int> kInternalLevels = [1, 2, 3];

bool isValidInternalLevel(int? level) =>
    level != null && kInternalLevels.contains(level);

String internalLevelLabel(int level) => 'المستوى $level';

enum LessonStatus {
  draft,
  inReview,
  published;

  String get toDb => name;

  static LessonStatus fromDb(String value) =>
      LessonStatus.values.firstWhere((e) => e.name == value,
          orElse: () => throw StateError('Unrecognized LessonStatus "$value".'));

  String get label {
    switch (this) {
      case LessonStatus.draft:
        return 'مسودة';
      case LessonStatus.inReview:
        return 'قيد المراجعة';
      case LessonStatus.published:
        return 'منشور';
    }
  }
}

enum LessonOrigin {
  authored,
  imported;

  String get toDb => name;

  static LessonOrigin fromDb(String value) =>
      LessonOrigin.values.firstWhere((e) => e.name == value,
          orElse: () => throw StateError('Unrecognized LessonOrigin "$value".'));
}

/// Allowed status moves (D-2 X03):
///   draft → inReview, inReview → published, inReview → draft (always allowed
///   before publication), published → draft (when edited: a new version).
/// Everything else (draft → published directly, published → inReview, a move
/// to the same status) is refused.
bool canTransition(LessonStatus from, LessonStatus to) {
  switch (from) {
    case LessonStatus.draft:
      return to == LessonStatus.inReview;
    case LessonStatus.inReview:
      return to == LessonStatus.published || to == LessonStatus.draft;
    case LessonStatus.published:
      return to == LessonStatus.draft;
  }
}

/// A node typed by the teacher, before it is stored.
class NodeDraft {
  const NodeDraft({
    required this.key,
    required this.name,
    this.pageFrom,
    this.pageTo,
    this.requiresKey,
  });

  /// Stable key inside one draft (the stored id for an existing node).
  final String key;
  final String name;
  final int? pageFrom;
  final int? pageTo;
  final String? requiresKey;
}

/// One problem found while checking a lesson. [code] is machine-readable,
/// [message] is the Arabic text shown to the teacher.
class LessonIssue {
  const LessonIssue(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => code;
}

/// Checks the mandatory fields of step 1.
List<LessonIssue> validateLessonFields({
  required String title,
  required String subjectName,
  required int? internalLevel,
  required String teacherName,
}) {
  final issues = <LessonIssue>[];
  if (title.trim().isEmpty) {
    issues.add(const LessonIssue('title_required', 'عنوان الدرس مطلوب.'));
  }
  if (subjectName.trim().isEmpty) {
    issues.add(const LessonIssue('subject_required', 'المادة مطلوبة.'));
  }
  if (!isValidInternalLevel(internalLevel)) {
    issues.add(const LessonIssue(
        'level_invalid', 'اختر المستوى 1 أو 2 أو 3.'));
  }
  if (teacherName.trim().isEmpty) {
    issues.add(const LessonIssue('teacher_required', 'اسم الأستاذ مطلوب.'));
  }
  return issues;
}

/// Checks the nodes of step 3 against [pageCount] pages:
///   - every name is non-empty and unique inside the lesson,
///   - page ranges are inside 1..pageCount and from <= to (both or neither),
///   - a required node exists, is another node, and no cycle is formed.
List<LessonIssue> validateNodes(List<NodeDraft> nodes, int pageCount) {
  final issues = <LessonIssue>[];
  final keys = <String>{};
  final names = <String>{};
  for (final n in nodes) {
    if (!keys.add(n.key)) {
      issues.add(LessonIssue('node_key_duplicate', 'عقدة مكررة داخليًا: ${n.key}'));
    }
    final name = n.name.trim();
    if (name.isEmpty) {
      issues.add(const LessonIssue('node_name_required', 'اسم العقدة مطلوب.'));
    } else if (!names.add(name)) {
      issues.add(LessonIssue('node_name_duplicate', 'اسم العقدة مكرر: $name'));
    }
    final from = n.pageFrom;
    final to = n.pageTo;
    if ((from == null) != (to == null)) {
      issues.add(LessonIssue('node_range_incomplete',
          'حدّد بداية الصفحات ونهايتها معًا للعقدة «$name».'));
    } else if (from != null && to != null) {
      if (from < 1 || to < from || to > pageCount) {
        issues.add(LessonIssue('node_range_invalid',
            'نطاق صفحات العقدة «$name» خارج صفحات الدرس.'));
      }
    }
  }
  final byKey = {for (final n in nodes) n.key: n};
  for (final n in nodes) {
    final r = n.requiresKey;
    if (r == null) continue;
    if (r == n.key) {
      issues.add(LessonIssue('node_requires_self',
          'العقدة «${n.name.trim()}» لا تتطلب نفسها.'));
    } else if (!byKey.containsKey(r)) {
      issues.add(LessonIssue('node_requires_missing',
          'العقدة «${n.name.trim()}» تتطلب عقدة غير موجودة في الدرس.'));
    }
  }
  // Cycle check: each node has at most ONE requirement, so following the
  // chain from every node either ends or revisits a node.
  for (final n in nodes) {
    // A node requiring itself is already reported as node_requires_self.
    if (n.requiresKey == n.key) continue;
    final seen = <String>{n.key};
    var cur = n.requiresKey;
    while (cur != null && byKey.containsKey(cur)) {
      if (!seen.add(cur)) {
        issues.add(LessonIssue('node_requires_cycle',
            'تسلسل المتطلبات حول العقدة «${n.name.trim()}» دائري.'));
        break;
      }
      cur = byKey[cur]!.requiresKey;
    }
  }
  return issues;
}

/// "اكتملت الخطوات الأربع": a lesson may be sent to review only when its
/// fields are valid, it has at least one page and its nodes are valid.
List<LessonIssue> readinessForReview({
  required String title,
  required String subjectName,
  required int? internalLevel,
  required String teacherName,
  required int pageCount,
  required List<NodeDraft> nodes,
}) {
  final issues = validateLessonFields(
    title: title,
    subjectName: subjectName,
    internalLevel: internalLevel,
    teacherName: teacherName,
  );
  if (pageCount < 1) {
    issues.add(const LessonIssue(
        'pages_required', 'أضف صفحة واحدة على الأقل قبل الإرسال إلى المراجعة.'));
  }
  issues.addAll(validateNodes(nodes, pageCount));
  return issues;
}

/// Image kinds accepted for lesson pages. TEMPORARY decision (O-3): the
/// formats a phone camera/gallery normally produces. Detected from the
/// file's own first bytes, never from its name.
String? sniffImageMime(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46 && // F
      bytes[8] == 0x57 && // W
      bytes[9] == 0x45 && // E
      bytes[10] == 0x42 && // B
      bytes[11] == 0x50) {
    // P
    return 'image/webp';
  }
  return null;
}

/// Human-readable size, e.g. 2.4 م.ب (used for the size lines of D-2).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes ب';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
}

/// Order change for a list of pages: moves the item at [index] by [delta]
/// positions (−1 earlier, +1 later). Returns a NEW list; out-of-range moves
/// return the list unchanged.
List<T> movedItem<T>(List<T> items, int index, int delta) {
  final target = index + delta;
  if (index < 0 ||
      index >= items.length ||
      target < 0 ||
      target >= items.length) {
    return List<T>.of(items);
  }
  final copy = List<T>.of(items);
  final item = copy.removeAt(index);
  copy.insert(target, item);
  return copy;
}

/// Bytes helper kept here so the UI never needs dart:typed_data directly.
Uint8List asUint8List(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
