import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/teacher_content_domain.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/task_repository.dart';
import '../../repositories/teacher_content_repository.dart';
import '../../services/intelligence_service.dart';
import '../state/app_state.dart';
import '../teacher/teacher_widgets.dart';
import '../theme/app_theme.dart';
import 'node_detail_screen.dart';

/// L03 · عارض الدرس. Shows the teacher's page images (zoomable), the
/// teacher's notes and the lesson's nodes. Back returns to wherever the
/// lesson was opened from (library) — it never jumps to the root.
class LessonViewerScreen extends StatefulWidget {
  const LessonViewerScreen({super.key, required this.lessonId});
  final String lessonId;

  @override
  State<LessonViewerScreen> createState() => _LessonViewerScreenState();
}

class _LessonViewerScreenState extends State<LessonViewerScreen> {
  late final Future<LessonAggregate?> _future;
  final _pager = PageController();
  int _current = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().teacherRepository
        .read(widget.lessonId);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// Adds a task for this lesson through the SAME path the student's own
  /// «مهمة جديدة» uses (a subject + a node + a task). The link between the
  /// teacher's subject name and the student's subjects is the open point
  /// O-17: here the lesson's subject name is simply used as typed.
  Future<void> _addTask(LessonAggregate agg) async {
    if (_busy) return;
    final minutes = TextEditingController(text: '30');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('أضف مهمة من هذا الدرس'),
        content: TextField(
          controller: minutes,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'المدة التقديرية (دقائق)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('أضف')),
        ],
      ),
    );
    final value = int.tryParse(minutes.text.trim());
    minutes.dispose();
    if (ok != true || !mounted) return;
    if (value == null || value <= 0) {
      showSnack(context, 'أدخل مدة صحيحة بالدقائق.');
      return;
    }
    setState(() => _busy = true);
    try {
      final db = context.read<AppState>().db;
      final content = ContentRepository(db);
      final level = await content.getOrCreateDefaultLevel();
      final node = await content.quickCreateNode(
        educationLevelId: level.id,
        subjectName: agg.lesson.subjectName,
        nodeName: agg.lesson.title,
      );
      await TaskRepository(db).createTask(
        knowledgeNodeId: node.id,
        estimatedDurationMinutes: value,
        isSplittable: false,
      );
      await IntelligenceService(db).processPendingEvents();
      if (mounted) showSnack(context, 'أُضيفت المهمة إلى مهامك.');
    } catch (e) {
      if (mounted) showSnack(context, 'تعذّرت إضافة المهمة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LessonAggregate?>(
      future: _future,
      builder: (context, snap) {
        final agg = snap.data;
        return Scaffold(
          appBar: AppBar(title: Text(agg?.lesson.title ?? 'الدرس')),
          body: SafeArea(
            child: snap.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : snap.hasError
                    ? Center(child: Text('تعذّر فتح الدرس: ${snap.error}'))
                    : agg == null
                        ? const Center(
                            child: Text('هذا الدرس لم يعد موجودًا.'))
                        : _content(agg),
          ),
        );
      },
    );
  }

  Widget _content(LessonAggregate agg) {
    final l = agg.lesson;
    final notes = (l.notes ?? '').trim();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const TeacherBadge(),
            Chip(label: Text(internalLevelLabel(l.internalLevel))),
            Text(
                '${l.subjectName} · القسم: '
                '${(l.sectionLabel ?? '').trim().isEmpty ? 'غير محدد' : l.sectionLabel} · '
                '${l.teacherName}',
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        if (agg.pages.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('لا صفحات في هذا الدرس.')),
          )
        else ...[
          Text('الصفحة ${_current + 1} / ${agg.pages.length}',
              style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 4),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: PageView.builder(
              controller: _pager,
              itemCount: agg.pages.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) => Container(
                decoration: BoxDecoration(
                    color: const Color(0xFFE9EEF0),
                    borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: PageImage(
                      bytes: agg.pages[i].bytes,
                      quarterTurns: agg.pages[i].quarterTurns),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: agg.pages.length,
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => _pager.animateToPage(i,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut),
                child: Container(
                  width: 44,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: i == _current
                            ? AppColors.primary
                            : Colors.transparent,
                        width: 2),
                    color: const Color(0xFFE9EEF0),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: RotatedBox(
                    quarterTurns: agg.pages[i].quarterTurns,
                    child: Image.memory(agg.pages[i].bytes,
                        fit: BoxFit.cover,
                        cacheWidth: 160,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ملاحظات الأستاذ',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(notes),
                ],
              ),
            ),
          ),
        ],
        if (agg.nodes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final n in agg.nodes)
                ActionChip(
                  label: Text(n.name),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => NodeDetailScreen(
                          lessonId: agg.lesson.id, nodeId: n.id),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (agg.attachments.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('المرفقات',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final a in agg.attachments)
                    Text('• ${a.name} (${formatBytes(a.byteSize)})',
                        style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('عرض المرفقات غير مدعوم بعد في هذه النسخة.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : () => _addTask(agg),
          icon: const Icon(Icons.add),
          label: const Text('أضف مهمة من هذا الدرس'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }
}
