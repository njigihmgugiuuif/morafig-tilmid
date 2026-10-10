import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../repositories/emergency_repository.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';

/// «وضع الطوارئ» (D-2 Q02): shows whether the plan is in emergency mode and
/// why. The mode is entered and left by the planner itself (with its own
/// hysteresis), so this screen only reads it: there is no manual switch to
/// invent. What the mode does is limited by the engine to the ORDER of tasks
/// and the workload ceilings; sleep, rest and prerequisites are never touched.
class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  String _trigger(String code) {
    switch (code) {
      case 'examProximity':
        return 'امتحان قريب';
      case 'workloadImpossible':
        return 'عبء لا يتّسع له وقتك';
      default:
        return code;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.mq;
    return MqPage(
      title: 'وضع الطوارئ',
      children: [
        MqAsync<EmergencyState?>(
          load: () => EmergencyRepository(app.db).readActive(app.studentId!),
          errorTitle: 'تعذّر قراءة الحالة',
          builder: (context, s) {
            if (s == null) {
              return const MqEmptyState(
                icon: Icons.shield_outlined,
                title: 'الطوارئ غير مفعّلة',
                message:
                    'يفعّلها المخطِّط تلقائيًا عند اقتراب امتحان أو حين لا يتّسع الوقت للعبء. ستراه هنا حين يحدث.',
              );
            }
            final since = s.enteredAt.toLocal();
            return MqCard(
              color: p.accentSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    MqIconTile(
                        icon: Icons.bolt_rounded, tone: MqTone.accent, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text('الطوارئ مفعّلة',
                            style: MqType.h2.copyWith(color: p.accentInk))),
                  ]),
                  const SizedBox(height: 12),
                  Text('السبب: ${_trigger(s.triggerReason)}',
                      style: MqType.body.copyWith(color: p.accentInk)),
                  Row(children: [
                    Text('منذ: ', style: MqType.body.copyWith(color: p.accentInk)),
                    MqNum('${since.day}/${since.month}/${since.year}',
                        style: MqType.body, color: p.accentInk),
                  ]),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        const MqBanner(
          icon: Icons.verified_user_outlined,
          tone: MqTone.ok,
          title: 'ما لا يمسّه وضع الطوارئ',
          text: 'حدّ نومك وفترات الراحة، وترتيب المتطلبات السابقة، وكتلك الثابتة.',
        ),
        const SizedBox(height: 10),
        const MqBanner(
          icon: Icons.tune_rounded,
          tone: MqTone.neutral,
          text:
              'أوزان الأولوية في هذا الوضع قيم أولية غير معايَرة بعد (نقطة مفتوحة).',
        ),
      ],
    );
  }
}
