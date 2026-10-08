import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../platform/device_files.dart';
import '../../repositories/teacher_content_repository.dart';
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
            ? 'صُدّرت الحزمة: ${out.fileName}'
            : 'نُسخت الحزمة إلى الحافظة. الصقها في ملف أو أرسلها للتلميذ.');
  } catch (e) {
    if (!context.mounted) return;
    showRefusal(context, e);
  }
}
