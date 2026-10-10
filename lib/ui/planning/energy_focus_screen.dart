import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../repositories/energy_focus_repository.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';

/// «طاقتي وتركيزي» (A04): the student logs how energy and focus felt. It is a
/// plain record — no engine reads it and nothing is inferred from it.
class EnergyFocusScreen extends StatefulWidget {
  const EnergyFocusScreen({super.key});
  @override
  State<EnergyFocusScreen> createState() => _EnergyFocusScreenState();
}

class _EnergyFocusScreenState extends State<EnergyFocusScreen> {
  int _energy = 3, _focus = 3, _tick = 0;

  Widget _scale(String label, int v, ValueChanged<int> on) {
    final p = context.mq;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: MqType.h3.copyWith(color: p.ink)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        for (var i = 1; i <= 5; i++)
          ChoiceChip(
              label: MqNum('$i', style: MqType.body, color: p.ink),
              selected: v == i,
              onSelected: (_) => on(i)),
      ]),
    ]);
  }

  Future<void> _save(AppState app) async {
    await EnergyFocusRepository(app.db).insertFromUser(
        studentId: app.studentId!,
        loggedAt: DateTime.now(),
        energyLevel: _energy,
        focusLevel: _focus);
    if (mounted) setState(() => _tick++);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.mq;
    return MqPage(
      title: 'طاقتي وتركيزي',
      children: [
        const MqBanner(
            icon: Icons.info_outline_rounded,
            tone: MqTone.neutral,
            text: 'من ١ (منخفض) إلى ٥ (مرتفع). يُحفظ كسجلّ فقط ولا يغيّر خطتك.'),
        const SizedBox(height: 12),
        _scale('طاقتي الآن', _energy, (v) => setState(() => _energy = v)),
        const SizedBox(height: 12),
        _scale('تركيزي الآن', _focus, (v) => setState(() => _focus = v)),
        const SizedBox(height: 14),
        MqButton(label: 'سجّل', block: true, onPressed: () => _save(app)),
        const SizedBox(height: 18),
        MqSectionTitle('آخر التسجيلات'),
        MqAsync<List<EnergyFocusLog>>(
          reloadKey: _tick,
          load: () => EnergyFocusRepository(app.db).readForStudent(app.studentId!),
          builder: (c, rows) {
            if (rows.isEmpty) {
              return const MqEmptyState(
                  icon: Icons.battery_charging_full_outlined,
                  title: 'لا تسجيلات بعد',
                  message: 'ستظهر هنا بعد أول تسجيل.');
            }
            return Column(children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MqCard(
                    child: Row(children: [
                      MqNum(
                          '${r.loggedAt.toLocal().day}/${r.loggedAt.toLocal().month} ${r.loggedAt.toLocal().hour.toString().padLeft(2, '0')}:${r.loggedAt.toLocal().minute.toString().padLeft(2, '0')}',
                          style: MqType.caption,
                          color: p.ink3),
                      const Spacer(),
                      Text('طاقة ', style: MqType.caption.copyWith(color: p.ink2)),
                      MqNum('${r.energyLevel}', style: MqType.body, color: p.ink),
                      Text('  تركيز ', style: MqType.caption.copyWith(color: p.ink2)),
                      MqNum('${r.focusLevel}', style: MqType.body, color: p.ink),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}
