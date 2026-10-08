import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/teacher_content_database.dart' show TeacherLessonNode;
import '../../repositories/teacher_content_repository.dart';
import '../state/app_state.dart';
import '../teacher/teacher_widgets.dart';
import '../theme/app_theme.dart';

/// L04 · تفاصيل العقدة (a node typed by the teacher inside a lesson).
///
/// What is shown is real: the node, its page range with the page images, and
/// the node it requires inside the same lesson. What is NOT shown, honestly:
/// mastery, next review and error patterns. Those engines work on the
/// student's own knowledge nodes, and a teacher node is not linked to one
/// (the subject mapping is the open point O-17), so no number is invented.
class NodeDetailScreen extends StatelessWidget {
  const NodeDetailScreen(
      {super.key, required this.lessonId, required this.nodeId});
  final String lessonId;
  final String nodeId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().teacherRepository;
    return FutureBuilder<LessonAggregate?>(
      future: repo.read(lessonId),
      builder: (context, snap) {
        final agg = snap.data;
        final matches = agg?.nodes.where((n) => n.id == nodeId).toList() ?? [];
        final node = matches.isEmpty ? null : matches.first;
        return Scaffold(
          appBar: AppBar(title: Text(node?.name ?? 'العقدة')),
          body: SafeArea(
            child: snap.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : (agg == null || node == null)
                    ? const Center(child: Text('هذه العقدة لم تعد موجودة.'))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Align(
                              alignment: Alignment.centerRight,
                              child: TeacherBadge()),
                          const SizedBox(height: 8),
                          Text(agg.lesson.subjectName,
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                          Text(agg.lesson.title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('المتطلب السابق (في هذا الدرس)',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(_requiresName(agg, node) ??
                                      'لا متطلب سابق.'),
                                ],
                              ),
                            ),
                          ),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('موارد الدرس',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  if (node.pageFrom == null ||
                                      node.pageTo == null)
                                    const Text('لم يحدّد الأستاذ صفحات لهذه العقدة.')
                                  else ...[
                                    Text(
                                        'الصفحات ${node.pageFrom}–${node.pageTo}'),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: 140,
                                      child: ListView(
                                        scrollDirection: Axis.horizontal,
                                        children: [
                                          for (var p = node.pageFrom!;
                                              p <= node.pageTo! &&
                                                  p <= agg.pages.length;
                                              p++)
                                            Container(
                                              width: 100,
                                              margin: const EdgeInsets.only(
                                                  left: 8),
                                              decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFE9EEF0),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
                                              clipBehavior: Clip.antiAlias,
                                              child: PageImage(
                                                bytes:
                                                    agg.pages[p - 1].bytes,
                                                quarterTurns: agg
                                                    .pages[p - 1].quarterTurns,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const InfoBox(
                            'الإتقان والمراجعة القادمة والأخطاء لا تظهر هنا: '
                            'عقدة الأستاذ غير مربوطة بعقد مادتك، وربط مواد '
                            'الأستاذ بمواد التلميذ قرار مفتوح (O-17). '
                            'لا نعرض أرقامًا غير حقيقية.',
                            icon: Icons.info_outline,
                          ),
                        ],
                      ),
          ),
        );
      },
    );
  }

  static String? _requiresName(LessonAggregate agg, TeacherLessonNode node) {
    final r = node.requiresNodeId;
    if (r == null) return null;
    final m = agg.nodes.where((n) => n.id == r).toList();
    return m.isEmpty ? null : m.first.name;
  }
}
