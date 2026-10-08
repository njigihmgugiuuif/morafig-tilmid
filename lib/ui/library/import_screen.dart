import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../domain/teacher_content_domain.dart';
import '../../platform/device_files.dart';
import '../../repositories/teacher_content_repository.dart';
import '../../services/teacher_package_service.dart';
import '../state/app_state.dart';
import '../teacher/teacher_widgets.dart';
import '../theme/app_theme.dart';

/// L02 · استيراد حزمة. Reads a teacher package from a file (web) or from the
/// clipboard, SHOWS what it would do (new / duplicate / newer version / older
/// version / conflict / corrupt) and writes only after the student confirms.
/// It adds lesson content only: tasks, mastery, memory and plans are never
/// touched.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _text;
  PackagePreview? _preview;
  bool _busy = false;

  TeacherPackageService _service() => TeacherPackageService(context.read<AppState>().teacherRepository);

  Future<void> _inspect(String text) async {
    final preview = await _service().inspect(text);
    if (!mounted) return;
    setState(() {
      _text = text;
      _preview = preview;
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showSnack(context, 'تعذّرت العملية: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFile() => _guard(() async {
        if (!deviceFilesAvailable) {
          showSnack(context,
              'اختيار الملفات غير متاح هنا. استعمل «الصق من الحافظة».');
          return;
        }
        final files = await pickAnyFiles(accept: '.json,application/json');
        if (files.isEmpty) return;
        final String text;
        try {
          text = utf8.decode(files.first.bytes);
        } on FormatException {
          if (!mounted) return;
          setState(() {
            _text = null;
            _preview = const PackagePreview(
                kind: PackageKind.corrupt,
                message: 'تعذّرت قراءة الملف. بياناتك لم تُمَس.');
          });
          return;
        }
        await _inspect(text);
      });

  Future<void> _paste() => _guard(() async {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text ?? '';
        if (text.trim().isEmpty) {
          if (mounted) showSnack(context, 'الحافظة فارغة.');
          return;
        }
        await _inspect(text);
      });

  Future<void> _confirm() => _guard(() async {
        final text = _text;
        if (text == null) return;
        final result = await _service().importPackage(text);
        if (!mounted) return;
        if (result.written) {
          showSnack(
              context,
              result.preview.kind == PackageKind.newerVersion
                  ? 'حُدّث الدرس.'
                  : 'أُضيف الدرس إلى مكتبتك.');
          Navigator.of(context).pop(true);
        } else {
          setState(() => _preview = result.preview);
        }
      });

  Color _tone(PackageKind k) {
    switch (k) {
      case PackageKind.fresh:
      case PackageKind.newerVersion:
        return const Color(0xFFE3EEF2);
      case PackageKind.duplicate:
      case PackageKind.olderVersion:
        return const Color(0xFFFFF1D6);
      case PackageKind.sameVersionConflict:
      case PackageKind.corrupt:
      case PackageKind.unsupported:
        return const Color(0xFFFBE3E0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final c = preview?.content;
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد حزمة')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('اختر ملف حزمة'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _paste,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('الصق من الحافظة'),
                ),
              ),
            ]),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (preview != null) ...[
              const SizedBox(height: 12),
              if (c != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const TeacherBadge(),
                          const SizedBox(width: 8),
                          Chip(label: Text('الإصدار ${c.versionNumber}')),
                        ]),
                        const SizedBox(height: 6),
                        Text(c.title,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                        Text(
                            '${c.subjectName} · ${internalLevelLabel(c.internalLevel)} · '
                            '${c.pages.length} صفحات · ${formatBytes(c.totalBytes)}',
                            style: const TextStyle(fontSize: 12.5)),
                        Text('المرسل: ${c.teacherName} (تسمية غير موثّقة)',
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _tone(preview.kind),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(preview.message),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (!_busy && preview.canImport) ? _confirm : null,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: Text(preview.kind == PackageKind.newerVersion
                    ? 'حدّث الدرس'
                    : 'أضف إلى مكتبتي'),
              ),
            ],
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('قبل أن تضيف',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6),
                    Text('• يضيف محتوى فقط ولا يمسّ مهامك أو إتقانك أو ذاكرتك.'),
                    Text('• لا تُضاف الحزمة مرتين: البصمة نفسها تُرفض كمكررة.'),
                    Text('• المحتوى غير رسمي: لا يغيّر المنهج ولا المعاملات.'),
                    Text('• البصمة تكشف التلف وليست إثباتًا لهوية المرسل.'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );
  }
}
