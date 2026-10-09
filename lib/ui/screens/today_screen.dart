import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../engines/scheduling_engine.dart';
import '../../engines/weekly_timeline_engine.dart' show WeekCalendar;
import '../../repositories/availability_repository.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/study_session_repository.dart';
import '../../services/planning_service.dart';
import '../state/app_state.dart';
import '../design/motion.dart';
import '../design/primitives.dart';
import '../design/progress.dart';
import '../design/states.dart';
import '../design/tokens.dart';

/// «اليوم» (D-1 S05 / S06): the plan of the day and of the week, read from the
/// study sessions that PlanningService (phase B) saved. The Sunday-first week
/// comes from WeekCalendar. Nothing is computed here: this screen lists what
/// is stored and asks the planning service to (re)generate the week.
///
/// What this first version shows: the saved study sessions, each with its
/// state (planned / done / missed — taken from the stored actual and the
/// clock), the planned minutes, and the result of the last generation (sessions
/// saved, tasks that did not fit, with the scheduler's own reason).
/// Fixed blocks (school, sleep, …), the available-time budget, the month and
/// year views and the planned-vs-actual screens are separate screens of the
/// next batches.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, this.active = true});

  /// True while this tab is the visible one. The shell keeps the tab alive
  /// (IndexedStack), so the data is re-read each time it becomes visible.
  final bool active;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _PlanData {
  const _PlanData({
    required this.shown,
    required this.weekHasSessions,
    required this.hasAvailability,
    required this.taskNames,
    required this.subjectNames,
  });

  /// Sessions inside the range being shown (a day or the week).
  final List<StudySession> shown;

  /// Whether the whole week has at least one saved session.
  final bool weekHasSessions;

  /// Whether the student has entered any availability window at all.
  final bool hasAvailability;
  final Map<String, String> taskNames;
  final Map<String, String> subjectNames;
}

class _TodayScreenState extends State<TodayScreen> {
  bool _week = false;
  bool _loadedOnce = false;
  Future<_PlanData>? _future;
  PlanGenerationResult? _lastResult;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      // No setState here: the first build has not happened yet.
      _loadedOnce = true;
      _future = _load(context.read<AppState>());
    }
  }

  @override
  void didUpdateWidget(TodayScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && (!old.active || !_loadedOnce)) _reload();
  }

  void _reload() {
    final appState = context.read<AppState>();
    setState(() {
      _loadedOnce = true;
      _future = _load(appState);
    });
  }

  Future<_PlanData> _load(AppState appState) async {
    final db = appState.db;
    final now = DateTime.now();
    final weekStart = WeekCalendar.startOfWeek(now);
    final weekEnd = WeekCalendar.endOfWeek(weekStart);
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = DateTime(now.year, now.month, now.day + 1);

    final sessionRepo = StudySessionRepository(db);
    final weekSessions = await sessionRepo.readOverlapping(weekStart, weekEnd);
    final shown = _week
        ? weekSessions
        : weekSessions
            .where((s) =>
                s.plannedStart.isBefore(dayEnd) &&
                s.plannedEnd.isAfter(dayStart))
            .toList();

    final availability = await AvailabilityRepository(db)
        .readForStudent(appState.studentId!);

    final content = ContentRepository(db);
    final taskNames = <String, String>{};
    final subjectNames = <String, String>{};
    for (final taskId in {for (final s in weekSessions) s.taskId}) {
      final task = await (db.select(db.tasks)
            ..where((t) => t.id.equals(taskId)))
          .getSingleOrNull();
      if (task == null) continue;
      taskNames[taskId] = await content.nameForNode(task.knowledgeNodeId);
      subjectNames[taskId] =
          await content.subjectNameForNode(task.knowledgeNodeId);
    }

    return _PlanData(
      shown: shown,
      weekHasSessions: weekSessions.isNotEmpty,
      hasAvailability: availability.isNotEmpty,
      taskNames: taskNames,
      subjectNames: subjectNames,
    );
  }

  Future<void> _generate({required bool replan}) async {
    final db = context.read<AppState>().db;
    final service = PlanningService(db);
    setState(() => _actionError = null);
    try {
      final result =
          replan ? await service.replanNow() : await service.generateWeekPlan();
      if (!mounted) return;
      setState(() => _lastResult = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = '$e');
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final future = _future;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(MqSpace.screen, 12, MqSpace.screen, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(_week ? 'خطة الأسبوع' : 'خطة اليوم',
                    style: MqType.h1.copyWith(color: p.ink, fontSize: 24)),
              ),
              MqIconButton(icon: Icons.refresh_rounded, label: 'تحديث', onTap: _reload),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MqSpace.screen),
          child: MqSegmented<bool>(
            options: const {false: 'اليوم', true: 'الأسبوع'},
            selected: _week,
            onChanged: (v) {
              _week = v;
              _reload();
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: future == null
              ? const SizedBox.shrink()
              : FutureBuilder<_PlanData>(
                  future: future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return ListView(
                        padding: const EdgeInsets.all(MqSpace.screen),
                        children: const [
                          MqLoadingCard(lines: 3),
                          SizedBox(height: 12),
                          MqLoadingCard(lines: 2),
                        ],
                      );
                    }
                    if (snap.hasError) {
                      return Center(
                        child: MqErrorState(
                          title: 'تعذّر تحميل الخطة',
                          message: 'لم تتغير بياناتك. حاول مرة أخرى.',
                          detail: '${snap.error}',
                          onRetry: _reload,
                        ),
                      );
                    }
                    return _body(context, snap.data!);
                  },
                ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, _PlanData data) {
    final p = context.mq;
    final children = <Widget>[
      _SummaryCard(sessions: data.shown),
      if (!data.hasAvailability)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: MqBanner(
            icon: Icons.info_outline_rounded,
            tone: MqTone.info,
            text: 'الخطة تُبنى على أوقات التفرغ التي تُدخلها أنت. لا نوافذ '
                'تفرغ مُدخلة بعد، لذلك تبقى الخطة فارغة ولا نفترض لك جدولًا.',
          ),
        ),
      if (_actionError != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: MqBanner(
            icon: Icons.error_outline_rounded,
            tone: MqTone.overdue,
            title: 'تعذّر تحديث الخطة',
            text: _actionError!,
          ),
        ),
      const SizedBox(height: 14),
      if (data.shown.isEmpty)
        MqEmptyState(
          icon: Icons.event_busy_outlined,
          title: 'لا جلسات هنا',
          message: data.weekHasSessions && !_week
              ? 'لا جلسات مخطَّطة لهذا اليوم. جلسات هذا الأسبوع في «الأسبوع».'
              : 'لم تُبنَ خطة بعد. ستُبنى من مهامك وأولوياتها وأوقات تفرغك.',
        )
      else if (_week)
        ..._weekList(data)
      else
        ...data.shown.map((s) => _SessionTile(session: s, data: data)),
      const SizedBox(height: 16),
      MqButton(
        label: data.weekHasSessions
            ? 'أعد تخطيط هذا الأسبوع'
            : 'ولّد خطة هذا الأسبوع',
        icon: data.weekHasSessions
            ? Icons.refresh_rounded
            : Icons.auto_awesome_rounded,
        kind: data.weekHasSessions ? MqButtonKind.secondary : MqButtonKind.primary,
        block: true,
        onPressed: () => _generate(replan: data.weekHasSessions),
      ),
      if (_lastResult != null) ...[
        const SizedBox(height: 16),
        _ResultCard(result: _lastResult!, taskNames: data.taskNames),
      ],
    ];
    return RefreshIndicator(
      color: p.brand,
      backgroundColor: p.surface,
      onRefresh: () async => _reload(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(MqSpace.screen, 4, MqSpace.screen, 28),
        children: [
          for (var i = 0; i < children.length; i++)
            i < 6 ? MqReveal(index: i, child: children[i]) : children[i],
        ],
      ),
    );
  }

  List<Widget> _weekList(_PlanData data) {
    final p = context.mq;
    final weekStart = WeekCalendar.startOfWeek(DateTime.now());
    final days = WeekCalendar.daysOf(weekStart);
    final widgets = <Widget>[];
    for (final day in days) {
      final next = DateTime(day.year, day.month, day.day + 1);
      final inDay = data.shown
          .where((s) => s.plannedStart.isBefore(next) && s.plannedEnd.isAfter(day))
          .toList();
      final name = WeekCalendar.arabicDayNames[WeekCalendar.indexInWeek(day)];
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(
          children: [
            Text(name, style: MqType.h3.copyWith(color: p.ink)),
            const SizedBox(width: 8),
            MqNum('${day.day}/${day.month}',
                style: MqType.caption.copyWith(color: p.ink3)),
            const Spacer(),
            MqNum('${_minutes(inDay)} د',
                style: MqType.caption.copyWith(color: p.ink3)),
          ],
        ),
      ));
      if (inDay.isEmpty) {
        widgets.add(Text('لا جلسات مخطَّطة',
            style: MqType.caption.copyWith(color: p.ink3)));
      } else {
        widgets.addAll(inDay.map((s) => _SessionTile(session: s, data: data)));
      }
    }
    return widgets;
  }
}

int _minutes(List<StudySession> sessions) => sessions.fold<int>(
    0, (sum, s) => sum + s.plannedEnd.difference(s.plannedStart).inMinutes);

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.sessions});
  final List<StudySession> sessions;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final done = sessions.where((s) => s.actualEnd != null).length;
    final now = DateTime.now();
    final missed = sessions
        .where((s) => s.actualStart == null && s.plannedEnd.isBefore(now))
        .length;
    final total = sessions.length;
    return MqCard(
      child: Row(
        children: [
          MqRing(
            value: total == 0 ? 0 : done / total,
            size: 72,
            thickness: 8,
            color: p.ok,
            track: p.okSoft,
            center: MqNum('$done/$total', style: MqType.label),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              children: [
                _Stat(label: 'دقيقة مخطَّطة', value: '${_minutes(sessions)}'),
                _Stat(label: 'فائتة', value: '$missed', warn: missed > 0),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.warn = false});
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MqNum(value,
              style: MqType.display.copyWith(fontSize: 26),
              color: warn ? p.overdue : p.ink),
          Text(label, style: MqType.caption.copyWith(color: p.ink3)),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.data});
  final StudySession session;
  final _PlanData data;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final now = DateTime.now();
    final String status;
    final MqTone tone;
    if (session.actualEnd != null) {
      status = 'منجزة';
      tone = MqTone.ok;
    } else if (session.actualStart == null && session.plannedEnd.isBefore(now)) {
      status = 'فائتة';
      tone = MqTone.overdue;
    } else {
      status = 'مخطَّطة';
      tone = MqTone.brand;
    }
    final subject = data.subjectNames[session.taskId] ?? '';
    final st = p.toneFor(subject);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MqCard(
        padding: const EdgeInsets.all(12),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: st.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MqNum(_hhmm(session.plannedStart), style: MqType.label),
                  MqNum(_hhmm(session.plannedEnd),
                      style: MqType.caption.copyWith(color: p.ink3)),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(data.taskNames[session.taskId] ?? 'مهمة محذوفة',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MqType.body.copyWith(
                            color: p.ink, fontWeight: FontWeight.w600)),
                    Text(
                      [
                        if (subject.isNotEmpty) subject,
                        '${session.plannedEnd.difference(session.plannedStart).inMinutes} دقيقة',
                      ].join(' · '),
                      style: MqType.caption.copyWith(color: p.ink3),
                    ),
                  ],
                ),
              ),
              MqChip(label: status, tone: tone),
            ],
          ),
        ),
      ),
    );
  }
}

/// The outcome of the last generation, exactly as the service returned it.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.taskNames});
  final PlanGenerationResult result;
  final Map<String, String> taskNames;

  String _reason(UnscheduledEntry e) {
    if (e.reason == UnscheduledReason.noSlotAvailable) {
      return 'لا يتّسع له وقت في الأسبوع';
    }
    if (e.reason == UnscheduledReason.partiallyScheduled) {
      return 'جُدول جزء منه، والمتبقي ${e.minutesRemaining ?? '؟'} دقيقة';
    }
    if (e.reason == UnscheduledReason.prerequisiteNotSatisfied) {
      return 'ينقصه متطلب سابق لم يُتقَن بعد';
    }
    return e.reason.name;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqCard(
      kind: MqCardKind.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('نتيجة آخر تخطيط', style: MqType.h3.copyWith(color: p.ink)),
          const SizedBox(height: 8),
          Text(
              'جلسات محفوظة: ${result.sessionsSaved} · دقائق مجدولة: ${result.scheduledMinutes}',
              style: MqType.small.copyWith(color: p.ink2)),
          if (result.emergencyActive)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('وضع الطوارئ فعّال في هذا التخطيط.',
                  style: MqType.small.copyWith(color: p.ink2)),
            ),
          if (result.unprioritizedTaskIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'مهام بلا أولوية محسوبة بعد: ${result.unprioritizedTaskIds.length} (وُضعت بعد المهام ذات الأولوية)',
                  style: MqType.small.copyWith(color: p.ink2)),
            ),
          if (result.unscheduled.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('لم تُجدول كاملة:',
                style: MqType.label.copyWith(color: p.ink)),
            for (final u in result.unscheduled)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• ${taskNames[u.taskId] ?? 'مهمة'} — ${_reason(u)}',
                    style: MqType.small.copyWith(color: p.ink2)),
              ),
          ],
        ],
      ),
    );
  }
}
