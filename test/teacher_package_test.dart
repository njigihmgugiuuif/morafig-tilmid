import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:student_app/database/teacher_content_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/teacher_content_domain.dart';
import 'package:student_app/repositories/teacher_content_repository.dart';
import 'package:student_app/services/teacher_package_service.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
/// Teacher device and student device are two separate in-memory databases.
Uint8List jpeg(int n, [int seed = 0]) => Uint8List.fromList(
    [0xFF, 0xD8, 0xFF, 0xE0, ...List<int>.generate(n, (i) => (i + seed) % 256)]);

void main() {
  late TeacherContentDatabase teacherDb;
  late TeacherContentDatabase studentDb;
  late TeacherContentRepository teacherRepo;
  late TeacherContentRepository studentRepo;
  late TeacherPackageService teacherService;
  late TeacherPackageService studentService;

  setUp(() {
    teacherDb = createInMemoryTeacherDatabase();
    studentDb = createInMemoryTeacherDatabase();
    teacherRepo = TeacherContentRepository(teacherDb);
    studentRepo = TeacherContentRepository(studentDb);
    teacherService = TeacherPackageService(teacherRepo);
    studentService = TeacherPackageService(studentRepo);
  });
  tearDown(() async {
    await teacherDb.close();
    await studentDb.close();
  });

  Future<String> publishedLesson({String title = 'الدوال الأسية', int level = 2}) async {
    final id = await teacherRepo.saveLesson(LessonInput(
      title: title,
      subjectName: 'الرياضيات',
      internalLevel: level,
      teacherName: 'أ. سمير',
      sectionLabel: '2 علوم تجريبية',
      notes: 'انتبه',
      pages: [
        PageInput(bytes: jpeg(10), quarterTurns: 1),
        PageInput(bytes: jpeg(20, 7)),
      ],
      nodes: const [
        NodeDraft(key: 'n1', name: 'تعريف', pageFrom: 1, pageTo: 1),
        NodeDraft(key: 'n2', name: 'خصائص', pageFrom: 2, pageTo: 2, requiresKey: 'n1'),
      ],
    ));
    await teacherRepo.transition(id, LessonStatus.inReview);
    await teacherRepo.transition(id, LessonStatus.published);
    return id;
  }

  group('export', () {
    test('only a published lesson can be exported', () async {
      final id = await teacherRepo.saveLesson(LessonInput(
        title: 'ت',
        subjectName: 'م',
        internalLevel: 1,
        teacherName: 'أ',
        pages: [PageInput(bytes: jpeg(3))],
      ));
      expect(() => teacherService.exportLesson(id),
          throwsA(isA<TeacherContentException>()));
    });

    test('export records the export and carries no student data', () async {
      final id = await publishedLesson();
      final out = await teacherService.exportLesson(id);
      expect(out.fileName, endsWith('.marafiq-lesson.json'));
      final decoded = jsonDecode(out.json) as Map<String, dynamic>;
      expect(decoded.keys.toSet(),
          {'format', 'formatVersion', 'fingerprint', 'lesson', 'pages', 'nodes', 'attachments'});
      final summary = await teacherRepo.exportSummary();
      expect(summary.packages, 1);
      expect(summary.last, isNotNull);
    });
  });

  group('import', () {
    test('round trip: a package becomes a read-only imported lesson in the '
        'SAME level slot', () async {
      final id = await publishedLesson(level: 3);
      final json = (await teacherService.exportLesson(id)).json;

      final preview = await studentService.inspect(json);
      expect(preview.kind, PackageKind.fresh);
      expect(preview.canImport, isTrue);

      final result = await studentService.importPackage(json);
      expect(result.written, isTrue);
      final agg = (await studentRepo.read(result.lessonId!))!;
      expect(agg.lesson.origin, 'imported');
      expect(agg.lesson.status, 'published');
      expect(agg.lesson.internalLevel, 3);
      expect(agg.lesson.sectionLabel, '2 علوم تجريبية');
      expect(agg.lesson.teacherName, 'أ. سمير');
      expect(agg.pages.map((p) => p.quarterTurns), [1, 0]);
      expect(agg.pages[0].bytes, jpeg(10));
      expect(agg.nodes.length, 2);
      // node ids are re-generated locally but the requirement is preserved
      expect(agg.nodes[1].requiresNodeId, agg.nodes[0].id);
      expect(agg.nodes[0].id, isNot('n1'));
    });

    test('an imported lesson cannot be edited or moved', () async {
      final id = await publishedLesson();
      final json = (await teacherService.exportLesson(id)).json;
      final lessonId = (await studentService.importPackage(json)).lessonId!;
      expect(
          () => studentRepo.saveLesson(LessonInput(
              id: lessonId,
              title: 'x',
              subjectName: 'm',
              internalLevel: 1,
              teacherName: 'a')),
          throwsA(isA<TeacherContentException>()));
      expect(() => studentRepo.transition(lessonId, LessonStatus.draft),
          throwsA(isA<TeacherContentException>()));
    });

    test('the same package twice is a duplicate and adds nothing', () async {
      final id = await publishedLesson();
      final json = (await teacherService.exportLesson(id)).json;
      await studentService.importPackage(json);
      final second = await studentService.importPackage(json);
      expect(second.preview.kind, PackageKind.duplicate);
      expect(second.written, isFalse);
      expect((await studentRepo.listImported()).length, 1);
    });

    test('a newer version replaces the content in place', () async {
      final id = await publishedLesson();
      final v1 = (await teacherService.exportLesson(id)).json;
      final localId = (await studentService.importPackage(v1)).lessonId!;

      await teacherRepo.saveLesson(LessonInput(
        id: id,
        title: 'الدوال الأسية (محدّث)',
        subjectName: 'الرياضيات',
        internalLevel: 2,
        teacherName: 'أ. سمير',
        pages: [PageInput(bytes: jpeg(40))],
      ));
      await teacherRepo.transition(id, LessonStatus.inReview);
      await teacherRepo.transition(id, LessonStatus.published);
      final v2 = (await teacherService.exportLesson(id)).json;

      final preview = await studentService.inspect(v2);
      expect(preview.kind, PackageKind.newerVersion);
      final r = await studentService.importPackage(v2);
      expect(r.lessonId, localId);
      final agg = (await studentRepo.read(localId))!;
      expect(agg.lesson.versionNumber, 2);
      expect(agg.lesson.title, 'الدوال الأسية (محدّث)');
      expect(agg.pages.length, 1);
      expect((await studentRepo.listImported()).length, 1);
    });

    test('an older version is refused when a newer one is present', () async {
      final id = await publishedLesson();
      final v1 = (await teacherService.exportLesson(id)).json;
      await teacherRepo.saveLesson(LessonInput(
          id: id,
          title: 'v2',
          subjectName: 'م',
          internalLevel: 2,
          teacherName: 'أ',
          pages: [PageInput(bytes: jpeg(8))]));
      await teacherRepo.transition(id, LessonStatus.inReview);
      await teacherRepo.transition(id, LessonStatus.published);
      final v2 = (await teacherService.exportLesson(id)).json;

      await studentService.importPackage(v2);
      final old = await studentService.importPackage(v1);
      expect(old.preview.kind, PackageKind.olderVersion);
      expect(old.written, isFalse);
      expect((await studentRepo.listImported()).single.lesson.versionNumber, 2);
    });

    test('corrupt: not JSON, wrong format, tampered content, bad pages',
        () async {
      expect((await studentService.inspect('not json')).kind, PackageKind.corrupt);
      expect((await studentService.inspect('{"format":"other"}')).kind,
          PackageKind.corrupt);

      final id = await publishedLesson();
      final json = (await teacherService.exportLesson(id)).json;
      final tampered = json.replaceFirst('الدوال الأسية', 'عنوان مزوَّر');
      expect((await studentService.inspect(tampered)).kind, PackageKind.corrupt);

      final m = jsonDecode(json) as Map<String, dynamic>;
      (m['pages'] as List).first['data'] = base64Encode([1, 2, 3, 4]);
      expect((await studentService.inspect(jsonEncode(m))).kind,
          PackageKind.corrupt);

      final m2 = jsonDecode(json) as Map<String, dynamic>;
      (m2['lesson'] as Map)['internalLevel'] = 4;
      expect((await studentService.inspect(jsonEncode(m2))).kind,
          PackageKind.corrupt);

      expect(await studentRepo.listImported(), isEmpty,
          reason: 'a refused package writes nothing');
    });

    test('an unknown formatVersion is unsupported, not corrupt', () async {
      final id = await publishedLesson();
      final m = jsonDecode((await teacherService.exportLesson(id)).json)
          as Map<String, dynamic>;
      m['formatVersion'] = 99;
      expect((await studentService.inspect(jsonEncode(m))).kind,
          PackageKind.unsupported);
    });

    test('fingerprint is stable for equal content', () async {
      final id = await publishedLesson();
      final a = jsonDecode((await teacherService.exportLesson(id)).json)
          as Map<String, dynamic>;
      final b = jsonDecode((await teacherService.exportLesson(id)).json)
          as Map<String, dynamic>;
      expect(a['fingerprint'], b['fingerprint']);
      expect((a['fingerprint'] as String).length, 64);
    });

    test('deleting an imported lesson leaves nothing behind and the size '
        'accounting follows', () async {
      final id = await publishedLesson();
      final json = (await teacherService.exportLesson(id)).json;
      final lessonId = (await studentService.importPackage(json)).lessonId!;
      expect(await studentRepo.importedBytes(), greaterThan(0));
      await studentRepo.deleteLesson(lessonId);
      expect(await studentRepo.importedBytes(), 0);
      expect(await studentDb.select(studentDb.teacherLessonPages).get(), isEmpty);
    });
  });
}
