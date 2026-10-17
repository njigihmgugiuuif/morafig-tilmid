import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/school_timetable_domain.dart';
import '../../engines/weekly_timeline_engine.dart' show WeekCalendar;
import '../../services/planning_service.dart';
import '../../services/school_timetable_service.dart';
import '../../services/teacher_session.dart'
    show KeyValueStore, SharedPrefsKeyValueStore;
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/progress.dart';
import '../design/sheet.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';

/// «جدول المدرسة»: the student's school timetable as a grid (days x slots).
///
/// Everything is typed by the student. The app never reads the photo of a
/// timetable (there is no reading of images in this version) and never fills
/// in subjects. The model of the photo the student sent is only a blank
/// SHAPE the student may choose; days and times stay editable.
///
/// What is entered here is saved on the device (works without a
/// connection) and is read by the planner as fixed school time.
class SchoolTimetableScreen extends StatefulWidget {
  const SchoolTimetableScreen({super.key, KeyValueStore? store})
      : _store = store;
  final KeyValueStore? _store;

  @override
  State<SchoolTimetableScreen> createState() => _SchoolTimetableScreenState();
}

class _SchoolTimetableScreenState extends State<SchoolTimetableScreen> {
  int _tick = 0;
  late final SchoolTimetableStore _store =
      SchoolTimetableStore(widget._store ?? SharedPrefsKeyValueStore());

  SchoolTimetableService _service(AppState app) =>
      SchoolTimetableService(app.db, _store);

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _refresh() => setState(() => _tick++);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final studentId = app.studentId;
    if (studentId == null) {
      return const MqPage(
        title: 'جدول المدرسة',
        caption: 'واقعي',
        children: [
          MqEmptyState(
              icon: Icons.person_outline_rounded,
              title: 'سجّل نفسك أولًا',
              message: 'يُحفظ جدولك باسم حسابك على هذا الجهاز.'),
        ],
      );
    }
    return MqPage(
      title: 'جدول المدرسة',
      caption: 'واقعي',
      children: [
        const MqBanner(
          icon: Icons.info_outline_rounded,
          tone: MqTone.neutral,
          text: 'هذا جدولك أنت: تكتب موادك بنفسك. لا نقرأ صورة الجدول تلقائيًا '
              'ولا نضع لك مواد افتراضية. يُحفظ على جهازك ويعمل دون إنترنت.',
        ),
        const SizedBox(height: 10),
        MqAsync<SchoolTimetableState>(
          reloadKey: _tick,
          load: () => _service(app).load(studentId),
          errorTitle: 'تعذّر عرض الجدول',
          builder: (context, s) => s.isConfigured
              ? _content(context, app, studentId, s)
              : _start(context, app, studentId, s),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- start

  Widget _start(BuildContext context, AppState app, String studentId,
      SchoolTimetableState s) {
    final p = context.mq;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MqEmptyState(
          icon: Icons.table_chart_outlined,
          title: 'لم تُنشئ جدولك المدرسي بعد',
          message: 'اختر كيف تبدأ. في الحالتين تكتب موادك بنفسك.',
        ),
        const SizedBox(height: 12),
        MqButton(
          label: 'ابدأ من نموذج الجدول الذي أرسلته',
          icon: Icons.view_week_outlined,
          block: true,
          onPressed: () async {
            await _service(app).saveLayout(SchoolTimetableLayout.photoModel());
            if (!mounted) return;
            _refresh();
            _snack('وُضع شكل النموذج. المربعات فارغة: اضغط كل مربع واكتب مادتك.');
          },
        ),
        const SizedBox(height: 6),
        Text(
            'الأحد إلى الخميس، من 08:00 إلى 17:00، والاستراحة من 12:00 إلى 13:00. '
            'شكل فارغ فقط، وتعدّل أيامه وأوقاته كما تشاء.',
            style: MqType.caption.copyWith(color: p.ink3)),
        const SizedBox(height: 12),
        MqButton(
          label: 'ابدأ بجدول فارغ وأحدّد أنا الأيام والحصص',
          icon: Icons.edit_calendar_outlined,
          kind: MqButtonKind.secondary,
          block: true,
          onPressed: () => _editLayout(app, studentId, s),
        ),
      ],
    );
  }

  // -------------------------------------------------------- content

  Widget _content(BuildContext context, AppState app, String studentId,
      SchoolTimetableState s) {
    final p = context.mq;
    final total = s.totalCells;
    final filled = s.filledCells;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MqCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text('حصص مكتوبة',
                        style: MqType.body.copyWith(color: p.ink))),
                MqNum('$filled / $total', style: MqType.label),
              ]),
              const SizedBox(height: 8),
              MqBar(value: total == 0 ? 0 : filled / total),
              const SizedBox(height: 6),
              Text(
                  'اضغط أي مربع لتكتب مادته. يعامل المخطِّط هذه الحصص كوقت مدرسة '
                  'ثابت فلا يضع فيها جلسات دراسة.',
                  style: MqType.caption.copyWith(color: p.ink3)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Grid(
          layout: s.layout,
          entries: s.entries,
          onCell: (d, slot) => _openCell(app, studentId, s, d, slot),
        ),
        const SizedBox(height: 8),
        if (s.layout.slots.any((x) => x.isBreak))
          Text(
              'الاستراحة تبقى وقتًا حرًّا في الخطة. إن أردتها وجبة أو راحة ثابتة '
              'أضفها من «أسبوعي».',
              style: MqType.caption.copyWith(color: p.ink3)),
        if (s.outsideGrid > 0) ...[
          const SizedBox(height: 10),
          MqBanner(
            icon: Icons.info_outline_rounded,
            tone: MqTone.neutral,
            text: '${s.outsideGrid} كتلة مدرسية مكتوبة بأوقات خارج هذه الحصص. '
                'هي محفوظة ويستعملها المخطِّط، وتجدها في «واقعي ← أسبوعي».',
          ),
        ],
        const SizedBox(height: 10),
        const MqBanner(
          icon: Icons.schedule_outlined,
          tone: MqTone.neutral,
          text: 'يضع المخطِّط جلسات الدراسة داخل «نوافذ الفراغ» التي تدخلها في '
              'واقعي ← فراغي، وخارج حصص المدرسة.',
        ),
        const SizedBox(height: 14),
        MqButton(
          label: 'تعديل الأيام والحصص',
          icon: Icons.tune_rounded,
          kind: MqButtonKind.secondary,
          block: true,
          onPressed: () => _editLayout(app, studentId, s),
        ),
        const SizedBox(height: 8),
        MqButton(
          label: 'أعد تخطيط أسبوعي بهذا الجدول',
          icon: Icons.autorenew_rounded,
          block: true,
          onPressed: () => _replan(app),
        ),
        const SizedBox(height: 8),
        MqButton(
          label: 'امسح الجدول المدرسي',
          icon: Icons.delete_outline_rounded,
          kind: MqButtonKind.ghost,
          block: true,
          onPressed: () => _clearAll(app, studentId),
        ),
      ],
    );
  }

  // -------------------------------------------------------- actions

  Future<void> _openCell(AppState app, String studentId,
      SchoolTimetableState s, int dayIndex, SchoolSlot slot) async {
    final current = SchoolTimetableLayout.cellAt(s.entries, dayIndex, slot);
    final saved = await showMqSheet<bool>(
      context,
      title:
          '${WeekCalendar.arabicDayNames[dayIndex]} · ${SchoolTimetableLayout.slotText(slot)}',
      builder: (_) => _CellForm(
        service: _service(app),
        studentId: studentId,
        layout: s.layout,
        dayIndex: dayIndex,
        slot: slot,
        currentLabel: current?.label,
        suggestions: SchoolTimetableLayout.usedLabels(s.entries),
      ),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _editLayout(
      AppState app, String studentId, SchoolTimetableState s) async {
    final saved = await showMqSheet<bool>(
      context,
      title: 'الأيام والحصص',
      subtitle: 'اختر أيام الدراسة وأوقات كل حصة. لا يوجد جدول جاهز مفروض عليك.',
      builder: (_) => _LayoutForm(
        service: _service(app),
        studentId: studentId,
        current: s.layout,
      ),
    );
    if (saved == true && mounted) {
      _refresh();
      _snack('حُفظ شكل الجدول.');
    }
  }

  Future<void> _replan(AppState app) async {
    try {
      final r = await PlanningService(app.db).replanNow();
      if (!mounted) return;
      _snack(r == null
          ? 'لا يمكن التخطيط قبل التسجيل.'
          : 'أُعيد تخطيط أسبوعك (${r.sessionsSaved} جلسة محفوظة).');
    } catch (_) {
      if (!mounted) return;
      _snack('تعذّرت إعادة التخطيط. حاول من «مراجعة الخطة».');
    }
  }

  Future<void> _clearAll(AppState app, String studentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح الجدول المدرسي'),
        content: const Text(
            'ستُمسح كل حصص المدرسة المكتوبة وشكل الجدول. لا يُمسح النوم ولا '
            'الوجبات ولا التزاماتك الأخرى ولا مهامك.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('امسح الجدول')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await _service(app).clearAll(studentId);
    if (!mounted) return;
    _refresh();
    _snack('مُسح الجدول المدرسي ($n كتلة).');
  }
}

// ------------------------------------------------------------------ grid

class _Grid extends StatelessWidget {
  const _Grid({
    required this.layout,
    required this.entries,
    required this.onCell,
  });

  final SchoolTimetableLayout layout;
  final List<SchoolEntry> entries;
  final void Function(int dayIndex, SchoolSlot slot) onCell;

  static const double _timeW = 50;
  static const double _cellH = 54;
  static const double _minCell = 54;
  static const double _maxCell = 140;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return LayoutBuilder(builder: (context, c) {
      final n = layout.days.length;
      final room = (c.maxWidth - _timeW) / n;
      final cellW = math.min(_maxCell, math.max(_minCell, room));
      final totalW = _timeW + cellW * n;

      final rows = <Widget>[
        Row(children: [
          const SizedBox(width: _timeW, height: 30),
          for (final d in layout.days)
            SizedBox(
              width: cellW,
              height: 30,
              child: Center(
                child: Text(WeekCalendar.arabicDayNames[d],
                    style: MqType.caption
                        .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ];
      for (final slot in layout.slots) {
        if (slot.isBreak) {
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Container(
              width: totalW,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('استراحة · ${SchoolTimetableLayout.slotText(slot)}',
                  style: MqType.caption.copyWith(color: p.ink3)),
            ),
          ));
          continue;
        }
        rows.add(Row(children: [
          SizedBox(
            width: _timeW,
            height: _cellH,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MqNum(SchoolTimetableLayout.minutesText(slot.startMinutes),
                    style: MqType.caption, color: p.ink2),
                MqNum(SchoolTimetableLayout.minutesText(slot.endMinutes),
                    style: MqType.caption, color: p.ink3),
              ],
            ),
          ),
          for (final d in layout.days)
            _cell(context, d, slot, cellW),
        ]));
      }

      final grid = SizedBox(
        width: totalW,
        child: Column(children: rows),
      );
      if (totalW <= c.maxWidth) return grid;
      return SingleChildScrollView(
          scrollDirection: Axis.horizontal, child: grid);
    });
  }

  Widget _cell(BuildContext context, int d, SchoolSlot slot, double w) {
    final p = context.mq;
    final e = SchoolTimetableLayout.cellAt(entries, d, slot);
    final name = WeekCalendar.arabicDayNames[d];
    return Padding(
      padding: const EdgeInsets.all(2),
      child: MqPressable(
        onTap: () => onCell(d, slot),
        semanticLabel: e == null
            ? '$name ${SchoolTimetableLayout.slotText(slot)}: فارغة'
            : '$name ${SchoolTimetableLayout.slotText(slot)}: ${e.label}',
        child: Container(
          width: w - 4,
          height: _cellH - 4,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: e == null ? p.surface2 : p.brandSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.line),
          ),
          child: e == null
              ? Icon(Icons.add_rounded, size: 16, color: p.ink3)
              : Text(
                  e.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: MqType.caption
                      .copyWith(color: p.ink, fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- cell form

class _ErrText extends StatelessWidget {
  const _ErrText(this.text);
  final String? text;
  @override
  Widget build(BuildContext context) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(text!,
              style: MqType.caption.copyWith(color: context.mq.overdue)));
}

class _CellForm extends StatefulWidget {
  const _CellForm({
    required this.service,
    required this.studentId,
    required this.layout,
    required this.dayIndex,
    required this.slot,
    required this.currentLabel,
    required this.suggestions,
  });

  final SchoolTimetableService service;
  final String studentId;
  final SchoolTimetableLayout layout;
  final int dayIndex;
  final SchoolSlot slot;
  final String? currentLabel;
  final List<String> suggestions;

  @override
  State<_CellForm> createState() => _CellFormState();
}

class _CellFormState extends State<_CellForm> {
  late final TextEditingController _c =
      TextEditingController(text: widget.currentLabel ?? '');
  late final Set<int> _days = {widget.dayIndex};
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = SchoolTimetableLayout.validateLabel(_c.text);
    if (problem != null) {
      setState(() => _err = problem);
      return;
    }
    try {
      await widget.service.setCells(
        studentId: widget.studentId,
        slot: widget.slot,
        dayIndexes: _days,
        label: _c.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _err = 'تعذّر الحفظ. حاول مرة أخرى.');
    }
  }

  Future<void> _clear() async {
    try {
      await widget.service.clearCell(
        studentId: widget.studentId,
        dayIndex: widget.dayIndex,
        slot: widget.slot,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _err = 'تعذّر المسح. حاول مرة أخرى.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final others = widget.layout.days;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _c,
          textAlign: TextAlign.right,
          maxLength: kSchoolMaxLabel,
          onChanged: (_) {
            if (_err != null) setState(() => _err = null);
          },
          decoration: const InputDecoration(
            labelText: 'اسم المادة',
            prefixIcon: Icon(Icons.menu_book_outlined),
          ),
        ),
        if (widget.suggestions.isNotEmpty) ...[
          Text('موادك المكتوبة سابقًا',
              style: MqType.caption.copyWith(color: p.ink3)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final name in widget.suggestions.take(12))
              ActionChip(
                label: Text(name),
                onPressed: () => setState(() {
                  _c.text = name;
                  _err = null;
                }),
              ),
          ]),
          const SizedBox(height: 12),
        ],
        if (others.length > 1) ...[
          Text('اكتبها أيضًا في (لنفس الحصة)',
              style: MqType.caption.copyWith(color: p.ink3)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in others)
              FilterChip(
                label: Text(WeekCalendar.arabicDayNames[d]),
                selected: _days.contains(d),
                onSelected: (on) => setState(() {
                  if (on) {
                    _days.add(d);
                  } else if (_days.length > 1) {
                    _days.remove(d);
                  }
                }),
              ),
          ]),
          const SizedBox(height: 4),
          Text('ما كُتب في الأيام المحددة لهذه الحصة يُستبدل.',
              style: MqType.caption.copyWith(color: p.ink3)),
        ],
        _ErrText(_err),
        const SizedBox(height: 14),
        MqButton(label: 'حفظ', icon: Icons.check_rounded, block: true, onPressed: _save),
        if ((widget.currentLabel ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          MqButton(
            label: 'فرّغ هذا المربع',
            icon: Icons.backspace_outlined,
            kind: MqButtonKind.ghost,
            block: true,
            onPressed: _clear,
          ),
        ],
      ],
    );
  }
}

// ----------------------------------------------------------- layout form

class _LayoutForm extends StatefulWidget {
  const _LayoutForm({
    required this.service,
    required this.studentId,
    required this.current,
  });

  final SchoolTimetableService service;
  final String studentId;
  final SchoolTimetableLayout current;

  @override
  State<_LayoutForm> createState() => _LayoutFormState();
}

class _LayoutFormState extends State<_LayoutForm> {
  late Set<int> _days = {...widget.current.days};
  late List<SchoolSlot> _slots = [...widget.current.slots];
  String? _err;

  Future<int?> _pick(int initial) async {
    final t = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: (initial ~/ 60) % 24, minute: initial % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  void _addSlot() {
    final lastEnd = _slots.isEmpty
        ? 480
        : _slots.map((s) => s.endMinutes).reduce(math.max);
    final start = math.min(lastEnd, 1380);
    final id = _slots.fold<int>(0, (m, s) => math.max(m, s.id)) + 1;
    setState(() {
      _slots.add(SchoolSlot(id: id, startMinutes: start, endMinutes: start + 60));
      _err = null;
    });
  }

  void _useModel() {
    final model = SchoolTimetableLayout.photoModel();
    // New ids, so the old cells are not mistaken for cells of the model.
    final base = _slots.fold<int>(
        widget.current.nextSlotId, (m, s) => math.max(m, s.id + 1));
    setState(() {
      _days = {...model.days};
      _slots = [
        for (var i = 0; i < model.slots.length; i++)
          SchoolSlot(
            id: base + i,
            startMinutes: model.slots[i].startMinutes,
            endMinutes: model.slots[i].endMinutes,
            isBreak: model.slots[i].isBreak,
          ),
      ];
      _err = null;
    });
  }

  Future<void> _save() async {
    final next = SchoolTimetableLayout.normalized(_days, _slots);
    final problem = SchoolTimetableLayout.validate(next.days, next.slots);
    if (problem != null) {
      setState(() => _err = problem);
      return;
    }
    try {
      final plan = await widget.service.previewLayout(
        studentId: widget.studentId,
        current: widget.current,
        next: next,
      );
      if (plan.removed.isNotEmpty) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ستُحذف بعض الحصص'),
            content: Text(
                'هذا التغيير يحذف ${plan.removed.length} حصة مكتوبة لأن يومها أو '
                'حصتها لم تعد موجودة. هل تتابع؟'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('تراجع')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('تابع واحذفها')),
            ],
          ),
        );
        if (ok != true) return;
      }
      await widget.service.applyLayout(
        studentId: widget.studentId,
        current: widget.current,
        next: next,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _err = 'تعذّر الحفظ. تحقّق من الأوقات.');
    }
  }

  Widget _slotRow(int i) {
    final p = context.mq;
    final s = _slots[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MqCard(
        kind: MqCardKind.soft,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: MqButton(
                  label: 'من ${SchoolTimetableLayout.minutesText(s.startMinutes)}',
                  icon: Icons.schedule_rounded,
                  kind: MqButtonKind.secondary,
                  small: true,
                  onPressed: () async {
                    final v = await _pick(s.startMinutes);
                    if (v != null && mounted) {
                      setState(() {
                        _slots[i] = s.copyWith(startMinutes: v);
                        _err = null;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MqButton(
                  label: 'إلى ${SchoolTimetableLayout.minutesText(s.endMinutes)}',
                  icon: Icons.schedule_rounded,
                  kind: MqButtonKind.secondary,
                  small: true,
                  onPressed: () async {
                    final v = await _pick(s.endMinutes);
                    if (v != null && mounted) {
                      setState(() {
                        _slots[i] = s.copyWith(endMinutes: v);
                        _err = null;
                      });
                    }
                  },
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              FilterChip(
                label: const Text('هذا الصف استراحة'),
                selected: s.isBreak,
                onSelected: (on) => setState(() {
                  _slots[i] = s.copyWith(isBreak: on);
                  _err = null;
                }),
              ),
              const Spacer(),
              MqIconButton(
                icon: Icons.delete_outline_rounded,
                label: 'احذف هذا الصف',
                onTap: () => setState(() {
                  _slots.removeAt(i);
                  _err = null;
                }),
              ),
            ]),
            if (s.endMinutes <= s.startMinutes)
              Text('النهاية يجب أن تكون بعد البداية.',
                  style: MqType.caption.copyWith(color: p.overdue)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final sorted = <int>[
      for (var i = 0; i < _slots.length; i++) i,
    ]..sort((a, b) => _slots[a].startMinutes.compareTo(_slots[b].startMinutes));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('أيام الدراسة',
            style: MqType.body
                .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var d = 0; d < 7; d++)
            FilterChip(
              label: Text(WeekCalendar.arabicDayNames[d]),
              selected: _days.contains(d),
              onSelected: (on) => setState(() {
                if (on) {
                  _days.add(d);
                } else {
                  _days.remove(d);
                }
                _err = null;
              }),
            ),
        ]),
        const SizedBox(height: 14),
        Text('الحصص (من الأولى إلى الأخيرة)',
            style: MqType.body
                .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_slots.isEmpty)
          Text('لا حصص بعد. أضف أول حصة.',
              style: MqType.caption.copyWith(color: p.ink3)),
        for (final i in sorted) _slotRow(i),
        MqButton(
          label: 'إضافة حصة',
          icon: Icons.add_rounded,
          kind: MqButtonKind.secondary,
          block: true,
          onPressed: _addSlot,
        ),
        const SizedBox(height: 8),
        MqButton(
          label: 'املأ الشكل من نموذج الجدول الذي أرسلته',
          icon: Icons.view_week_outlined,
          kind: MqButtonKind.ghost,
          block: true,
          onPressed: _useModel,
        ),
        Text(
            'يضع النموذج الأيام من الأحد إلى الخميس والحصص من 08:00 إلى 17:00 '
            'مع استراحة 12:00 إلى 13:00 في الشاشة فقط، ولا يُحفظ حتى تضغط «حفظ». '
            'إن كانت لديك حصص مكتوبة فسيُسأل عن حذفها.',
            style: MqType.caption.copyWith(color: p.ink3)),
        _ErrText(_err),
        const SizedBox(height: 14),
        MqButton(label: 'حفظ', icon: Icons.check_rounded, block: true, onPressed: _save),
      ],
    );
  }
}
