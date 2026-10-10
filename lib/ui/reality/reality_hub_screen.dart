import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../engines/weekly_timeline_engine.dart';
import '../../repositories/academic_calendar_repository.dart';
import '../../repositories/availability_repository.dart';
import '../../repositories/reality_and_prerequisite_repositories.dart';
import '../../repositories/student_repository.dart';
import '../../repositories/weekly_template_repository.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/sheet.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';

String _fmtMin(int m) {
  final mm = m % 1440;
  return '${(mm ~/ 60).toString().padLeft(2, '0')}:${(mm % 60).toString().padLeft(2, '0')}';
}

String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// Product day index (0 = Sunday) -> stored day number (Dart weekday).
int _stored(int sundayIndex) => sundayIndex == 0 ? 7 : sundayIndex;

String _dayName(int stored) => WeekCalendar.arabicDayNames[stored % 7];

const _kindLabels = <TimelineBlockKind, String>{
  TimelineBlockKind.school: 'مدرسة',
  TimelineBlockKind.commute: 'تنقّل',
  TimelineBlockKind.sleep: 'نوم',
  TimelineBlockKind.rest: 'راحة',
  TimelineBlockKind.meal: 'وجبة',
  TimelineBlockKind.commitment: 'التزام ثابت',
  TimelineBlockKind.activity: 'نشاط',
  TimelineBlockKind.extraClass: 'دروس خاصة',
};

/// «واقعي» (R01–R05): the student describes the real shape of the week.
/// Everything here is typed by the student — the app ships no default
/// timetable, and the planner only uses what is entered.
class RealityHubScreen extends StatefulWidget {
  const RealityHubScreen({super.key});
  @override
  State<RealityHubScreen> createState() => _RealityHubScreenState();
}

enum _Part { week, free, urgent, calendar }

class _RealityHubScreenState extends State<RealityHubScreen> {
  _Part _part = _Part.week;
  int _tick = 0;

  Future<void> _sheet(Widget Function(BuildContext) b, String title) async {
    final ok = await showMqSheet<bool>(context, title: title, builder: b);
    if (ok == true && mounted) setState(() => _tick++);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.mq;
    return MqPage(
      title: 'واقعي',
      children: [
        MqSegmented<_Part>(
          options: const {
            _Part.week: 'أسبوعي',
            _Part.free: 'فراغي',
            _Part.urgent: 'طارئ',
            _Part.calendar: 'الفصول',
          },
          selected: _part,
          onChanged: (v) => setState(() => _part = v),
        ),
        const SizedBox(height: 14),
        if (_part == _Part.week) ...[
          const MqBanner(
              icon: Icons.info_outline_rounded,
              tone: MqTone.neutral,
              text:
                  'أدخل ما يملأ أسبوعك فعلًا (مدرسة، نوم، التزامات). لا نضع لك جدولًا افتراضيًا.'),
          const SizedBox(height: 10),
          MqButton(
              label: 'إضافة كتلة',
              icon: Icons.add_rounded,
              kind: MqButtonKind.secondary,
              block: true,
              onPressed: () =>
                  _sheet((_) => _BlockForm(app.studentId!, app.db), 'كتلة أسبوعية')),
          const SizedBox(height: 10),
          MqAsync<List<WeeklyTemplateEntry>>(
            reloadKey: _tick,
            load: () => WeeklyTemplateRepository(app.db).readForStudent(app.studentId!),
            builder: (c, rows) {
              if (rows.isEmpty) {
                return const MqEmptyState(
                    icon: Icons.view_week_outlined,
                    title: 'لم تُدخل شيئًا بعد',
                    message: 'أضف أول كتلة ليعرف المخطِّط ما يشغلك.');
              }
              final sorted = [...rows]..sort((a, b) {
                  final d = (a.dayOfWeek % 7).compareTo(b.dayOfWeek % 7);
                  return d != 0 ? d : a.startMinutes.compareTo(b.startMinutes);
                });
              return Column(children: [
                for (final e in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: MqCard(
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${_dayName(e.dayOfWeek)} · ${e.label ?? _kindLabels[TimelineBlockKind.values.byName(e.kind)] ?? e.kind}',
                                  style: MqType.h3.copyWith(color: p.ink)),
                              MqNum(
                                  '${_fmtMin(e.startMinutes)} – ${_fmtMin(e.endMinutes)}',
                                  style: MqType.caption,
                                  color: p.ink3),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ],
        if (_part == _Part.free) ...[
          const MqBanner(
              icon: Icons.info_outline_rounded,
              tone: MqTone.neutral,
              text: 'نوافذ الوقت التي تستطيع فيها الدراسة. المخطِّط لا يضع جلسات خارجها.'),
          const SizedBox(height: 10),
          MqButton(
              label: 'إضافة نافذة',
              icon: Icons.add_rounded,
              kind: MqButtonKind.secondary,
              block: true,
              onPressed: () =>
                  _sheet((_) => _FreeForm(app.studentId!, app.db), 'نافذة فراغ')),
          const SizedBox(height: 10),
          MqAsync<List<Availability>>(
            reloadKey: _tick,
            load: () => AvailabilityRepository(app.db).readForStudent(app.studentId!),
            builder: (c, rows) {
              if (rows.isEmpty) {
                return const MqEmptyState(
                    icon: Icons.schedule_outlined,
                    title: 'لا نوافذ فراغ',
                    message: 'من دونها لا يستطيع المخطِّط وضع جلسات.');
              }
              return Column(children: [
                for (final a in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: MqCard(
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  a.isRecurring
                                      ? 'كل ${_dayName(a.dayOfWeek ?? 7)}'
                                      : (a.specificDate == null
                                          ? 'يوم محدّد'
                                          : _fmtDate(a.specificDate!.toLocal())),
                                  style: MqType.h3.copyWith(color: p.ink)),
                              MqNum(
                                  '${_fmtMin(a.windowStartMinutes)} – ${_fmtMin(a.windowEndMinutes)}',
                                  style: MqType.caption,
                                  color: p.ink3),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ],
        if (_part == _Part.urgent) ...[
          const MqBanner(
              icon: Icons.info_outline_rounded,
              tone: MqTone.neutral,
              text: 'ظرف طارئ يحجز وقتك لفترة محدّدة (مرض، سفر، مناسبة). سجّله ثم أعد تخطيط الأسبوع.'),
          const SizedBox(height: 10),
          MqButton(
              label: 'تسجيل ظرف طارئ',
              icon: Icons.add_rounded,
              block: true,
              onPressed: () =>
                  _sheet((_) => _UrgentForm(app.studentId!, app.db), 'ظرف طارئ')),
          const SizedBox(height: 10),
          MqAsync<List<RealityConstraint>>(
            reloadKey: _tick,
            load: () => RealityConstraintRepository(app.db).readForStudent(app.studentId!),
            builder: (c, rows) {
              if (rows.isEmpty) {
                return const MqEmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'لا ظروف مسجّلة',
                    message: 'ما تسجّله هنا يظهر في القائمة.');
              }
              return Column(children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: MqCard(
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.type == 'unexpectedEvent' ? 'ظرف طارئ' : r.type,
                                  style: MqType.h3.copyWith(color: p.ink)),
                              MqNum(
                                  '${_fmtDate(r.windowStart.toLocal())} → ${_fmtDate(r.windowEnd.toLocal())}',
                                  style: MqType.caption,
                                  color: p.ink3),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ],
        if (_part == _Part.calendar)
          MqAsync<Student?>(
            reloadKey: _tick,
            load: () => StudentRepository(app.db).readExisting(),
            builder: (c, s) {
              if (s == null) return const SizedBox.shrink();
              final yearId = s.currentAcademicYearId;
              final repo = AcademicCalendarRepository(app.db);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MqBanner(
                      icon: Icons.info_outline_rounded,
                      tone: MqTone.neutral,
                      text:
                          'الفصول والعطل تُكتب بيدك من تقويم مؤسستك؛ لا نعرض تواريخ رسمية غير موثّقة.'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: MqButton(
                            label: 'فصل',
                            icon: Icons.add_rounded,
                            kind: MqButtonKind.secondary,
                            onPressed: () => _sheet(
                                (_) => _CalForm(db: app.db, yearId: yearId, holiday: false),
                                'فصل دراسي'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: MqButton(
                            label: 'عطلة',
                            icon: Icons.add_rounded,
                            kind: MqButtonKind.secondary,
                            onPressed: () => _sheet(
                                (_) => _CalForm(db: app.db, yearId: yearId, holiday: true),
                                'عطلة'))),
                  ]),
                  const SizedBox(height: 12),
                  FutureBuilder<List<List<Object>>>(
                    key: ValueKey(_tick),
                    future: Future.wait<List<Object>>([
                      repo.readTerms(yearId),
                      repo.readHolidays(yearId),
                    ]),
                    builder: (c, snap) {
                      if (!snap.hasData) return const MqLoadingCard(lines: 2);
                      final terms = snap.data![0].cast<AcademicTerm>();
                      final hols = snap.data![1].cast<Holiday>();
                      if (terms.isEmpty && hols.isEmpty) {
                        return const MqEmptyState(
                            icon: Icons.calendar_month_outlined,
                            title: 'لا فصول ولا عطل',
                            message: 'أضفها لتظهر تحذيرات الامتحانات الواقعة في العطل.');
                      }
                      Widget row(String name, DateTime a, DateTime b, MqTone t, String tag) =>
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: MqCard(
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: MqType.h3.copyWith(color: p.ink)),
                                      MqNum('${_fmtDate(a.toLocal())} → ${_fmtDate(b.toLocal())}',
                                          style: MqType.caption, color: p.ink3),
                                    ],
                                  ),
                                ),
                                MqChip(label: tag, tone: t),
                              ]),
                            ),
                          );
                      return Column(children: [
                        for (final t in terms)
                          row(t.name, t.startDate, t.endDate, MqTone.brand, 'فصل'),
                        for (final h in hols)
                          row(h.name, h.startDate, h.endDate, MqTone.accent, 'عطلة'),
                      ]);
                    },
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- forms

Future<int?> _pickTime(BuildContext c, int initial) async {
  final t = await showTimePicker(
      context: c,
      initialTime: TimeOfDay(hour: (initial ~/ 60) % 24, minute: initial % 60));
  return t == null ? null : t.hour * 60 + t.minute;
}

Future<DateTime?> _pickDate(BuildContext c, DateTime initial) => showDatePicker(
    context: c,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100));

class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.value, required this.onChanged});
  final int value; // product index, 0 = Sunday
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < 7; i++)
            ChoiceChip(
              label: Text(WeekCalendar.arabicDayNames[i]),
              selected: value == i,
              onSelected: (_) => onChanged(i),
            ),
        ],
      );
}

class _TimeRow extends StatelessWidget {
  const _TimeRow(
      {required this.start, required this.end, required this.onStart, required this.onEnd});
  final int start, end;
  final VoidCallback onStart, onEnd;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: MqButton(
                label: 'من ${_fmtMin(start)}',
                icon: Icons.schedule_rounded,
                kind: MqButtonKind.secondary,
                onPressed: onStart)),
        const SizedBox(width: 10),
        Expanded(
            child: MqButton(
                label: 'إلى ${_fmtMin(end)}',
                icon: Icons.schedule_rounded,
                kind: MqButtonKind.secondary,
                onPressed: onEnd)),
      ]);
}

class _ErrText extends StatelessWidget {
  const _ErrText(this.text);
  final String? text;
  @override
  Widget build(BuildContext context) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(text!, style: MqType.caption.copyWith(color: context.mq.overdue)));
}

class _BlockForm extends StatefulWidget {
  const _BlockForm(this.studentId, this.db);
  final String studentId;
  final AppDatabase db;
  @override
  State<_BlockForm> createState() => _BlockFormState();
}

class _BlockFormState extends State<_BlockForm> {
  int day = 0;
  int start = 8 * 60, end = 12 * 60;
  TimelineBlockKind kind = TimelineBlockKind.school;
  final label = TextEditingController();
  String? err;

  @override
  void dispose() {
    label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await WeeklyTemplateRepository(widget.db).insertFromUser(
        studentId: widget.studentId,
        dayOfWeek: _stored(day),
        startMinutes: start,
        endMinutes: end,
        kind: kind,
        label: label.text.trim().isEmpty ? null : label.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => err = 'تعذّر الحفظ: تحقّق من الوقتين.');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DayPicker(value: day, onChanged: (v) => setState(() => day = v)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _kindLabels.entries)
              ChoiceChip(
                  label: Text(e.value),
                  selected: kind == e.key,
                  onSelected: (_) => setState(() => kind = e.key)),
          ]),
          const SizedBox(height: 12),
          _TimeRow(
            start: start,
            end: end,
            onStart: () async {
              final v = await _pickTime(context, start);
              if (v != null) setState(() => start = v);
            },
            onEnd: () async {
              final v = await _pickTime(context, end);
              if (v != null) setState(() => end = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
              controller: label,
              decoration: const InputDecoration(labelText: 'تسمية (اختياري)')),
          _ErrText(err),
          const SizedBox(height: 14),
          MqButton(label: 'حفظ', block: true, onPressed: _save),
        ],
      );
}

class _FreeForm extends StatefulWidget {
  const _FreeForm(this.studentId, this.db);
  final String studentId;
  final AppDatabase db;
  @override
  State<_FreeForm> createState() => _FreeFormState();
}

class _FreeFormState extends State<_FreeForm> {
  int day = 0;
  int start = 17 * 60, end = 19 * 60;
  bool recurring = true;
  DateTime date = DateTime.now();
  String? err;

  Future<void> _save() async {
    if (end <= start) {
      setState(() => err = 'وقت النهاية يجب أن يكون بعد البداية.');
      return;
    }
    await AvailabilityRepository(widget.db).insert(
      studentId: widget.studentId,
      dayOfWeek: recurring ? _stored(day) : null,
      specificDate: recurring ? null : DateTime(date.year, date.month, date.day),
      windowStartMinutes: start,
      windowEndMinutes: end,
      isRecurring: recurring,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MqSegmented<bool>(
              options: const {true: 'كل أسبوع', false: 'يوم محدّد'},
              selected: recurring,
              onChanged: (v) => setState(() => recurring = v)),
          const SizedBox(height: 12),
          if (recurring)
            _DayPicker(value: day, onChanged: (v) => setState(() => day = v))
          else
            MqButton(
                label: _fmtDate(date),
                icon: Icons.event_rounded,
                kind: MqButtonKind.secondary,
                onPressed: () async {
                  final v = await _pickDate(context, date);
                  if (v != null) setState(() => date = v);
                }),
          const SizedBox(height: 12),
          _TimeRow(
            start: start,
            end: end,
            onStart: () async {
              final v = await _pickTime(context, start);
              if (v != null) setState(() => start = v);
            },
            onEnd: () async {
              final v = await _pickTime(context, end);
              if (v != null) setState(() => end = v);
            },
          ),
          _ErrText(err),
          const SizedBox(height: 14),
          MqButton(label: 'حفظ', block: true, onPressed: _save),
        ],
      );
}

class _UrgentForm extends StatefulWidget {
  const _UrgentForm(this.studentId, this.db);
  final String studentId;
  final AppDatabase db;
  @override
  State<_UrgentForm> createState() => _UrgentFormState();
}

class _UrgentFormState extends State<_UrgentForm> {
  DateTime from = DateTime.now();
  DateTime to = DateTime.now().add(const Duration(days: 1));
  String? err;

  Future<void> _save() async {
    if (to.isBefore(from)) {
      setState(() => err = 'النهاية يجب ألا تسبق البداية.');
      return;
    }
    await RealityConstraintRepository(widget.db).insertFromUser(
      studentId: widget.studentId,
      type: 'unexpectedEvent',
      windowStart: DateTime(from.year, from.month, from.day),
      windowEnd: DateTime(to.year, to.month, to.day, 23, 59),
      isHard: true,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MqButton(
              label: 'من ${_fmtDate(from)}',
              icon: Icons.event_rounded,
              kind: MqButtonKind.secondary,
              block: true,
              onPressed: () async {
                final v = await _pickDate(context, from);
                if (v != null) setState(() => from = v);
              }),
          const SizedBox(height: 10),
          MqButton(
              label: 'إلى ${_fmtDate(to)}',
              icon: Icons.event_rounded,
              kind: MqButtonKind.secondary,
              block: true,
              onPressed: () async {
                final v = await _pickDate(context, to);
                if (v != null) setState(() => to = v);
              }),
          _ErrText(err),
          const SizedBox(height: 14),
          MqButton(label: 'حفظ', block: true, onPressed: _save),
        ],
      );
}

class _CalForm extends StatefulWidget {
  const _CalForm({required this.db, required this.yearId, required this.holiday});
  final AppDatabase db;
  final String yearId;
  final bool holiday;
  @override
  State<_CalForm> createState() => _CalFormState();
}

class _CalFormState extends State<_CalForm> {
  final name = TextEditingController();
  DateTime from = DateTime.now();
  DateTime to = DateTime.now().add(const Duration(days: 14));
  String? err;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final r = AcademicCalendarRepository(widget.db);
      if (widget.holiday) {
        await r.insertHolidayFromUser(
            academicYearId: widget.yearId, name: name.text, startDate: from, endDate: to);
      } else {
        await r.insertTerm(
            academicYearId: widget.yearId, name: name.text, startDate: from, endDate: to);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => err = 'تحقّق من الاسم والتاريخين.');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: name,
              decoration: InputDecoration(
                  labelText: widget.holiday ? 'اسم العطلة' : 'اسم الفصل')),
          const SizedBox(height: 10),
          MqButton(
              label: 'من ${_fmtDate(from)}',
              icon: Icons.event_rounded,
              kind: MqButtonKind.secondary,
              block: true,
              onPressed: () async {
                final v = await _pickDate(context, from);
                if (v != null) setState(() => from = v);
              }),
          const SizedBox(height: 10),
          MqButton(
              label: 'إلى ${_fmtDate(to)}',
              icon: Icons.event_rounded,
              kind: MqButtonKind.secondary,
              block: true,
              onPressed: () async {
                final v = await _pickDate(context, to);
                if (v != null) setState(() => to = v);
              }),
          _ErrText(err),
          const SizedBox(height: 14),
          MqButton(label: 'حفظ', block: true, onPressed: _save),
        ],
      );
}
