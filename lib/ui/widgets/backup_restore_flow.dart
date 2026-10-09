import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../export_import/export_import_service.dart';
import '../state/app_state.dart';

/// Restores a backup whose text is on the clipboard, replacing everything on
/// this device. Same rules and same service as the restore in Settings
/// (ExportImportService.restoreReplacingAll — all or nothing); this copy lets
/// the first screen offer «لدي نسخة احتياطية» (D-1 S01) before any student
/// exists. Returns true when the backup was restored and the student set.
///
/// The Settings screen keeps its own copy of this flow untouched; the two
/// can be merged when Settings is revisited.
Future<bool> restoreBackupFromClipboard(
  BuildContext context,
  AppState appState,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text?.trim() ?? '';
  if (text.isEmpty) {
    snack('الحافظة فارغة. انسخ نص النسخة الاحتياطية أولًا.');
    return false;
  }

  // The backup must hold exactly one student; its id becomes the current
  // student after the restore.
  String? backupStudentId;
  try {
    final parsed = jsonDecode(text);
    final students = (parsed is Map && parsed['tables'] is Map)
        ? (parsed['tables'] as Map)['students']
        : null;
    if (students is List && students.length == 1 && students.first is Map) {
      backupStudentId = (students.first as Map)['id'] as String?;
    }
  } catch (_) {
    backupStudentId = null;
  }
  if (backupStudentId == null) {
    snack('محتوى الحافظة ليس نسخة احتياطية صالحة.');
    return false;
  }

  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('استعادة النسخة الاحتياطية؟'),
      content: const Text(
        'ستُستبدل كل بيانات هذا الجهاز ببيانات النسخة الاحتياطية. إن '
        'فشلت الاستعادة فلن يتغير شيء.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('استعادة'),
        ),
      ],
    ),
  );
  if (ok != true) return false;

  try {
    await ExportImportService(appState.db).restoreReplacingAll(text);
  } on ImportValidationException catch (e) {
    snack('نسخة غير صالحة، لم يتغير شيء: ${e.reason}');
    return false;
  }
  await appState.setStudentId(backupStudentId);
  return true;
}
