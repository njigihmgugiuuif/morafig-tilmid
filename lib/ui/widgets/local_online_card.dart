import 'package:flutter/material.dart';

import '../design/primitives.dart';
import '../design/tokens.dart';

/// Says plainly which parts live on the device and which need the internet.
/// (What is stored on the device does not ask the network for anything; the
/// first opening of the app and the arrival of new lessons do.)
class LocalVsOnlineCard extends StatelessWidget {
  const LocalVsOnlineCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    Widget block(IconData icon, MqTone tone, String title, String body) =>
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MqIconTile(icon: icon, tone: tone, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: MqType.h3.copyWith(color: p.ink)),
                  const SizedBox(height: 2),
                  Text(body, style: MqType.small.copyWith(color: p.ink2)),
                ],
              ),
            ),
          ],
        );
    return MqCard(
      child: Column(children: [
        block(
          Icons.phone_android_rounded,
          MqTone.ok,
          'محفوظ على جهازك',
          'مهامك، خطتك، تقدّمك، أهدافك، امتحاناتك، التزاماتك، '
              'والدروس التي وصلتك. لا تطلب هذه الأجزاء الشبكة عند العمل.',
        ),
        const SizedBox(height: 14),
        block(
          Icons.wifi_rounded,
          MqTone.info,
          'يحتاج إنترنت',
          'الفتح الأول للتطبيق، ووصول دروس جديدة من أساتذتك. '
              'عند انقطاع الاتصال نعيد المحاولة تلقائيًا حين يعود.',
        ),
      ]),
    );
  }
}
