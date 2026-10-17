import 'package:flutter/material.dart';

import '../design/charts.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../reality/reality_hub_screen.dart';
import '../state/app_state.dart';
import '../state/exam_load.dart';
import 'exams_screen.dart';
import 'progress_pages.dart' show ChartCard;

/// «الحمل قبل الامتحانات»: for each coming exam, the time its subject's open
/// tasks still need next to the free study time left before it. Real data
/// only (see [ExamLoadReader]); when something is missing the card says what
/// to add instead of showing an empty chart.
class ExamLoadCard extends StatelessWidget {
  const ExamLoadCard({super.key, required this.app, required this.reloadKey});
  final AppState app;
  final int reloadKey;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqAsync<ExamLoadData>(
      reloadKey: reloadKey,
      load: () => ExamLoadReader(app.db).read(app.studentId!, DateTime.now()),
      loading: const MqLoadingCard(lines: 3),
      errorTitle: 'تعذّر عرض الحمل قبل الامتحانات',
      builder: (context, d) {
        if (d.rows.isEmpty) {
          return ChartCard(
            title: 'الحمل قبل الامتحانات',
            summary: 'لا امتحانات قادمة مسجّلة.',
            child: MqEmptyState(
              icon: Icons.event_outlined,
              title: 'لا امتحانات قادمة',
              message:
                  'سجّل امتحانك لنقارن ما تحتاجه مهام مادته بوقت فراغك قبله.',
              actionLabel: 'إلى الامتحانات',
              onAction: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                      builder: (_) => const ExamsScreen())),
            ),
          );
        }
        final withWork = d.rows.where((r) => r.neededMinutes > 0).toList();
        if (withWork.isEmpty) {
          return ChartCard(
            title: 'الحمل قبل الامتحانات',
            summary: 'لا مهام مفتوحة مرتبطة بمواد امتحاناتك.',
            child: const MqEmptyState(
              icon: Icons.task_alt_rounded,
              title: 'لا عمل متبقٍّ يُقاس',
              message:
                  'حين تضيف مهامًا لمادة لها امتحان يظهر هنا ما تحتاجه من وقت.',
            ),
          );
        }
        if (!d.hasAvailability) {
          return ChartCard(
            title: 'الحمل قبل الامتحانات',
            summary:
                'لم تُدخل أوقات فراغك، فلا نقارن المطلوب بالمتاح.',
            child: MqEmptyState(
              icon: Icons.event_busy_outlined,
              title: 'أضف أوقات فراغك',
              message:
                  'المطلوب ${withWork.map((r) => '${r.subjectName}: ${r.neededMinutes} د').join(' · ')}. '
                  'أضف نوافذ فراغك من «واقعي ← فراغي» لنقارنه بها.',
              actionLabel: 'افتح «واقعي»',
              onAction: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                      builder: (_) => const RealityHubScreen())),
            ),
          );
        }
        final nearest = withWork.first;
        return ChartCard(
          title: 'الحمل قبل الامتحانات',
          note: 'لكل امتحان: دقائق مهام مادته المتبقية مقابل وقت فراغك '
              'حتى يومه (بعد استبعاد حصص المدرسة والنوم والتزاماتك)',
          summary:
              '${nearest.subjectName}: ${ExamLoadMath.summaryFor(needed: nearest.neededMinutes, available: nearest.availableMinutes, hasAvailability: d.hasAvailability, openTasks: nearest.openTasks)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MqPairedBars(
                rows: [
                  for (final r in withWork)
                    MqPairRow(
                      '${r.subjectName} · ${r.daysAway <= 0 ? 'اليوم' : 'بعد ${r.daysAway} يومًا'}',
                      r.neededMinutes.toDouble(),
                      r.availableMinutes.toDouble(),
                    ),
                ],
                firstLabel: 'المطلوب',
                secondLabel: 'المتاح',
              ),
              const SizedBox(height: 4),
              for (final r in withWork)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                      '${r.subjectName}: ${ExamLoadMath.summaryFor(needed: r.neededMinutes, available: r.availableMinutes, hasAvailability: d.hasAvailability, openTasks: r.openTasks)}',
                      style: MqType.caption.copyWith(color: p.ink3)),
                ),
              const SizedBox(height: 4),
              Text(
                  'وقت الفراغ نفسه يخدم كل الامتحانات، فلا تجمع المتاح بين صفّين.',
                  style: MqType.caption.copyWith(color: p.ink3)),
            ],
          ),
        );
      },
    );
  }
}
