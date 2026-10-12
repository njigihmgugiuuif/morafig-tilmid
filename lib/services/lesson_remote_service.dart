import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../repositories/teacher_content_repository.dart';
import 'remote_config.dart';
import 'teacher_package_service.dart';

/// A network/server problem with a message that can be shown to the user.
class RemoteException implements Exception {
  const RemoteException(this.message);
  final String message;
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
  })  : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        anonKey = anonKey,
        _client = client ?? http.Client();

  final String baseUrl;
  final String anonKey;
  final Duration timeout;
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
      throw const RemoteException('انتهت مهلة الاتصال بالخادم. حاول لاحقًا.');
    } on http.ClientException {
      throw const RemoteException(
          'تعذّر الاتصال بالخادم. تحقّق من الإنترنت.');
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
      throw RemoteException(msg is String && msg.isNotEmpty
          ? msg
          : 'رفض الخادم الطلب (${res.statusCode}).');
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

  /// Uploads a published lesson ([packageJson] is the output of
  /// `TeacherPackageService.exportLesson`) to the shared storage.
  Future<void> publish({
    required String password,
    required String originLessonId,
    required int versionNumber,
    required int internalLevel,
    required String title,
    required String subjectName,
    required String teacherName,
    required String fingerprint,
    required String packageJson,
  }) async {
    await _function({
      'action': 'publish',
      'password': password,
      'lesson': {
        'originLessonId': originLessonId,
        'versionNumber': versionNumber,
        'internalLevel': internalLevel,
        'title': title,
        'subjectName': subjectName,
        'teacherName': teacherName,
        'fingerprint': fingerprint,
      },
      'package': packageJson,
    });
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

  /// The lesson file text (the same format as the manual export).
  Future<String> downloadPackage(String packagePath) async {
    _requireConfigured();
    final uri = Uri.parse('$baseUrl/storage/v1/object/public/$bucket/'
        '${packagePath.split('/').map(Uri.encodeComponent).join('/')}');
    final res = await _send(() => _client.get(uri, headers: _headers));
    if (res.statusCode != 200) {
      throw RemoteException('تعذّر تنزيل ملف الدرس (${res.statusCode}).');
    }
    return utf8.decode(res.bodyBytes);
  }

  /// Proof that a published lesson really is on the shared storage: it must
  /// be listed under its level, its file must download, and the file must
  /// carry the same fingerprint and the same number of pages. Every failing
  /// step has its own message so the cause is visible, never a silent "ok".
  Future<PublishCheck> verifyPublished({
    required String originLessonId,
    required int level,
    required String fingerprint,
    required int expectedPages,
  }) async {
    final listed = await list(level: level);
    RemoteLessonEntry? entry;
    for (final e in listed) {
      if (e.originLessonId == originLessonId) {
        entry = e;
        break;
      }
    }
    if (entry == null) {
      throw RemoteException(
          'رُفع الدرس لكنه لا يظهر في قائمة المستوى $level على الخادم '
          '(عدد دروس هذا المستوى الآن: ${listed.length}).');
    }
    if (entry.fingerprint != fingerprint) {
      throw const RemoteException(
          'الدرس موجود على الخادم لكن محتواه لا يطابق ما أرسلته.');
    }
    final text = await downloadPackage(entry.packagePath);
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const RemoteException(
          'نُزّل ملف الدرس من الخادم لكنه غير مقروء.');
    }
    final pages = decoded is Map<String, dynamic> && decoded['pages'] is List
        ? (decoded['pages'] as List).length
        : -1;
    if (decoded is! Map<String, dynamic> ||
        decoded['fingerprint'] != fingerprint) {
      throw const RemoteException(
          'الملف الذي على الخادم لا يطابق الدرس المرسَل (المحتوى مختلف).');
    }
    if (pages != expectedPages) {
      throw RemoteException(
          'وصل الدرس بـ $pages صفحة بدل $expectedPages.');
    }
    return PublishCheck(pages: pages, bytes: utf8.encode(text).length);
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
      final text = await downloadPackage(first.packagePath);
      final d = jsonDecode(text);
      final pages = d is Map<String, dynamic> && d['pages'] is List
          ? (d['pages'] as List).length
          : 0;
      final mb = (utf8.encode(text).length / 1048576).toStringAsFixed(2);
      out.add('✓ تنزيل «${first.title}» نجح: $pages صفحة، $mb ميغابايت.');
    } on RemoteException catch (e) {
      out.add('✗ تنزيل «${first.title}»: ${e.message}');
    } on FormatException {
      out.add('✗ ملف «${first.title}» نُزّل لكنه غير مقروء.');
    }
    return out;
  }

  void close() => _client.close();
}

/// What a read-back of a published lesson proved.
class PublishCheck {
  const PublishCheck({required this.pages, required this.bytes});
  final int pages;
  final int bytes;
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
        if (same != null && same.versionNumber >= e.versionNumber) {
          unchanged++;
          continue;
        }
        final text = await _remote.downloadPackage(e.packagePath);
        final result = await _packages.importPackage(text);
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
          case PackageKind.sameVersionConflict:
            failed++;
            errors.add('${e.title}: ${result.preview.message}');
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
