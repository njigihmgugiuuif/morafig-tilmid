import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../domain/enums.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/exam_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import '../widgets/debounced_button.dart';

class ExamsScreen extends StatelessWidget {
  const ExamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppState>().db;
    final repo = ExamRepository(db);

    return Scaffold(
      appBar: AppBar(title: const Text('الامتحانات والاستحقاقات')),
      body: AsyncSection<List<Exam>>(
        future: () => repo.readUpcoming(now: DateTime.now().toUtc()),
        isEmpty: (d) => d.isEmpty,
        emptyIcon: Icons.event_note,
        emptyMessage: 'لا امتحانات مسجّلة. اضغط + لإضافة امتحان.',
        builder: (context, List<Exam> exams) => ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: exams.length,
          itemBuilder: (context, i) {
            final e = exams[i];
            final days = e.examDate
                .difference(DateTime.now().toUtc())
                .inDays;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: days <= 3
                      ? AppColors.danger.withOpacity(0.15)
                      : AppColors.primary.withOpacity(0.1),
                  child: Text('$days',
                      style: TextStyle(
                          fontSize: 12,
                          color: days <= 3
                              ? AppColors.danger
                              : AppColors.primary)),
                ),
                title: FutureBuilder<String>(
                  future: ContentRepository(db).subjectNameForNode(e.subjectId),
                  builder: (context, snap) => Text(_typeLabel(e.examType)),
                ),
                subtitle: Text(
                  '${e.examDate.year}/${e.examDate.month}/${e.examDate.day}'
                  '${e.officialWeight != null ? " • الوزن: ${e.officialWeight}" : ""}',
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('امتحان جديد'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => const _AddExamSheet(),
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'bac':
        return 'بكالوريا';
      case 'summative':
        return 'فرض/اختبار فصلي';
      default:
        return 'تقييم مستمر';
    }
  }
}

class _AddExamSheet extends StatefulWidget {
  const _AddExamSheet();
  @override
  State<_AddExamSheet> createState() => _AddExamSheetState();
}

class _AddExamSheetState extends State<_AddExamSheet> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 7));
  String _type = 'summative';

  @override
  void dispose() {
    _subjectController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final db = context.read<AppState>().db;
    final content = ContentRepository(db);
    final level = await content.getOrCreateDefaultLevel();
    final subject = await content.getOrCreateSubject(
      educationLevelId: level.id,
      name: _subjectController.text,
    );
    await ExamRepository(db).insert(
      subjectId: subject.id,
      examDate: _date,
      examType: ExamType.values.byName(_type),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('امتحان جديد',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _subjectController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'المادة'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'أدخل اسم المادة' : null,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('التاريخ'),
              subtitle: Text('${_date.year}/${_date.month}/${_date.day}'),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'النوع'),
              items: const [
                DropdownMenuItem(value: 'summative', child: Text('فرض/اختبار فصلي')),
                DropdownMenuItem(value: 'formative', child: Text('تقييم مستمر')),
                DropdownMenuItem(value: 'bac', child: Text('بكالوريا')),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'summative'),
            ),
            const SizedBox(height: 16),
            DebouncedButton(label: 'إضافة', onPressed: _submit),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
