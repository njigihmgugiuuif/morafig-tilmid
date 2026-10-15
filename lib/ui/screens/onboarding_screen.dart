import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../domain/enums.dart';
import '../../engines/weekly_timeline_engine.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/exam_repository.dart';
import '../../repositories/goal_repository.dart';
import '../../repositories/student_repository.dart';
import '../../repositories/weekly_template_repository.dart';
import '../../services/intelligence_service.dart';
import '../../services/student_setup_store.dart';
import '../../services/teacher_session.dart';
import '../design/logo.dart';
import '../design/motion.dart';
import '../design/primitives.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';
import '../widgets/backup_restore_flow.dart';
import '../widgets/exit_confirm_scope.dart';

enum _GoalKind { exam, general, later }

/// First-run flow (D-1 S01 + the four setup steps S02a / S02 / S02c / S02d).
/// Shown only when no Student row exists yet.
///
///   0  البداية        identity, promise, «ابدأ الآن», «لدي نسخة احتياطية»
///   1  الاسم          1/5
///   2  السنة والشعبة  2/5  year (1/2/3 ثانوي) + stream/section as FREE text;
///                          «تخطي» is always available
///   3  النوم          3/5  minimum sleep (the hard floor no plan may break)
///   4  الالتزامات     4/5  recurring busy times the planner must respect
///   5  أول هدف        5/5  upcoming exam / general goal / later
///
/// Progress is saved after every change (device storage), so closing the app
/// and opening it again resumes where the student stopped.
///
/// Nothing is assumed about the curriculum: the level list contains only what
/// is stored, and a date or subject is entered by the student and kept as
/// theirs. Back goes one step back with the typed values kept (D-2 X01);
/// from the first screen it asks before leaving.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  final _nameController = TextEditingController();
  final _subjectController = TextEditingController();
  final _goalTitleController = TextEditingController();

  final _trackController = TextEditingController();
  int _sleepHours = 7;
  int? _year;
  final List<DraftCommitment> _commitments = [];
  _GoalKind _goalKind = _GoalKind.exam;
  DateTime? _goalDate;
  String? _stepError;
  bool _resumed = false;

  final _draftStore = OnboardingDraftStore(SharedPrefsKeyValueStore());

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    for (final c in [
      _nameController,
      _subjectController,
      _goalTitleController,
      _trackController,
    ]) {
      c.addListener(_persist);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    _goalTitleController.dispose();
    _trackController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------- saved progress

  bool _restoring = false;

  Future<void> _restoreDraft() async {
    _restoring = true;
    final d = await _draftStore.read();
    if (!mounted) return;
    if (d != null) {
      setState(() {
        _nameController.text = d.name;
        _subjectController.text = d.subject;
        _goalTitleController.text = d.goalTitle;
        _trackController.text = d.track;
        _sleepHours = d.sleepHours;
        _year = d.year;
        _commitments
          ..clear()
          ..addAll(d.commitments);
        _goalKind = _GoalKind.values.firstWhere((k) => k.name == d.goalKind,
            orElse: () => _GoalKind.exam);
        _goalDate = d.goalDate;
        if (d.step > 0) {
          _step = d.step;
          _resumed = true;
        }
      });
    }
    _restoring = false;
  }

  /// Saves everything typed so far. Failures are ignored: saving progress
  /// must never block the journey.
  void _persist() {
    if (_restoring) return;
    _draftStore
        .write(OnboardingDraft(
          step: _step,
          name: _nameController.text,
          sleepHours: _sleepHours,
          year: _year,
          track: _trackController.text,
          commitments: List.of(_commitments),
          goalKind: _goalKind.name,
          subject: _subjectController.text,
          goalTitle: _goalTitleController.text,
          goalDate: _goalDate,
        ))
        .catchError((_) {});
  }

  // ------------------------------------------------------------------ nav

  void _go(int step) {
    setState(() {
      _stepError = null;
      _resumed = false;
      _step = step;
    });
    _persist();
  }

  void _next() {
    if (_step == 1 && _nameController.text.trim().isEmpty) {
      setState(() => _stepError = 'الرجاء إدخال اسمك.');
      return;
    }
    _go(_step + 1);
  }

  void _back() {
    if (_step > 0) {
      _go(_step - 1);
    } else {
      _confirmExit();
    }
  }

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الخروج من الإعداد الأولي؟'),
        content: const Text(
          'لم يكتمل إنشاء ملفك الدراسي بعد. ما أدخلته محفوظ، وستكمل '
          'من حيث توقفت عند فتح التطبيق مرة أخرى.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('البقاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    if (leave == true && !exitAppIfPossible() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'تقدّمك محفوظ. اضغط زر الصفحة الرئيسية في هاتفك أو أغلق التبويب.'),
      ));
    }
  }

  // --------------------------------------------------------------- finish

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _goalDate ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => _goalDate = picked);
      _persist();
    }
  }

  Future<void> _finish() async {
    // Validate the goal the student chose BEFORE creating anything.
    if (_goalKind == _GoalKind.exam) {
      if (_subjectController.text.trim().isEmpty || _goalDate == null) {
        setState(() =>
            _stepError = 'أدخل مادة الامتحان وتاريخه، أو اختر «لاحقًا».');
        return;
      }
    } else if (_goalKind == _GoalKind.general) {
      if (_goalTitleController.text.trim().isEmpty) {
        setState(() => _stepError = 'اكتب هدفك، أو اختر «لاحقًا».');
        return;
      }
    }
    setState(() => _stepError = null);

    final appState = context.read<AppState>();
    final db = appState.db;
    final messenger = ScaffoldMessenger.of(context);
    final repo = StudentRepository(db);

    // 1) The student itself. A retry after a half-finished run reuses the
    //    row that was already created instead of failing.
    final Student student;
    try {
      student = await repo.readExisting() ??
          await repo.createInitialStudent(
            fullNameOrNickname: _nameController.text.trim(),
            sleepFloorMinMinutes: _sleepHours * 60,
          );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('تعذّر إنشاء الملف: $e')));
      return;
    }

    // 2) Optional parts. Each is independent: a failure in one is reported
    //    and never blocks entering the app (the student exists already, and
    //    everything here can be entered again later).
    final problems = <String>[];

    // Year and stream (free text) are kept on this device.
    try {
      await StudentSetupStore(SharedPrefsKeyValueStore()).save(StudentSetup(
          year: _year, track: _trackController.text.trim()));
      if (_year != null) appState.autoSync.trigger(force: true);
    } catch (e) {
      problems.add('السنة والشعبة: $e');
    }

    // Recurring busy times: stored for the planner (hard blocks).
    final templates = WeeklyTemplateRepository(db);
    for (final c in _commitments) {
      try {
        await templates.insertFromUser(
          studentId: student.id,
          dayOfWeek: c.day == 0 ? 7 : c.day,
          startMinutes: c.startMinutes,
          endMinutes: c.endMinutes,
          kind: TimelineBlockKind.commitment,
          label: c.label.trim().isEmpty ? null : c.label.trim(),
        );
      } catch (e) {
        problems.add('التزام ${WeekCalendar.arabicDayNames[c.day]}: $e');
      }
    }

    try {
      if (_goalKind == _GoalKind.exam) {
        final content = ContentRepository(db);
        final level = await content.getOrCreateDefaultLevel();
        final subject = await content.getOrCreateSubject(
          educationLevelId: level.id,
          name: _subjectController.text,
        );
        await ExamRepository(db).insert(
          subjectId: subject.id,
          examDate: _goalDate!,
          // The same default the «امتحان جديد» form of the app uses; the
          // first-run screen does not ask for a type.
          examType: ExamType.summative,
        );
        try {
          await IntelligenceService(db).refreshPriorities();
        } catch (_) {
          // Priorities are recomputed on the next processing run anyway.
        }
      } else if (_goalKind == _GoalKind.general) {
        String? subjectId;
        if (_subjectController.text.trim().isNotEmpty) {
          final content = ContentRepository(db);
          final level = await content.getOrCreateDefaultLevel();
          subjectId = (await content.getOrCreateSubject(
            educationLevelId: level.id,
            name: _subjectController.text,
          ))
              .id;
        }
        await GoalRepository(db).insertFromUser(
          studentId: student.id,
          title: _goalTitleController.text,
          subjectId: subjectId,
          targetDate: _goalDate,
        );
      }
    } catch (e) {
      problems.add('الهدف: $e');
    }

    if (problems.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text('تم إنشاء ملفك، لكن: ${problems.join(' — ')}. '
            'يمكنك إدخال ذلك لاحقًا.'),
        duration: const Duration(seconds: 6),
      ));
    }
    await _draftStore.clear();
    await appState.setStudentId(student.id);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _back();
      },
      child: AnimatedSwitcher(
        duration: MqMotion.of(context, MqMotion.base),
        child: KeyedSubtree(
          key: ValueKey<int>(_step),
          child: _step == 0 ? _welcome(context) : _stepPage(context),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- welcome

  Widget _welcome(BuildContext context) {
    const deep = Color(0xFF064B4D);
    const soft = Color(0xC7FFFFFF);
    return Scaffold(
      backgroundColor: deep,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      MqChip(
                          label: 'يعمل دون إنترنت',
                          icon: Icons.cloud_off_outlined,
                          onHero: true),
                      MqChip(
                          label: 'بياناتك على جهازك',
                          icon: Icons.lock_outline_rounded,
                          onHero: true),
                    ],
                  ),
                  const SizedBox(height: 44),
                  const Center(
                      child: MqLogo(size: 112, animate: true, onDark: true)),
                  const SizedBox(height: 22),
                  Text('ثانوية رابح بطاط',
                      textAlign: TextAlign.center,
                      style: MqType.label.copyWith(color: soft)),
                  const SizedBox(height: 4),
                  Text('مرافق التلميذ',
                      textAlign: TextAlign.center,
                      style: MqType.display
                          .copyWith(color: Colors.white, fontSize: 40)),
                  const SizedBox(height: 6),
                  Text('المرافقة والتنظيم الدراسي طوال العام',
                      textAlign: TextAlign.center,
                      style: MqType.small.copyWith(color: soft)),
                  const SizedBox(height: 26),
                  Text('يعرف ما تحتاج إلى دراسته الآن، ويشرح لك لماذا.',
                      textAlign: TextAlign.center,
                      style: MqType.h3.copyWith(color: Colors.white)),
                  const SizedBox(height: 20),
                  const _Point(
                      icon: Icons.track_changes_rounded,
                      text: 'يرصد ما أتقنته وما ضعف فيه'),
                  const _Point(
                      icon: Icons.layers_outlined, text: 'ينبّهك قبل أن تنسى'),
                  const _Point(
                      icon: Icons.autorenew_rounded,
                      text: 'يعيد ترتيب خطتك حين تتغير ظروفك'),
                  const SizedBox(height: 28),
                  MqButton(
                    label: 'ابدأ الآن',
                    icon: Icons.arrow_forward_rounded,
                    kind: MqButtonKind.accent,
                    block: true,
                    onPressed: () => _go(1),
                  ),
                  const SizedBox(height: 10),
                  MqButton(
                    label: 'لدي نسخة احتياطية',
                    icon: Icons.restore_rounded,
                    kind: MqButtonKind.outlineOnHero,
                    block: true,
                    onPressed: () async {
                      await restoreBackupFromClipboard(
                          context, context.read<AppState>());
                    },
                  ),
                  const SizedBox(height: 4),
                  Text('يمكن تثبيته على الشاشة الرئيسية كتطبيق',
                      textAlign: TextAlign.center,
                      style: MqType.caption.copyWith(color: soft)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- steps

  Widget _stepPage(BuildContext context) {
    final p = context.mq;
    final Widget body;
    final String title;
    final String subtitle;
    switch (_step) {
      case 1:
        title = 'أهلًا بك، ما اسمك؟';
        subtitle = 'اسم أو لقب نناديك به. يبقى على جهازك ولا يغادره.';
        body = _nameStep();
        break;
      case 2:
        title = 'في أي سنة أنت؟';
        subtitle = 'تصلك دروس أساتذتك لسنتك تلقائيًا. يمكنك تغييرها لاحقًا.';
        body = _yearStep();
        break;
      case 3:
        title = 'نومك';
        subtitle = 'نبني خطتك حول حياتك، لا العكس.';
        body = _sleepStep();
        break;
      case 4:
        title = 'متى تكون مشغولًا؟';
        subtitle = 'أدخل أوقاتك الثابتة (دروس خاصة، رياضة، التزامات) '
            'حتى لا نضع لك دراسة فيها.';
        body = _commitmentsStep();
        break;
      default:
        title = 'ما أول ما تريد الوصول إليه؟';
        subtitle = 'اختر ما يهمك الآن، وسنرتّب الأولويات حوله.';
        body = _goalStep();
    }
    final isLast = _step == 5;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  MqSpace.screen, 12, MqSpace.screen, 8),
              child: Row(
                children: [
                  MqIconButton(
                      icon: Icons.arrow_back_rounded,
                      label: 'رجوع',
                      onTap: _back),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 1; i <= 5; i++)
                          Expanded(
                            child: AnimatedContainer(
                              duration: MqMotion.of(context, MqMotion.base),
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: i <= _step ? p.brand : p.line,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  MqNum('$_step/5',
                      style: MqType.caption.copyWith(color: p.ink3)),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(title, style: MqType.h1.copyWith(color: p.ink)),
                        const SizedBox(height: 6),
                        Text(subtitle,
                            style: MqType.small.copyWith(color: p.ink2)),
                        const SizedBox(height: 22),
                        if (_resumed) ...[
                          const MqBanner(
                            icon: Icons.history_rounded,
                            tone: MqTone.brand,
                            text: 'أكملنا من حيث توقفت. ما أدخلته سابقًا محفوظ.',
                          ),
                          const SizedBox(height: 14),
                        ],
                        body,
                        if (_stepError != null) ...[
                          const SizedBox(height: 12),
                          MqBanner(
                            icon: Icons.error_outline_rounded,
                            tone: MqTone.overdue,
                            text: _stepError!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: isLast
                    ? MqButton(
                        label: 'ابدأ رحلتك',
                        icon: Icons.arrow_forward_rounded,
                        kind: MqButtonKind.accent,
                        block: true,
                        onPressed: _finish,
                      )
                    : Row(
                        children: [
                          if (_step >= 2 && _step <= 4) ...[
                            MqButton(
                              label: _step == 2
                                  ? 'تخطي'
                                  : (_step == 4 ? 'لا التزامات الآن' : 'لاحقًا'),
                              kind: MqButtonKind.ghost,
                              onPressed: () {
                                if (_step == 2) {
                                  _year = null;
                                  _trackController.clear();
                                }
                                _next();
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: MqButton(
                              label: 'التالي',
                              icon: Icons.arrow_forward_rounded,
                              block: true,
                              onPressed: _next,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _next(),
          decoration: const InputDecoration(
            labelText: 'الاسم أو اللقب',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 16),
        const MqBanner(
          icon: Icons.lock_outline_rounded,
          tone: MqTone.brand,
          title: 'بياناتك لك وحدك',
          text: 'كل ما تدخله يُحفظ على هذا الجهاز، ويعمل التطبيق دون إنترنت. '
              'يمكنك أخذ نسخة احتياطية في أي وقت.',
        ),
        const SizedBox(height: 10),
        const MqBanner(
          icon: Icons.info_outline_rounded,
          tone: MqTone.neutral,
          text: 'سنسأل عن سنتك وشعبتك ونومك وأوقات انشغالك وأول هدف، وكلها '
              'قابلة للتغيير لاحقًا من الإعدادات.',
        ),
      ],
    );
  }

  Widget _yearStep() {
    final p = context.mq;
    const labels = {1: 'الأولى ثانوي', 2: 'الثانية ثانوي', 3: 'الثالثة ثانوي'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in labels.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MqPressable(
              onTap: () {
                setState(() => _year = e.key);
                _persist();
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _year == e.key ? p.brandSoft : p.surface,
                  borderRadius: BorderRadius.circular(MqSpace.radiusButton),
                  border: Border.all(
                      color: _year == e.key ? p.brand : p.line,
                      width: _year == e.key ? 2.5 : 1),
                ),
                child: Row(
                  children: [
                    Icon(
                        _year == e.key
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 28,
                        color: _year == e.key ? p.brand : p.ink3),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(e.value,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: _year == e.key ? p.brandInk : p.ink)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        TextField(
          controller: _trackController,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'الشعبة أو القسم (اكتبها بنفسك)',
            hintText: 'مثال: جذع مشترك علوم وتكنولوجيا · 2 علوم تجريبية',
            prefixIcon: Icon(Icons.edit_note_rounded),
          ),
        ),
        const SizedBox(height: 16),
        const MqBanner(
          icon: Icons.verified_outlined,
          tone: MqTone.neutral,
          text: 'لا نفترض لك منهجًا ولا قائمة شعب. المعاملات والساعات الرسمية '
              'لا تظهر في التطبيق إلا إذا وُثّقت من مصدر رسمي.',
        ),
      ],
    );
  }

  String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _addCommitment() async {
    var day = 0;
    var start = 16 * 60;
    var end = 17 * 60;
    final label = TextEditingController();
    String? err;
    final saved = await showModalBottomSheet<DraftCommitment>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('إضافة وقت مشغول', style: MqType.h2),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < 7; i++)
                    ChoiceChip(
                      label: Text(WeekCalendar.arabicDayNames[i]),
                      selected: day == i,
                      onSelected: (_) => setSheet(() => day = i),
                    ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: MqButton(
                      label: 'من ${_fmt(start)}',
                      icon: Icons.schedule_rounded,
                      kind: MqButtonKind.secondary,
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay(
                                hour: start ~/ 60, minute: start % 60));
                        if (t != null) {
                          setSheet(() => start = t.hour * 60 + t.minute);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MqButton(
                      label: 'إلى ${_fmt(end)}',
                      icon: Icons.schedule_rounded,
                      kind: MqButtonKind.secondary,
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx,
                            initialTime:
                                TimeOfDay(hour: end ~/ 60, minute: end % 60));
                        if (t != null) {
                          setSheet(() => end = t.hour * 60 + t.minute);
                        }
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: label,
                  decoration: const InputDecoration(
                      labelText: 'ما هو؟ (اختياري)',
                      hintText: 'مثال: دروس خاصة، رياضة'),
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(err!,
                        style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                  ),
                const SizedBox(height: 14),
                MqButton(
                  label: 'أضف',
                  block: true,
                  onPressed: () {
                    if (end <= start) {
                      setSheet(() => err = 'وقت النهاية يجب أن يكون بعد البداية.');
                      return;
                    }
                    Navigator.of(ctx).pop(DraftCommitment(
                        day: day,
                        startMinutes: start,
                        endMinutes: end,
                        label: label.text.trim()));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    label.dispose();
    if (saved != null && mounted) {
      setState(() => _commitments.add(saved));
      _persist();
    }
  }

  Widget _commitmentsStep() {
    final p = context.mq;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_commitments.isEmpty)
          const MqBanner(
            icon: Icons.info_outline_rounded,
            tone: MqTone.neutral,
            text: 'لم تُضف شيئًا بعد. يمكنك المتابعة، وإضافة جدولك وأوقاتك '
                'لاحقًا من «واقعي» في قائمة المزيد.',
          )
        else
          for (var i = 0; i < _commitments.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MqCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.block_rounded, color: p.ink2),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${WeekCalendar.arabicDayNames[_commitments[i].day]} · '
                        '${_fmt(_commitments[i].startMinutes)}–${_fmt(_commitments[i].endMinutes)}'
                        '${_commitments[i].label.isEmpty ? '' : ' · ${_commitments[i].label}'}',
                        style: MqType.body.copyWith(color: p.ink),
                      ),
                    ),
                    MqIconButton(
                      icon: Icons.close_rounded,
                      label: 'احذف',
                      onTap: () {
                        setState(() => _commitments.removeAt(i));
                        _persist();
                      },
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 8),
        MqButton(
          label: 'أضف وقتًا مشغولًا',
          icon: Icons.add_rounded,
          kind: MqButtonKind.secondary,
          block: true,
          onPressed: _addCommitment,
        ),
        const SizedBox(height: 16),
        const MqBanner(
          icon: Icons.lock_outline_rounded,
          tone: MqTone.brand,
          text: 'هذه الأوقات تُحفظ على جهازك، ولا يضع المخطِّط دراسة داخلها.',
        ),
      ],
    );
  }

  Widget _sleepStep() {
    final p = context.mq;
    return MqCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text('أقل مدة نوم لا تريد أن تنقص عنها',
              style: MqType.h3.copyWith(color: p.ink)),
          const SizedBox(height: 2),
          Text('الخطة لا تمسّها أبدًا، حتى في وضع الطوارئ.',
              style: MqType.caption.copyWith(color: p.ink3)),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MqIconButton(
                icon: Icons.remove_rounded,
                label: 'أنقص',
                onTap: _sleepHours > 5
                    ? () {
                        setState(() => _sleepHours--);
                        _persist();
                      }
                    : null,
              ),
              const SizedBox(width: 24),
              Column(
                children: [
                  MqNum('$_sleepHours',
                      style: MqType.display.copyWith(fontSize: 56)),
                  Text('ساعات', style: MqType.caption.copyWith(color: p.ink3)),
                ],
              ),
              const SizedBox(width: 24),
              MqIconButton(
                icon: Icons.add_rounded,
                label: 'زِد',
                onTap: _sleepHours < 10
                    ? () {
                        setState(() => _sleepHours++);
                        _persist();
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _goalStep() {
    final p = context.mq;
    final dateText = _goalDate == null
        ? 'اختر التاريخ'
        : '${_goalDate!.day}/${_goalDate!.month}/${_goalDate!.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MqSegmented<_GoalKind>(
          options: const {
            _GoalKind.exam: 'امتحان قادم',
            _GoalKind.general: 'هدف عام',
            _GoalKind.later: 'لاحقًا',
          },
          selected: _goalKind,
          onChanged: (v) {
            setState(() {
              _goalKind = v;
              _stepError = null;
            });
            _persist();
          },
        ),
        const SizedBox(height: 18),
        if (_goalKind == _GoalKind.later)
          const MqBanner(
            icon: Icons.schedule_rounded,
            tone: MqTone.neutral,
            text: 'لا بأس. يمكنك إضافة امتحان أو هدف في أي وقت.',
          )
        else ...[
          if (_goalKind == _GoalKind.general) ...[
            TextField(
              controller: _goalTitleController,
              decoration: const InputDecoration(labelText: 'هدفك'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _subjectController,
            decoration: InputDecoration(
              labelText: _goalKind == _GoalKind.exam
                  ? 'مادة الامتحان'
                  : 'المادة (اختياري)',
            ),
          ),
          const SizedBox(height: 12),
          MqPressable(
            onTap: _pickDate,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(MqSpace.radiusButton),
                border: Border.all(color: p.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_outlined, color: p.ink2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _goalKind == _GoalKind.exam
                          ? 'تاريخ الامتحان: $dateText'
                          : 'تاريخ مستهدف (اختياري): $dateText',
                      style: MqType.body.copyWith(
                          color: _goalDate == null ? p.ink3 : p.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0x29FFFFFF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: MqType.body.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
