import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/tables/core_tables.dart' show uuidGen;
import '../../domain/teacher_content_domain.dart';
import '../../platform/device_files.dart';
import '../../repositories/teacher_content_repository.dart';
import '../state/app_state.dart';
import '../design/tokens.dart';
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
          'اختيار الصور من الجهاز متاح في نسخة المتصفح فقط حاليًا. '
          'استعمل المتصفح لاختيار الصور.');
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
          _pages.add(_PageDraft(await compressImage(f.bytes)));
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
          title: Text(existing == null ? 'أضف محورًا' : 'عدّل المحور'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'اسم المحور'),
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
                  decoration: const InputDecoration(labelText: 'يسبقه'),
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
          'إرفاق المستندات متاح في نسخة المتصفح فقط حاليًا.');
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

  /// The one action of the wizard: save the lesson as published, send it to
  /// the students, and say it arrived only after it was read back.
  Future<void> _sendToStudents() async {
    if (_busy) return;
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
    if (readiness.isNotEmpty) {
      showSnack(context, readiness.first.message);
      return;
    }
    // An unchanged published lesson is sent as it is: saving it again would
    // only create a needless new version.
    final unchanged = !_dirty &&
        _lessonId != null &&
        _savedStatus == LessonStatus.published;
    if (!unchanged) {
      final ok = await _save(LessonStatus.published);
      if (!ok || !mounted) return;
    }
    if (!canSendToStudents(context)) {
      showSnack(context,
          'حُفظ الدرس. للإرسال ادخل برقمك الخاص ثم اضغط «إرسال الدرس للتلاميذ».');
      return;
    }
    setState(() => _busy = true);
    final sent = await publishLessonOnline(context, _lessonId!);
    if (mounted) setState(() => _busy = false);
    if (sent && mounted) Navigator.of(context).pop(true);
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    const titles = [
      'درس جديد',
      'صور الدرس',
      'المراجعة والإرسال',
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
              child: Center(child: Text('${_step + 1} / 3')),
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
                          for (var i = 0; i < 3; i++)
                            Expanded(
                              child: Container(
                                height: 4,
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  color: i <= _step
                                      ? context.mq.brand
                                      : context.mq.line,
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
        const Text('لأي سنة هذا الدرس؟',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('يصل الدرس تلقائيًا إلى تلاميذ هذه السنة فقط.',
            style: TextStyle(fontSize: 12.5, color: context.mq.ink2)),
        const SizedBox(height: 10),
        for (final lv in kInternalLevels)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _BigChoice(
              label: internalLevelLabel(lv),
              selected: _level == lv,
              onTap: () => setState(() {
                _level = lv;
                _dirty = true;
              }),
            ),
          ),
        const SizedBox(height: 8),
        _field('المادة', _subject, hint: 'مثال: الرياضيات'),
        _field('عنوان الدرس', _title),
        _field('اسم الأستاذ', _teacher),
        _field('ملاحظة للتلميذ (اختيارية)', _notes,
            maxLines: 3, hint: 'اكتب ما تريد أن ينتبه إليه التلميذ'),
        _field('رقم القسم', _section, hint: 'مثال: 5'),
        _field('الشعبة أو الجذع', _track,
            hint: 'مثال: جذع مشترك علوم وتكنولوجيا، أو 1 علمي'),
        Card(
          child: ExpansionTile(
            title: const Text('تفاصيل إضافية (اختيارية)'),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: [
              _field('الوحدة أو الفصل', _unit),
            ],
          ),
        ),
        _nextButton('التالي: صور الدرس', _next),
      ],
    );
  }

  Widget _stepPages() {
    final total = _pages.fold<int>(0, (s, p) => s + p.bytes.length);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
            _level == null
                ? 'اختر السنة في الخطوة الأولى.'
                : 'الدرس موجّه لتلاميذ ${internalLevelLabel(_level!)}.',
            style: TextStyle(fontSize: 12.5, color: context.mq.ink2)),
        if (!deviceFilesAvailable)
          const InfoBox(
              'التقاط الصور واختيارها من الهاتف متاح في نسخة المتصفح.',
              icon: Icons.warning_amber_rounded),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _addImages(capture: true),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('التقط صورة'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _addImages(capture: false),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('اختر صورًا من هاتفك'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (_pages.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('لا صور بعد. التقط صورة أو اختر عدة صور من هاتفك.')),
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
                        color: selected ? context.mq.brand : Colors.transparent,
                        width: 2),
                    color: context.mq.surface2,
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
                IconButton(
                    tooltip: 'احذف الصفحة',
                    onPressed: _pages.isEmpty ? null : _deletePage,
                    icon: const Icon(Icons.close)),
              ],
            ),
          ),
        ),
        Text('${_pages.length} صورة · الحجم ${formatBytes(total)}',
            style: const TextStyle(fontSize: 12.5)),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerRight,
          child: Chip(
              label: Text('يُفضَّل ألا يزيد الدرس عن 20 ميغابايت',
                  style: TextStyle(fontSize: 11.5))),
        ),
        _nextButton('التالي: المراجعة والإرسال', _next),
      ],
    );
  }

  List<Widget> _advancedCards() {
    return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(
                    child: Text('محاور الدرس (اختيارية)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  Text('تكتبها أنت بنفسك',
                      style: TextStyle(
                          fontSize: 12, color: context.mq.ink2)),
                ]),
                if (_nodes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('لا محاور بعد.'),
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
                  label: const Text('أضف محورًا'),
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
                    child: Text('مستندات مرفقة (اختيارية)',
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
                const Text('الربط بالمنهج الرسمي (اختياري)',
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
    ];
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
                    'القسم: ${_section.text.trim().isEmpty ? 'غير محدد' : _section.text.trim()}'
                    '${_track.text.trim().isEmpty ? '' : ' · ${_track.text.trim()}'}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
                Text('${_subject.text} · الأستاذ: ${_teacher.text}',
                    style: TextStyle(
                        fontSize: 13.5, color: context.mq.ink2)),
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
                Text('${_nodes.length} محاور · ${_attachments.length} مرفقات',
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
                  const Text('ينقص قبل الإرسال:',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final i in readiness)
                    Text('• ${i.message}', style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        Card(
          child: ExpansionTile(
            title: const Text('خيارات إضافية (اختيارية)'),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: _advancedCards(),
          ),
        ),
        const SizedBox(height: 8),
        if (!canSendToStudents(context))
          const InfoBox(
              'للإرسال إلى التلاميذ ادخل برقمك الخاص من رابط لوحة الأستاذ. '
              'يُحفظ الدرس هنا في الحالتين.',
              icon: Icons.lock_outline),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _sendToStudents,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_outlined),
          label: Text(_busy ? 'جارٍ الإرسال…' : 'إرسال الدرس للتلاميذ'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  final ok = await _save(LessonStatus.draft);
                  if (ok && mounted) Navigator.of(context).pop(true);
                },
          child: const Text('احفظ دون إرسال (لأكمله لاحقًا)'),
        ),
      ],
    );
  }
}

/// A large, clear choice (used for the lesson's school year).
class _BigChoice extends StatelessWidget {
  const _BigChoice(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? mq.brandSoft : mq.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? mq.brand : mq.line, width: selected ? 2.5 : 1),
        ),
        child: Row(children: [
          Icon(selected ? Icons.check_circle : Icons.circle_outlined,
              size: 26, color: selected ? mq.brand : mq.ink3),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: selected ? mq.brandInk : mq.ink)),
          ),
        ]),
      ),
    );
  }
}
