import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../domain/enums.dart';
import '../../domain/exam_link_domain.dart';
import '../../repositories/academic_calendar_repository.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/exam_repository.dart';
import '../../repositories/goal_repository.dart';
import '../../repositories/student_repository.dart';
import '../../services/intelligence_service.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/sheet.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';

class _ExamRow {
  const _ExamRow(this.exam, this.subjectName, this.context);
  final Exam exam;
  final String subjectName;

  /// Null when the student has no academic year yet (nothing to link to).
  final ExamContext? context;
}

/// «الامتحانات والاستحقاقات» (D-1 S07, D-2 Q03): upcoming exams, each with the
/// context the data already holds (term, holiday, active goals) and the
/// warnings ExamLinkService reports. It never moves an exam or decides
/// anything: a suspicious date is shown, not corrected.
class ExamsScreen extends StatefulWidget {
  const ExamsScreen({super.key});
  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  int _tick = 0;

  Future<List<_ExamRow>> _load(AppDatabase db) async {
    final student = await StudentRepository(db).readExisting();
    final examRepo = ExamRepository(db);
    final now = DateTime.now().toUtc();
    final exams = await examRepo.readUpcoming(now: now);
    final service = ExamLinkService(
        examRepo, GoalRepository(db), AcademicCalendarRepository(db));
    final rows = <_ExamRow>[];
    for (final e in exams) {
      final subject = await (db.select(db.subjects)
            ..where((t) => t.id.equals(e.subjectId)))
          .getSingleOrNull();
      ExamContext? ctx;
      if (student != null) {
        ctx = await service.contextFor(e,
            studentId: student.id,
            academicYearId: student.currentAcademicYearId,
            studentLevelId: student.educationLevelId);
      }
      rows.add(_ExamRow(e, subject?.name ?? '', ctx));
    }
    return rows;
  }

  Future<void> _add() async {
    final ok = await showMqSheet<bool>(
      context,
      title: 'امتحان جديد',
      builder: (ctx) => const _AddExamBody(),
    );
    if (ok == true && mounted) setState(() => _tick++);
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppState>().db;
    final p = context.mq;
    return MqPage(
      title: 'الامتحانات',
      caption: 'والاستحقاقات',
      floating: MqFab(label: 'امتحان جديد', icon: Icons.add_rounded, onPressed: _add),
      reveal: false,
      bodyBuilder: (context) => MqAsync<List<_ExamRow>>(
        reloadKey: _tick,
        load: () => _load(db),
        loading: const Padding(
            padding: EdgeInsets.all(MqSpace.screen), child: MqLoadingCard(lines: 3)),
        errorTitle: 'تعذّر عرض الامتحانات',
        builder: (context, rows) {
          if (rows.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(MqSpace.screen),
              children: [
                MqEmptyState(
                  icon: Icons.event_note_rounded,
                  title: 'لا امتحانات مسجّلة',
                  message: 'أضف امتحانًا وسنقرّب أولوية موادّه كلما اقترب موعده.',
                  actionLabel: 'امتحان جديد',
                  onAction: _add,
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                MqSpace.screen, 4, MqSpace.screen, 96),
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ExamCard(row: r),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _typeLabel(String type) {
  switch (type) {
    case 'bac':
      return 'بكالوريا';
    case 'summative':
      return 'فرض / اختبار فصلي';
    default:
      return 'تقييم مستمر';
  }
}

String _warningText(String code) {
  switch (code) {
    case 'exam_on_holiday':
      return 'يقع في يوم عطلة مسجّلة.';
    case 'exam_outside_terms':
      return 'يقع خارج الفصول المسجّلة.';
    case 'exam_level_differs_from_student':
      return 'مستوى مادته يختلف عن مستواك المسجّل.';
    default:
      return code;
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.row});
  final _ExamRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final e = row.exam;
    final local = e.examDate.toLocal();
    final today = DateTime.now();
    final days = DateTime(local.year, local.month, local.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    final near = days <= 3;
    final tone = p.toneFor(row.subjectName);
    final warnings = row.context?.warnings ?? const <String>[];
    return MqCard(
      onTap: () => _showDetail(context, row),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: near ? p.overdueSoft : tone.soft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    MqNum(days <= 0 ? '0' : '$days',
                        style: MqType.display.copyWith(fontSize: 22),
                        color: near ? p.overdue : tone.color),
                    Text('يوم', style: MqType.caption.copyWith(color: p.ink3, height: 1)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.subjectName.isEmpty ? 'مادة' : row.subjectName,
                        style: MqType.h3.copyWith(color: p.ink)),
                    Text(_typeLabel(e.examType),
                        style: MqType.caption.copyWith(color: p.ink3)),
                    MqNum('${local.day}/${local.month}/${local.year}',
                        style: MqType.small.copyWith(color: p.ink2)),
                  ],
                ),
              ),
            ],
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: MqChip(
                    label: _warningText(w),
                    icon: Icons.warning_amber_rounded,
                    tone: MqTone.accent),
              ),
          ],
        ],
      ),
    );
  }
}

void _showDetail(BuildContext context, _ExamRow row) {
  final c = row.context;
  showMqSheet<void>(
    context,
    title: row.subjectName.isEmpty ? 'الامتحان' : row.subjectName,
    subtitle: _typeLabel(row.exam.examType),
    builder: (ctx) {
      final p = ctx.mq;
      if (c == null) {
        return const MqBanner(
          icon: Icons.info_outline_rounded,
          tone: MqTone.neutral,
          text:
              'لا سنة دراسية مرتبطة بملفك بعد، لذلك لا نعرض فصلًا ولا عطلًا لهذا الامتحان.',
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              c.term == null ? 'لا فصل يحوي هذا اليوم.' : 'الفصل: ${c.term!.name}',
              style: MqType.body.copyWith(color: p.ink)),
          const SizedBox(height: 8),
          Text(
              c.holidays.isEmpty
                  ? 'لا عطلة في هذا اليوم.'
                  : 'عطلة: ${c.holidays.map((h) => h.name).join('، ')}',
              style: MqType.body.copyWith(color: p.ink)),
          const SizedBox(height: 8),
          Text(
              c.activeGoals.isEmpty
                  ? 'لا أهداف فعّالة على هذه المادة.'
                  : 'أهداف فعّالة: ${c.activeGoals.map((g) => g.title).join('، ')}',
              style: MqType.body.copyWith(color: p.ink)),
          const SizedBox(height: 10),
          Text('الأهداف تُسجَّل وتُعرض، ولا تغيّر الأولوية بعد.',
              style: MqType.caption.copyWith(color: p.ink3)),
        ],
      );
    },
  );
}

class _AddExamBody extends StatefulWidget {
  const _AddExamBody();
  @override
  State<_AddExamBody> createState() => _AddExamBodyState();
}

class _AddExamBodyState extends State<_AddExamBody> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 7));
  ExamType _type = ExamType.summative;

  @override
  void dispose() {
    _subject.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final db = context.read<AppState>().db;
    final content = ContentRepository(db);
    final level = await content.getOrCreateDefaultLevel();
    final subject = await content.getOrCreateSubject(
      educationLevelId: level.id,
      name: _subject.text,
    );
    await ExamRepository(db).insert(
      subjectId: subject.id,
      examDate: _date,
      examType: _type,
    );
    await IntelligenceService(db).refreshPriorities();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'المادة'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'أدخل اسم المادة' : null,
          ),
          const SizedBox(height: 12),
          MqPressable(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(MqSpace.radiusButton),
                border: Border.all(color: p.line),
              ),
              child: Row(children: [
                Icon(Icons.event_outlined, color: p.ink2),
                const SizedBox(width: 12),
                Text('التاريخ: ', style: MqType.body.copyWith(color: p.ink2)),
                MqNum('${_date.day}/${_date.month}/${_date.year}',
                    style: MqType.body),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          MqSegmented<ExamType>(
            options: const {
              ExamType.summative: 'فصلي',
              ExamType.formative: 'مستمر',
              ExamType.bac: 'بكالوريا',
            },
            selected: _type,
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 16),
          MqButton(label: 'إضافة', icon: Icons.add_rounded, block: true, onPressed: _submit),
        ],
      ),
    );
  }
}
