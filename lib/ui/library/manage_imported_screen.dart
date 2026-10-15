import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/teacher_content_domain.dart';
import '../../repositories/teacher_content_repository.dart';
import '../state/app_state.dart';
import '../teacher/teacher_widgets.dart';
import '../widgets/async_section.dart';
import '../design/tokens.dart';

/// L05 · إدارة المحتوى المستورد: size used, delete. Deleting removes
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
      message: 'سيُحذف «${item.lesson.title}» من جهازك. يمكنك إضافته مرة '
          'أخرى بتحديث الدروس من الإنترنت. مهامك وإتقانك وذاكرتك لا تتأثر.',
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

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().teacherRepository;
    return Scaffold(
      appBar: AppBar(title: const Text('دروسي على هذا الجهاز')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AsyncSection<List<LessonListItem>>(
              future: repo.listImported,
              isEmpty: (d) => d.isEmpty,
              emptyMessage: 'لا دروس محفوظة على جهازك.',
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
                            'ما زال في جهازك متّسع.'),
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
                                    'النسخة ${i.lesson.versionNumber} · '
                                    '${formatBytes(i.bytes)}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                        onPressed: () => _delete(i),
                                        child: Text('احذف',
                                            style: TextStyle(
                                                color: context.mq.overdue))),
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
                'حذف درس يزيل محتواه من جهازك فقط. مهامك وإتقانك وذاكرتك لا تتأثر.'),
          ],
        ),
      ),
    );
  }
}
