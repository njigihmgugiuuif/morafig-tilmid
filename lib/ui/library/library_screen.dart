import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/teacher_content_domain.dart';
import '../../repositories/teacher_content_repository.dart';
import '../state/app_state.dart';
import '../teacher/teacher_widgets.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import 'import_screen.dart';
import 'lesson_viewer_screen.dart';
import 'manage_imported_screen.dart';

/// L01 · مكتبة الدروس (student side): teacher lessons the student imported.
///
/// ACCESS RULE (open point O-18): nothing in the approved rules says which
/// imported lessons should be shown to which student by level/section/track,
/// and none is invented here. Every imported lesson is shown; the level chips
/// are a manual FILTER chosen by the student, never an access restriction.
/// Every lesson carries «أستاذ · غير رسمي».
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  int? _level;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openImport() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ImportScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openManage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ManageImportedScreen()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().teacherRepository;
    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتبة الدروس'),
        actions: [
          IconButton(
              tooltip: 'إدارة المحتوى المستورد',
              icon: const Icon(Icons.storage_outlined),
              onPressed: _openManage),
          IconButton(
              tooltip: 'استيراد حزمة',
              icon: const Icon(Icons.download_outlined),
              onPressed: _openImport),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _search,
              textAlign: TextAlign.right,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'ابحث في الدروس',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('كل ما استوردته'),
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
            AsyncSection<List<LessonListItem>>(
              future: () =>
                  repo.listImported(level: _level, query: _search.text),
              isEmpty: (d) => d.isEmpty,
              emptyMessage:
                  'لا دروس مستوردة بعد. اطلب من أستاذك حزمة درس ثم اضغط «استيراد حزمة».',
              emptyIcon: Icons.menu_book_outlined,
              builder: (context, items) {
                final bySubject = <String, List<LessonListItem>>{};
                for (final i in items) {
                  bySubject.putIfAbsent(i.lesson.subjectName, () => []).add(i);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in bySubject.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(e.key,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            children: [
                              for (final i in e.value)
                                LessonRow(
                                  item: i,
                                  showStatus: false,
                                  showBadge: true,
                                  trailing: const Icon(Icons.chevron_left,
                                      color: AppColors.textSecondary),
                                  onTap: () async {
                                    await Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) => LessonViewerScreen(
                                            lessonId: i.lesson.id),
                                      ),
                                    );
                                    if (mounted) setState(() {});
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            const InfoBox(
              'أي دروس تظهر لي حسب مستواي؟ قاعدة الوصول غير محسومة (O-18): '
              'تظهر كل الدروس المستوردة، والمستوى مجرد تصفية تختارها أنت.',
              icon: Icons.help_outline,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openImport,
              icon: const Icon(Icons.download),
              label: const Text('استيراد حزمة من أستاذ'),
            ),
          ],
        ),
      ),
    );
  }
}
