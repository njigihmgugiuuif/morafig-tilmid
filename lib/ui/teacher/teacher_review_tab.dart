import 'package:flutter/material.dart';

import '../../domain/teacher_content_domain.dart';
import '../../repositories/teacher_content_repository.dart';
import '../widgets/async_section.dart';
import 'teacher_actions.dart';
import 'teacher_widgets.dart';

/// T04 · المراجعة. TEMPORARY decision recorded as O-2: with no server there
/// is no reviewer other than the teacher, so «قيد المراجعة» is a deliberate
/// pause where the teacher re-reads the lesson and then approves it or sends
/// it back. What "review" means in the final product is NOT decided.
class TeacherReviewTab extends StatefulWidget {
  const TeacherReviewTab({
    super.key,
    required this.rev,
    required this.onOpenLesson,
    required this.onChanged,
  });

  final int rev;
  final void Function(String lessonId) onOpenLesson;
  final VoidCallback onChanged;

  @override
  State<TeacherReviewTab> createState() => _TeacherReviewTabState();
}

class _TeacherReviewTabState extends State<TeacherReviewTab> {
  final Map<String, TextEditingController> _notes = {};

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _move(String id, LessonStatus to, {String? notes}) async {
    final repo = teacherRepo(context);
    try {
      if (notes != null) await repo.setReviewNotes(id, notes);
      await repo.transition(id, to);
      widget.onChanged();
      if (mounted) {
        showSnack(context, 'صارت حالة الدرس «${to.label}».');
      }
    } catch (e) {
      if (mounted) showRefusal(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = teacherRepo(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('مسار كل درس',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: const [
                    LessonStatusChip(LessonStatus.draft),
                    Icon(Icons.arrow_back, size: 16),
                    LessonStatusChip(LessonStatus.inReview),
                    Icon(Icons.arrow_back, size: 16),
                    LessonStatusChip(LessonStatus.published),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                    'الرجوع من «قيد المراجعة» إلى «مسودة» متاح دائمًا قبل النشر.',
                    style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        AsyncSection<List<LessonListItem>>(
          future: () =>
              repo.listAuthored(status: LessonStatus.inReview),
          builder: (context, items) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('قيد المراجعة (${items.length})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('لا دروس قيد المراجعة.'),
                ),
              for (final i in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LessonRow(
                            item: i,
                            onTap: () => widget.onOpenLesson(i.lesson.id)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _notes.putIfAbsent(
                              i.lesson.id,
                              () => TextEditingController(
                                  text: i.lesson.reviewNotes ?? '')),
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات المراجعة',
                            hintText: 'لا ملاحظات بعد.',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _move(
                                    i.lesson.id, LessonStatus.published,
                                    notes: _notes[i.lesson.id]?.text),
                                child: const Text('اعتمد للنشر'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _move(
                                    i.lesson.id, LessonStatus.draft,
                                    notes: _notes[i.lesson.id]?.text),
                                child: const Text('أعده مسودة'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AsyncSection<List<LessonListItem>>(
          future: () async {
            final drafts = await repo.listAuthored(status: LessonStatus.draft);
            final ready = <LessonListItem>[];
            for (final d in drafts) {
              final agg = await repo.read(d.lesson.id);
              if (agg == null) continue;
              final issues = readinessForReview(
                title: agg.lesson.title,
                subjectName: agg.lesson.subjectName,
                internalLevel: agg.lesson.internalLevel,
                teacherName: agg.lesson.teacherName,
                pageCount: agg.pages.length,
                nodes: agg.nodes
                    .map((n) => NodeDraft(
                          key: n.id,
                          name: n.name,
                          pageFrom: n.pageFrom,
                          pageTo: n.pageTo,
                          requiresKey: n.requiresNodeId,
                        ))
                    .toList(),
              );
              if (issues.isEmpty) ready.add(d);
            }
            return ready;
          },
          builder: (context, items) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('جاهزة للإرسال إلى المراجعة (${items.length})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                      'لا مسودات مكتملة. تكتمل المسودة بالعنوان والمادة والمستوى '
                      'واسم الأستاذ وصفحة واحدة على الأقل.'),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      for (final i in items)
                        LessonRow(
                          item: i,
                          showStatus: false,
                          onTap: () => widget.onOpenLesson(i.lesson.id),
                          trailing: OutlinedButton(
                            onPressed: () =>
                                _move(i.lesson.id, LessonStatus.inReview),
                            child: const Text('أرسل'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const InfoBox(
          'من يراجع؟ دون خادم لا يوجد مراجع غيرك. تعريف هذه المرحلة غير '
          'محسوم، قرار مفتوح (O-2).',
          icon: Icons.help_outline,
        ),
      ],
    );
  }
}
