import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../domain/enums.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/exam_repository.dart';
import '../../repositories/goal_repository.dart';
import '../../repositories/student_repository.dart';
import '../../services/intelligence_service.dart';
import '../design/logo.dart';
import '../design/motion.dart';
import '../design/primitives.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';
import '../teacher/teacher_entry_screen.dart';
import '../widgets/backup_restore_flow.dart';

enum _GoalKind { exam, general, later }

/// First-run flow (D-1 S01 + the four setup steps S02a / S02 / S02c / S02d).
/// Shown only when no Student row exists yet.
///
///   0  البداية        identity, promise, «ابدأ الآن», «لدي نسخة احتياطية»
///   1  الاسم          1/4
///   2  المسار         2/4  level and stream — only from rows that exist;
///                          «تخطي» is always available
///   3  النوم          3/4  minimum sleep (the hard floor no plan may break)
///   4  أول هدف        4/4  upcoming exam / general goal / later
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

  int _sleepHours = 7;
  String? _levelId;
  String? _streamId;
  _GoalKind _goalKind = _GoalKind.exam;
  DateTime? _goalDate;
  String? _stepError;

  Future<List<EducationLevel>>? _levelsFuture;

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    _goalTitleController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ nav

  void _go(int step) => setState(() {
        _stepError = null;
        _step = step;
      });

  void _next() {
    if (_step == 1 && _nameController.text.trim().isEmpty) {
      setState(() => _stepError = 'الرجاء إدخال اسمك.');
      return;
    }
    if (_step == 1) {
      // Read the stored levels once, when the track step is first reached.
      final db = context.read<AppState>().db;
      _levelsFuture ??= (db.select(db.educationLevels)
            ..orderBy([(t) => OrderingTerm.asc(t.order)]))
          .get();
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
          'لم يتم إنشاء ملفك الدراسي بعد. سيتعين عليك إكمال هذه '
          'الخطوة عند فتح التطبيق مرة أخرى.',
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
    if (leave == true) SystemNavigator.pop();
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
    if (picked != null && mounted) setState(() => _goalDate = picked);
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

    if (_levelId != null) {
      try {
        await repo.setAcademicTrack(
          studentId: student.id,
          educationLevelId: _levelId!,
          streamId: _streamId,
        );
      } catch (e) {
        problems.add('المسار الدراسي: $e');
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
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton.icon(
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white70),
                      // A teacher may use this device without being a
                      // student: the teacher entry is a separate door.
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const TeacherEntryScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.shield_outlined, size: 18),
                      label: const Text('أنا أستاذ: مدخل الأستاذ'),
                    ),
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
        title = 'ما مسارك الدراسي؟';
        subtitle = 'نستعمله لتنظيم موادك فقط. يمكنك تغييره أو تركه لاحقًا.';
        body = _trackStep();
        break;
      case 3:
        title = 'نومك ووقتك';
        subtitle = 'نبني خطتك حول حياتك، لا العكس.';
        body = _sleepStep();
        break;
      default:
        title = 'ما أول ما تريد الوصول إليه؟';
        subtitle = 'اختر ما يهمك الآن، وسنرتّب الأولويات حوله.';
        body = _goalStep();
    }
    final isLast = _step == 4;
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
                        for (var i = 1; i <= 4; i++)
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
                  MqNum('$_step/4',
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
                          if (_step == 2 || _step == 3) ...[
                            MqButton(
                              label: _step == 2 ? 'تخطي' : 'لاحقًا',
                              kind: MqButtonKind.ghost,
                              onPressed: () {
                                if (_step == 2) {
                                  _levelId = null;
                                  _streamId = null;
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
          text: 'سنسأل عن مسارك ونومك وأول هدف، وكلها قابلة للتغيير لاحقًا '
              'من الإعدادات.',
        ),
      ],
    );
  }

  Widget _trackStep() {
    final db = context.read<AppState>().db;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<List<EducationLevel>>(
          future: _levelsFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const MqLoadingCard(lines: 2);
            }
            final levels = snap.data ?? const <EducationLevel>[];
            if (snap.hasError || levels.isEmpty) {
              return const MqBanner(
                icon: Icons.help_outline_rounded,
                tone: MqTone.info,
                title: 'لا قائمة مسارات بعد',
                text: 'القوائم تحمل فقط ما أُدخل وتحقّق منه، ولا يوجد شيء '
                    'منها على هذا الجهاز بعد. يمكنك المتابعة بدون تحديد، '
                    'وستعمل الخطة بما تدخله أنت.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: _levelId,
                  decoration:
                      const InputDecoration(labelText: 'المستوى الدراسي'),
                  items: [
                    for (final l in levels)
                      DropdownMenuItem(value: l.id, child: Text(l.name)),
                  ],
                  onChanged: (v) => setState(() {
                    _levelId = v;
                    _streamId = null;
                  }),
                ),
                const SizedBox(height: 12),
                if (_levelId != null)
                  FutureBuilder<List<StudyStream>>(
                    future: (db.select(db.streams)
                          ..where((t) => t.educationLevelId.equals(_levelId!)))
                        .get(),
                    builder: (context, s) {
                      final streams = s.data ?? const <StudyStream>[];
                      if (streams.isEmpty) {
                        return const MqBanner(
                          icon: Icons.info_outline_rounded,
                          tone: MqTone.neutral,
                          text: 'لا شعب مُدخلة لهذا المستوى. يمكنك المتابعة.',
                        );
                      }
                      return DropdownButtonFormField<String>(
                        value: _streamId,
                        decoration: const InputDecoration(
                            labelText: 'الشعبة / الخيار'),
                        items: [
                          for (final st in streams)
                            DropdownMenuItem(
                                value: st.id, child: Text(st.name)),
                        ],
                        onChanged: (v) => setState(() => _streamId = v),
                      );
                    },
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const MqBanner(
          icon: Icons.verified_outlined,
          tone: MqTone.neutral,
          text: 'لا نفترض لك منهجًا. المعاملات والساعات الرسمية لا تظهر في '
              'التطبيق إلا إذا وُثّقت من مصدر رسمي.',
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
                    ? () => setState(() => _sleepHours--)
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
                    ? () => setState(() => _sleepHours++)
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
          onChanged: (v) => setState(() {
            _goalKind = v;
            _stepError = null;
          }),
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
