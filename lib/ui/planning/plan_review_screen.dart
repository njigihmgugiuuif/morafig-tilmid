import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../engines/weekly_timeline_engine.dart';
import '../../repositories/content_repository.dart';
import '../../services/planning_service.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';

Future<String> _taskName(AppDatabase db, String taskId) async {
  final t = await (db.select(db.tasks)..where((x) => x.id.equals(taskId)))
      .getSingleOrNull();
  if (t == null) return 'مهمة';
  return ContentRepository(db).nameForNode(t.knowledgeNodeId);
}

Future<Map<String, String>> _namesFor(AppDatabase db, Iterable<String> ids) async {
  final out = <String, String>{};
  for (final id in ids) {
    out[id] = await _taskName(db, id);
  }
  return out;
}

String _gapLabel(String code) => 'ملاحظة من المخطِّط ($code)';

/// «مراجعة إعادة التخطيط» (S19) + «المخطَّط والفعلي» (P04) + الفجوات (P05).
/// Replanning is requested by the student; the screen shows what the planner
/// itself reports (changes, unscheduled tasks and its reasons). There is no
/// «تراجع» because the engine has no undo and none is invented.
class PlanReviewScreen extends StatefulWidget {
  const PlanReviewScreen({super.key});
  @override
  State<PlanReviewScreen> createState() => _PlanReviewScreenState();
}

class _PlanReviewScreenState extends State<PlanReviewScreen> {
  PlanGenerationResult? _result;
  Map<String, String> _names = {};
  bool _ran = false;
  int _reload = 0;

  Future<void> _replan(AppDatabase db) async {
    final r = await PlanningService(db).replanNow();
    final names = <String, String>{};
    if (r != null) {
      final ids = <String>{
        for (final c in r.changes) c.taskId,
        for (final u in r.unscheduled) u.taskId,
        for (final g in r.gaps)
          if (g.taskId != null) g.taskId!,
      };
      for (final id in ids) {
        names[id] = await _taskName(db, id);
      }
    }
    if (!mounted) return;
    setState(() {
      _result = r;
      _names = names;
      _ran = true;
      _reload++;
    });
  }

  String _kind(PlanChangeKind k) {
    switch (k) {
      case PlanChangeKind.added:
        return 'أُضيفت';
      case PlanChangeKind.removed:
        return 'أُزيلت';
      case PlanChangeKind.moved:
        return 'نُقلت';
      case PlanChangeKind.resized:
        return 'تغيّرت مدّتها';
    }
  }

  String _status(RealityStatus s) {
    switch (s) {
      case RealityStatus.onTrack:
        return 'كما خُطّط';
      case RealityStatus.overran:
        return 'أكثر من المخطَّط';
      case RealityStatus.shortened:
        return 'أقل من المخطَّط';
      default:
        return 'لم تُنجَز';
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.mq;
    final r = _result;
    return MqPage(
      title: 'مراجعة الخطة',
      children: [
        MqBanner(
          icon: Icons.info_outline_rounded,
          tone: MqTone.info,
          text:
              'إعادة التخطيط تحسب الأسبوع من جديد بما تعرفه الآن. نعرض لك ما تغيّر وأسبابه كما يذكرها المخطِّط، ولا يوجد تراجع تلقائي.',
        ),
        const SizedBox(height: 12),
        MqButton(
          label: 'أعد تخطيط هذا الأسبوع',
          icon: Icons.autorenew_rounded,
          block: true,
          onPressed: () => _replan(app.db),
        ),
        const SizedBox(height: 16),
        if (_ran && r == null)
          const MqEmptyState(
            icon: Icons.event_busy_outlined,
            title: 'لا يمكن التخطيط بعد',
            message: 'أضف أوقات فراغك من «واقعي» أولًا ثم أعد المحاولة.',
          ),
        if (r != null) ...[
          MqSectionTitle('نتيجة الإعادة'),
          MqCard(
            child: Row(children: [
              const Icon(Icons.event_available_rounded, size: 22),
              const SizedBox(width: 10),
              Expanded(
                  child: Row(children: [
                MqNum('${r.sessionsSaved}', style: MqType.h3, color: p.ink),
                Text(' جلسة · ', style: MqType.body.copyWith(color: p.ink)),
                MqNum('${r.scheduledMinutes}',
                    style: MqType.h3, color: p.ink),
                Text(' دقيقة', style: MqType.body.copyWith(color: p.ink)),
              ])),
            ]),
          ),
          const SizedBox(height: 12),
          MqSectionTitle('ما الذي تغيّر؟'),
          if (r.changes.isEmpty)
            Text('لم يتغيّر شيء عن الخطة السابقة.',
                style: MqType.body.copyWith(color: p.ink2))
          else
            for (final c in r.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MqCard(
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_names[c.taskId] ?? 'مهمة',
                              style: MqType.h3.copyWith(color: p.ink)),
                          Row(children: [
                            Text('${_kind(c.kind)} · ',
                                style: MqType.caption.copyWith(color: p.ink3)),
                            MqNum('${c.minutesBefore} ← ${c.minutesAfter}',
                                style: MqType.caption, color: p.ink3),
                            Text(' د',
                                style: MqType.caption.copyWith(color: p.ink3)),
                          ]),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
          if (r.unscheduled.isNotEmpty) ...[
            const SizedBox(height: 12),
            MqSectionTitle('لم تأخذ وقتها الكامل'),
            for (final u in r.unscheduled)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MqCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_names[u.taskId] ?? 'مهمة',
                          style: MqType.h3.copyWith(color: p.ink)),
                      Text('السبب: ${u.reason.name}',
                          style: MqType.caption.copyWith(color: p.ink3)),
                    ],
                  ),
                ),
              ),
          ],
          if (r.gaps.isNotEmpty) ...[
            const SizedBox(height: 12),
            MqSectionTitle('فجوات في تحضيرك'),
            for (final g in r.gaps)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MqCard(
                  child: Text(
                      '${g.taskId == null ? '' : '${_names[g.taskId] ?? ''} · '}${_gapLabel(g.code)}',
                      style: MqType.body.copyWith(color: p.ink)),
                ),
              ),
            Text(
                'حدّ اعتبار المتطلّب «ضعيفًا» لم يُعتمد بعد، لذلك نعرض ما يرصده المحرّك دون حكم نهائي.',
                style: MqType.caption.copyWith(color: p.ink3)),
          ],
          if (r.droppedTaskIds.isNotEmpty ||
              r.unprioritizedTaskIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
                'مهام مؤجَّلة مؤقتًا: ${r.droppedTaskIds.length} · بلا أولوية بعد: ${r.unprioritizedTaskIds.length}',
                style: MqType.caption.copyWith(color: p.ink3)),
          ],
        ],
        const SizedBox(height: 20),
        MqSectionTitle('المخطَّط مقابل الفعلي هذا الأسبوع'),
        MqAsync<List<TaskReality>>(
          reloadKey: _reload,
          load: () => PlanningService(app.db).compareWeekWithActual(),
          errorTitle: 'تعذّرت المقارنة',
          builder: (context, rows) {
            if (rows.isEmpty) {
              return const MqEmptyState(
                icon: Icons.compare_arrows_rounded,
                title: 'لا جلسات بعد',
                message: 'ستظهر المقارنة حين تكون لك جلسات مخطَّطة هذا الأسبوع.',
              );
            }
            return FutureBuilder<Map<String, String>>(
              future: _namesFor(app.db, rows.map((x) => x.taskId)),
              builder: (context, snap) {
                final n = snap.data ?? const <String, String>{};
                return Column(children: [
                  for (final x in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: MqCard(
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n[x.taskId] ?? 'مهمة',
                                    style: MqType.h3.copyWith(color: p.ink)),
                                Row(children: [
                                  Text('مخطَّط ',
                                      style: MqType.caption
                                          .copyWith(color: p.ink3)),
                                  MqNum('${x.plannedMinutes}',
                                      style: MqType.caption, color: p.ink3),
                                  Text(' · فعلي ',
                                      style: MqType.caption
                                          .copyWith(color: p.ink3)),
                                  MqNum('${x.actualMinutes}',
                                      style: MqType.caption, color: p.ink3),
                                ]),
                              ],
                            ),
                          ),
                          MqChip(label: _status(x.status)),
                        ]),
                      ),
                    ),
                ]);
              },
            );
          },
        ),
      ],
    );
  }
}
