import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/teacher_content_domain.dart';
import '../../repositories/teacher_content_repository.dart';
import '../../services/lesson_auto_sync.dart';
import '../../services/teacher_session.dart';
import '../state/app_state.dart';
import '../teacher/teacher_widgets.dart';
import '../widgets/async_section.dart';
import 'lesson_viewer_screen.dart';
import 'manage_imported_screen.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/tokens.dart';

/// L01 · مكتبة الدروس (student side): teacher lessons the student imported.
///
/// Lessons arrive from the shared storage for the level path the student
/// picks (1/2/3), or by manual file import as a backup.
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

  // The student's school year (kept on this device). New lessons arrive by
  // themselves (see LessonAutoSync); there is no update button.
  final KeyValueStore _prefs = SharedPrefsKeyValueStore();
  int? _myPath;

  @override
  void initState() {
    super.initState();
    _loadPath();
  }

  Future<void> _loadPath() async {
    final raw = await _prefs.getString(kStudentLessonLevelKey);
    final v = int.tryParse(raw ?? '');
    if (!mounted) return;
    setState(() => _myPath = isValidInternalLevel(v) ? v : null);
    context.read<AppState>().autoSync.trigger();
  }

  Future<void> _choosePath(int level) async {
    await _prefs.setString(kStudentLessonLevelKey, '$level');
    if (!mounted) return;
    setState(() => _myPath = level);
    context.read<AppState>().autoSync.trigger(force: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
    return ListenableBuilder(
      listenable: context.read<AppState>().autoSync.revisionListenable,
      builder: (context, _) => _buildPage(context, repo),
    );
  }

  Widget _buildPage(BuildContext context, TeacherContentRepository repo) {
    return MqPage(
      title: 'دروس الأستاذ(ة)',
      caption: 'تصلك تلقائيًا',
      actions: [
        MqIconButton(
            icon: Icons.storage_outlined,
            label: 'دروسي على هذا الجهاز',
            onTap: _openManage),
      ],
      children: [
            MqCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('في أي سنة أنت؟',
                      style: MqType.h2.copyWith(color: context.mq.ink)),
                  const SizedBox(height: 4),
                  Text(
                      'اختر سنتك الدراسية فتصلك دروس أساتذتك لها تلقائيًا. '
                      'تُحفظ الدروس وصورها على جهازك وتُفتح دون إنترنت.',
                      style: MqType.small.copyWith(color: context.mq.ink2)),
                  const SizedBox(height: 12),
                  for (final lv in kInternalLevels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LevelChoice(
                        label: internalLevelLabel(lv),
                        selected: _myPath == lv,
                        onTap: () => _choosePath(lv),
                      ),
                    ),
                  if (_myPath == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('اضغط على سنتك للبدء.',
                          style: MqType.small.copyWith(color: context.mq.accentInk)),
                    ),
                  _SyncStatus(sync: context.read<AppState>().autoSync, hasLevel: _myPath != null),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
            Text('اعرض الدروس المحفوظة عندي:',
                style: MqType.small.copyWith(color: context.mq.ink2)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('كل دروسي'),
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
                  'لا دروس عندك بعد. اختر سنتك الدراسية وستصلك دروس أساتذتك تلقائيًا.',
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
                                  trailing: Icon(Icons.chevron_left,
                                      color: context.mq.ink2),
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
              'تظهر لك كل دروسك المحفوظة على الجهاز. خيارات السنة للعرض فقط '
              'وليست قيدًا على ما يمكنك فتحه. دروس الأساتذة غير رسمية.',
              icon: Icons.help_outline,
            ),
      ],
    );
  }
}

/// A large, clear choice for the student's school year.
class _LevelChoice extends StatelessWidget {
  const _LevelChoice(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? mq.brandSoft : mq.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? mq.brand : mq.line, width: selected ? 2.5 : 1),
          ),
          child: Row(
            children: [
              Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 28, color: selected ? mq.brand : mq.ink3),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: selected ? mq.brandDeep : mq.ink)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Calm one-line status of the automatic update. It only speaks when there is
/// something worth saying: new lessons arrived, no connection, or a problem.
class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.sync, required this.hasLevel});
  final LessonAutoSync sync;
  final bool hasLevel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final mq = context.mq;
        String text;
        Color color = mq.ink2;
        IconData icon = Icons.sync;
        if (!hasLevel) {
          text = 'بعد اختيار سنتك تصلك الدروس تلقائيًا، دون أي زر.';
          icon = Icons.info_outline;
        } else if (sync.syncing) {
          text = 'نبحث عن دروس جديدة…';
        } else if (sync.problem != null) {
          text = sync.problem!;
          color = mq.overdue;
          icon = Icons.error_outline;
        } else if (sync.offline) {
          text = 'لا يوجد اتصال الآن. دروسك المحفوظة تُفتح عادة، '
              'وسنكمل التحديث تلقائيًا عند عودة الإنترنت.';
          icon = Icons.cloud_off_outlined;
        } else if (sync.notice != null) {
          text = sync.notice!;
          color = mq.ok;
          icon = Icons.check_circle_outline;
        } else {
          text = 'الدروس الجديدة تصلك تلقائيًا عند فتح التطبيق.';
          icon = Icons.check_circle_outline;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: MqType.small.copyWith(color: color)),
            ),
          ],
        );
      },
    );
  }
}
