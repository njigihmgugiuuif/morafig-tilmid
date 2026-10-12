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
            ? 'حُفظت نسخة الدرس: ${out.fileName}'
            : 'نُسخ الدرس. الصقه في ملف أو أرسله للتلميذ.');
  } catch (e) {
    if (!context.mounted) return;
    showRefusal(context, e);
  }
}

/// True when the teacher entered the server password in this visit, so the
/// lessons can be sent to the students.
bool canSendToStudents(BuildContext context) {
  final state = context.read<AppState>();
  return state.lessonRemote.configured && state.teacherRemote.password != null;
}

/// Sends ONE published lesson and proves it arrived by reading it back.
/// Returns the success sentence; every failure throws [RemoteException] with
/// the step that failed.
Future<String> _sendOne(
    AppState state, TeacherContentRepository repo, String lessonId,
    {void Function(String)? onProgress}) async {
  final password = state.teacherRemote.password;
  if (password == null) {
    throw const RemoteException(
        'ادخل أولًا بكلمة مرور الأساتذة ثم أعد المحاولة.');
  }
  final out = await TeacherPackageService(repo).exportLesson(lessonId);
  final decoded = jsonDecode(out.json) as Map<String, dynamic>;
  final level = (decoded['lesson'] as Map<String, dynamic>)['internalLevel'] as int;
  // Photos go one by one, then everything is read back and compared.
  final check = await state.lessonRemote.publishLesson(
    password: password,
    packageJson: out.json,
    onProgress: onProgress,
  );
  return 'وصل إلى تلاميذ ${internalLevelLabel(level)}: '
      '${check.pages} صفحة (${check.sizeLabel}) وتحققنا من كل صورة.';
}

/// Sends a PUBLISHED lesson to the students of its level. Nothing is said to
/// have arrived unless the lesson was read back from the server.
Future<void> publishLessonOnline(BuildContext context, String lessonId) async {
  final state = context.read<AppState>();
  if (!canSendToStudents(context)) {
    showSnack(context,
        'الإرسال للتلاميذ يحتاج الدخول بكلمة مرور الأساتذة من رابط لوحة الأستاذ.');
    return;
  }
  try {
    final msg = await _sendOne(state, teacherRepo(context), lessonId,
        onProgress: (m) {
      if (context.mounted) showSnack(context, m);
    });
    if (!context.mounted) return;
    showSnack(context, msg);
  } on RemoteException catch (e) {
    if (context.mounted) showSnack(context, e.message);
  } catch (e) {
    if (context.mounted) showRefusal(context, e);
  }
}

/// Sends every published lesson of this teacher, one by one, and shows a
/// result line for each (✓ arrived / ✗ why not).
Future<void> publishAllOnline(BuildContext context) async {
  final state = context.read<AppState>();
  final repo = teacherRepo(context);
  if (!canSendToStudents(context)) {
    showSnack(context,
        'الإرسال للتلاميذ يحتاج الدخول بكلمة مرور الأساتذة من رابط لوحة الأستاذ.');
    return;
  }
  final items = await repo.listAuthored(status: LessonStatus.published);
  if (!context.mounted) return;
  if (items.isEmpty) {
    showSnack(context, 'لا دروس «منشورة» لإرسالها. اعتمد درسًا أولًا.');
    return;
  }
  final lines = <String>[];
  var ok = 0;
  for (final i in items) {
    try {
      final msg = await _sendOne(state, repo, i.lesson.id);
      lines.add('✓ ${i.lesson.title}: $msg');
      ok++;
    } on RemoteException catch (e) {
      lines.add('✗ ${i.lesson.title}: ${e.message}');
    } catch (e) {
      lines.add('✗ ${i.lesson.title}: $e');
    }
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('وصل $ok من ${items.length}'),
      content: SingleChildScrollView(child: Text(lines.join('\n\n'))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('حسنًا')),
      ],
    ),
  );
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
