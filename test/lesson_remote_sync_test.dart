import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:student_app/database/teacher_content_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/sha256.dart';
import 'package:student_app/domain/teacher_content_domain.dart';
import 'package:student_app/repositories/teacher_content_repository.dart';
import 'package:student_app/services/lesson_remote_service.dart';
import 'package:student_app/services/teacher_package_service.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// These tests run the REAL client code against a FAKE of the server (an
/// in-memory stand-in for the Supabase REST / Storage / Edge Function). They
/// prove the app's logic, NOT the real Supabase project: that is tested by
/// hand between two phones (see SUPABASE_SETUP_AR.md).
Uint8List jpeg(int n, [int seed = 0]) => Uint8List.fromList(
    [0xFF, 0xD8, 0xFF, 0xE0, ...List<int>.generate(n, (i) => (i + seed) % 256)]);

class FakeServer {
  FakeServer(this.password);
  final String password;
  final Map<String, Map<String, dynamic>> rows = {};

  /// Shared storage: path → bytes (photos AND manifests).
  final Map<String, List<int>> storage = {};
  bool offline = false;
  int downloads = 0;
  int functionVersion = 2;

  /// Failure injection.
  int putFailuresLeft = 0; // next N putFile calls answer 500
  final Set<String> flakyGetOnce = {}; // first GET of these paths answers 503
  final Set<String> silentlyDrop = {}; // putFile "succeeds" but stores nothing

  http.Response _json(int code, Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)), code,
      headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request req) async {
    if (offline) throw http.ClientException('offline');
    final path = req.url.path;
    if (req.method == 'POST' && path == '/functions/v1/teacher-publish') {
      final body =
          jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
      if (body['password'] != password) {
        return _json(401, {'error': 'wrong_password'});
      }
      switch (body['action']) {
        case 'verify':
          return _json(200, {'ok': true, 'version': functionVersion});
        case 'putFile':
          if (putFailuresLeft > 0) {
            putFailuresLeft--;
            return _json(500, {'message': 'storage busy'});
          }
          final bytes = base64Decode(body['data'] as String);
          if (!silentlyDrop.contains(body['path'])) {
            storage[body['path'] as String] = bytes;
          }
          return _json(200, {'ok': true, 'size': bytes.length});
        case 'commit':
          final l = body['lesson'] as Map<String, dynamic>;
          final m = jsonDecode(body['manifest'] as String)
              as Map<String, dynamic>;
          final bad = <String>[];
          for (final f in [...m['pages'] as List, ...m['attachments'] as List]) {
            final got = storage[f['path']];
            if (got == null) {
              bad.add('${f['path']} (مفقود)');
            } else if (got.length != f['size']) {
              bad.add('${f['path']} (حجم مختلف)');
            }
          }
          if (bad.isNotEmpty) {
            return _json(409, {'message': 'ملفات ناقصة: ${bad.join('، ')}'});
          }
          final id = l['originLessonId'] as String;
          final mp = 'lessons/$id/v${l['versionNumber']}/manifest.json';
          storage[mp] = utf8.encode(body['manifest'] as String);
          rows[id] = {
            'origin_lesson_id': id,
            'version_number': l['versionNumber'],
            'internal_level': l['internalLevel'],
            'title': l['title'],
            'subject_name': l['subjectName'],
            'teacher_name': l['teacherName'],
            'fingerprint': l['fingerprint'],
            'package_path': mp,
          };
          return _json(200, {'ok': true});
        case 'unpublish':
          final r = rows.remove(body['originLessonId']);
          if (r != null) {
            final folder = (r['package_path'] as String)
                .substring(0, (r['package_path'] as String).lastIndexOf('/'));
            storage.removeWhere((k, _) => k.startsWith('$folder/'));
          }
          return _json(200, {'ok': true});
      }
      return _json(400, {'message': 'bad action'});
    }
    if (req.method == 'GET' && path == '/rest/v1/lessons') {
      final lv = req.url.queryParameters['internal_level']!.substring(3);
      return _json(
          200,
          rows.values
              .where((r) => '${r['internal_level']}' == lv)
              .toList());
    }
    if (req.method == 'GET' &&
        path.startsWith('/storage/v1/object/public/lesson-files/')) {
      downloads++;
      final p = Uri.decodeFull(
          path.substring('/storage/v1/object/public/lesson-files/'.length));
      if (flakyGetOnce.remove(p)) return _json(503, {'error': 'busy'});
      final f = storage[p];
      if (f == null) return _json(404, {'error': 'not found'});
      return http.Response.bytes(f, 200);
    }
    return _json(404, {});
  }
}

void main() {
  late FakeServer server;
  late LessonRemoteService remote;
  late TeacherContentDatabase teacherDb;
  late TeacherContentDatabase studentDb;
  late TeacherContentRepository teacherRepo;
  late TeacherContentRepository studentRepo;

  setUp(() {
    server = FakeServer('secret-pass');
    remote = LessonRemoteService(
      baseUrl: 'https://x.supabase.co/',
      anonKey: 'anon',
      client: MockClient(server.handle),
      retryDelay: Duration.zero,
    );
    teacherDb = createInMemoryTeacherDatabase();
    studentDb = createInMemoryTeacherDatabase();
    teacherRepo = TeacherContentRepository(teacherDb);
    studentRepo = TeacherContentRepository(studentDb);
  });
  tearDown(() async {
    await teacherDb.close();
    await studentDb.close();
  });

  var keySeq = 0;

  Future<String> publishedLesson(int level,
      {String title = 'الدوال الأسية'}) async {
    // Node keys become row ids: they must be unique across lessons.
    final nodeKey = 'node-${keySeq++}';
    final id = await teacherRepo.saveLesson(LessonInput(
      title: title,
      subjectName: 'الرياضيات',
      internalLevel: level,
      teacherName: 'أ. سمير',
      pages: [PageInput(bytes: jpeg(10)), PageInput(bytes: jpeg(20, 7))],
      nodes: [NodeDraft(key: nodeKey, name: 'تعريف', pageFrom: 1, pageTo: 2)],
    ));
    await teacherRepo.transition(id, LessonStatus.inReview);
    await teacherRepo.transition(id, LessonStatus.published);
    return id;
  }

  Future<PublishCheck> publish(String id,
      {String password = 'secret-pass'}) async {
    final out = await TeacherPackageService(teacherRepo).exportLesson(id);
    return remote.publishLesson(password: password, packageJson: out.json);
  }

  test('not configured: refuses with a clear message', () async {
    final off = LessonRemoteService(baseUrl: '', anonKey: '');
    expect(off.configured, isFalse);
    expect(() => off.list(level: 1), throwsA(isA<RemoteException>()));
  });

  test('password is checked by the server: wrong → false, right → true',
      () async {
    expect(await remote.verifyPassword('nope'), isFalse);
    expect(await remote.verifyPassword('secret-pass'), isTrue);
  });

  test('wrong password cannot publish anything', () async {
    final id = await publishedLesson(1);
    expect(() => publish(id, password: 'nope'),
        throwsA(isA<RemoteException>()));
    expect(server.rows, isEmpty);
    expect(server.storage, isEmpty);
  });

  test('offline during verification is an error, not a wrong password',
      () async {
    server.offline = true;
    expect(() => remote.verifyPassword('x'), throwsA(isA<RemoteException>()));
  });

  test('teacher publishes → student of that level receives lesson AND images',
      () async {
    final id = await publishedLesson(2);
    await publish(id);

    final report = await LessonSyncService(remote, studentRepo).syncLevel(2);
    expect(report.added, 1);
    expect(report.failed, 0);

    final list = await studentRepo.listImported();
    expect(list, hasLength(1));
    final agg = await studentRepo.read(list.single.lesson.id);
    expect(agg!.pages.map((p) => p.bytes).toList(),
        [jpeg(10), jpeg(20, 7)]);
    expect(agg.lesson.internalLevel, 2);
    expect(agg.lesson.origin, LessonOrigin.imported.toDb);
  });

  test('a student only receives the path of their own level', () async {
    await publish(await publishedLesson(1, title: 'أ'));
    await publish(await publishedLesson(2, title: 'ب'));
    await publish(await publishedLesson(3, title: 'ج'));
    final report = await LessonSyncService(remote, studentRepo).syncLevel(3);
    expect(report.added, 1);
    final list = await studentRepo.listImported();
    expect(list.single.lesson.title, 'ج');
  });

  test('second sync downloads nothing and changes nothing', () async {
    await publish(await publishedLesson(1));
    final sync = LessonSyncService(remote, studentRepo);
    await sync.syncLevel(1);
    final before = server.downloads;
    final again = await sync.syncLevel(1);
    expect(again.unchanged, 1);
    expect(again.added, 0);
    expect(server.downloads, before);
    expect(await studentRepo.listImported(), hasLength(1));
  });

  test('a newer version updates the local copy', () async {
    final id = await publishedLesson(1);
    await publish(id);
    final sync = LessonSyncService(remote, studentRepo);
    await sync.syncLevel(1);

    // Editing a published lesson creates version 2; publish it again.
    await teacherRepo.saveLesson(LessonInput(
      id: id,
      title: 'عنوان معدّل',
      subjectName: 'الرياضيات',
      internalLevel: 1,
      teacherName: 'أ. سمير',
      pages: [PageInput(bytes: jpeg(5))],
      nodes: [NodeDraft(key: 'node-v2-${keySeq++}', name: 'تعريف', pageFrom: 1, pageTo: 1)],
    ));
    await teacherRepo.transition(id, LessonStatus.inReview);
    await teacherRepo.transition(id, LessonStatus.published);
    await publish(id);

    final report = await sync.syncLevel(1);
    expect(report.updated, 1);
    final list = await studentRepo.listImported();
    expect(list, hasLength(1));
    expect(list.single.lesson.title, 'عنوان معدّل');
  });

  test('the teacher fills the section later with the SAME version: the '
      'student copy is corrected', () async {
    final id = await publishedLesson(1);
    await publish(id);
    final sync = LessonSyncService(remote, studentRepo);
    await sync.syncLevel(1);
    expect((await studentRepo.listImported()).single.lesson.sectionLabel,
        isNull);

    // Fix the lesson directly (same version number), then send it again.
    await (teacherDb.update(teacherDb.teacherLessons)
          ..where((t) => t.id.equals(id)))
        .write(TeacherLessonsCompanion(
            sectionLabel: const Value('قسم 3'),
            trackLabel: const Value('علوم تجريبية')));
    await publish(id);

    final report = await sync.syncLevel(1);
    expect(report.updated, 1);
    expect(report.failed, 0);
    final l = (await studentRepo.listImported()).single.lesson;
    expect(l.sectionLabel, 'قسم 3');
    expect(l.trackLabel, 'علوم تجريبية');
    expect(l.teacherName, 'أ. سمير');
    // And a second sync changes nothing.
    final again = await sync.syncLevel(1);
    expect(again.changedAnything, isFalse);
  });

  test('offline sync fails with a message and keeps local lessons', () async {
    await publish(await publishedLesson(1));
    final sync = LessonSyncService(remote, studentRepo);
    await sync.syncLevel(1);
    server.offline = true;
    expect(() => sync.syncLevel(1), throwsA(isA<RemoteException>()));
    expect(await studentRepo.listImported(), hasLength(1));
  });

  test('unpublish removes it from the list for new syncs only', () async {
    final id = await publishedLesson(1);
    await publish(id);
    await remote.unpublish(password: 'secret-pass', originLessonId: id);
    final report = await LessonSyncService(remote, studentRepo).syncLevel(1);
    expect(report.total, 0);
    expect(report.summary, contains('لا دروس'));
  });

  String manifestPathOf(String id) =>
      server.rows[id]!['package_path'] as String;

  List<String> photoPathsOf(String id) {
    final folder = manifestPathOf(id)
        .substring(0, manifestPathOf(id).lastIndexOf('/'));
    return server.storage.keys
        .where((k) => k.startsWith('$folder/page-'))
        .toList()
      ..sort();
  }

  test('a corrupt manifest on the server is reported, not imported', () async {
    final id = await publishedLesson(1);
    await publish(id);
    server.storage[manifestPathOf(id)] =
        utf8.encode('{"format":"marafiq.teacher-lesson","broken":');
    final report = await LessonSyncService(remote, studentRepo).syncLevel(1);
    expect(report.failed, 1);
    expect(await studentRepo.listImported(), isEmpty);
  });

  group('real delivery of photos', () {
    test('every photo is its own file and the student gets identical bytes',
        () async {
      final id = await publishedLesson(2);
      final check = await publish(id);
      expect(check.pages, 2);
      expect(photoPathsOf(id), hasLength(2));

      final sync = await LessonSyncService(remote, studentRepo).syncLevel(2);
      expect(sync.added, 1);
      expect(sync.pagesReceived, 2);
      final list = await studentRepo.listImported();
      final agg = await studentRepo.read(list.single.lesson.id);
      expect(agg!.pages, hasLength(2));
      // Fingerprint of each received image equals the teacher's image.
      final teacherAgg = await teacherRepo.read(id);
      for (var i = 0; i < 2; i++) {
        expect(Sha256.hex(agg.pages[i].bytes),
            Sha256.hex(teacherAgg!.pages[i].bytes));
      }
    });

    test('publishing several lessons at once all arrive', () async {
      final ids = [
        await publishedLesson(1, title: 'أ'),
        await publishedLesson(1, title: 'ب'),
        await publishedLesson(1, title: 'ج'),
      ];
      for (final id in ids) {
        await publish(id);
      }
      final report = await LessonSyncService(remote, studentRepo).syncLevel(1);
      expect(report.added, 3);
      expect(report.pagesReceived, 6);
    });

    test('a failed photo upload is retried and then succeeds', () async {
      final id = await publishedLesson(1);
      server.putFailuresLeft = 2;
      final check = await publish(id);
      expect(check.pages, 2);
      expect(server.rows, hasLength(1));
    });

    test('upload that keeps failing is an error and nothing is listed',
        () async {
      final id = await publishedLesson(1);
      server.putFailuresLeft = 99;
      expect(
          () => publish(id),
          throwsA(isA<RemoteException>()
              .having((e) => e.message, 'message', contains('تعذّر رفع'))));
      expect(server.rows, isEmpty);
    });

    test('a photo the server silently lost is caught before success',
        () async {
      final id = await publishedLesson(1);
      final out = await TeacherPackageService(teacherRepo).exportLesson(id);
      final split = LessonRemoteService.splitPackage(out.json);
      server.silentlyDrop.add(split.files.last.path);
      expect(
          () => remote.publishLesson(
              password: 'secret-pass', packageJson: out.json),
          throwsA(isA<RemoteException>()
              .having((e) => e.message, 'message', contains('مفقود'))));
      expect(server.rows, isEmpty);
    });

    test('offline during upload is an error, not success', () async {
      final id = await publishedLesson(1);
      server.offline = true;
      expect(() => publish(id), throwsA(isA<RemoteException>()));
    });

    test('an old server function is detected with a clear message', () async {
      final id = await publishedLesson(1);
      server.functionVersion = 1;
      expect(
          () => publish(id),
          throwsA(isA<RemoteException>()
              .having((e) => e.message, 'message', contains('قديمة'))));
    });

    test('student download retries a flaky photo and still completes',
        () async {
      final id = await publishedLesson(1);
      await publish(id);
      server.flakyGetOnce.add(photoPathsOf(id).first);
      final report = await LessonSyncService(remote, studentRepo).syncLevel(1);
      expect(report.added, 1);
      expect(report.failed, 0);
    });

    test('a missing photo means the lesson is NOT saved on the student phone',
        () async {
      final id = await publishedLesson(1);
      await publish(id);
      server.storage.remove(photoPathsOf(id).last);
      final report = await LessonSyncService(remote, studentRepo).syncLevel(1);
      expect(report.added, 0);
      expect(report.failed, 1);
      expect(report.errors.single, contains('الصورة 2 من 2'));
      expect(await studentRepo.listImported(), isEmpty);
    });

    test('a damaged photo (same size, other bytes) is detected', () async {
      final id = await publishedLesson(1);
      await publish(id);
      final p = photoPathsOf(id).first;
      server.storage[p] = server.storage[p]!.map((b) => b ^ 0xFF).toList();
      final report = await LessonSyncService(remote, studentRepo).syncLevel(1);
      expect(report.failed, 1);
      expect(await studentRepo.listImported(), isEmpty);
    });

    test('after a failure, the next sync completes once the file is back',
        () async {
      final id = await publishedLesson(1);
      await publish(id);
      final p = photoPathsOf(id).last;
      final saved = server.storage.remove(p)!;
      final sync = LessonSyncService(remote, studentRepo);
      expect((await sync.syncLevel(1)).failed, 1);
      server.storage[p] = saved;
      final again = await sync.syncLevel(1);
      expect(again.added, 1);
      expect(await studentRepo.listImported(), hasLength(1));
    });

    test('unpublish removes the photos from storage too', () async {
      final id = await publishedLesson(1);
      await publish(id);
      await remote.unpublish(password: 'secret-pass', originLessonId: id);
      expect(server.storage, isEmpty);
    });
  });

  group('proof of delivery', () {
    test('student sync reports how many pages (photos) arrived', () async {
      await publish(await publishedLesson(3));
      final report = await LessonSyncService(remote, studentRepo).syncLevel(3);
      expect(report.pagesReceived, 2);
      expect(report.summary, contains('وصلت 2 صفحة'));
    });

    test('connection check shows each step as ✓', () async {
      await publish(await publishedLesson(1));
      final lines = await remote.diagnose(1);
      expect(lines.where((l) => l.startsWith('✓')).length, 3);
      expect(lines.any((l) => l.startsWith('✗')), isFalse);
    });

    test('connection check on an empty level says so', () async {
      final lines = await remote.diagnose(2);
      expect(lines.first, startsWith('✓'));
      expect(lines.last, contains('لا درس منشور'));
    });

    test('connection check offline stops at the first failing step', () async {
      server.offline = true;
      final lines = await remote.diagnose(1);
      expect(lines, hasLength(1));
      expect(lines.single, startsWith('✗'));
    });

    test('connection check names a missing photo', () async {
      final id = await publishedLesson(1);
      await publish(id);
      server.storage.remove(photoPathsOf(id).first);
      final lines = await remote.diagnose(1);
      expect(lines.last, startsWith('✗'));
      expect(lines.last, contains('الصورة 1'));
    });
  });

  test('teacher password session is memory-only and clearable', () {
    final s = TeacherRemoteSession();
    expect(s.signedIn, isFalse);
    s.signIn('p');
    expect(s.password, 'p');
    s.signOut();
    expect(s.signedIn, isFalse);
    expect(s.password, isNull);
  });
}
