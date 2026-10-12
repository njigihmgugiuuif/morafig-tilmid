import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../domain/teacher_content_domain.dart';
import '../../platform/device_files.dart';
import '../../repositories/teacher_content_repository.dart';
import '../../services/lesson_remote_service.dart';
import '../../services/teacher_package_service.dart';
import '../state/app_state.dart';
import 'teacher_widgets.dart';

/// Largest lesson file the app will try to publish (the server accepts a
/// little more; this keeps a clear message on the teacher's side).
const int kMaxPublishBytes = 20 * 1024 * 1024;

/// Actions shared by several teacher screens.

TeacherContentRepository teacherRepo(BuildContext context) =>
    context.read<AppState>().teacherRepository;

/// Exports a published lesson as a package: a file download on the web, the
/// clipboard everywhere else. Nothing is exported unless the lesson is
/// published (the service refuses otherwise and the reason is shown).
Future<void> exportLessonPackage(BuildContext context, String lessonId) async {
  final service = TeacherPackageService(teacherRepo(context));
  try {
    final out = await service.exportLesson(lessonId);
    final bytes = Uint8List.fromList(utf8.encode(out.json));
    var saved = false;
    if (deviceFilesAvailable) {
      saved = await saveBytesAs(out.fileName, bytes, 'application/json');
    }
    if (!saved) {
      await Clipboard.setData(ClipboardData(text: out.json));
    }
    if (!context.mounted) return;
    showSnack(
        context,
        saved
            ? 'صُدّر الملف: ${out.fileName}'
            : 'نُسخ الملف إلى الحافظة. الصقها في ملف أو أرسلها للتلميذ.');
  } catch (e) {
    if (!context.mounted) return;
    showRefusal(context, e);
  }
}

/// Publishes a PUBLISHED lesson to the shared storage so students of its
/// level path receive it in the app. The server checks the teachers'
/// password; nothing is claimed as delivered unless the server answered OK.
Future<void> publishLessonOnline(BuildContext context, String lessonId) async {
  final state = context.read<AppState>();
  final password = state.teacherRemote.password;
  if (!state.lessonRemote.configured || password == null) {
    showSnack(context,
        'النشر للتلاميذ غير مفعّل: ادخل بكلمة مرور الأساتذة بعد تفعيل الخادم.');
    return;
  }
  try {
    final out = await TeacherPackageService(teacherRepo(context))
        .exportLesson(lessonId);
    final bytes = utf8.encode(out.json).length;
    if (bytes > kMaxPublishBytes) {
      if (!context.mounted) return;
      showSnack(
          context,
          'حجم الدرس ${(bytes / 1048576).toStringAsFixed(1)} ميغابايت، '
          'والحد المسموح للنشر ${kMaxPublishBytes ~/ 1048576}. '
          'احذف بعض الصفحات أو أعد التقاطها ثم انشر.');
      return;
    }
    final decoded = jsonDecode(out.json) as Map<String, dynamic>;
    final lesson = decoded['lesson'] as Map<String, dynamic>;
    final level = lesson['internalLevel'] as int;
    final pages = (decoded['pages'] as List).length;
    await state.lessonRemote.publish(
      password: password,
      originLessonId: lesson['originLessonId'] as String,
      versionNumber: lesson['versionNumber'] as int,
      internalLevel: level,
      title: lesson['title'] as String,
      subjectName: lesson['subjectName'] as String,
      teacherName: lesson['teacherName'] as String,
      fingerprint: decoded['fingerprint'] as String,
      packageJson: out.json,
    );
    // The server said OK; now PROVE it by reading the lesson back.
    final check = await state.lessonRemote.verifyPublished(
      originLessonId: lesson['originLessonId'] as String,
      level: level,
      fingerprint: decoded['fingerprint'] as String,
      expectedPages: pages,
    );
    if (!context.mounted) return;
    showSnack(
        context,
        'نُشر الدرس في ${internalLevelLabel(level)} وتحقّقت من وجوده على '
        'الخادم: ${check.pages} صفحة (${check.sizeLabel}).');
  } on RemoteException catch (e) {
    if (context.mounted) showSnack(context, e.message);
  } catch (e) {
    if (context.mounted) showRefusal(context, e);
  }
}

/// Withdraws a lesson from the shared storage (students who already synced
/// keep their local copy; this app never deletes a student's data).
Future<void> unpublishLessonOnline(
    BuildContext context, String lessonId) async {
  final state = context.read<AppState>();
  final password = state.teacherRemote.password;
  if (!state.lessonRemote.configured || password == null) {
    showSnack(context, 'سحب الدرس غير متاح قبل تفعيل الخادم والدخول بكلمة المرور.');
    return;
  }
  try {
    await state.lessonRemote
        .unpublish(password: password, originLessonId: lessonId);
    if (!context.mounted) return;
    showSnack(context, 'سُحب الدرس من قائمة التلاميذ.');
  } on RemoteException catch (e) {
    if (context.mounted) showSnack(context, e.message);
  }
}
