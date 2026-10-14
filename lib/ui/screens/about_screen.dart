import 'package:flutter/material.dart';

import '../design/logo.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/tokens.dart';
import 'constitution_screen.dart';

/// «عن التطبيق»: who it is for, what it does, and what it is not.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    Widget bullet(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_rounded, size: 18, color: p.brand),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(t, style: MqType.body.copyWith(color: p.ink))),
            ],
          ),
        );
    return MqPage(
      title: 'عن التطبيق',
      children: [
        MqCard(
          child: Column(children: [
            const MqLogoTile(size: 72),
            const SizedBox(height: 12),
            Text('مرافق التلميذ', style: MqType.h1.copyWith(color: p.ink)),
            Text('ثانوية رابح بطاط',
                style: MqType.small.copyWith(color: p.ink3)),
            const SizedBox(height: 8),
            Text('المرافقة والتنظيم الدراسي طوال العام',
                textAlign: TextAlign.center,
                style: MqType.body.copyWith(color: p.ink2)),
          ]),
        ),
        const SizedBox(height: 14),
        const MqSectionTitle('ماذا يفعل؟'),
        MqCard(
          child: Column(children: [
            bullet('يرتّب لك مهامك ويقترح ما تبدأ به الآن ولماذا.'),
            bullet('يبني خطة أسبوعك على أوقاتك الحرة لا على أوقات انشغالك.'),
            bullet('يتابع إتقانك لكل موضوع ويذكّرك بالمراجعة قبل أن تنسى.'),
            bullet('يقرّبك من امتحاناتك وأهدافك ويعرض لك ما فاتك.'),
            bullet('يصلك فيه دروس أساتذتك، وتبقى على جهازك.'),
          ]),
        ),
        const SizedBox(height: 14),
        const MqSectionTitle('وما الذي ليس هو؟'),
        MqCard(
          child: Text(
            'ليس تطبيقًا رسميًا لوزارة التربية، ولا يعطي علامات ولا يحلّ مكان '
            'أستاذك. هو مساعد ينظّم وقتك ويعرض لك ما سجّلته أنت بصدق.',
            style: MqType.body.copyWith(color: p.ink),
          ),
        ),
        const SizedBox(height: 14),
        MqCard(
          onTap: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (_) => const ConstitutionScreen())),
          child: Row(children: [
            const MqIconTile(icon: Icons.gavel_rounded, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('دستور التطبيق',
                      style: MqType.h3.copyWith(color: p.ink)),
                  Text('ما نلتزم به معك',
                      style: MqType.caption.copyWith(color: p.ink3)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: p.ink3, size: 20),
          ]),
        ),
      ],
    );
  }
}
