import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../design/primitives.dart';
import '../design/tokens.dart';
import 'install_logic.dart';
import 'install_stub.dart' if (dart.library.js_interop) 'install_web.dart'
    as inst;

/// Settings entry about installing. The install BUTTON lives only at the top
/// of the home screen (one button, one place); this card just says whether
/// the app is installed and where the button is. Nothing is claimed as
/// installed unless the page runs as an installed app.
class InstallAppTile extends StatelessWidget {
  const InstallAppTile({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    if (!kIsWeb) return const SizedBox.shrink();
    final installed = inst.isStandalone();
    final stage = decideInstallStage(
      isWeb: kIsWeb,
      standalone: installed,
      promptAvailable: inst.canPromptInstall(),
      installedThisVisit: false,
      ios: inst.isIos(),
    );
    return MqCard(
      child: Row(children: [
        MqIconTile(
            icon: installed
                ? Icons.check_circle_outline
                : Icons.install_mobile_rounded,
            tone: installed ? MqTone.ok : MqTone.brand,
            size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  installed
                      ? 'التطبيق يعمل كتطبيق مثبَّت.'
                      : 'التثبيت من زر «تثبيت التطبيق» في أعلى الرئيسية.',
                  style: MqType.body.copyWith(color: p.ink)),
              if (!installed && stage != InstallStage.promptable)
                Text(installManualSteps(stage),
                    style: MqType.caption.copyWith(color: p.ink3)),
            ],
          ),
        ),
      ]),
    );
  }
}
