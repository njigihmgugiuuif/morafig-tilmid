import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:student_app/database/teacher_content_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/sha256.dart';
import 'package:student_app/domain/teacher_content_domain.dart';
import 'package:student_app/repositories/teacher_content_repository.dart';
import 'package:student_app/services/lesson_remote_service.dart';
import 'package:student_app/services/teacher_package_service.dart';

/// REAL-SERVER test: talks to the real Supabase project of the app.
///
/// It is skipped unless the environment variable TEACHER_PASSWORD is set (the
/// manual workflow "Real delivery test" sets it from a GitHub secret). The
/// teacher and the student are two independent clients with two separate
/// databases, exactly as on two phones. It publishes a clearly named test
/// lesson, receives it, compares every photo by SHA-256, then withdraws it.
///
/// What it proves: the server, storage and function really carry photos from
/// a teacher client to a student client. What it does NOT prove: anything
/// about a real phone's browser, camera, or service worker.
Uint8List photo(int n, int seed) {
  final b = Uint8List(n);
  var x = seed * 2654435761 % 4294967296;
  for (var i = 0; i < n; i++) {
    x = (x * 1103515245 + 12345) % 2147483648;
    b[i] = (x >> 8) & 0xFF;
  }
  b[0] = 0xFF;
  b[1] = 0xD8;
  b[2] = 0xFF;
  return b;
}

void main() {
  final password = Platform.environment['TEACHER_PASSWORD'] ?? '';
  final skip = password.isEmpty
      ? 'يتطلب المتغيّر TEACHER_PASSWORD (يُشغَّل من workflow «Real delivery test»).'
      : false;

  test('real server: teacher photos reach an independent student client',
      () async {
    final teacherRemote = LessonRemoteService();
    final studentRemote = LessonRemoteService();
    expect(teacherRemote.configured, isTrue,
        reason: 'remote_config.dart فارغ: عنوان Supabase غير مضبوط.');
    expect(await teacherRemote.verifyPassword(password), isTrue,
        reason: 'كلمة المرور في السرّ لا تطابق الخادم.');

    final teacherDb = createInMemoryTeacherDatabase();
    final studentDb = createInMemoryTeacherDatabase();
    final teacherRepo = TeacherContentRepository(teacherDb);
    final studentRepo = TeacherContentRepository(studentDb);
    String? lessonId;
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final sent = [photo(300 * 1024, 1), photo(310 * 1024, 2), photo(290 * 1024, 3)];
      lessonId = await teacherRepo.saveLesson(LessonInput(
        title: 'اختبار آلي $stamp',
        subjectName: 'اختبار',
        internalLevel: 1,
        teacherName: 'اختبار آلي',
        pages: sent.map((b) => PageInput(bytes: b)).toList(),
        nodes: [
          NodeDraft(
              key: 'auto-$stamp', name: 'اختبار', pageFrom: 1, pageTo: 3),
        ],
      ));
      await teacherRepo.transition(lessonId, LessonStatus.inReview);
      await teacherRepo.transition(lessonId, LessonStatus.published);

      final out = await TeacherPackageService(teacherRepo).exportLesson(lessonId);
      final check = await teacherRemote.publishLesson(
          password: password, packageJson: out.json);
      expect(check.pages, 3);

      // A different client (fresh object, fresh database) as the student.
      final report = await LessonSyncService(studentRemote, studentRepo)
          .syncLevel(1);
      expect(report.errors, isEmpty);
      final list = await studentRepo.listImported();
      final mine = list.where((e) => e.lesson.title == 'اختبار آلي $stamp');
      expect(mine, hasLength(1), reason: 'الدرس لم يصل إلى جهاز التلميذ.');
      final agg = await studentRepo.read(mine.single.lesson.id);
      expect(agg!.pages, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(agg.pages[i].bytes.length, sent[i].length);
        expect(Sha256.hex(agg.pages[i].bytes), Sha256.hex(sent[i]),
            reason: 'الصورة ${i + 1} وصلت بمحتوى مختلف.');
      }

      // Second sync: nothing new.
      final again = await LessonSyncService(studentRemote, studentRepo)
          .syncLevel(1);
      expect(again.added, 0);
    } finally {
      if (lessonId != null) {
        try {
          await teacherRemote.unpublish(
              password: password, originLessonId: lessonId);
        } catch (_) {}
        final left = await studentRemote.list(level: 1);
        expect(left.where((e) => e.originLessonId == lessonId), isEmpty,
            reason: 'تعذّر سحب درس الاختبار من الخادم.');
      }
      await teacherDb.close();
      await studentDb.close();
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}
