import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/tables/core_tables.dart' show uuidGen;
import '../../domain/teacher_content_domain.dart';
import '../../platform/device_files.dart';
import '../../repositories/teacher_content_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'teacher_actions.dart';
import 'teacher_widgets.dart';

class _PageDraft {
  _PageDraft(this.bytes, {this.turns = 0});
  final Uint8List bytes;
  int turns;
}

class _NodeEdit {
  _NodeEdit({
    required this.key,
    required this.name,
    this.from,
    this.to,
    this.requires,
  });
  final String key;
  String name;
  int? from;
  int? to;
  String? requires;
}

/// Lesson creation / edit path: 1 المادة والبيانات → 2 صفحات الدرس → 3 العقد
/// والربط → 4 المعاينة والنشر (D-2 T06–T09).
///
/// Back (X01): inside the path it goes one step back keeping the inputs;
/// from step 1 it leaves the path, asking «تجاهل التعديلات؟» when anything
/// was changed and not saved. Nothing is lost silently.
///
/// Everything is held in memory until step 4 saves, in ONE transaction.
class LessonWizardScreen extends StatefulWidget {
  const LessonWizardScreen({super.key, this.lessonId});
  final String? lessonId;

  @override
  State<LessonWizardScreen> createState() => _LessonWizardScreenState();
}

class _LessonWizardScreenState extends State<LessonWizardScreen> {
  int _step = 0;
  bool _loading = true;
  bool _dirty = false;
  bool _busy = false;
  String? _lessonId;
  LessonStatus _savedStatus = LessonStatus.draft;
  int _savedVersion = 1;

  final _title = TextEditingController();
  final _subject = TextEditingController();
  final _unit = TextEditingController();
  final _section = TextEditingController();
  final _track = TextEditingController();
  final _teacher = TextEditingController();
  final _notes = TextEditingController();
  int? _level;
  String? _linkedVersionId;

  final List<_PageDraft> _pages = [];
  int _selectedPage = 0;
  final List<_NodeEdit> _nodes = [];
  final List<AttachmentInput> _attachments = [];
  LessonStatus _targetStatus = LessonStatus.draft;

  List<LinkableVersion> _linkable = const [];

  @override
  void initState() {
    super.initState();
    _lessonId = widget.lessonId;
    _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _subject, _unit, _section, _track, _teacher, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    final repo = appState.teacherRepository;
    final defaultName = await appState.teacherSession.savedName();
    final linkable = await repo.linkableVersions();
    final LessonAggregate? agg =
        _lessonId == null ? null : await repo.read(_lessonId!);
    if (!mounted) return;
    setState(() {
      _linkable = linkable;
      if (agg != null) {
        final l = agg.lesson;
        _title.text = l.title;
        _subject.text = l.subjectName;
        _unit.text = l.unitLabel ?? '';
        _section.text = l.sectionLabel ?? '';
        _track.text = l.trackLabel ?? '';
        _teacher.text = l.teacherName;
        _notes.text = l.notes ?? '';
        _level = l.internalLevel;
        _linkedVersionId = l.linkedCurriculumVersionId;
        _savedStatus = LessonStatus.fromDb(l.status);
        _savedVersion = l.versionNumber;
        _targetStatus = _savedStatus;
        for (final p in agg.pages) {
          _pages.add(_PageDraft(p.bytes, turns: p.quarterTurns));
        }
        for (final n in agg.nodes) {
          _nodes.add(_NodeEdit(
            key: n.id,
            name: n.name,
            from: n.pageFrom,
            to: n.pageTo,
            requires: n.requiresNodeId,
          ));
        }
        _attachments.addAll(agg.attachments.map((a) =>
            AttachmentInput(name: a.name, mimeType: a.mimeType, bytes: a.bytes)));
      } else {
        _lessonId = null;
        _teacher.text = defaultName;
      }
      _loading = false;
    });
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  // ----------------------------------------------------------- navigation

  Future<void> _handleBack() async {
    if (_step > 0) {
      setState(() => _step--);
      return;
    }
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await confirmDialog(
      context,
      title: 'تجاهل التعديلات؟',
      message: 'فيه تعديلات لم تُحفظ. إن غادرت ستضيع.',
      confirmLabel: 'تجاهل',
      cancelLabel: 'ابقَ',
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  void _next() {
    if (_step == 0) {
      final issues = validateLessonFields(
        title: _title.text,
        subjectName: _subject.text,
        internalLevel: _level,
        teacherName: _teacher.text,
      );
      if (issues.isNotEmpty) {
        showSnack(context, issues.first.message);
        return;
      }
    }
    setState(() => _step++);
  }

  // ---------------------------------------------------------------- pages

  Future<void> _addImages({required bool capture}) async {
    if (_busy) return;
    if (!deviceFilesAvailable) {
      showSnack(
          context,
          'اختيار الصور من الجهاز متاح في نسخة الويب/PWA فقط حاليًا. '
          'حزمة الصور لنسخة الهاتف الأصلية قرار مفتوح (O-4).');
      return;
    }
    setState(() => _busy = true);
    try {
      final files = await pickImages(capture: capture);
      var rejected = 0;
      for (final f in files) {
        if (sniffImageMime(f.bytes) == null) {
          rejected++;
        } else {
          _pages.add(_PageDraft(f.bytes));
        }
      }
      if (files.isNotEmpty) {
        _dirty = true;
        _selectedPage = _pages.isEmpty ? 0 : _pages.length - 1;
      }
      if (mounted && rejected > 0) {
        showSnack(context,
            'تُجوهل $rejected ملف(ات): الصيغ المدعومة JPEG وPNG وWebP.');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'تعذّر اختيار الصور: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _movePage(int delta) {
    if (_pages.isEmpty) return;
    final moved = movedItem(_pages, _selectedPage, delta);
    final newIndex = (_selectedPage + delta).clamp(0, _pages.length - 1);
    setState(() {
      _pages
        ..clear()
        ..addAll(moved);
      _selectedPage = newIndex;
      _dirty = true;
    });
  }

  void _rotatePage() {
    if (_pages.isEmpty) return;
    setState(() {
      final p = _pages[_selectedPage];
      p.turns = (p.turns + 1) % 4;
      _dirty = true;
    });
  }

  void _deletePage() {
    if (_pages.isEmpty) return;
    setState(() {
      _pages.removeAt(_selectedPage);
      if (_selectedPage >= _pages.length) {
        _selectedPage = _pages.isEmpty ? 0 : _pages.length - 1;
      }
      // Ranges that pointed past the last page would now be invalid: they
      // are cleared, never silently kept (the teacher sees them blank).
      for (final n in _nodes) {
        final to = n.to;
        if (to != null && to > _pages.length) {
          n.from = null;
          n.to = null;
        }
      }
      _dirty = true;
    });
  }

  // ---------------------------------------------------------------- nodes

  Future<void> _editNode({_NodeEdit? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final from = TextEditingController(text: existing?.from?.toString() ?? '');
    final to = TextEditingController(text: existing?.to?.toString() ?? '');
    String? requires = existing?.requires;
    final others = _nodes.where((n) => n.key != existing?.key).toList();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'أضف عقدة' : 'عدّل العقدة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'اسم العقدة'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: from,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'من صفحة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: to,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'إلى صفحة'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: requires,
                  decoration: const InputDecoration(labelText: 'يتطلب'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('لا شيء')),
                    for (final o in others)
                      DropdownMenuItem<String?>(
                          value: o.key, child: Text(o.name)),
                  ],
                  onChanged: (v) => setLocal(() => requires = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('تراجع')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('احفظ')),
          ],
        ),
      ),
    );
    final nameText = name.text;
    final fromText = from.text.trim();
    final toText = to.text.trim();
    name.dispose();
    from.dispose();
    to.dispose();
    if (saved != true || !mounted) return;

    final f = fromText.isEmpty ? null : int.tryParse(fromText);
    final t = toText.isEmpty ? null : int.tryParse(toText);
    if ((fromText.isNotEmpty && f == null) || (toText.isNotEmpty && t == null)) {
      showSnack(context, 'أرقام الصفحات يجب أن تكون أعدادًا صحيحة.');
      return;
    }
    final candidate = <NodeDraft>[
      for (final n in _nodes)
        if (n.key != existing?.key)
          NodeDraft(
              key: n.key,
              name: n.name,
              pageFrom: n.from,
              pageTo: n.to,
              requiresKey: n.requires),
      NodeDraft(
          key: existing?.key ?? 'new',
          name: nameText,
          pageFrom: f,
          pageTo: t,
          requiresKey: requires),
    ];
    final issues = validateNodes(candidate, _pages.length);
    if (issues.isNotEmpty) {
      showSnack(context, issues.first.message);
      return;
    }
    setState(() {
      if (existing == null) {
        _nodes.add(_NodeEdit(
            key: uuidGen.v4(),
            name: nameText.trim(),
            from: f,
            to: t,
            requires: requires));
      } else {
        existing
          ..name = nameText.trim()
          ..from = f
          ..to = t
          ..requires = requires;
      }
      _dirty = true;
    });
  }

  void _deleteNode(_NodeEdit n) {
    setState(() {
      _nodes.remove(n);
      for (final o in _nodes) {
        if (o.requires == n.key) o.requires = null;
      }
      _dirty = true;
    });
  }

  Future<void> _addAttachment() async {
    if (_busy) return;
    if (!deviceFilesAvailable) {
      showSnack(context,
          'إرفاق الملفات متاح في نسخة الويب/PWA فقط حاليًا (O-4).');
      return;
    }
    setState(() => _busy = true);
    try {
      final files = await pickAnyFiles();
      for (final f in files) {
        _attachments.add(AttachmentInput(
          name: f.name,
          mimeType: sniffImageMime(f.bytes) ?? 'application/octet-stream',
          bytes: f.bytes,
        ));
      }
      if (files.isNotEmpty) _dirty = true;
    } catch (e) {
      if (mounted) showSnack(context, 'تعذّر الإرفاق: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ----------------------------------------------------------------- save

  LessonInput _input() => LessonInput(
        id: _lessonId,
        title: _title.text,
        subjectName: _subject.text,
        internalLevel: _level,
        teacherName: _teacher.text,
        sectionLabel: _section.text,
        trackLabel: _track.text,
        unitLabel: _unit.text,
        notes: _notes.text,
        linkedCurriculumVersionId: _linkedVersionId,
        pages: [
          for (final p in _pages) PageInput(bytes: p.bytes, quarterTurns: p.turns),
        ],
        nodes: [
          for (final n in _nodes)
            NodeDraft(
              key: n.key,
              name: n.name,
              pageFrom: n.from,
              pageTo: n.to,
              requiresKey: n.requires,
            ),
        ],
        attachments: List.of(_attachments),
      );

  /// Saves, then walks the status forward to [target] (draft → inReview →
  /// published) using the repository's own transition rules.
  Future<bool> _save(LessonStatus target) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final repo = teacherRepo(context);
      final id = await repo.saveLesson(_input());
      _lessonId = id;
      if (target == LessonStatus.inReview ||
          target == LessonStatus.published) {
        await repo.transition(id, LessonStatus.inReview);
      }
      if (target == LessonStatus.published) {
        await repo.transition(id, LessonStatus.published);
      }
      final agg = await repo.read(id);
      if (!mounted) return true;
      setState(() {
        _dirty = false;
        _savedStatus = agg == null
            ? LessonStatus.draft
            : LessonStatus.fromDb(agg.lesson.status);
        _savedVersion = agg?.lesson.versionNumber ?? 1;
        _targetStatus = _savedStatus;
      });
      showSnack(context, 'حُفظ الدرس: ${_savedStatus.label}.');
      return true;
    } catch (e) {
      if (mounted) {
        // A transition refusal after a successful save still saved the
        // draft; say what happened.
        showRefusal(context, e);
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    // Only a published lesson can be exported: save with target "published"
    // first, which itself requires the lesson to be ready (≥ 1 page, valid
    // fields and nodes).
    // An unchanged, already-published lesson is exported as it is: saving it
    // again would needlessly create a new version.
    final unchangedPublished = !_dirty &&
        _lessonId != null &&
        _savedStatus == LessonStatus.published;
    if (!unchangedPublished) {
      final ok = await _save(LessonStatus.published);
      if (!ok || !mounted) return;
    }
    final id = _lessonId;
    if (id != null) await exportLessonPackage(context, id);
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    const titles = [
      'درس جديد',
      'صفحات الدرس',
      'العقد والربط',
      'المعاينة والنشر',
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'رجوع',
            icon: const Icon(Icons.arrow_forward),
            onPressed: _handleBack,
          ),
          title: Text(widget.lessonId == null && _lessonId == null
              ? titles[_step]
              : (_step == 0 ? 'تعديل الدرس' : titles[_step])),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text('${_step + 1} / 4')),
            ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          for (var i = 0; i < 4; i++)
                            Expanded(
                              child: Container(
                                height: 4,
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  color: i <= _step
                                      ? AppColors.primary
                                      : const Color(0xFFD8E0E3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _step,
                        children: [
                          _stepFields(),
                          _stepPages(),
                          _stepNodes(),
                          _stepPreview(),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {int maxLines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        textAlign: TextAlign.right,
        onChanged: (_) => _touch(),
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _nextButton(String label, VoidCallback onPressed) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FilledButton.icon(
          onPressed: _busy ? null : onPressed,
          icon: const Icon(Icons.arrow_back),
          label: Text(label),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      );

  Widget _stepFields() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: _field('المادة', _subject)),
          const SizedBox(width: 10),
          Expanded(child: _field('الوحدة / الفصل', _unit)),
        ]),
        const Text('المستوى', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          segments: [
            for (final lv in kInternalLevels)
              ButtonSegment<int>(value: lv, label: Text(internalLevelLabel(lv))),
          ],
          selected: _level == null ? <int>{} : <int>{_level!},
          onSelectionChanged: (s) {
            setState(() {
              _level = s.isEmpty ? null : s.first;
              _dirty = true;
            });
          },
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Text('«2 ثانوي» يحدد الخانة الداخلية 2 فقط.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
        _field('القسم (معلومة وصفية)', _section, hint: 'مثال: 2 علوم تجريبية'),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('لا يغيّر المستوى ولا منطق الخانات الثلاث.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
        _field('الشعبة / المسار', _track),
        _field('عنوان الدرس', _title),
        _field('اسم الأستاذ', _teacher),
        _field('ملاحظات للتلميذ', _notes,
            maxLines: 3, hint: 'اكتب ما تريد أن ينتبه إليه التلميذ'),
        _nextButton('التالي: صفحات الدرس', _next),
      ],
    );
  }

  Widget _stepPages() {
    final total = _pages.fold<int>(0, (s, p) => s + p.bytes.length);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الخانة الداخلية للدرس',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(children: [
                  for (final lv in kInternalLevels)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: _level == lv
                              ? const Color(0xFFDDEBF0)
                              : const Color(0xFFF0F2F3),
                          border: Border.all(
                              color: _level == lv
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 2),
                        ),
                        child: Column(children: [
                          Text(internalLevelLabel(lv),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _level == lv
                                      ? AppColors.primary
                                      : AppColors.textSecondary)),
                          Text(_level == lv ? 'فعّالة' : 'مغلقة',
                              style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    ),
                ]),
                const SizedBox(height: 6),
                Text(
                    _level == null
                        ? 'اختر المستوى في الخطوة الأولى.'
                        : 'الصور تذهب إلى خانة ${internalLevelLabel(_level!)} '
                            'فقط، ولا تظهر في الخانتين الأخريين.',
                    style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (!deviceFilesAvailable)
          const InfoBox(
              'التقاط الصور واختيارها من الهاتف متاح في نسخة الويب/PWA. '
              'نسخة الهاتف الأصلية تحتاج حزمة صور لم تُعتمد بعد (O-4).',
              icon: Icons.warning_amber_rounded),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _addImages(capture: true),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('التقط صفحة'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _addImages(capture: false),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('من الجهاز'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (_pages.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('لا صفحات بعد. التقط صفحة أو اخترها من جهازك.')),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _pages.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8,
                childAspectRatio: 3 / 4),
            itemBuilder: (context, i) {
              final selected = i == _selectedPage;
              return GestureDetector(
                onTap: () => setState(() => _selectedPage = i),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selected ? AppColors.primary : Colors.transparent,
                        width: 2),
                    color: const Color(0xFFE9EEF0),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    RotatedBox(
                      quarterTurns: _pages[i].turns,
                      child: Image.memory(_pages[i].bytes,
                          fit: BoxFit.cover,
                          cacheWidth: 360,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined)),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.black54,
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white))),
                    ),
                  ]),
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                    tooltip: 'قدّم الصفحة',
                    onPressed: _pages.isEmpty ? null : () => _movePage(-1),
                    icon: const Icon(Icons.chevron_right)),
                IconButton(
                    tooltip: 'أخّر الصفحة',
                    onPressed: _pages.isEmpty ? null : () => _movePage(1),
                    icon: const Icon(Icons.chevron_left)),
                IconButton(
                    tooltip: 'أدِر الصفحة',
                    onPressed: _pages.isEmpty ? null : _rotatePage,
                    icon: const Icon(Icons.rotate_right)),
                const IconButton(
                    tooltip: 'القص غير متاح بعد (يحتاج مكتبة صور، O-4)',
                    onPressed: null,
                    icon: Icon(Icons.crop)),
                IconButton(
                    tooltip: 'احذف الصفحة',
                    onPressed: _pages.isEmpty ? null : _deletePage,
                    icon: const Icon(Icons.close)),
              ],
            ),
          ),
        ),
        Text('${_pages.length} صفحات · الحجم ${formatBytes(total)}',
            style: const TextStyle(fontSize: 12.5)),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerRight,
          child: Chip(
              label: Text('الحد الأقصى للصور: يُحدَّد لاحقًا (O-3)',
                  style: TextStyle(fontSize: 11.5))),
        ),
        _nextButton('التالي: العقد والربط', _next),
      ],
    );
  }

  Widget _stepNodes() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(
                    child: Text('عقد المعرفة في الدرس',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const Text('تُدخلها أنت يدويًا',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ]),
                if (_nodes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('لا عقد بعد.'),
                  ),
                for (final n in _nodes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.adjust),
                    title: Text(n.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      if (n.from != null && n.to != null)
                        'الصفحات ${n.from}–${n.to}',
                      if (n.requires != null)
                        'يتطلب: ${_nodes.where((o) => o.key == n.requires).map((o) => o.name).join()}',
                    ].join(' · ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            tooltip: 'عدّل',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editNode(existing: n)),
                        IconButton(
                            tooltip: 'احذف',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteNode(n)),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _editNode,
                  icon: const Icon(Icons.add),
                  label: const Text('أضف عقدة'),
                ),
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
                Row(children: [
                  const Expanded(
                    child: Text('المرفقات',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  TextButton.icon(
                      onPressed: _busy ? null : _addAttachment,
                      icon: const Icon(Icons.add),
                      label: const Text('أرفق')),
                ]),
                if (_attachments.isEmpty)
                  const Text('لا مرفقات بعد.')
                else
                  for (var i = 0; i < _attachments.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file),
                      title: Text(_attachments[i].name),
                      subtitle: Text(formatBytes(_attachments[i].bytes.length)),
                      trailing: IconButton(
                        tooltip: 'احذف المرفق',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _attachments.removeAt(i);
                          _dirty = true;
                        }),
                      ),
                    ),
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
                const Text('الربط بالمنهج الرسمي',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text(
                    'لا تُربط إلا بنسخة منهج معروفة ومتحقَّق منها. أي درس غير '
                    'مربوط يبقى «$kTeacherBadge».',
                    style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 8),
                if (_linkable.isEmpty)
                  const Chip(label: Text('نسخة المنهج: غير متاح'))
                else
                  DropdownButtonFormField<String?>(
                    value: _linkable.any((v) => v.id == _linkedVersionId)
                        ? _linkedVersionId
                        : null,
                    decoration: const InputDecoration(labelText: 'نسخة المنهج'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('غير مربوط')),
                      for (final v in _linkable)
                        DropdownMenuItem<String?>(
                            value: v.id, child: Text(v.label)),
                    ],
                    onChanged: (v) => setState(() {
                      _linkedVersionId = v;
                      _dirty = true;
                    }),
                  ),
              ],
            ),
          ),
        ),
        const InfoBox(
            'الدرس لا يضيف معاملًا ولا ساعات ولا يغيّر شيئًا في المنهج الرسمي.',
            icon: Icons.shield_outlined),
        _nextButton('التالي: المعاينة والنشر', _next),
      ],
    );
  }

  Widget _stepPreview() {
    final readiness = readinessForReview(
      title: _title.text,
      subjectName: _subject.text,
      internalLevel: _level,
      teacherName: _teacher.text,
      pageCount: _pages.length,
      nodes: [
        for (final n in _nodes)
          NodeDraft(
              key: n.key,
              name: n.name,
              pageFrom: n.from,
              pageTo: n.to,
              requiresKey: n.requires),
      ],
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('هكذا يراه التلميذ',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const TeacherBadge(),
                  const SizedBox(width: 8),
                  if (_level != null) Chip(label: Text(internalLevelLabel(_level!))),
                ]),
                const SizedBox(height: 8),
                Text(_title.text.trim().isEmpty ? 'عنوان الدرس' : _title.text,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
                Text(
                    '${_subject.text} · القسم: '
                    '${_section.text.trim().isEmpty ? 'غير محدد' : _section.text} · '
                    '${_teacher.text}',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 70,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        Container(
                          width: 54,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: const Color(0xFFE9EEF0)),
                          clipBehavior: Clip.antiAlias,
                          child: RotatedBox(
                            quarterTurns: _pages[i].turns,
                            child: Image.memory(_pages[i].bytes,
                                fit: BoxFit.cover,
                                cacheWidth: 200,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.broken_image_outlined)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text('${_nodes.length} عقد · ${_attachments.length} مرفقات',
                    style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
        ),
        if (readiness.isNotEmpty)
          Card(
            color: const Color(0xFFFFF4E0),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ينقص قبل الإرسال إلى المراجعة:',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final i in readiness)
                    Text('• ${i.message}', style: const TextStyle(fontSize: 13)),
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
                Row(children: [
                  const Expanded(
                    child: Text('الحالة',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  if (_lessonId != null)
                    Text('محفوظ: ${_savedStatus.label} · الإصدار $_savedVersion',
                        style: const TextStyle(fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                SegmentedButton<LessonStatus>(
                  showSelectedIcon: false,
                  segments: [
                    for (final s in LessonStatus.values)
                      ButtonSegment<LessonStatus>(
                          value: s, label: Text(s.label)),
                  ],
                  selected: {_targetStatus},
                  onSelectionChanged: (s) =>
                      setState(() => _targetStatus = s.first),
                ),
                if (_savedStatus == LessonStatus.published && _lessonId != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                        'تعديل درس منشور ينشئ إصدارًا جديدًا ويعيده إلى مسودة.',
                        style: TextStyle(fontSize: 12)),
                  ),
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
                Row(children: [
                  const Expanded(
                    child: Text('حزمة للتلميذ',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  Chip(label: Text('الإصدار $_savedVersion')),
                ]),
                const Text('بصمة الحزمة تُحسب عند التصدير.',
                    style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 6),
                const InfoBox(
                    'الحزمة وسيلة نقل لهذه النسخة فقط، وليست تصور المنتج '
                    'النهائي. لا تُصدَّر إلا الدروس المنشورة.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.upload_file),
          label: const Text('صدّر الحزمة'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () async {
                  // Nothing changed and the status is the same: nothing to
                  // save (saving a published lesson would make a new version).
                  if (!_dirty &&
                      _lessonId != null &&
                      _targetStatus == _savedStatus) {
                    Navigator.of(context).pop(true);
                    return;
                  }
                  final ok = await _save(_targetStatus);
                  if (ok && mounted) Navigator.of(context).pop(true);
                },
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48)),
          child: Text(_targetStatus == LessonStatus.draft
              ? 'احفظ كمسودة'
              : 'احفظ واجعل الحالة «${_targetStatus.label}»'),
        ),
      ],
    );
  }
}
