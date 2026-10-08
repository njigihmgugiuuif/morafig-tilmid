import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/teacher_content_domain.dart';
import '../../repositories/teacher_content_repository.dart';
import '../state/app_state.dart';
import '../teacher/teacher_widgets.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import 'import_screen.dart';

/// L05 · إدارة المحتوى المستورد: size used, update, delete. Deleting removes
/// the lesson's content only; tasks, mastery and memory are not touched. The
/// storage ceiling is an open decision (O-3): none is enforced.
class ManageImportedScreen extends StatefulWidget {
  const ManageImportedScreen({super.key});

  @override
  State<ManageImportedScreen> createState() => _ManageImportedScreenState();
}

class _ManageImportedScreenState extends State<ManageImportedScreen> {
  Future<void> _delete(LessonListItem item) async {
    final ok = await confirmDialog(
      context,
      title: 'تأكيد الحذف',
      message: 'سيُحذف «${item.lesson.title}» من جهازك. يمكنك استيراده مرة '
          'أخرى متى توفّرت الحزمة. مهامك وإتقانك وذاكرتك لا تتأثر.',
      confirmLabel: 'احذف',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<AppState>().teacherRepository
          .deleteLesson(item.lesson.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showRefusal(context, e);
    }
  }

  Future<void> _update() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ImportScreen()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().teacherRepository;
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المحتوى المستورد')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AsyncSection<List<LessonListItem>>(
              future: repo.listImported,
              isEmpty: (d) => d.isEmpty,
              emptyMessage: 'لا محتوى مستوردًا.',
              emptyIcon: Icons.storage_outlined,
              builder: (context, items) {
                final used = items.fold<int>(0, (s, i) => s + i.bytes);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.storage_outlined),
                        title: Text('المساحة المستعملة ${formatBytes(used)}'),
                        subtitle: const Text(
                            'الحد الأقصى غير محدد بعد. قرار مفتوح (O-3).'),
                      ),
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: [
                            for (final i in items)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(i.lesson.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                    'الإصدار ${i.lesson.versionNumber} · '
                                    '${formatBytes(i.bytes)}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                        onPressed: _update,
                                        child: const Text('حدّث')),
                                    TextButton(
                                        onPressed: () => _delete(i),
                                        child: const Text('احذف',
                                            style: TextStyle(
                                                color: AppColors.danger))),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const InfoBox(
                'حذف حزمة يزيل محتواها فقط. مهامك وإتقانك وذاكرتك لا تتأثر.'),
          ],
        ),
      ),
    );
  }
}
