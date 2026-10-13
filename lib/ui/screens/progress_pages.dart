import 'package:flutter/material.dart';

import '../../repositories/goal_repository.dart';
import '../design/charts.dart';
import '../design/primitives.dart';
import '../design/progress.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../goals/goals_screen.dart';
import '../planning/plan_review_screen.dart';
import '../state/app_state.dart';
import '../state/home_data.dart';
import '../state/progress_insights.dart';
import '../widgets/priority_views.dart';
import 'exams_screen.dart';

MqTone _bandTone(double v) {
  if (v < 0.4) return MqTone.overdue;
  if (v < 0.7) return MqTone.accent;
  return MqTone.ok;
}

/// Every chart on the progress pages lives in one of these: a clear Arabic
/// title, what the axes/units are, the chart, and a short sentence that says
/// what the student is seeing.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    required this.summary,
    this.note,
  });
  final String title;
  final Widget child;
  final String summary;

  /// Units / axes, in one short line under the title.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MqCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: MqType.h3.copyWith(color: p.ink)),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(note!,
                    style: MqType.caption.copyWith(color: p.ink3)),
              ),
            const SizedBox(height: 12),
            child,
            const SizedBox(height: 10),
            Text(summary, style: MqType.small.copyWith(color: p.ink2)),
          ],
        ),
      ),
    );
  }
}

/// Vertical columns with the value above and a short label below. Drawn only
/// from the numbers given; a column of 0 is a thin stub, never a guess.
class ColumnBars extends StatelessWidget {
  const ColumnBars({
    super.key,
    required this.values,
    required this.labels,
    this.color,
    this.highlight,
    this.valueText,
    this.height = 110,
  });
  final List<int> values;
  final List<String> labels;
  final Color? color;

  /// Index drawn in the accent colour (e.g. today), or null.
  final int? highlight;
  final String Function(int)? valueText;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final maxV = values.fold<int>(1, (a, v) => v > a ? v : a);
    return SizedBox(
      height: height + 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: MqNum(
                          valueText == null
                              ? '${values[i]}'
                              : valueText!(values[i]),
                          style: MqType.caption,
                          color: p.ink3),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: 4 + (height - 22) * (values[i] / maxV),
                      decoration: BoxDecoration(
                        color: values[i] == 0
                            ? p.surface2
                            : (i == highlight
                                ? p.accent
                                : (color ?? p.brand)),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(labels[i],
                          style: MqType.caption.copyWith(color: p.ink3)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _emptyPage(IconData icon, String title, String message,
        {String? actionLabel, VoidCallback? onAction}) =>
    MqEmptyState(
        icon: icon,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction);

// =================================================== mastery by subject

/// Comparison of the subjects' mastery (الإتقان حسب المادة).
class SubjectMasteryChart extends StatelessWidget {
  const SubjectMasteryChart({super.key, required this.subjects});
  final List<SubjectMastery> subjects;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    if (subjects.isEmpty) return const SizedBox.shrink();
    String summary;
    if (subjects.length == 1) {
      summary = 'لديك مادة واحدة مقيَّمة (${subjects.first.name}). '
          'تظهر المقارنة بين المواد حين تقيّم مواضيع من مادة ثانية.';
    } else {
      final sorted = [...subjects]..sort((a, b) => a.average.compareTo(b.average));
      summary = 'أعلى متوسط في ${sorted.last.name} '
          '(${(sorted.last.average * 100).round()}%) وأقله في ${sorted.first.name} '
          '(${(sorted.first.average * 100).round()}%).';
    }
    return ChartCard(
      title: 'الإتقان حسب المادة',
      note: 'النسبة = متوسط إتقان المواضيع التي قيّمتَها في المادة (0–100%)',
      summary: summary,
      child: Column(children: [
        for (final s in subjects)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(s.name,
                          style: MqType.body.copyWith(color: p.ink))),
                  MqNum('${(s.average * 100).round()}%', style: MqType.label),
                ]),
                const SizedBox(height: 6),
                MqBar(value: s.average.clamp(0.0, 1.0), tone: _bandTone(s.average)),
                const SizedBox(height: 4),
                Text(
                    '${s.topics} موضوعًا · الأضعف: ${s.weakestName} '
                    '(${(s.weakestValue * 100).round()}%)',
                    style: MqType.caption.copyWith(color: p.ink3)),
              ],
            ),
          ),
      ]),
    );
  }
}

// ======================================================= review forecast

/// Upcoming reviews: what is overdue and what falls due in the next 7 days.
class ReviewForecastChart extends StatelessWidget {
  const ReviewForecastChart({super.key, required this.forecast, required this.now});
  final ReviewForecast forecast;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    if (forecast.total == 0) return const SizedBox.shrink();
    final todayIdx = now.toLocal().weekday % 7;
    final labels = [
      'متأخرة',
      for (var i = 0; i < 7; i++) i == 0 ? 'اليوم' : kDayShortAr[(todayIdx + i) % 7],
    ];
    return ChartCard(
      title: 'المراجعات القادمة',
      note: 'عدد المواضيع التي يحين وقت مراجعتها يومًا بيوم، من اليمين: المتأخرة ثم اليوم',
      summary: forecast.summary,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ColumnBars(
          values: [forecast.overdue, ...forecast.perDay],
          labels: labels,
          color: p.info,
          highlight: forecast.overdue > 0 ? 0 : null,
        ),
      ),
    );
  }
}

// ================================================================= time

class TimePage extends StatefulWidget {
  const TimePage({super.key, required this.app, required this.reloadKey});
  final AppState app;
  final int reloadKey;
  @override
  State<TimePage> createState() => _TimePageState();
}

class _TimePageState extends State<TimePage> {
  TimePeriod _period = TimePeriod.week;
  DateTime _anchor = DateTime.now();

  void _shift(int dir) {
    setState(() {
      final a = _anchor;
      switch (_period) {
        case TimePeriod.week:
          _anchor = DateTime(a.year, a.month, a.day + 7 * dir);
          break;
        case TimePeriod.month:
          _anchor = DateTime(a.year, a.month + dir, 1);
          break;
        case TimePeriod.year:
          _anchor = DateTime(a.year + dir, a.month, 1);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final app = widget.app;
    return ListView(
      padding: const EdgeInsets.fromLTRB(MqSpace.screen, 4, MqSpace.screen, 28),
      children: [
        MqSegmented<TimePeriod>(
          options: const {
            TimePeriod.week: 'أسبوع',
            TimePeriod.month: 'شهر',
            TimePeriod.year: 'سنة',
          },
          selected: _period,
          onChanged: (v) => setState(() => _period = v),
        ),
        const SizedBox(height: 10),
        MqAsync<PeriodReport>(
          reloadKey: '${widget.reloadKey}-$_period-$_anchor',
          load: () => ProgressInsights(app.db)
              .periodReport(_period, _anchor, DateTime.now()),
          loading: const MqLoadingCard(lines: 4),
          errorTitle: 'تعذّر عرض الوقت',
          builder: (context, r) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                MqIconButton(
                    icon: Icons.arrow_forward_rounded,
                    label: 'السابق',
                    onTap: () => _shift(-1)),
                Expanded(
                    child: Center(
                        child: MqNum(r.title, style: MqType.h2, color: p.ink))),
                MqIconButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'التالي',
                    onTap: () => _shift(1)),
              ]),
              const SizedBox(height: 10),
              _plannedVsActual(context, r),
              _completed(context, r),
            ],
          ),
        ),
        _WorkloadSection(app: app, reloadKey: widget.reloadKey),
        MqBanner(
          icon: Icons.info_outline_rounded,
          tone: MqTone.neutral,
          title: 'فجوات الخطة',
          text:
              'الوقت الذي لم يتّسع لمهمة، أو الوقت الفارغ بينما توجد مهام، يحسبها المخطِّط '
              'حين تطلب إعادة التخطيط ولا تُحفظ. تجدها في «مراجعة الخطة».',
          action: MqButton(
            label: 'افتح مراجعة الخطة',
            small: true,
            kind: MqButtonKind.secondary,
            onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                    builder: (_) => const PlanReviewScreen())),
          ),
        ),
      ],
    );
  }

  Widget _plannedVsActual(BuildContext context, PeriodReport r) {
    if (r.sessions == 0) {
      return ChartCard(
        title: 'المخطَّط مقابل الفعلي',
        summary: r.summary,
        child: _emptyPage(
          Icons.compare_arrows_rounded,
          'لا جلسات في هذه الفترة',
          'الخطة تُبنى أسبوعًا بأسبوع ولا نخمّن المستقبل. ستظهر المقارنة بعد تسجيل جلسات الدراسة.',
        ),
      );
    }
    if (!r.canCompare) {
      return ChartCard(
        title: 'الوقت المخطَّط',
        note: 'الدقائق المخطَّطة في كل ${r.period == TimePeriod.year ? 'شهر' : r.period == TimePeriod.month ? 'أسبوع' : 'يوم'}',
        summary: r.summary,
        child: ColumnBars(
          values: [for (final b in r.buckets) b.plannedMinutes],
          labels: [for (final b in r.buckets) b.shortLabel],
        ),
      );
    }
    final rows = [
      for (final b in r.buckets)
        if (b.plannedMinutes > 0 || b.actualMinutes > 0)
          MqPairRow(b.label, b.plannedMinutes.toDouble(),
              b.actualMinutes.toDouble()),
    ];
    return ChartCard(
      title: 'المخطَّط مقابل الفعلي',
      note: 'الدقائق: المخطَّط للجلسات مقابل ما سجّلتَه فعليًا',
      summary: r.summary,
      child: MqPairedBars(
        rows: rows,
        firstLabel: 'المخطَّط',
        secondLabel: 'الفعلي',
      ),
    );
  }

  Widget _completed(BuildContext context, PeriodReport r) {
    if (r.completedTasks == 0) {
      return ChartCard(
        title: 'المهام المنجزة',
        summary: 'لا مهام منجزة مسجّلة في هذه الفترة.',
        child: _emptyPage(Icons.task_alt_rounded, 'لا إنجازات بعد',
            'تُحصى هنا المهام التي تسجّل إنجازها.'),
      );
    }
    return ChartCard(
      title: 'المهام المنجزة',
      note: 'عدد المهام التي سجّلتَ إنجازها في كل '
          '${r.period == TimePeriod.year ? 'شهر' : r.period == TimePeriod.month ? 'أسبوع' : 'يوم'}',
      summary: 'أنجزتَ ${r.completedTasks} مهمة في هذه الفترة.',
      child: ColumnBars(
        values: [for (final b in r.buckets) b.completedTasks],
        labels: [for (final b in r.buckets) b.shortLabel],
      ),
    );
  }
}

class _WorkloadSection extends StatelessWidget {
  const _WorkloadSection({required this.app, required this.reloadKey});
  final AppState app;
  final int reloadKey;

  @override
  Widget build(BuildContext context) {
    return MqAsync<WorkloadView?>(
      reloadKey: reloadKey,
      load: () => ProgressInsights(app.db).workload(app.studentId!),
      loading: const MqLoadingCard(lines: 2),
      errorTitle: 'تعذّر عرض الحمل',
      builder: (context, w) {
        if (w == null) {
          return ChartCard(
            title: 'الحمل الدراسي',
            summary: 'لم يُحسب الحمل بعد. يُحسب حين يخطّط التطبيق أسبوعك.',
            child: _emptyPage(Icons.speed_rounded, 'لا حمل محسوب',
                'أضف مهامك وأوقات فراغك ثم اطلب التخطيط.'),
          );
        }
        if (!w.hasAvailability) {
          return ChartCard(
            title: 'الحمل الدراسي',
            summary: w.summary,
            child: _emptyPage(Icons.event_busy_outlined, 'لا وقت متاح مسجّل',
                'المطلوب ${formatMinutes(w.neededMinutes)}. أضف أوقات فراغك لنقارنه بها.'),
          );
        }
        return ChartCard(
          title: 'الحمل الدراسي',
          note: 'الدقائق المطلوبة لمهامك مقابل المتاحة (لقطة الآن، لا تتبع الفترة المختارة)',
          summary: w.summary,
          child: MqPairedBars(
            rows: [
              MqPairRow('العمل مقابل الوقت', w.neededMinutes.toDouble(),
                  w.availableMinutes.toDouble()),
            ],
            firstLabel: 'المطلوب',
            secondLabel: 'المتاح',
          ),
        );
      },
    );
  }
}

// ============================================================ priorities

class PrioritiesPage extends StatelessWidget {
  const PrioritiesPage({super.key, required this.app, required this.reloadKey});
  final AppState app;
  final int reloadKey;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqAsync<PriorityPageData>(
      reloadKey: reloadKey,
      load: () => ProgressInsights(app.db)
          .priorities(app.studentId!, DateTime.now()),
      loading: const Padding(
          padding: EdgeInsets.all(MqSpace.screen), child: MqLoadingCard(lines: 4)),
      errorTitle: 'تعذّر عرض الأولويات',
      builder: (context, d) {
        return ListView(
          padding:
              const EdgeInsets.fromLTRB(MqSpace.screen, 4, MqSpace.screen, 28),
          children: [
            _rankedCard(context, d.ranked),
            _examsCard(context, d.exams),
            Text(
                'الأولوية رقم من 0 إلى 1 يحسبه محرّك الأولويات من عوامل مسجَّلة. '
                'المعامل الرسمي وارتباط المهمة بهدفك لا يدخلان فيه إلا حين تتوفر بياناتهما.',
                style: MqType.caption.copyWith(color: p.ink3)),
          ],
        );
      },
    );
  }

  Widget _rankedCard(BuildContext context, List<PrioritizedTask> ranked) {
    final p = context.mq;
    if (ranked.isEmpty) {
      return ChartCard(
        title: 'ترتيب أولوياتك',
        summary: 'لا أولويات محسوبة بعد.',
        child: _emptyPage(Icons.low_priority_rounded, 'لا أولويات بعد',
            'تُحسب الأولوية عند معالجة مهامك. أضف مهمة وستظهر هنا مع سبب ترتيبها.'),
      );
    }
    String reasonOf(PrioritizedTask t) => t.dominantFactor.isEmpty
        ? 'لا عامل مسجَّل'
        : prioritySignalLabel(t.dominantFactor);
    final first = ranked.first;
    var summary = 'قُدِّمت «${first.nodeName}» لأن أقوى عامل فيها: ${reasonOf(first)}.';
    if (ranked.length > 1) {
      final second = ranked[1];
      summary += ' وجاءت «${second.nodeName}» بعدها لأن أقوى عاملها: ${reasonOf(second)}.';
    }
    return ChartCard(
      title: 'ترتيب أولوياتك',
      note: 'طول الشريط = درجة الأولوية من 0 إلى 1. اضغط مهمة لترى كل أسبابها.',
      summary: summary,
      child: Column(children: [
        for (var i = 0; i < ranked.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MqPressable(
              onTap: () => showWhySheet(context, ranked[i]),
              semanticLabel: ranked[i].nodeName,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    MqNum('${i + 1}', style: MqType.label, color: p.ink3),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(ranked[i].nodeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MqType.body.copyWith(color: p.ink))),
                    MqNum(ranked[i].priority.score.toStringAsFixed(2),
                        style: MqType.label),
                  ]),
                  const SizedBox(height: 6),
                  MqBar(value: ranked[i].priority.score.clamp(0.0, 1.0)),
                  const SizedBox(height: 4),
                  Text(
                      [
                        if (ranked[i].subjectName.isNotEmpty)
                          ranked[i].subjectName,
                        'السبب الأقوى: ${reasonOf(ranked[i])}',
                      ].join(' · '),
                      style: MqType.caption.copyWith(color: p.ink3)),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  Widget _examsCard(BuildContext context, List<ExamOutlook> exams) {
    final p = context.mq;
    if (exams.isEmpty) {
      return ChartCard(
        title: 'الامتحانات القادمة',
        summary: 'لا امتحانات قادمة مسجّلة.',
        child: _emptyPage(
          Icons.event_outlined,
          'لا امتحانات قادمة',
          'سجّل امتحانك ليظهر قربه هنا ويدخل في ترتيب أولوياتك.',
          actionLabel: 'إلى الامتحانات',
          onAction: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const ExamsScreen())),
        ),
      );
    }
    final nearest = exams.first;
    return ChartCard(
      title: 'الامتحانات القادمة',
      note: 'أقربها أولًا. الشريط = متوسط إتقانك لما قيّمتَه في المادة (0–100%)',
      summary:
          'أقرب امتحان: ${nearest.subjectName} ${nearest.daysAway <= 0 ? 'اليوم' : 'بعد ${nearest.daysAway} يومًا'}.',
      child: Column(children: [
        for (final e in exams)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(e.subjectName,
                          style: MqType.body.copyWith(color: p.ink))),
                  MqChip(
                      label: e.daysAway <= 0 ? 'اليوم' : 'بعد ${e.daysAway} يومًا',
                      tone: e.daysAway <= 7 ? MqTone.accent : MqTone.neutral),
                ]),
                const SizedBox(height: 6),
                if (e.masteryAverage != null)
                  MqBar(
                      value: e.masteryAverage!.clamp(0.0, 1.0),
                      tone: _bandTone(e.masteryAverage!))
                else
                  Container(
                      height: 8,
                      decoration: BoxDecoration(
                          color: p.surface2,
                          borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 4),
                Text('${e.summary}${e.openTasks > 0 ? ' · ${e.openTasks} مهمة مفتوحة' : ''}',
                    style: MqType.caption.copyWith(color: p.ink3)),
              ],
            ),
          ),
      ]),
    );
  }
}

// =============================================================== goals

class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key, required this.app, required this.reloadKey});
  final AppState app;
  final int reloadKey;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqAsync<GoalsPageData>(
      reloadKey: reloadKey,
      load: () =>
          ProgressInsights(app.db).goalsAndGaps(app.studentId!, DateTime.now()),
      loading: const Padding(
          padding: EdgeInsets.all(MqSpace.screen), child: MqLoadingCard(lines: 4)),
      errorTitle: 'تعذّر عرض الأهداف',
      builder: (context, d) {
        return ListView(
          padding:
              const EdgeInsets.fromLTRB(MqSpace.screen, 4, MqSpace.screen, 28),
          children: [
            _goalsCard(context, d.goals),
            _gapsCard(context, d.weakest),
            Text(
                'الأهداف لا تؤثر في ترتيب الأولويات بعد: تعريف «الارتباط بالهدف» لم يُعتمد، '
                'ولا حدّ رسمي لاعتبار موضوع ضعيفًا، لذلك نعرض الترتيب فقط دون حكم.',
                style: MqType.caption.copyWith(color: p.ink3)),
          ],
        );
      },
    );
  }

  Widget _goalsCard(BuildContext context, List<GoalView> goals) {
    final p = context.mq;
    if (goals.isEmpty) {
      return ChartCard(
        title: 'أهدافي',
        summary: 'لا أهداف مسجّلة.',
        child: _emptyPage(
          Icons.flag_outlined,
          'لا أهداف بعد',
          'سجّل هدفك لترى ما تحقق منه وما بقي.',
          actionLabel: 'سجّل هدفًا',
          onAction: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const GoalsScreen())),
        ),
      );
    }
    final active = goals.where((g) => g.goal.status == GoalRepository.statusActive).length;
    final achieved = goals.where((g) => g.goal.status == GoalRepository.statusAchieved).length;
    return ChartCard(
      title: 'أهدافي',
      note: 'ما تحقق وما بقي، وتقدّم المادة المرتبطة بكل هدف',
      summary: '$active هدف جارٍ · $achieved محقَّق.',
      child: Column(children: [
        for (final g in goals)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(g.goal.title,
                          style: MqType.body.copyWith(color: p.ink))),
                  MqChip(
                    label: g.goal.status == GoalRepository.statusAchieved
                        ? 'تحقق'
                        : g.goal.status == GoalRepository.statusDropped
                            ? 'متروك'
                            : 'جارٍ',
                    tone: g.goal.status == GoalRepository.statusAchieved
                        ? MqTone.ok
                        : MqTone.neutral,
                  ),
                ]),
                Text(
                    [
                      if (g.subjectName != null) g.subjectName!,
                      if (g.daysLeft != null)
                        (g.daysLeft! < 0
                            ? 'مضى موعده بـ ${-g.daysLeft!} يومًا'
                            : g.daysLeft == 0
                                ? 'موعده اليوم'
                                : 'بقي ${g.daysLeft} يومًا'),
                    ].join(' · '),
                    style: MqType.caption.copyWith(color: p.ink3)),
                if (g.masteryAverage != null) ...[
                  const SizedBox(height: 6),
                  MqBar(
                      value: g.masteryAverage!.clamp(0.0, 1.0),
                      tone: _bandTone(g.masteryAverage!)),
                  Text(
                      'إتقان المادة: ${(g.masteryAverage! * 100).round()}% (${g.topics} موضوعًا)',
                      style: MqType.caption.copyWith(color: p.ink3)),
                ],
                if (g.doneTasks + g.openTasks > 0) ...[
                  const SizedBox(height: 6),
                  MqSegmentBar(segments: [
                    (g.doneTasks.toDouble(), p.brand),
                    (g.openTasks.toDouble(), p.surface2),
                  ]),
                  Text('مهام المادة: ${g.doneTasks} منجزة · ${g.openTasks} متبقية',
                      style: MqType.caption.copyWith(color: p.ink3)),
                ],
              ],
            ),
          ),
      ]),
    );
  }

  Widget _gapsCard(BuildContext context, List<GapTopic> weakest) {
    final p = context.mq;
    if (weakest.isEmpty) {
      return ChartCard(
        title: 'مواضيع تحتاج معالجة',
        summary: 'لا تقييمات بعد.',
        child: _emptyPage(Icons.psychology_alt_outlined, 'لا بيانات كافية',
            'تظهر هنا أضعف المواضيع بعد أن تنجز مهامك وتقيّم فهمك.'),
      );
    }
    return ChartCard(
      title: 'مواضيع تحتاج معالجة',
      note: 'الأقل إتقانًا أولًا (من تقييماتك المسجَّلة، 0–100%)',
      summary:
          'أضعف موضوع الآن: ${weakest.first.nodeName} (${(weakest.first.probability * 100).round()}%).',
      child: Column(children: [
        for (final w in weakest)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              MqRing(
                value: w.probability.clamp(0.0, 1.0),
                size: 44,
                thickness: 5,
                color: _bandTone(w.probability) == MqTone.ok ? p.ok : p.overdue,
                track: _bandTone(w.probability) == MqTone.ok
                    ? p.okSoft
                    : p.overdueSoft,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.nodeName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MqType.body.copyWith(color: p.ink)),
                    Text(
                        [
                          if (w.subjectName.isNotEmpty) w.subjectName,
                          if (w.reviewOverdueDays != null)
                            'مراجعتها مستحقة${w.reviewOverdueDays! > 0 ? ' منذ ${w.reviewOverdueDays} يومًا' : ' الآن'}',
                        ].join(' · '),
                        style: MqType.caption.copyWith(color: p.ink3)),
                  ],
                ),
              ),
              MqNum('${(w.probability * 100).round()}%', style: MqType.label),
            ]),
          ),
      ]),
    );
  }
}
