import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:student_app/database/teacher_content_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
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
  final Map<String, String> files = {};
  bool offline = false;
  int downloads = 0;

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
          return _json(200, {'ok': true});
        case 'publish':
          final l = body['lesson'] as Map<String, dynamic>;
          final id = l['originLessonId'] as String;
          final p = 'packages/$id-v${l['versionNumber']}.json';
          files[p] = body['package'] as String;
          rows[id] = {
            'origin_lesson_id': id,
            'version_number': l['versionNumber'],
            'internal_level': l['internalLevel'],
            'title': l['title'],
            'subject_name': l['subjectName'],
            'teacher_name': l['teacherName'],
            'fingerprint': l['fingerprint'],
            'package_path': p,
          };
          return _json(200, {'ok': true});
        case 'unpublish':
          rows.remove(body['originLessonId']);
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
      final f = files[p];
      if (f == null) return _json(404, {'error': 'not found'});
      return http.Response.bytes(utf8.encode(f), 200);
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

  Future<void> publish(String id, {String password = 'secret-pass'}) async {
    final out = await TeacherPackageService(teacherRepo).exportLesson(id);
    final d = jsonDecode(out.json) as Map<String, dynamic>;
    final l = d['lesson'] as Map<String, dynamic>;
    await remote.publish(
      password: password,
      originLessonId: l['originLessonId'] as String,
      versionNumber: l['versionNumber'] as int,
      internalLevel: l['internalLevel'] as int,
      title: l['title'] as String,
      subjectName: l['subjectName'] as String,
      teacherName: l['teacherName'] as String,
      fingerprint: d['fingerprint'] as String,
      packageJson: out.json,
    );
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
    expect(server.files, isEmpty);
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

  test('a corrupt file on the server is reported, not imported', () async {
    final id = await publishedLesson(1);
    await publish(id);
    final path = server.rows.values.single['package_path'] as String;
    server.files[path] = '{"format":"marafiq.teacher-lesson","broken":';
    final report = await LessonSyncService(remote, studentRepo).syncLevel(1);
    expect(report.failed, 1);
    expect(await studentRepo.listImported(), isEmpty);
  });

  group('proof of delivery', () {
    Future<(String id, String fp)> published(int level) async {
      final id = await publishedLesson(level);
      await publish(id);
      return (id, server.rows[id]!['fingerprint'] as String);
    }

    test('read-back proves the lesson and its pages are on the server',
        () async {
      final (id, fp) = await published(2);
      final check = await remote.verifyPublished(
          originLessonId: id, level: 2, fingerprint: fp, expectedPages: 2);
      expect(check.pages, 2);
      expect(check.bytes, greaterThan(0));
    });

    test('a lesson missing from the level list is reported with the count',
        () async {
      final (id, fp) = await published(2);
      server.rows.remove(id);
      expect(
          () => remote.verifyPublished(
              originLessonId: id, level: 2, fingerprint: fp, expectedPages: 2),
          throwsA(isA<RemoteException>()
              .having((e) => e.message, 'message', contains('لا يظهر'))));
    });

    test('wrong page count is reported, not accepted', () async {
      final (id, fp) = await published(1);
      expect(
          () => remote.verifyPublished(
              originLessonId: id, level: 1, fingerprint: fp, expectedPages: 5),
          throwsA(isA<RemoteException>()
              .having((e) => e.message, 'message', contains('بدل 5'))));
    });

    test('a fingerprint that differs from the server copy is reported',
        () async {
      final (id, _) = await published(1);
      expect(
          () => remote.verifyPublished(
              originLessonId: id,
              level: 1,
              fingerprint: 'other',
              expectedPages: 2),
          throwsA(isA<RemoteException>()));
    });

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
