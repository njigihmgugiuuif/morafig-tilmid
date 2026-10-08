import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../export_import/export_import_service.dart';
import '../../repositories/reset_repository.dart';
import '../../repositories/student_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/debounced_button.dart';

/// Settings: edit the student's basic profile, back up / restore all data
/// through the clipboard (fully offline), and an explicit, confirmed
/// "reset all data" action.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  double _sleepHours = 7;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadProfile() async {
    final db = context.read<AppState>().db;
    final student = await StudentRepository(db).readExisting();
    if (!mounted) return;
    setState(() {
      _nameController.text = student?.fullNameOrNickname ?? '';
      _sleepHours =
          ((student?.sleepFloorMinMinutes ?? 420) / 60).clamp(5.0, 10.0).toDouble();
      _loaded = true;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final appState = context.read<AppState>();
    final id = appState.studentId;
    if (id == null) return;
    await StudentRepository(appState.db).updateProfile(
      studentId: id,
      fullNameOrNickname: _nameController.text.trim(),
      sleepFloorMinMinutes: (_sleepHours * 60).round(),
    );
    _snack('تم حفظ التعديلات');
  }

  /// Runs one action at a time; the buttons are disabled meanwhile, so a
  /// double tap can never run an export/restore/reset twice.
  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack('تعذّرت العملية: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final db = context.read<AppState>().db;
    final json = await ExportImportService(db).exportAll();
    await Clipboard.setData(ClipboardData(text: json));
    _snack('تم نسخ النسخة الاحتياطية إلى الحافظة. الصقها في ملاحظة أو '
        'رسالة لنفسك للاحتفاظ بها.');
  }

  Future<void> _restore() async {
    final appState = context.read<AppState>();
    final nav = Navigator.of(context);

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _snack('الحافظة فارغة. انسخ نص النسخة الاحتياطية أولًا.');
      return;
    }

    // The backup must hold exactly one student; its id becomes the
    // current student after the restore.
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
      _snack('محتوى الحافظة ليس نسخة احتياطية صالحة.');
      return;
    }

    if (!mounted) return;
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
    if (ok != true) return;

    try {
      await ExportImportService(appState.db).restoreReplacingAll(text);
    } on ImportValidationException catch (e) {
      _snack('نسخة غير صالحة، لم يتغير شيء: ${e.reason}');
      return;
    }
    await appState.setStudentId(backupStudentId);
    nav.popUntil((route) => route.isFirst);
  }

  Future<void> _reset() async {
    final appState = context.read<AppState>();
    final nav = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ResetConfirmDialog(),
    );
    if (confirmed != true) return;

    await ResetRepository(appState.db).wipeAllData();
    // Teacher lessons live in their own database (DEVIATION-23): "reset all
    // data" removes them too.
    await appState.teacherDb.wipeAll();
    await appState.clearStudent();
    nav.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SectionHeader('الملف الشخصي'),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          labelText: 'الاسم أو اللقب',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'الرجاء إدخال اسمك'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'الحد الأدنى لساعات النوم يوميًا: '
                        '${_sleepHours.round()} ساعات',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Slider(
                        value: _sleepHours,
                        min: 5,
                        max: 10,
                        divisions: 10,
                        label: '${_sleepHours.round()}',
                        onChanged: (v) => setState(() => _sleepHours = v),
                      ),
                      DebouncedButton(
                        label: 'حفظ التعديلات',
                        icon: Icons.save_outlined,
                        onPressed: _saveProfile,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const _SectionHeader('النسخ الاحتياطي (بدون إنترنت)'),
                Text(
                  'التصدير ينسخ كل بياناتك كنص إلى الحافظة. للاستعادة انسخ '
                  'ذلك النص ثم اضغط «استعادة من الحافظة».',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _guard(_export),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('تصدير نسخة احتياطية'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _guard(_restore),
                  icon: const Icon(Icons.restore),
                  label: const Text('استعادة من الحافظة'),
                ),
                const SizedBox(height: 28),
                const _SectionHeader('منطقة الخطر'),
                Text(
                  'إعادة الضبط تحذف ملفك الدراسي وكل المهام والامتحانات '
                  'والتقدم من هذا الجهاز نهائيًا.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _guard(_reset),
                  icon: const Icon(Icons.delete_forever, color: AppColors.danger),
                  label: const Text('إعادة ضبط كل البيانات',
                      style: TextStyle(color: AppColors.danger)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Requires typing the word «حذف» so a reset can never happen by accident.
class _ResetConfirmDialog extends StatefulWidget {
  const _ResetConfirmDialog();

  @override
  State<_ResetConfirmDialog> createState() => _ResetConfirmDialogState();
}

class _ResetConfirmDialogState extends State<_ResetConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _controller.text.trim() == 'حذف';
    return AlertDialog(
      title: const Text('إعادة ضبط كل البيانات؟'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'سيُحذف كل شيء من هذا الجهاز نهائيًا ولا يمكن التراجع. صدّر '
            'نسخة احتياطية أولًا إن أردت الاحتفاظ ببياناتك.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              labelText: 'اكتب كلمة «حذف» للتأكيد',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: canDelete ? () => Navigator.pop(context, true) : null,
          child: Text(
            'حذف نهائي',
            style: TextStyle(color: canDelete ? AppColors.danger : null),
          ),
        ),
      ],
    );
  }
}
