import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/goal_repository.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/sheet.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';

/// «أهدافي» (D-2 Q04): the goals the student typed in. They are recorded and
/// shown, and they do not change the priority yet: the definition of
/// «alignment with a goal» is an open decision, so nothing is invented here.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  int _tick = 0;

  Future<void> _add() async {
    final ok = await showMqSheet<bool>(
      context,
      title: 'هدف جديد',
      builder: (ctx) => const _AddGoalBody(),
    );
    if (ok == true && mounted) setState(() => _tick++);
  }

  Future<void> _setStatus(Goal g, String status) async {
    await GoalRepository(context.read<AppState>().db).setStatus(g.id, status);
    if (mounted) setState(() => _tick++);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.mq;
    return MqPage(
      title: 'أهدافي',
      floating: MqFab(label: 'هدف جديد', icon: Icons.add_rounded, onPressed: _add),
      reveal: false,
      bodyBuilder: (context) => MqAsync<List<Goal>>(
        reloadKey: _tick,
        load: () => GoalRepository(app.db).readForStudent(app.studentId!),
        loading: const Padding(
            padding: EdgeInsets.all(MqSpace.screen), child: MqLoadingCard(lines: 3)),
        errorTitle: 'تعذّر عرض الأهداف',
        builder: (context, goals) => ListView(
          padding:
              const EdgeInsets.fromLTRB(MqSpace.screen, 4, MqSpace.screen, 96),
          children: [
            const MqBanner(
              icon: Icons.info_outline_rounded,
              tone: MqTone.neutral,
              text: 'الأهداف تُسجَّل وتُعرض هنا، ولا تغيّر ترتيب مهامك بعد.',
            ),
            const SizedBox(height: 12),
            if (goals.isEmpty)
              MqEmptyState(
                icon: Icons.flag_outlined,
                title: 'لا أهداف بعد',
                message: 'اكتب ما تريد الوصول إليه، مع تاريخ إن كان لك موعد.',
                actionLabel: 'هدف جديد',
                onAction: _add,
              ),
            for (final g in goals)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MqCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(g.title,
                                  style: MqType.h3.copyWith(color: p.ink))),
                          MqChip(
                            label: g.status == GoalRepository.statusAchieved
                                ? 'تحقق'
                                : g.status == GoalRepository.statusDropped
                                    ? 'متروك'
                                    : 'فعّال',
                            tone: g.status == GoalRepository.statusAchieved
                                ? MqTone.ok
                                : g.status == GoalRepository.statusDropped
                                    ? MqTone.neutral
                                    : MqTone.brand,
                          ),
                        ],
                      ),
                      if (g.targetDate != null)
                        MqNum(
                            '${g.targetDate!.toLocal().day}/${g.targetDate!.toLocal().month}/${g.targetDate!.toLocal().year}',
                            style: MqType.small.copyWith(color: p.ink3)),
                      if (g.status == GoalRepository.statusActive) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: MqButton(
                                label: 'تحقق',
                                icon: Icons.check_rounded,
                                small: true,
                                kind: MqButtonKind.secondary,
                                block: true,
                                onPressed: () =>
                                    _setStatus(g, GoalRepository.statusAchieved),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: MqButton(
                                label: 'أتركه',
                                small: true,
                                kind: MqButtonKind.ghost,
                                block: true,
                                onPressed: () =>
                                    _setStatus(g, GoalRepository.statusDropped),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddGoalBody extends StatefulWidget {
  const _AddGoalBody();
  @override
  State<_AddGoalBody> createState() => _AddGoalBodyState();
}

class _AddGoalBodyState extends State<_AddGoalBody> {
  final _title = TextEditingController();
  final _subject = TextEditingController();
  DateTime? _date;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'اكتب هدفك أولًا.');
      return;
    }
    final app = context.read<AppState>();
    String? subjectId;
    if (_subject.text.trim().isNotEmpty) {
      final content = ContentRepository(app.db);
      final level = await content.getOrCreateDefaultLevel();
      subjectId = (await content.getOrCreateSubject(
        educationLevelId: level.id,
        name: _subject.text,
      ))
          .id;
    }
    await GoalRepository(app.db).insertFromUser(
      studentId: app.studentId!,
      title: _title.text,
      subjectId: subjectId,
      targetDate: _date,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'هدفك')),
        const SizedBox(height: 12),
        TextField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'المادة (اختياري)')),
        const SizedBox(height: 12),
        MqPressable(
          onTap: () async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: _date ?? now.add(const Duration(days: 30)),
              firstDate: DateTime(now.year, now.month, now.day),
              lastDate: DateTime(now.year + 3, 12, 31),
            );
            if (d != null) setState(() => _date = d);
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
              Text('تاريخ مستهدف (اختياري): ',
                  style: MqType.body.copyWith(color: p.ink2)),
              if (_date != null)
                MqNum('${_date!.day}/${_date!.month}/${_date!.year}',
                    style: MqType.body),
            ]),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: MqType.small.copyWith(color: p.overdue)),
        ],
        const SizedBox(height: 16),
        MqButton(label: 'حفظ', icon: Icons.check_rounded, block: true, onPressed: _save),
      ],
    );
  }
}
