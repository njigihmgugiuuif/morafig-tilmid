import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../design/primitives.dart';
import '../design/sheet.dart';
import '../design/tokens.dart';
import 'install_logic.dart';
import 'install_stub.dart' if (dart.library.js_interop) 'install_web.dart'
    as inst;

/// The one «تثبيت التطبيق» button, shown at the top of the home screen.
///
/// - Appears only in a browser, and only while the app is NOT already running
///   as an installed app.
/// - If the browser handed over its install prompt, the button runs it.
/// - Otherwise it opens short manual steps (browser menu / iPhone Share).
/// - After an install during this visit it turns into a calm «تم التثبيت».
///
/// It does not claim to work the same on every device: see [InstallStage].
class InstallButton extends StatefulWidget {
  const InstallButton({super.key});

  @override
  State<InstallButton> createState() => _InstallButtonState();
}

class _InstallButtonState extends State<InstallButton> {
  bool _installedThisVisit = false;
  late InstallStage _stage = _compute();

  InstallStage _compute() => decideInstallStage(
        isWeb: kIsWeb,
        standalone: inst.isStandalone(),
        promptAvailable: inst.canPromptInstall(),
        installedThisVisit: _installedThisVisit,
        ios: inst.isIos(),
      );

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      inst.watchInstall(() {
        if (!mounted) return;
        // The prompt becoming available is one event; the browser's
        // «appinstalled» is the other and it removes the prompt. So: we had
        // a prompt and now we do not -> the app was installed.
        final wasPromptable = _stage == InstallStage.promptable;
        setState(() {
          if (wasPromptable && !inst.canPromptInstall()) {
            _installedThisVisit = true;
          }
          _stage = _compute();
        });
      });
    }
  }

  Future<void> _onTap() async {
    switch (_stage) {
      case InstallStage.promptable:
        final ok = await inst.promptInstall();
        if (!mounted) return;
        setState(() {
          if (ok) _installedThisVisit = true;
          _stage = _compute();
        });
        if (!ok) {
          // The prompt can be shown once per page load; if it was dismissed,
          // say how to install by hand instead of leaving a dead button.
          _showSteps(InstallStage.manual);
        }
        break;
      case InstallStage.manual:
      case InstallStage.iosManual:
        _showSteps(_stage);
        break;
      default:
        break;
    }
  }

  void _showSteps(InstallStage stage) {
    showMqSheet<void>(
      context,
      title: 'تثبيت التطبيق',
      subtitle: 'ثبّته لتفتحه من الشاشة الرئيسية دون إنترنت.',
      builder: (ctx) => Text(installManualSteps(stage),
          style: MqType.body.copyWith(color: ctx.mq.ink)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == InstallStage.hidden) return const SizedBox.shrink();
    final p = context.mq;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onGreen = dark ? const Color(0xFF0B2A1E) : Colors.white;

    if (_stage == InstallStage.installed) {
      return Container(
        constraints: const BoxConstraints(minHeight: MqSpace.touch),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: p.okSoft,
          borderRadius: BorderRadius.circular(MqSpace.radiusButton),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_rounded, size: 20, color: p.ok),
          const SizedBox(width: 8),
          Flexible(
            child: Text('تم التثبيت — افتحه من الشاشة الرئيسية',
                style: MqType.label.copyWith(color: p.ok)),
          ),
        ]),
      );
    }

    return MqPressable(
      onTap: _onTap,
      semanticLabel: 'تثبيت التطبيق',
      child: Container(
        constraints: const BoxConstraints(minHeight: MqSpace.touch),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: p.ok,
          borderRadius: BorderRadius.circular(MqSpace.radiusButton),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.install_mobile_rounded, size: 20, color: onGreen),
          const SizedBox(width: 8),
          Text('تثبيت التطبيق',
              style: MqType.label.copyWith(color: onGreen)),
        ]),
      ),
    );
  }
}
