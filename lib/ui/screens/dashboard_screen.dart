import 'package:drift/drift.dart'
    show OrderingMode, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../design/logo.dart';
import '../design/motion.dart';
import '../design/primitives.dart';
import '../design/progress.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';
import '../state/home_data.dart';
import '../widgets/priority_views.dart';
import 'now_screen.dart';
import 'settings_screen.dart';
import 'task_detail_screen.dart';

class _HomeBundle {
  const _HomeBundle(this.snapshot, this.workload);
  final HomeSnapshot snapshot;
  final WorkloadState? workload;
}

/// «الرئيسية» (D-1 S03): the first screen. It answers one question — what
/// should I do now — and shows the identity, the day's figures and what needs
/// attention around it. Everything is read from what the engines stored
/// (HomeData); nothing is computed here.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onGoToTab, this.active = true});

  /// Jumps to a tab of the shell (0 home, 1 today, 2 tasks, 3 progress).
  final ValueChanged<int>? onGoToTab;

  /// True while this tab is visible; the data is re-read when it becomes so.
  final bool active;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tick = 0;

  @override
  void didUpdateWidget(DashboardScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _tick++;
  }

  Future<_HomeBundle> _load(AppState s) async {
    final db = s.db;
    final snap = await HomeData(db).loadHome(studentId: s.studentId!);
    final workload = await (db.select(db.workloadStates)
          ..where((t) => t.studentId.equals(s.studentId!))
          ..orderBy([
            (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();
    return _HomeBundle(snap, workload);
  }

  void _open(Widget screen) async {
    final r = await Navigator.of(context)
        .push<Object?>(MaterialPageRoute<Object?>(builder: (_) => screen));
    if (r == true && mounted) setState(() => _tick++);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final app = context.watch<AppState>();
    if (app.studentId == null) return const SizedBox.shrink();

    return RefreshIndicator(
      color: p.brand,
      backgroundColor: p.surface,
      onRefresh: () async {
        await app.runAppOpen();
        if (mounted) setState(() => _tick++);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(MqSpace.screen, 12, MqSpace.screen, 28),
        children: [
          MqReveal(index: 0, child: _IdentityRow(onSettings: () => _open(const SettingsScreen()))),
          const SizedBox(height: 14),
          MqAsync<_HomeBundle>(
            reloadKey: '$_tick-${app.lastAppOpen.hashCode}',
            load: () => _load(app),
            loading: const Column(children: [
              MqLoadingCard(lines: 4),
              SizedBox(height: 12),
              MqLoadingCard(lines: 2),
            ]),
            errorTitle: 'تعذّر تحميل الرئيسية',
            builder: (context, b) => _Body(
              bundle: b,
              app: app,
              onOpen: _open,
              onGoToTab: widget.onGoToTab,
            ),
          ),
        ],
      ),
    );
  }
}

/// The identity of the product, always visible on the first screen: the
/// institution, the app name and its tagline (never dropped).
class _IdentityRow extends StatelessWidget {
  const _IdentityRow({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Row(
      children: [
        const MqLogoTile(size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ثانوية رابح بطاط',
                  style: MqType.caption.copyWith(color: p.ink3)),
              Text('مرافق التلميذ', style: MqType.h2.copyWith(color: p.ink)),
              Text('المرافقة والتنظيم الدراسي طوال العام',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MqType.caption.copyWith(color: p.ink2)),
            ],
          ),
        ),
        MqIconButton(
            icon: Icons.settings_outlined,
            label: 'الإعدادات',
            onTap: onSettings),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.bundle,
    required this.app,
    required this.onOpen,
    required this.onGoToTab,
  });
  final _HomeBundle bundle;
  final AppState app;
  final void Function(Widget) onOpen;
  final ValueChanged<int>? onGoToTab;

  static const _days = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد'
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final s = bundle.snapshot;
    final now = DateTime.now();
    final date = '${_days[now.weekday - 1]} ${now.day}/${now.month}';
    final nowItem = s.now;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.studentName.trim().isEmpty
                    ? 'مرحبًا'
                    : 'مرحبًا، ${s.studentName.trim()}',
                style: MqType.h1.copyWith(color: p.ink),
              ),
              Text(date, style: MqType.small.copyWith(color: p.ink3)),
            ],
          ),
        ),
        _AppOpenBanner(app: app),
        if (nowItem != null)
          NowHero(
            item: nowItem,
            startLabel: 'ابدأ',
            onStart: () => onOpen(NowScreen(item: nowItem)),
            onWhy: () => showWhySheet(context, nowItem),
          )
        else
          MqEmptyState(
            icon: Icons.task_alt_rounded,
            title: 'لا شيء عاجل الآن',
            message: s.openTasks == 0
                ? 'لا مهام مفتوحة. أضف مهمة من تبويب «المهام» وستظهر أولويتها هنا.'
                : 'لم تُحسب أولويات بعد. تُحسب عند معالجة مهامك.',
            actionLabel: 'إلى المهام',
            onAction: onGoToTab == null ? null : () => onGoToTab!(2),
          ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.layers_outlined,
                tone: MqTone.info,
                value: '${s.reviewsDue}',
                label: 'مراجعات مستحقة',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: Icons.school_outlined,
                tone: MqTone.accent,
                value: s.nearestExam == null
                    ? '—'
                    : (s.nearestExam!.daysAway <= 0
                        ? 'اليوم'
                        : '${s.nearestExam!.daysAway}'),
                label: s.nearestExam == null
                    ? 'لا امتحان مسجّل'
                    : (s.nearestExam!.daysAway <= 0
                        ? s.nearestExam!.subjectName
                        : 'يوم لـ ${s.nearestExam!.subjectName}'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _TodayTile(snapshot: s, onTap: () => onGoToTab?.call(1))),
          ],
        ),
        if (bundle.workload != null) ...[
          const SizedBox(height: 12),
          _WorkloadCard(state: bundle.workload!),
        ],
        if (s.lowestMastery.isNotEmpty) ...[
          const SizedBox(height: 6),
          MqSectionTitle('يحتاج انتباهك',
              trailing: 'التقدم', onTrailing: () => onGoToTab?.call(3)),
          for (final m in s.lowestMastery)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MqCard(
                kind: MqCardKind.soft,
                child: Row(
                  children: [
                    MqRing(
                      value: m.probability.clamp(0.0, 1.0),
                      size: 44,
                      thickness: 5,
                      color: p.overdue,
                      track: p.overdueSoft,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.nodeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MqType.body.copyWith(color: p.ink)),
                          if (m.subjectName.isNotEmpty)
                            Text(m.subjectName,
                                style: MqType.caption.copyWith(color: p.ink3)),
                        ],
                      ),
                    ),
                    MqNum('${(m.probability * 100).round()}%',
                        style: MqType.label),
                  ],
                ),
              ),
            ),
        ],
        if (s.alternatives.isNotEmpty) ...[
          const SizedBox(height: 6),
          MqSectionTitle('بدائل أخرى',
              trailing: 'كل المهام', onTrailing: () => onGoToTab?.call(2)),
          for (final a in s.alternatives)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RankedTaskRow(
                item: a,
                onTap: () => onOpen(TaskDetailScreen(task: a.task)),
              ),
            ),
        ],
      ],
    );
  }
}

/// What the app did when it was opened (PlanningService.onAppOpen): replanned,
/// found missed sessions, or failed. Shown, never silent.
class _AppOpenBanner extends StatelessWidget {
  const _AppOpenBanner({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    if (app.appOpenRunning) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: MqBanner(
            icon: Icons.sync_rounded,
            tone: MqTone.info,
            text: 'نراجع خطتك…'),
      );
    }
    final err = app.lastAppOpenError;
    if (err != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: MqBanner(
          icon: Icons.error_outline_rounded,
          tone: MqTone.overdue,
          title: 'تعذّرت مراجعة الخطة',
          text: 'يمكنك المتابعة، وسنحاول مجددًا عند السحب للتحديث.',
          action: MqButton(
              label: 'أعد المحاولة',
              small: true,
              kind: MqButtonKind.secondary,
              onPressed: app.runAppOpen),
        ),
      );
    }
    final r = app.lastAppOpen;
    if (r == null || (r.status == 'unchanged' && r.missedTaskIds.isEmpty)) {
      return const SizedBox.shrink();
    }
    final parts = <String>[
      if (r.replanned) 'حُدّثت خطتك.',
      if (r.missedTaskIds.isNotEmpty)
        'فاتتك ${r.missedTaskIds.length} مهمة وأُعيد ترتيبها.',
      if (r.errors.isNotEmpty) 'بعض الخطوات لم تكتمل.',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MqBanner(
        icon: Icons.auto_awesome_rounded,
        tone: r.errors.isEmpty ? MqTone.brand : MqTone.accent,
        text: parts.join(' '),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.tone,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final MqTone tone;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MqIconTile(icon: icon, tone: tone, size: 34),
          const SizedBox(height: 10),
          MqNum(value, style: MqType.display.copyWith(fontSize: 26)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MqType.caption.copyWith(color: p.ink3)),
        ],
      ),
    );
  }
}

class _TodayTile extends StatelessWidget {
  const _TodayTile({required this.snapshot, required this.onTap});
  final HomeSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final total = snapshot.todaySessions;
    final done = snapshot.todayDone;
    return MqCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      semanticLabel: 'جلسات اليوم',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MqRing(
            value: total == 0 ? 0 : done / total,
            size: 34,
            thickness: 4,
            color: p.ok,
            track: p.okSoft,
          ),
          const SizedBox(height: 10),
          MqNum('$done/$total', style: MqType.display.copyWith(fontSize: 26)),
          const SizedBox(height: 2),
          Text(total == 0 ? 'لا جلسات اليوم' : 'جلسات اليوم',
              style: MqType.caption.copyWith(color: p.ink3)),
        ],
      ),
    );
  }
}

class _WorkloadCard extends StatelessWidget {
  const _WorkloadCard({required this.state});
  final WorkloadState state;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final (label, tone) = switch (state.status) {
      'underload' => ('عبء خفيف', MqTone.ok),
      'balanced' => ('عبء متوازن', MqTone.brand),
      'overload' => ('عبء زائد', MqTone.accent),
      'impossible' => ('غير قابل للتحقيق بالوقت الحالي', MqTone.overdue),
      _ => ('عبء غير معروف', MqTone.neutral),
    };
    return MqCard(
      kind: MqCardKind.soft,
      child: Row(
        children: [
          MqIconTile(icon: Icons.speed_rounded, tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: MqType.h3.copyWith(color: p.ink)),
                Text(
                  'المطلوب ${state.totalEstimatedTimeNeededMinutes} د · المتاح ${state.totalAvailableTimeMinutes} د',
                  style: MqType.caption.copyWith(color: p.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
