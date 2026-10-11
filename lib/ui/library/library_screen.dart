import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/teacher_content_domain.dart';
import '../../repositories/teacher_content_repository.dart';
import '../../services/lesson_remote_service.dart';
import '../../services/teacher_session.dart';
import '../state/app_state.dart';
import '../teacher/teacher_widgets.dart';
import '../widgets/async_section.dart';
import 'import_screen.dart';
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

  // Online sync (the student's level path, kept on this device).
  static const _levelKey = 'student_lesson_path';
  final KeyValueStore _prefs = SharedPrefsKeyValueStore();
  int? _myPath;
  bool _syncing = false;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    _loadPath();
  }

  Future<void> _loadPath() async {
    final raw = await _prefs.getString(_levelKey);
    final v = int.tryParse(raw ?? '');
    if (!mounted) return;
    setState(() => _myPath = isValidInternalLevel(v) ? v : null);
    if (_myPath != null && context.read<AppState>().lessonRemote.configured) {
      _sync(silent: true);
    }
  }

  Future<void> _choosePath(int level) async {
    await _prefs.setString(_levelKey, '$level');
    if (!mounted) return;
    setState(() => _myPath = level);
    _sync();
  }

  Future<void> _sync({bool silent = false}) async {
    final state = context.read<AppState>();
    final level = _myPath;
    if (level == null || _syncing) return;
    if (!state.lessonRemote.configured) {
      if (!silent) {
        setState(() => _syncMessage =
            'التحديث عبر الإنترنت غير مفعّل بعد. يمكنك استيراد ملف دروس يدويًا.');
      }
      return;
    }
    setState(() {
      _syncing = true;
      if (!silent) _syncMessage = null;
    });
    try {
      final report = await LessonSyncService(
              state.lessonRemote, state.teacherRepository)
          .syncLevel(level);
      if (!mounted) return;
      setState(() {
        _syncMessage = report.errors.isEmpty
            ? 'اكتمل التحديث: ${report.summary}'
            : 'اكتمل جزئيًا: ${report.summary}';
      });
    } on RemoteException catch (e) {
      // Offline or server problem: the lessons already on the device stay.
      if (mounted && !silent) setState(() => _syncMessage = e.message);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

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
    return MqPage(
      title: 'مكتبة الدروس',
      actions: [
        MqIconButton(
            icon: Icons.storage_outlined,
            label: 'إدارة المحتوى المستورد',
            onTap: _openManage),
        MqIconButton(
            icon: Icons.download_outlined,
            label: 'استيراد ملف دروس',
            onTap: _openImport),
      ],
      children: [
            MqCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('مسار دروسي', style: MqType.h3.copyWith(color: context.mq.ink)),
                  const SizedBox(height: 4),
                  Text(
                      'اختر مستواك فتصلك دروس أساتذتك لهذا المستوى. بعد التحديث '
                      'تُحفظ الدروس وصورها على جهازك وتُفتح دون إنترنت.',
                      style: MqType.caption.copyWith(color: context.mq.ink2)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final lv in kInternalLevels)
                        ChoiceChip(
                          label: Text(internalLevelLabel(lv)),
                          selected: _myPath == lv,
                          onSelected: (_) => _choosePath(lv),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MqButton(
                    label: _syncing ? 'جارٍ التحديث…' : 'حدّث الدروس من الإنترنت',
                    icon: Icons.sync,
                    block: true,
                    onPressed: (_syncing || _myPath == null) ? null : _sync,
                  ),
                  if (_syncMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(_syncMessage!,
                        style: MqType.small.copyWith(color: context.mq.ink)),
                  ],
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
                  'لا دروس مستوردة بعد. اطلب من أستاذك ملف الدروس ثم اضغط «استيراد ملف دروس».',
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
              'تظهر لك كل الدروس التي استوردتها. خيارات المستوى أعلاه للتصفية فقط '
              'وليست قيدًا على ما يمكنك فتحه.',
              icon: Icons.help_outline,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openImport,
              icon: const Icon(Icons.download),
              label: const Text('استيراد ملف دروس من أستاذ'),
            ),
      ],
    );
  }
}
