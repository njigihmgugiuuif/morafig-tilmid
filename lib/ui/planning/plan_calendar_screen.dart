import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../engines/weekly_timeline_engine.dart';
import '../../repositories/study_session_repository.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';

/// «الشهر والسنة» (P01/P02): read-only. A week that has no stored plan shows
/// «لم يُخطَّط بعد» — nothing is projected or invented for the future.
class PlanCalendarScreen extends StatefulWidget {
  const PlanCalendarScreen({super.key});
  @override
  State<PlanCalendarScreen> createState() => _PlanCalendarScreenState();
}

class _PlanCalendarScreenState extends State<PlanCalendarScreen> {
  bool _year = false;
  late DateTime _anchor = DateTime(DateTime.now().year, DateTime.now().month);

  static const _months = [
    'جانفي', 'فيفري', 'مارس', 'أفريل', 'ماي', 'جوان',
    'جويلية', 'أوت', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

  Future<List<StudySession>> _load(AppDatabase db) {
    final from = _year ? DateTime(_anchor.year) : _anchor;
    final to = _year
        ? DateTime(_anchor.year + 1)
        : DateTime(_anchor.year, _anchor.month + 1);
    return StudySessionRepository(db).readOverlapping(from, to);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.mq;
    final title = _year ? '${_anchor.year}' : '${_months[_anchor.month - 1]} ${_anchor.year}';
    return MqPage(
      title: 'الشهر والسنة',
      children: [
        MqSegmented<bool>(
            options: const {false: 'الشهر', true: 'السنة'},
            selected: _year,
            onChanged: (v) => setState(() => _year = v)),
        const SizedBox(height: 10),
        Row(children: [
          MqIconButton(
              icon: Icons.arrow_forward_rounded,
              label: 'السابق',
              onTap: () => setState(() => _anchor = _year
                  ? DateTime(_anchor.year - 1)
                  : DateTime(_anchor.year, _anchor.month - 1))),
          Expanded(
              child: Center(
                  child: MqNum(title, style: MqType.h2, color: p.ink))),
          MqIconButton(
              icon: Icons.arrow_back_rounded,
              label: 'التالي',
              onTap: () => setState(() => _anchor = _year
                  ? DateTime(_anchor.year + 1)
                  : DateTime(_anchor.year, _anchor.month + 1))),
        ]),
        const SizedBox(height: 12),
        MqAsync<List<StudySession>>(
          reloadKey: '$_year-$_anchor',
          load: () => _load(app.db),
          errorTitle: 'تعذّر عرض الخطة',
          builder: (context, rows) {
            final byDay = <DateTime, int>{};
            for (final s in rows) {
              final l = s.plannedStart.toLocal();
              final d = DateTime(l.year, l.month, l.day);
              byDay[d] = (byDay[d] ?? 0) +
                  s.plannedEnd.difference(s.plannedStart).inMinutes;
            }
            if (rows.isEmpty) {
              return const MqEmptyState(
                  icon: Icons.calendar_month_outlined,
                  title: 'لم يُخطَّط بعد',
                  message:
                      'لا توجد جلسات محفوظة في هذه الفترة. الخطة تُبنى أسبوعًا بأسبوع ولا نخمّن المستقبل.');
            }
            return _year ? _yearView(p, byDay) : _monthView(p, byDay);
          },
        ),
      ],
    );
  }

  Widget _monthView(MqPalette p, Map<DateTime, int> byDay) {
    final first = DateTime(_anchor.year, _anchor.month);
    final days = DateTime(_anchor.year, _anchor.month + 1)
        .difference(first)
        .inDays;
    final lead = WeekCalendar.indexInWeek(first);
    final cells = <Widget>[
      for (final n in WeekCalendar.arabicDayNames)
        Center(
            child: Text(n.substring(0, 2),
                style: MqType.caption.copyWith(color: p.ink3))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++)
        _cell(p, d, byDay[DateTime(_anchor.year, _anchor.month, d)] ?? 0),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: cells,
    );
  }

  Widget _cell(MqPalette p, int d, int minutes) => Container(
        decoration: BoxDecoration(
          color: minutes > 0 ? p.brandSoft : p.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          MqNum('$d', style: MqType.body, color: p.ink),
          if (minutes > 0)
            MqNum('$minutes', style: MqType.caption, color: p.brandDeep),
        ]),
      );

  Widget _yearView(MqPalette p, Map<DateTime, int> byDay) {
    final perMonth = List<int>.filled(12, 0);
    byDay.forEach((d, m) => perMonth[d.month - 1] += m);
    return Column(children: [
      for (var i = 0; i < 12; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MqCard(
            child: Row(children: [
              Expanded(
                  child: Text(_months[i],
                      style: MqType.h3.copyWith(color: p.ink))),
              perMonth[i] == 0
                  ? Text('لم يُخطَّط بعد',
                      style: MqType.caption.copyWith(color: p.ink3))
                  : Row(children: [
                      MqNum('${perMonth[i]}',
                          style: MqType.body, color: p.ink),
                      Text(' دقيقة',
                          style: MqType.caption.copyWith(color: p.ink3)),
                    ]),
            ]),
          ),
        ),
    ]);
  }
}
