import 'package:flutter/material.dart';

import '../../domain/teacher_content_domain.dart';
import '../../repositories/teacher_content_repository.dart';
import '../widgets/async_section.dart';
import 'teacher_actions.dart';
import 'teacher_widgets.dart';

/// دروسي: search + year filter over the teacher's
/// own lessons. The level filter uses the three internal levels only; the
/// «القسم» is shown as information and filters nothing.
class TeacherLessonsTab extends StatefulWidget {
  const TeacherLessonsTab({
    super.key,
    required this.rev,
    required this.onNewLesson,
    required this.onOpenLesson,
    required this.onChanged,
  });

  final int rev;
  final VoidCallback onNewLesson;
  final void Function(String lessonId) onOpenLesson;
  final VoidCallback onChanged;

  @override
  State<TeacherLessonsTab> createState() => _TeacherLessonsTabState();
}

class _TeacherLessonsTabState extends State<TeacherLessonsTab> {
  final _search = TextEditingController();
  int? _level;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _delete(LessonListItem item) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف الدرس',
      message: 'سيُحذف «${item.lesson.title}» بصفحاته ومحاوره من هذا الجهاز. '
          'لا يمس هذا بيانات أي تلميذ.',
      confirmLabel: 'احذف',
    );
    if (!ok || !mounted) return;
    try {
      await teacherRepo(context).deleteLesson(item.lesson.id);
      widget.onChanged();
    } catch (e) {
      if (mounted) showRefusal(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = teacherRepo(context);
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('أنشئ درسًا وأرسله لتلاميذك',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                        canSendToStudents(context)
                            ? 'اختر السنة، اكتب بيانات الدرس، اختر صوره من هاتفك، '
                                'ثم أرسله. يصل إلى التلاميذ تلقائيًا ونتحقق من وصول كل صورة.'
                            : 'للإرسال ادخل من رابط لوحة الأستاذ بكلمة مرور الأساتذة.',
                        style: const TextStyle(fontSize: 12.5)),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: widget.onNewLesson,
                      icon: const Icon(Icons.add),
                      label: const Text('درس جديد'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52)),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: canSendToStudents(context)
                          ? () async {
                              await publishAllOnline(context);
                              widget.onChanged();
                            }
                          : null,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('أعد إرسال كل دروسي للتلاميذ'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              textAlign: TextAlign.right,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'ابحث في دروسي',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: _level == null,
                  onSelected: (_) => setState(() => _level = null),
                ),
                for (final lv in kInternalLevels)
                  ChoiceChip(
                    label: Text(internalLevelLabel(lv)),
                    selected: _level == lv,
                    onSelected: (_) => setState(() => _level = lv),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AsyncSection<List<LessonListItem>>(
                  future: () => repo.listAuthored(
                      level: _level, query: _search.text),
                  isEmpty: (d) => d.isEmpty,
                  emptyMessage: 'لا دروس بعد. اضغط «درس جديد» لتبدأ.',
                  emptyIcon: Icons.menu_book_outlined,
                  builder: (context, items) => Column(
                    children: [
                      for (final i in items)
                        LessonRow(
                          item: i,
                          onTap: () => widget.onOpenLesson(i.lesson.id),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'خيارات الدرس',
                            onSelected: (v) async {
                              if (v == 'edit') {
                                widget.onOpenLesson(i.lesson.id);
                              } else if (v == 'backup') {
                                await exportLessonPackage(context, i.lesson.id);
                                widget.onChanged();
                              } else if (v == 'publishOnline') {
                                await publishLessonOnline(context, i.lesson.id);
                                widget.onChanged();
                              } else if (v == 'unpublishOnline') {
                                await unpublishLessonOnline(
                                    context, i.lesson.id);
                              } else if (v == 'delete') {
                                await _delete(i);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'edit', child: Text('تعديل')),
                              if (LessonStatus.fromDb(i.lesson.status) ==
                                  LessonStatus.published)
                                const PopupMenuItem(
                                    value: 'backup',
                                    child: Text('احفظ نسخة احتياطية')),
                              if (LessonStatus.fromDb(i.lesson.status) ==
                                  LessonStatus.published)
                                const PopupMenuItem(
                                    value: 'publishOnline',
                                    child: Text('أرسل للتلاميذ')),
                              if (LessonStatus.fromDb(i.lesson.status) ==
                                  LessonStatus.published)
                                const PopupMenuItem(
                                    value: 'unpublishOnline',
                                    child: Text('اسحب من التلاميذ')),
                              const PopupMenuItem(
                                  value: 'delete', child: Text('حذف')),
                            ],
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                LessonStatusChip(
                                    LessonStatus.fromDb(i.lesson.status)),
                                const Icon(Icons.more_horiz, size: 18),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
