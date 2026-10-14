import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/sha256.dart';
import '../repositories/teacher_content_repository.dart';
import 'remote_config.dart';
import 'teacher_package_service.dart';

/// A network/server problem with a message that can be shown to the user.
class RemoteException implements Exception {
  const RemoteException(this.message, {this.transient = false});
  final String message;

  /// True for problems that may disappear on a second try (no connection,
  /// timeout, server busy). Wrong password / refused data are never retried.
  final bool transient;
  @override
  String toString() => message;
}

/// One lesson as listed on the shared storage (metadata only).
class RemoteLessonEntry {
  const RemoteLessonEntry({
    required this.originLessonId,
    required this.versionNumber,
    required this.internalLevel,
    required this.title,
    required this.subjectName,
    required this.teacherName,
    required this.fingerprint,
    required this.packagePath,
  });

  final String originLessonId;
  final int versionNumber;
  final int internalLevel;
  final String title;
  final String subjectName;
  final String teacherName;
  final String fingerprint;
  final String packagePath;

  static RemoteLessonEntry fromJson(Map<String, dynamic> j) =>
      RemoteLessonEntry(
        originLessonId: j['origin_lesson_id'] as String,
        versionNumber: (j['version_number'] as num).toInt(),
        internalLevel: (j['internal_level'] as num).toInt(),
        title: (j['title'] as String?) ?? '',
        subjectName: (j['subject_name'] as String?) ?? '',
        teacherName: (j['teacher_name'] as String?) ?? '',
        fingerprint: (j['fingerprint'] as String?) ?? '',
        packagePath: j['package_path'] as String,
      );
}

/// Talks to the shared lesson storage (Supabase REST / Storage / one Edge
/// Function). Reading is public; writing goes through `teacher-publish`,
/// which verifies the teachers' password ON THE SERVER.
class LessonRemoteService {
  LessonRemoteService({
    String baseUrl = kSupabaseUrl,
    String anonKey = kSupabaseAnonKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
    this.retryDelay = const Duration(milliseconds: 700),
    this.attempts = 3,
  })  : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        anonKey = anonKey,
        _client = client ?? http.Client();

  final String baseUrl;
  final String anonKey;
  final Duration timeout;

  /// Pause before a second try of a failed file, and how many tries in all.
  final Duration retryDelay;
  final int attempts;
  final http.Client _client;

  static const bucket = 'lesson-files';

  bool get configured => baseUrl.isNotEmpty && anonKey.isNotEmpty;

  Map<String, String> get _headers => {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      };

  void _requireConfigured() {
    if (!configured) {
      throw const RemoteException(
          'التحديث عبر الإنترنت غير مفعّل بعد في هذه النسخة.');
    }
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException {
      throw const RemoteException('انتهت مهلة الاتصال بالخادم. حاول لاحقًا.',
          transient: true);
    } on http.ClientException {
      throw const RemoteException(
          'تعذّر الاتصال بالخادم. تحقّق من الإنترنت.',
          transient: true);
    }
  }

  Future<Map<String, dynamic>> _function(Map<String, dynamic> body) async {
    _requireConfigured();
    final res = await _send(() => _client.post(
          Uri.parse('$baseUrl/functions/v1/teacher-publish'),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ));
    Map<String, dynamic> parsed = const {};
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      if (d is Map<String, dynamic>) parsed = d;
    } on FormatException {
      // handled by status below
    }
    if (res.statusCode == 401) {
      throw const RemoteException('كلمة مرور الأساتذة غير صحيحة.');
    }
    if (res.statusCode == 429) {
      throw const RemoteException('محاولات كثيرة. انتظر قليلًا ثم حاول.');
    }
    if (res.statusCode != 200) {
      final msg = parsed['message'];
      throw RemoteException(
          msg is String && msg.isNotEmpty
              ? msg
              : 'رفض الخادم الطلب (${res.statusCode}).',
          transient: res.statusCode >= 500);
    }
    return parsed;
  }

  /// True when the server accepts [password]. A wrong password is `false`;
  /// network problems throw [RemoteException].
  Future<bool> verifyPassword(String password) async {
    try {
      await _function({'action': 'verify', 'password': password});
      return true;
    } on RemoteException catch (e) {
      if (e.message == 'كلمة مرور الأساتذة غير صحيحة.') return false;
      rethrow;
    }
  }

  Future<void> unpublish({
    required String password,
    required String originLessonId,
  }) async {
    await _function({
      'action': 'unpublish',
      'password': password,
      'originLessonId': originLessonId,
    });
  }

  /// Lessons of one level path (1, 2 or 3), newest first.
  Future<List<RemoteLessonEntry>> list({required int level}) async {
    _requireConfigured();
    final uri = Uri.parse('$baseUrl/rest/v1/lessons').replace(
      queryParameters: {
        'select': 'origin_lesson_id,version_number,internal_level,title,'
            'subject_name,teacher_name,fingerprint,package_path',
        'internal_level': 'eq.$level',
        'order': 'updated_at.desc',
      },
    );
    final res = await _send(() => _client.get(uri, headers: _headers));
    if (res.statusCode != 200) {
      throw RemoteException('تعذّر جلب قائمة الدروس (${res.statusCode}).');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! List) {
      throw const RemoteException('ردّ غير متوقع من الخادم.');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(RemoteLessonEntry.fromJson)
        .toList();
  }

  /// Runs [job]; a transient failure is retried (with a pause) up to
  /// [attempts] times in all. Other failures surface at once.
  Future<T> _retry<T>(Future<T> Function() job) async {
    var n = 0;
    while (true) {
      n++;
      try {
        return await job();
      } on RemoteException catch (e) {
        if (!e.transient || n >= attempts) rethrow;
        if (retryDelay > Duration.zero) await Future<void>.delayed(retryDelay);
      }
    }
  }

  static String _extFor(String mime) {
    switch (mime) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'application/pdf':
        return 'pdf';
      default:
        return 'bin';
    }
  }

  /// Splits a lesson file (the manual-export text) into the small index
  /// (manifest) and the separate photo / attachment files.
  static ({String manifest, List<LessonFile> files, Map<String, dynamic> meta})
      splitPackage(String packageJson) {
    final d = jsonDecode(packageJson);
    if (d is! Map<String, dynamic>) {
      throw const RemoteException('ملف الدرس غير مقروء.');
    }
    final lesson = d['lesson'] as Map<String, dynamic>;
    final id = lesson['originLessonId'] as String;
    final ver = lesson['versionNumber'] as int;
    final folder = 'lessons/$id/v$ver';
    final files = <LessonFile>[];
    final pages = <Map<String, dynamic>>[];
    var i = 0;
    for (final p in (d['pages'] as List).cast<Map<String, dynamic>>()) {
      i++;
      final bytes = base64Decode(p['data'] as String);
      final mime = p['mimeType'] as String;
      final f = LessonFile(
          path: '$folder/page-$i.${_extFor(mime)}',
          mimeType: mime,
          bytes: bytes);
      files.add(f);
      pages.add({
        'mimeType': mime,
        'quarterTurns': p['quarterTurns'],
        'path': f.path,
        'size': bytes.length,
        'sha256': Sha256.hex(bytes),
      });
    }
    final atts = <Map<String, dynamic>>[];
    i = 0;
    for (final a in (d['attachments'] as List).cast<Map<String, dynamic>>()) {
      i++;
      final bytes = base64Decode(a['data'] as String);
      final mime = a['mimeType'] as String;
      final f = LessonFile(
          path: '$folder/att-$i.${_extFor(mime)}',
          mimeType: mime,
          bytes: bytes);
      files.add(f);
      atts.add({
        'name': a['name'],
        'mimeType': mime,
        'path': f.path,
        'size': bytes.length,
        'sha256': Sha256.hex(bytes),
      });
    }
    final manifest = <String, dynamic>{...d, 'pages': pages, 'attachments': atts};
    return (
      manifest: jsonEncode(manifest),
      files: files,
      meta: {
        'originLessonId': id,
        'versionNumber': ver,
        'internalLevel': lesson['internalLevel'],
        'title': lesson['title'],
        'subjectName': lesson['subjectName'],
        'teacherName': lesson['teacherName'],
        'fingerprint': d['fingerprint'],
      },
    );
  }

  /// Teacher side: sends a lesson photo by photo, asks the server to confirm
  /// that every file is there, then READS EVERYTHING BACK (every file's size
  /// and SHA-256) before saying it arrived. Throws [RemoteException] naming
  /// the step that failed; never returns normally unless the read-back passed.
  Future<PublishCheck> publishLesson({
    required String password,
    required String packageJson,
    void Function(String message)? onProgress,
  }) async {
    _requireConfigured();
    final Map<String, dynamic> info = await _retry(
        () => _function({'action': 'verify', 'password': password}));
    if ((info['version'] as num?)?.toInt() != 2) {
      throw const RemoteException(
          'دالة الخادم قديمة. الصق نص الدالة الجديد في Supabase ثم أعد الإرسال '
          '(الخطوات في ملف SUPABASE_SETUP_AR.md).');
    }
    final split = splitPackage(packageJson);
    final total = split.files.length;
    var n = 0;
    for (final f in split.files) {
      n++;
      onProgress?.call('رفع الصورة $n من $total…');
      try {
        await _retry(() => _function({
              'action': 'putFile',
              'password': password,
              'path': f.path,
              'mimeType': f.mimeType,
              'data': base64Encode(f.bytes),
            }));
      } on RemoteException catch (e) {
        throw RemoteException('تعذّر رفع الصورة $n من $total: ${e.message}');
      }
    }
    onProgress?.call('تأكيد وصول كل الصور…');
    await _retry(() => _function({
          'action': 'commit',
          'password': password,
          'lesson': split.meta,
          'manifest': split.manifest,
        }));
    onProgress?.call('قراءة الدرس من الخادم للتأكد…');
    final level = (split.meta['internalLevel'] as num).toInt();
    final listed = await _retry(() => list(level: level));
    RemoteLessonEntry? entry;
    for (final e in listed) {
      if (e.originLessonId == split.meta['originLessonId']) entry = e;
    }
    if (entry == null) {
      throw RemoteException(
          'رُفع الدرس لكنه لا يظهر في قائمة المستوى $level على الخادم.');
    }
    if (entry.fingerprint != split.meta['fingerprint']) {
      throw const RemoteException(
          'الدرس على الخادم لا يطابق ما أرسلته (المحتوى مختلف).');
    }
    final got = await fetchLesson(entry);
    if (got.pages != (jsonDecode(split.manifest)['pages'] as List).length) {
      throw RemoteException(
          'وصل الدرس بـ ${got.pages} صفحة بدل '
          '${(jsonDecode(split.manifest)['pages'] as List).length}.');
    }
    return PublishCheck(
        pages: got.pages, bytes: got.bytes, files: got.files);
  }

  /// Downloads ONE file and checks its size and SHA-256 against the index.
  Future<List<int>> _fetchFile(String path, int size, String sha) async {
    final uri = Uri.parse('$baseUrl/storage/v1/object/public/$bucket/'
        '${path.split('/').map(Uri.encodeComponent).join('/')}');
    final res = await _send(() => _client.get(uri, headers: _headers));
    if (res.statusCode == 404 || res.statusCode == 400) {
      throw const RemoteException('الملف غير موجود على الخادم.');
    }
    if (res.statusCode != 200) {
      throw RemoteException('تعذّر تنزيل الملف (${res.statusCode}).',
          transient: res.statusCode >= 500);
    }
    final bytes = res.bodyBytes;
    if (bytes.length != size || Sha256.hex(bytes) != sha) {
      // A cut-off or damaged download is worth one more try.
      throw RemoteException(
          'الملف وصل ناقصًا أو تالفًا (${bytes.length} بايت من $size).',
          transient: true);
    }
    return bytes;
  }

  /// Student side: downloads the index and EVERY file of a lesson, verifies
  /// each one, and returns the full lesson file text for the normal import.
  /// If any photo is missing or damaged nothing is returned (the lesson is
  /// never saved half-complete).
  Future<FetchedLesson> fetchLesson(RemoteLessonEntry e) async {
    _requireConfigured();
    final uri = Uri.parse('$baseUrl/storage/v1/object/public/$bucket/'
        '${e.packagePath.split('/').map(Uri.encodeComponent).join('/')}');
    final res = await _retry(() async {
      final r = await _send(() => _client.get(uri, headers: _headers));
      if (r.statusCode != 200) {
        throw RemoteException('تعذّر تنزيل فهرس الدرس (${r.statusCode}).',
            transient: r.statusCode >= 500);
      }
      return r;
    });
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const RemoteException('فهرس الدرس غير مقروء.');
    }
    if (decoded is! Map<String, dynamic> || decoded['pages'] is! List) {
      throw const RemoteException('فهرس الدرس غير صالح.');
    }
    // Older single-file lessons carry their photos inline.
    final firstPage = (decoded['pages'] as List).isEmpty
        ? null
        : (decoded['pages'] as List).first;
    if (firstPage is Map && firstPage.containsKey('data')) {
      final text = utf8.decode(res.bodyBytes);
      return FetchedLesson(
          json: text,
          pages: (decoded['pages'] as List).length,
          files: (decoded['pages'] as List).length,
          bytes: res.bodyBytes.length);
    }
    final pagesIn = (decoded['pages'] as List).cast<Map<String, dynamic>>();
    final attsIn =
        ((decoded['attachments'] as List?) ?? const []).cast<Map<String, dynamic>>();
    var total = 0;
    final pagesOut = <Map<String, dynamic>>[];
    var i = 0;
    for (final p in pagesIn) {
      i++;
      final List<int> bytes;
      try {
        bytes = await _retry(() => _fetchFile(
            p['path'] as String, (p['size'] as num).toInt(),
            p['sha256'] as String));
      } on RemoteException catch (ex) {
        throw RemoteException(
            'الصورة $i من ${pagesIn.length} لم تصل: ${ex.message}');
      }
      total += bytes.length;
      pagesOut.add({
        'mimeType': p['mimeType'],
        'quarterTurns': p['quarterTurns'],
        'data': base64Encode(bytes),
      });
    }
    final attsOut = <Map<String, dynamic>>[];
    i = 0;
    for (final a in attsIn) {
      i++;
      final List<int> bytes;
      try {
        bytes = await _retry(() => _fetchFile(
            a['path'] as String, (a['size'] as num).toInt(),
            a['sha256'] as String));
      } on RemoteException catch (ex) {
        throw RemoteException(
            'المرفق $i من ${attsIn.length} لم يصل: ${ex.message}');
      }
      total += bytes.length;
      attsOut.add({
        'name': a['name'],
        'mimeType': a['mimeType'],
        'data': base64Encode(bytes),
      });
    }
    final rebuilt = <String, dynamic>{
      ...decoded,
      'pages': pagesOut,
      'attachments': attsOut,
    };
    return FetchedLesson(
        json: jsonEncode(rebuilt),
        pages: pagesOut.length,
        files: pagesOut.length + attsOut.length,
        bytes: total);
  }

  /// Step-by-step connection test for one level path, in plain Arabic.
  /// Each line starts with ✓ or ✗ so a screenshot shows exactly where it stops.
  Future<List<String>> diagnose(int level) async {
    final out = <String>[];
    if (!configured) {
      return const ['✗ عنوان الخادم غير مضبوط في هذه النسخة.'];
    }
    List<RemoteLessonEntry> listed;
    try {
      listed = await list(level: level);
      out.add('✓ الاتصال بالخادم وقراءة القائمة نجحا.');
      out.add('✓ عدد الدروس المنشورة في المستوى $level: ${listed.length}.');
    } on RemoteException catch (e) {
      out.add('✗ قراءة القائمة: ${e.message}');
      return out;
    }
    if (listed.isEmpty) {
      out.add('• لا درس منشور في هذا المستوى بعد، فلا شيء لتنزيله.');
      return out;
    }
    final first = listed.first;
    try {
      final got = await fetchLesson(first);
      final mb = (got.bytes / 1048576).toStringAsFixed(2);
      out.add('✓ تنزيل «${first.title}» نجح كاملًا: ${got.pages} صفحة، '
          '$mb ميغابايت، وكل صورة طابقت بصمتها.');
    } on RemoteException catch (e) {
      out.add('✗ تنزيل «${first.title}»: ${e.message}');
    }
    return out;
  }

  void close() => _client.close();
}

/// One photo / attachment to upload.
class LessonFile {
  const LessonFile(
      {required this.path, required this.mimeType, required this.bytes});
  final String path;
  final String mimeType;
  final List<int> bytes;
}

/// A lesson fully downloaded and verified (every file matched its size and
/// SHA-256). [json] is the normal lesson file text, ready for the import.
class FetchedLesson {
  const FetchedLesson(
      {required this.json,
      required this.pages,
      required this.files,
      required this.bytes});
  final String json;
  final int pages;
  final int files;
  final int bytes;
}

/// What a read-back of a published lesson proved.
class PublishCheck {
  const PublishCheck(
      {required this.pages, required this.bytes, this.files = 0});
  final int pages;
  final int bytes;
  final int files;
  String get sizeLabel => '${(bytes / 1048576).toStringAsFixed(2)} ميغابايت';
}

/// The teachers' password kept IN MEMORY only, for the current visit to the
/// teacher panel. It is never written to disk and is cleared on exit.
class TeacherRemoteSession {
  String? _password;
  bool get signedIn => _password != null;
  String? get password => _password;
  void signIn(String password) => _password = password;
  void signOut() => _password = null;
}

class SyncReport {
  const SyncReport({
    this.added = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.failed = 0,
    this.pagesReceived = 0,
    this.errors = const [],
  });
  final int added;
  final int updated;
  final int unchanged;
  final int failed;

  /// Pages (photos) actually downloaded and stored in this run.
  final int pagesReceived;
  final List<String> errors;
  int get total => added + updated + unchanged + failed;
  bool get changedAnything => added + updated > 0;

  String get summary {
    if (total == 0) return 'لا دروس منشورة في هذا المستوى على الخادم حتى الآن.';
    final parts = <String>[];
    if (added > 0) parts.add('أُضيف $added');
    if (pagesReceived > 0) parts.add('وصلت $pagesReceived صفحة');
    if (updated > 0) parts.add('حُدّث $updated');
    if (unchanged > 0) parts.add('لم يتغيّر $unchanged');
    if (failed > 0) parts.add('تعذّر $failed');
    return parts.join(' · ');
  }
}

/// Student side: pulls the lessons of ONE level path from the shared storage
/// into the local library (the same import path as the manual file, so
/// duplicate / newer-version / corrupt checks are identical). Imported
/// lessons are stored locally and open offline afterwards.
class LessonSyncService {
  LessonSyncService(this._remote, this._repo)
      : _packages = TeacherPackageService(_repo);

  final LessonRemoteService _remote;
  final TeacherContentRepository _repo;
  final TeacherPackageService _packages;

  Future<SyncReport> syncLevel(int level) async {
    final entries = await _remote.list(level: level);
    var added = 0, updated = 0, unchanged = 0, failed = 0, pages = 0;
    final errors = <String>[];
    for (final e in entries) {
      try {
        if (e.fingerprint.isNotEmpty &&
            await _repo.findImportedByFingerprint(e.fingerprint) != null) {
          unchanged++;
          continue;
        }
        final same = await _repo.findImportedByOrigin(e.originLessonId);
        // A newer number always updates. The SAME number with a different
        // fingerprint means the teacher corrected the lesson (section, stream,
        // title...) without a new version: the copy here is replaced too.
        if (same != null && same.versionNumber > e.versionNumber) {
          unchanged++;
          continue;
        }
        if (same != null &&
            same.versionNumber == e.versionNumber &&
            e.fingerprint.isEmpty) {
          unchanged++;
          continue;
        }
        final got = await _remote.fetchLesson(e);
        final result =
            await _packages.importPackage(got.json, replaceSameVersion: true);
        switch (result.preview.kind) {
          case PackageKind.fresh:
            added++;
            pages += result.preview.content?.pages.length ?? 0;
          case PackageKind.newerVersion:
            updated++;
            pages += result.preview.content?.pages.length ?? 0;
          case PackageKind.duplicate:
          case PackageKind.olderVersion:
            unchanged++;
          case PackageKind.corrupt:
          case PackageKind.unsupported:
            if (result.written) {
              updated++;
              pages += result.preview.content?.pages.length ?? 0;
            } else {
              failed++;
              errors.add('${e.title}: ${result.preview.message}');
            }
        }
      } on RemoteException catch (ex) {
        failed++;
        errors.add('${e.title}: ${ex.message}');
      }
    }
    return SyncReport(
        added: added,
        updated: updated,
        unchanged: unchanged,
        failed: failed,
        pagesReceived: pages,
        errors: errors);
  }
}
