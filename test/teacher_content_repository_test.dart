import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/teacher_content_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/teacher_content_domain.dart';
import 'package:student_app/repositories/teacher_content_repository.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
Uint8List jpeg(int n, [int seed = 0]) => Uint8List.fromList(
    [0xFF, 0xD8, 0xFF, 0xE0, ...List<int>.generate(n, (i) => (i + seed) % 256)]);

LessonInput lesson({
  String? id,
  String title = 'الدوال الأسية',
  int? level = 2,
  String? section = '2 علوم تجريبية',
  List<PageInput>? pages,
  List<NodeDraft> nodes = const [],
  String? link,
}) =>
    LessonInput(
      id: id,
      title: title,
      subjectName: 'الرياضيات',
      internalLevel: level,
      teacherName: 'أ. سمير',
      sectionLabel: section,
      pages: pages ?? [PageInput(bytes: jpeg(10)), PageInput(bytes: jpeg(20))],
      nodes: nodes,
      linkedCurriculumVersionId: link,
    );

void main() {
  late TeacherContentDatabase db;
  late TeacherContentRepository repo;

  setUp(() {
    db = createInMemoryTeacherDatabase();
    repo = TeacherContentRepository(db);
  });
  tearDown(() => db.close());

  test('the main schema is untouched: still version 6 and 41 tables', () async {
    final main = createInMemoryTestDatabase();
    addTearDown(main.close);
    expect(main.schemaVersion, 6);
    expect(main.allTables.length, 41);
    expect(db.schemaVersion, 1);
    expect(db.allTables.length, 4);
  });

  group('saving', () {
    test('saves a lesson with pages in order, as a draft authored v1', () async {
      final id = await repo.saveLesson(lesson());
      final agg = (await repo.read(id))!;
      expect(agg.lesson.status, 'draft');
      expect(agg.lesson.origin, 'authored');
      expect(agg.lesson.versionNumber, 1);
      expect(agg.lesson.internalLevel, 2);
      expect(agg.pages.map((p) => p.pageOrder), [1, 2]);
      expect(agg.pages.every((p) => p.mimeType == 'image/jpeg'), isTrue);
      expect(agg.totalBytes, agg.pages[0].byteSize + agg.pages[1].byteSize);
    });

    test('section is stored as its own field and does not decide the level',
        () async {
      final id = await repo.saveLesson(lesson(level: 3, section: '1 جذع مشترك'));
      final l = (await repo.read(id))!.lesson;
      expect(l.sectionLabel, '1 جذع مشترك');
      expect(l.internalLevel, 3);
    });

    test('a lesson belongs to ONE level slot: lists filter by level only',
        () async {
      await repo.saveLesson(lesson(title: 'أ', level: 1));
      await repo.saveLesson(lesson(title: 'ب', level: 2));
      await repo.saveLesson(lesson(title: 'ج', level: 2, section: null));
      expect((await repo.listAuthored(level: 1)).map((i) => i.lesson.title), ['أ']);
      expect((await repo.listAuthored(level: 2)).length, 2);
      expect(await repo.listAuthored(level: 3), isEmpty);
    });

    test('refuses a level outside 1..3, an unknown image and bad nodes',
        () async {
      expect(() => repo.saveLesson(lesson(level: 4)),
          throwsA(isA<TeacherContentException>()));
      expect(
          () => repo.saveLesson(lesson(
              pages: [PageInput(bytes: Uint8List.fromList([1, 2, 3, 4]))])),
          throwsA(isA<TeacherContentException>()));
      expect(
          () => repo.saveLesson(lesson(nodes: const [
                NodeDraft(key: 'a', name: 'أ', pageFrom: 1, pageTo: 9)
              ])),
          throwsA(isA<TeacherContentException>()));
      expect(await db.select(db.teacherLessons).get(), isEmpty,
          reason: 'a refused save writes nothing');
    });

    test('nodes are stored with their ids and requirement', () async {
      final id = await repo.saveLesson(lesson(nodes: const [
        NodeDraft(key: 'n1', name: 'تعريف', pageFrom: 1, pageTo: 1),
        NodeDraft(key: 'n2', name: 'خصائص', pageFrom: 2, pageTo: 2, requiresKey: 'n1'),
      ]));
      final agg = (await repo.read(id))!;
      expect(agg.nodes.map((n) => n.id), ['n1', 'n2']);
      expect(agg.nodes[1].requiresNodeId, 'n1');
    });

    test('updating replaces pages and keeps one lesson', () async {
      final id = await repo.saveLesson(lesson());
      await repo.saveLesson(lesson(
          id: id, title: 'جديد', pages: [PageInput(bytes: jpeg(5))]));
      final agg = (await repo.read(id))!;
      expect(agg.lesson.title, 'جديد');
      expect(agg.pages.length, 1);
      expect(await db.select(db.teacherLessons).get(), hasLength(1));
    });

    test('page rotation is stored and the bytes are untouched', () async {
      final bytes = jpeg(30);
      final id = await repo.saveLesson(
          lesson(pages: [PageInput(bytes: bytes, quarterTurns: 3)]));
      final p = (await repo.read(id))!.pages.single;
      expect(p.quarterTurns, 3);
      expect(p.bytes, bytes);
    });
  });

  group('status path', () {
    test('draft → inReview → published, nothing skipped', () async {
      final id = await repo.saveLesson(lesson());
      expect(() => repo.transition(id, LessonStatus.published),
          throwsA(isA<TeacherContentException>()));
      await repo.transition(id, LessonStatus.inReview);
      await repo.transition(id, LessonStatus.published);
      expect((await repo.read(id))!.lesson.status, 'published');
    });

    test('a lesson without pages cannot go to review', () async {
      final id = await repo.saveLesson(lesson(pages: const []));
      expect(() => repo.transition(id, LessonStatus.inReview),
          throwsA(isA<TeacherContentException>()));
      expect((await repo.read(id))!.lesson.status, 'draft');
    });

    test('back to draft from review is always allowed', () async {
      final id = await repo.saveLesson(lesson());
      await repo.transition(id, LessonStatus.inReview);
      await repo.transition(id, LessonStatus.draft);
      expect((await repo.read(id))!.lesson.status, 'draft');
    });

    test('editing a published lesson makes a new version and a draft', () async {
      final id = await repo.saveLesson(lesson());
      await repo.transition(id, LessonStatus.inReview);
      await repo.transition(id, LessonStatus.published);
      await repo.saveLesson(lesson(id: id, title: 'معدّل'));
      final l = (await repo.read(id))!.lesson;
      expect(l.status, 'draft');
      expect(l.versionNumber, 2);
    });

    test('editing a lesson in review sends it back to draft, same version',
        () async {
      final id = await repo.saveLesson(lesson());
      await repo.transition(id, LessonStatus.inReview);
      await repo.saveLesson(lesson(id: id, title: 'معدّل'));
      final l = (await repo.read(id))!.lesson;
      expect(l.status, 'draft');
      expect(l.versionNumber, 1);
    });

    test('counts per status', () async {
      final a = await repo.saveLesson(lesson(title: 'أ'));
      await repo.saveLesson(lesson(title: 'ب'));
      await repo.transition(a, LessonStatus.inReview);
      final c = await repo.authoredStatusCounts();
      expect(c[LessonStatus.draft], 1);
      expect(c[LessonStatus.inReview], 1);
      expect(c[LessonStatus.published], 0);
    });
  });

  group('curriculum link', () {
    test('without the main database nothing is linkable and links are refused',
        () async {
      expect(await repo.linkableVersions(), isEmpty);
      expect(() => repo.saveLesson(lesson(link: 'some-version')),
          throwsA(isA<TeacherContentException>()));
    });

    test('only an ACTIVE, existing version can be linked', () async {
      final main = createInMemoryTestDatabase();
      addTearDown(main.close);
      final year = await main.into(main.academicYears).insertReturning(
          AcademicYearsCompanion.insert(
              label: 'T-YEAR',
              startDate: DateTime.utc(2000, 9, 1),
              endDate: DateTime.utc(2001, 6, 30)));
      final doc = await main.into(main.policyDocuments).insertReturning(
          PolicyDocumentsCompanion.insert(
              documentNumber: 'TEST-0001',
              documentType: 'test',
              issuingAuthority: 'test',
              verificationStatus: 'unverified'));
      final active = await main.into(main.curriculumVersions).insertReturning(
          CurriculumVersionsCompanion.insert(
              academicYearId: year.id,
              status: 'active',
              sourcePolicyDocumentId: doc.id));
      final frozen = await main.into(main.curriculumVersions).insertReturning(
          CurriculumVersionsCompanion.insert(
              academicYearId: year.id,
              status: 'frozen',
              sourcePolicyDocumentId: doc.id));
      final linked = TeacherContentRepository(db, mainDb: main);
      expect((await linked.linkableVersions()).map((v) => v.id), [active.id]);
      final id = await linked.saveLesson(lesson(link: active.id));
      expect((await linked.read(id))!.lesson.linkedCurriculumVersionId, active.id);
      expect(() => linked.saveLesson(lesson(link: frozen.id)),
          throwsA(isA<TeacherContentException>()));
      // Linking changed nothing in the curriculum.
      expect((await main.select(main.curriculumVersions).get()).length, 2);
    });
  });

  group('deleting and isolation', () {
    test('delete removes the lesson with all children', () async {
      final id = await repo.saveLesson(lesson(
          nodes: const [NodeDraft(key: 'n', name: 'ن')]));
      await repo.deleteLesson(id);
      expect(await db.select(db.teacherLessons).get(), isEmpty);
      expect(await db.select(db.teacherLessonPages).get(), isEmpty);
      expect(await db.select(db.teacherLessonNodes).get(), isEmpty);
    });

    test('teacher content never touches the student database', () async {
      final main = createInMemoryTestDatabase();
      addTearDown(main.close);
      final r = TeacherContentRepository(db, mainDb: main);
      await r.saveLesson(lesson());
      for (final t in main.allTables) {
        expect(await main.select(t).get(), isEmpty,
            reason: '${t.actualTableName} must stay empty');
      }
    });

    test('wipeAll (reset) clears every teacher table', () async {
      await repo.saveLesson(lesson());
      await db.wipeAll();
      for (final t in db.allTables) {
        expect(await db.select(t).get(), isEmpty);
      }
    });
  });
}
