import 'package:drift/drift.dart' show OrderingTerm, OrderingMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../repositories/exam_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';

/// The very first screen the student sees. Carries the required identity
/// block (institution / app name / tagline) plus a real, live snapshot
/// pulled from the actual database — not placeholder numbers.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final db = appState.db;
    final studentId = appState.studentId!;

    return RefreshIndicator(
      onRefresh: () async {
        // Nothing to "fetch" (fully offline), but pull-to-refresh is an
        // expected gesture — re-running the FutureBuilders below via a
        // plain setState keeps the interaction familiar with zero risk
        // (no network round-trip to fail or duplicate).
        setState(() {});
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _IdentityHeader(),
          const SizedBox(height: 20),
          _SectionTitle('مهام اليوم'),
          AsyncSection<List<Task>>(
            future: () => (db.select(db.tasks)
                  ..where((t) => t.completionStatus.equals('complete').not())
                  ..orderBy([(t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)])
                  ..limit(5))
                .get(),
            isEmpty: (data) => data.isEmpty,
            emptyMessage: 'لا توجد مهام غير منجزة حاليًا. أضف مهامك من '
                'تبويب «المهام».',
            emptyIcon: Icons.task_alt,
            builder: (context, tasks) => Column(
              children: tasks.map((t) => _TaskTile(task: t)).toList(),
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle('أقرب الامتحانات'),
          AsyncSection<List<Exam>>(
            future: () => ExamRepository(db)
                .readUpcoming(now: DateTime.now().toUtc()),
            isEmpty: (data) => data.isEmpty,
            emptyMessage: 'لا امتحانات مسجّلة قريبًا.',
            emptyIcon: Icons.event_available,
            builder: (context, exams) => Column(
              children: exams.take(3).map((e) => _ExamTile(exam: e)).toList(),
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle('حالة العبء الدراسي'),
          AsyncSection<WorkloadState?>(
            future: () => (db.select(db.workloadStates)
                  ..where((t) => t.studentId.equals(studentId))
                  ..orderBy([(t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)])
                  ..limit(1))
                .getSingleOrNull(),
            emptyMessage: 'لم يتم بعد احتساب حالة العبء الدراسي.\n'
                'يتم تحديثها تلقائيًا كلما تغيّرت خطتك.',
            emptyIcon: Icons.speed,
            builder: (context, state) => _WorkloadCard(state: state),
          ),
        ],
      ),
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'ثانوية رابح بطاط',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'مرافق التلميذ',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'المرافقة والتنظيم الدراسي طوال العام',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final Task task;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: task.completionStatus == 'partial'
              ? AppColors.warning.withOpacity(0.15)
              : AppColors.primary.withOpacity(0.1),
          child: Icon(
            task.completionStatus == 'partial'
                ? Icons.hourglass_bottom
                : Icons.radio_button_unchecked,
            color: task.completionStatus == 'partial'
                ? AppColors.warning
                : AppColors.primary,
            size: 20,
          ),
        ),
        title: Text('مدة تقديرية: ${task.estimatedDurationMinutes} د'),
        subtitle: Text(
          task.isSplittable ? 'قابلة للتقسيم' : 'مهمة متصلة (غير قابلة للتقسيم)',
        ),
      ),
    );
  }
}

class _ExamTile extends StatelessWidget {
  const _ExamTile({required this.exam});
  final Exam exam;
  @override
  Widget build(BuildContext context) {
    final days = exam.examDate.difference(DateTime.now().toUtc()).inDays;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event, color: AppColors.danger),
        title: Text(_examTypeLabel(exam.examType)),
        subtitle: Text(days >= 0 ? 'بعد $days يومًا' : 'اليوم/قريبًا'),
      ),
    );
  }

  String _examTypeLabel(String type) {
    switch (type) {
      case 'bac':
        return 'امتحان (بكالوريا)';
      case 'summative':
        return 'فرض/اختبار فصلي';
      default:
        return 'تقييم';
    }
  }
}

class _WorkloadCard extends StatelessWidget {
  const _WorkloadCard({required this.state});
  final WorkloadState? state;

  @override
  Widget build(BuildContext context) {
    if (state == null) return const SizedBox.shrink();
    final labelMap = {
      'underload': ('عبء خفيف', AppColors.success),
      'balanced': ('متوازن', AppColors.primary),
      'overload': ('عبء زائد', AppColors.warning),
      'impossible': ('غير قابل للتحقيق بالوقت الحالي', AppColors.danger),
    };
    final entry = labelMap[state!.status] ?? ('غير معروف', Colors.grey);
    return Card(
      child: ListTile(
        leading: Icon(Icons.speed, color: entry.$2),
        title: Text(entry.$1, style: TextStyle(color: entry.$2, fontWeight: FontWeight.bold)),
        subtitle: Text(
          'الوقت المطلوب: ${state!.totalEstimatedTimeNeededMinutes} د  •  '
          'المتاح: ${state!.totalAvailableTimeMinutes} د',
        ),
      ),
    );
  }
}
