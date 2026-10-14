import 'package:flutter/material.dart';

import '../design/logo.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/tokens.dart';
import 'about_screen.dart';

/// «دستور التطبيق»: the rules this app keeps with the student, in plain
/// words. Each line is something the app actually does (or refuses to do).
class ConstitutionScreen extends StatelessWidget {
  const ConstitutionScreen({super.key});

  static const List<(IconData, String, String)> articles = [
    (
      Icons.phone_android_rounded,
      'بياناتك لك',
      'مهامك وخطتك وتقدّمك وأهدافك والتزاماتك محفوظة على جهازك. '
          'لا تُرسل بياناتك الدراسية إلى أي خادم، ولا حساب ولا كلمة سر للتلميذ.'
    ),
    (
      Icons.wifi_off_rounded,
      'يخدمك دون إنترنت',
      'صُمّم ليعمل بما هو محفوظ على جهازك. الإنترنت يلزم لفتح التطبيق أول مرة '
          'ولوصول دروس جديدة من أساتذتك فقط.'
    ),
    (
      Icons.rule_rounded,
      'لا أرقام وهمية',
      'نعرض ما سجّلته أنت وما حسبته محرّكات التطبيق من تسجيلاتك. '
          'وحين لا تكفي البيانات نقول ذلك بدل أن نخترع نتيجة.'
    ),
    (
      Icons.edit_note_rounded,
      'لا نفرض عليك معلومات رسمية',
      'سنتك وشعبتك تكتبهما بنفسك. لا مواد ولا معاملات ولا شعب رسمية '
          'تظهر إلا بمصدر موثّق.'
    ),
    (
      Icons.school_outlined,
      'دروس الأساتذة غير رسمية',
      'ما يرسله أساتذتك اجتهاد منهم وليس نصًا رسميًا، وتبقى عليه هذه العلامة. '
          'ولا يغيّر ترتيب أولوياتك.'
    ),
    (
      Icons.lightbulb_outline_rounded,
      'القرار لك',
      'التطبيق يقترح ويشرح سبب اقتراحه، وأنت من يقرّر. يمكنك تعديل كل ما أدخلته '
          'أو مسحه متى شئت.'
    ),
    (
      Icons.balance_rounded,
      'أمانة في التقدّم',
      'لا نجمّل تقدّمك ولا نخفي ما فاتك. الرسوم تعكس ما سجّلته فعلًا.'
    ),
    (
      Icons.delete_outline_rounded,
      'المسح بيدك وبتأكيد',
      'إعادة الضبط تمسح من هذا الجهاز فقط، ولا تتم إلا بعد أن تكتب كلمة التأكيد. '
          'ما على أجهزة أخرى لا يُمسّ.'
    ),
  ];

  /// The next development, stated as a plan: it does not exist yet.
  static const String aiTitle = 'التطوّر القادم: نموذج ذكاء اصطناعي';
  static const List<String> aiPoints = [
    'نعمل على تطوير نموذج ذكاء اصطناعي ليكون مساعدًا لك في الدراسة. '
        'هو خطوة قادمة ولم يُنجَز بعد، وليس في التطبيق الآن.',
    'حين يُضاف سيبقى التزامنا كما هو: يقترح ويشرح ولا يقرّر عنك، '
        'ولا يخترع أرقامًا ولا معلومات رسمية.',
    'ولن يُستعمل شيء من بياناتك فيه قبل أن نخبرك بوضوح وتوافق أنت.',
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqPage(
      title: 'دستور التطبيق',
      caption: 'ما نلتزم به معك',
      children: [
        MqCard(
          child: Column(children: [
            const MqLogoTile(size: 64),
            const SizedBox(height: 10),
            Text('مرافق التلميذ', style: MqType.h1.copyWith(color: p.ink)),
            Text('ثانوية رابح بطاط',
                style: MqType.small.copyWith(color: p.ink3)),
            const SizedBox(height: 8),
            Text(
                'تطبيق يرافق تلميذ الثانوية في تنظيم وقته ومراجعته طوال العام: '
                'مهام وخطة أسبوعية وتتبّع إتقان وتذكير بالمراجعة، ويعمل دون إنترنت.',
                textAlign: TextAlign.center,
                style: MqType.body.copyWith(color: p.ink2)),
          ]),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < articles.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MqCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MqIconTile(icon: articles[i].$1, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ${articles[i].$2}',
                            style: MqType.h3.copyWith(color: p.ink)),
                        const SizedBox(height: 4),
                        Text(articles[i].$3,
                            style: MqType.small.copyWith(color: p.ink2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        const MqSectionTitle(aiTitle),
        MqCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in aiPoints)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 18, color: p.brand),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(t,
                              style: MqType.body.copyWith(color: p.ink))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        MqCard(
          onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
          child: Row(children: [
            const MqIconTile(icon: Icons.info_outline_rounded, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text('عن التطبيق',
                  style: MqType.h3.copyWith(color: p.ink)),
            ),
            Icon(Icons.arrow_forward_rounded, color: p.ink3, size: 20),
          ]),
        ),
      ],
    );
  }
}
