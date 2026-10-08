import 'package:flutter/material.dart';

import '../../domain/teacher_content_domain.dart';
import '../../repositories/teacher_content_repository.dart';
import '../widgets/async_section.dart';
import 'teacher_actions.dart';
import 'teacher_widgets.dart';

/// T02 · لوحتي: real counts from the database and the latest lessons.
class TeacherDashboardTab extends StatelessWidget {
  const TeacherDashboardTab({
    super.key,
    required this.rev,
    required this.onNewLesson,
    required this.onOpenLesson,
    required this.onShowAll,
  });

  final int rev;
  final VoidCallback onNewLesson;
  final void Function(String lessonId) onOpenLesson;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final repo = teacherRepo(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AsyncSection<Map<LessonStatus, int>>(
          future: repo.authoredStatusCounts,
          builder: (context, c) => Row(
            children: [
              _Counter('مسودات', c[LessonStatus.draft] ?? 0, Icons.edit_note),
              const SizedBox(width: 8),
              _Counter('قيد المراجعة', c[LessonStatus.inReview] ?? 0,
                  Icons.schedule),
              const SizedBox(width: 8),
              _Counter(
                  'منشور', c[LessonStatus.published] ?? 0, Icons.check_circle),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onNewLesson,
          icon: const Icon(Icons.add),
          label: const Text('درس جديد'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('آخر دروسي',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    TextButton(onPressed: onShowAll, child: const Text('عرض الكل')),
                  ],
                ),
                AsyncSection<List<LessonListItem>>(
                  future: repo.listAuthored,
                  isEmpty: (d) => d.isEmpty,
                  emptyMessage: 'لم تكتب أي درس بعد. ابدأ بـ «درس جديد».',
                  emptyIcon: Icons.menu_book_outlined,
                  builder: (context, items) => Column(
                    children: [
                      for (final i in items.take(3))
                        LessonRow(item: i, onTap: () => onOpenLesson(i.lesson.id)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const InfoBox(
          'ما تنشره يظهر عند التلميذ بشارة «$kTeacherBadge»، ولا يغيّر المنهج '
          'الرسمي ولا المعاملات.',
          icon: Icons.shield_outlined,
        ),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 6),
              Text('$value',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
