import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/study_session_repository.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';
import '../state/home_data.dart';
import '../widgets/priority_views.dart';

class _DetailData {
  const _DetailData({
    required this.task,
    required this.nodeName,
    required this.subjectName,
    required this.priority,
    required this.segments,
    required this.sessions,
  });
  final Task task;
  final String nodeName;
  final String subjectName;
  final PrioritizedTask? priority;
  final List<TaskSegment> segments;
  final List<StudySession> sessions;
}

/// «تفاصيل المهمة» (D-1 S14): everything stored about one task — its
/// duration, whether it can be split, its segments, the study sessions the
/// plan gave it, and the stored priority with its explanation. Read only,
/// plus the one action that already existed: marking it complete.
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.task});
  final Task task;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  int _tick = 0;

  Future<_DetailData> _load(AppDatabase db) async {
    // Re-read the task: it may have changed since the list was drawn.
    final fresh = await (db.select(db.tasks)
              ..where((t) => t.id.equals(widget.task.id)))
            .getSingleOrNull() ??
        widget.task;
    final content = ContentRepository(db);
    final sessions = StudySessionRepository(db);
    return _DetailData(
      task: fresh,
      nodeName: await content.nameForNode(fresh.knowledgeNodeId),
      subjectName: await content.subjectNameForNode(fresh.knowledgeNodeId),
      priority: await HomeData(db).readForTask(fresh),
      segments: await sessions.readSegmentsForTask(fresh.id),
      sessions: await sessions.readForTask(fresh.id),
    );
  }

  String _status(Task t) {
    switch (t.completionStatus) {
      case 'complete':
        return 'منجزة';
      case 'partial':
        return 'بدأتَها';
      default:
        return 'لم تبدأ';
    }
  }

  String _source(Task t) {
    switch (t.sourceType) {
      case 'assignment':
        return 'من واجب';
      case 'examPrep':
        return 'تحضير لامتحان';
      default:
        return 'مهمة عادية';
    }
  }

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final db = context.read<AppState>().db;
    return MqAsync<_DetailData>(
      reloadKey: _tick,
      load: () => _load(db),
      loading: const MqPage(
          title: 'تفاصيل المهمة', children: [MqLoadingCard(lines: 4)]),
      errorTitle: 'تعذّر عرض المهمة',
      builder: (context, d) {
        final t = d.task;
        final complete = t.completionStatus == 'complete';
        return MqPage(
          caption: d.subjectName.isEmpty ? 'مهمة' : d.subjectName,
          title: d.nodeName,
          children: [
            MqCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    MqChip(
                        label: _status(t),
                        tone: complete ? MqTone.ok : MqTone.brand),
                    MqChip(label: _source(t)),
                    MqChip(
                        label: t.isSplittable
                            ? 'قابلة للتقسيم'
                            : 'متصلة (غير قابلة للتقسيم)'),
                  ]),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Figure(
                          value: '${t.estimatedDurationMinutes}',
                          label: 'دقيقة مقدَّرة'),
                      _Figure(
                          value: '${t.remainingDurationMinutes}',
                          label: 'دقيقة متبقية'),
                      _Figure(value: '${d.segments.length}', label: 'قطع'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (d.priority != null) ...[
              const MqSectionTitle('أولويتها'),
              MqCard(
                onTap: () => showWhySheet(context, d.priority!),
                child: Row(
                  children: [
                    const MqIconTile(icon: Icons.flag_outlined, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MqNum(d.priority!.priority.score.toStringAsFixed(2),
                              style: MqType.h2),
                          Text(
                              'ثقة ${confidenceLabel(d.priority!.priority.confidenceLevel)} · اضغط لترى السبب',
                              style: MqType.caption.copyWith(color: p.ink3)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded, color: p.ink3, size: 20),
                  ],
                ),
              ),
            ] else ...[
              const MqSectionTitle('أولويتها'),
              const MqLockBox(
                title: 'لا أولوية محسوبة بعد',
                message:
                    'تُحسب الأولوية عند معالجة المهام. لا نخمّنها هنا.',
              ),
            ],
            const SizedBox(height: 12),
            const MqSectionTitle('جلسات الخطة'),
            if (d.sessions.isEmpty)
              const MqEmptyState(
                icon: Icons.event_busy_outlined,
                title: 'لا جلسات لهذه المهمة',
                message: 'لم تضع الخطة لها وقتًا بعد. ستظهر هنا عند التخطيط.',
              )
            else
              for (final s in d.sessions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MqCard(
                    kind: MqCardKind.soft,
                    child: Row(
                      children: [
                        MqIconTile(
                          icon: s.actualEnd != null
                              ? Icons.check_rounded
                              : Icons.schedule_rounded,
                          tone: s.actualEnd != null
                              ? MqTone.ok
                              : MqTone.neutral,
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                              '${s.plannedStart.day}/${s.plannedStart.month}',
                              style: MqType.body.copyWith(color: p.ink)),
                        ),
                        MqNum(
                            '${_hhmm(s.plannedStart)}–${_hhmm(s.plannedEnd)}',
                            style: MqType.small),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            if (!complete)
              MqButton(
                label: 'تمّت',
                icon: Icons.check_rounded,
                kind: MqButtonKind.accent,
                block: true,
                onPressed: () async {
                  final ok = await completeTaskWithFeedback(context, db, t);
                  if (ok && context.mounted) setState(() => _tick++);
                },
              ),
          ],
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Expanded(
      child: Column(
        children: [
          MqNum(value, style: MqType.display.copyWith(fontSize: 30)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: MqType.caption.copyWith(color: p.ink3)),
        ],
      ),
    );
  }
}
