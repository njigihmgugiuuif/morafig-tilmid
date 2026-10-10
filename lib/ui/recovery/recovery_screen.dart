import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/recovery_repository.dart';
import '../../repositories/study_session_repository.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';

class _MissedItem {
  const _MissedItem(this.taskName, this.subject, this.session, this.decision);
  final String taskName;
  final String subject;
  final StudySession session;
  final RecoveryRecord? decision;
}

/// «الفائت والاستعادة» (D-2 Q01 + S18): sessions whose time passed with no
/// actual recorded, each next to the recovery decision the planner stored
/// for its task. Read only: the decision was taken by the Recovery Engine
/// and is shown with the reasoning it saved.
class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({super.key});

  static String decisionLabel(String name) {
    switch (name) {
      case 'keep':
        return 'أُبقيت في مكانها';
      case 'move':
        return 'نُقلت إلى أول وقت متاح';
      case 'merge':
        return 'دُمجت في جلسة قادمة';
      case 'defer':
        return 'أُجّلت';
      case 'dropTemporarily':
        return 'أُسقطت مؤقتًا';
      case 'replan':
        return 'أُعيد تخطيطها';
      default:
        return name;
    }
  }

  Future<List<_MissedItem>> _load(AppState app) async {
    final db = app.db;
    final missed =
        await StudySessionRepository(db).readUnexecutedEndedBy(DateTime.now());
    final content = ContentRepository(db);
    final recovery = RecoveryRepository(db);
    final out = <_MissedItem>[];
    for (final s in missed) {
      final task = await (db.select(db.tasks)
            ..where((t) => t.id.equals(s.taskId)))
          .getSingleOrNull();
      if (task == null || task.completionStatus == 'complete') continue;
      final records = await recovery.readForTask(task.id);
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      out.add(_MissedItem(
        await content.nameForNode(task.knowledgeNodeId),
        await content.subjectNameForNode(task.knowledgeNodeId),
        s,
        records.isEmpty ? null : records.first,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.mq;
    return MqPage(
      title: 'الفائت والاستعادة',
      children: [
        MqAsync<List<_MissedItem>>(
          load: () => _load(app),
          errorTitle: 'تعذّر عرض الفائت',
          builder: (context, items) {
            if (items.isEmpty) {
              return const MqEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'لا شيء فائت',
                message: 'كل جلساتك التي مضى وقتها مسجّلة أو لا جلسات مخطَّطة بعد.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: MqCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(m.taskName,
                                    style: MqType.h3.copyWith(color: p.ink))),
                            const MqChip(label: 'فائتة', tone: MqTone.overdue),
                          ]),
                          if (m.subject.isNotEmpty)
                            Text(m.subject,
                                style: MqType.caption.copyWith(color: p.ink3)),
                          MqNum(
                              '${m.session.plannedStart.toLocal().day}/${m.session.plannedStart.toLocal().month}',
                              style: MqType.small.copyWith(color: p.ink3)),
                          const SizedBox(height: 10),
                          if (m.decision == null)
                            Text('لم يُتخذ قرار استعادة لها بعد.',
                                style: MqType.small.copyWith(color: p.ink2))
                          else ...[
                            Text(decisionLabel(m.decision!.decision),
                                style: MqType.body.copyWith(
                                    color: p.brand, fontWeight: FontWeight.w600)),
                            if (m.decision!.reasoning.isNotEmpty)
                              Text(m.decision!.reasoning,
                                  style: MqType.caption.copyWith(color: p.ink3)),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
