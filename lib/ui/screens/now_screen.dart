import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/page.dart';
import '../design/primitives.dart';
import '../design/progress.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';
import '../state/home_data.dart';
import '../widgets/not_now_sheet.dart';
import '../widgets/priority_views.dart';
import 'task_detail_screen.dart';

/// «الآن» (D-1 S04): one task, large, with the minutes it needs as the
/// biggest figure on the screen. It only presents what the Priority Engine
/// stored; «لماذا؟» opens the stored explanation, «تمّت» runs the same
/// completion pipeline as everywhere else. Pops with `true` when the task
/// was completed so the screen underneath refreshes.
class NowScreen extends StatelessWidget {
  const NowScreen({super.key, required this.item});
  final PrioritizedTask item;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final db = context.read<AppState>().db;
    final task = item.task;
    final minutes = task.remainingDurationMinutes;
    final total = task.estimatedDurationMinutes;
    final done = total <= 0 ? 0.0 : (1 - minutes / total).clamp(0.0, 1.0);
    final tone = p.toneFor(item.subjectName);

    return MqPage(
      caption: item.subjectName.isEmpty ? 'الآن' : item.subjectName,
      title: item.nodeName,
      children: [
        MqCard(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            children: [
              MqRing(
                value: done,
                size: 188,
                thickness: 12,
                color: tone.color,
                track: tone.soft,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MqNum('$minutes',
                        style: MqType.display.copyWith(fontSize: 52)),
                    Text('دقيقة متبقية',
                        style: MqType.caption.copyWith(color: p.ink3)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (task.completionStatus == 'partial')
                    const MqChip(
                        label: 'بدأتَها سابقًا',
                        icon: Icons.hourglass_bottom_rounded,
                        tone: MqTone.accent),
                  MqChip(
                      label: 'أولوية ${item.priority.score.toStringAsFixed(2)}',
                      tone: MqTone.brand),
                  MqChip(label: 'ثقة ${confidenceLabel(item.priority.confidenceLevel)}'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (item.factors.isNotEmpty) ...[
          const MqSectionTitle('سبب اختيارها'),
          MqCard(
            kind: MqCardKind.soft,
            child: Column(
              children: [
                for (final f in item.factors.take(3))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        MqIconTile(
                          icon: prioritySignalIcon(f.key),
                          tone: prioritySignalTone(f.key),
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(prioritySignalLabel(f.key),
                              style: MqType.body.copyWith(color: p.ink)),
                        ),
                        SizedBox(
                          width: 72,
                          child: MqBar(
                              value: f.value.clamp(0.0, 1.0),
                              tone: prioritySignalTone(f.key)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        MqButton(
          label: 'تمّت',
          icon: Icons.check_rounded,
          kind: MqButtonKind.accent,
          block: true,
          onPressed: () async {
            final ok = await completeTaskWithFeedback(context, db, task);
            if (ok && context.mounted) Navigator.of(context).pop(true);
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: MqButton(
                label: 'لماذا؟',
                icon: Icons.help_outline_rounded,
                kind: MqButtonKind.secondary,
                block: true,
                onPressed: () => showWhySheet(context, item),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MqButton(
                label: 'تفاصيل المهمة',
                icon: Icons.article_outlined,
                kind: MqButtonKind.secondary,
                block: true,
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                      builder: (_) => TaskDetailScreen(task: task)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        MqButton(
          label: 'ليست مناسبة الآن',
          icon: Icons.snooze_rounded,
          kind: MqButtonKind.ghost,
          block: true,
          onPressed: () async {
            final ok = await showNotNowSheet(context, db: db, task: task);
            if (ok && context.mounted) Navigator.of(context).pop(true);
          },
        ),
      ],
    );
  }
}
