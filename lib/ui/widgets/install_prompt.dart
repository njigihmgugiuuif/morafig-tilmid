import 'package:flutter/material.dart';

import '../design/primitives.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import 'install_stub.dart' if (dart.library.js_interop) 'install_web.dart'
    as inst;

/// «تثبيت التطبيق». Uses the browser's own install prompt when it offers one;
/// otherwise explains the manual route (browser menu / iOS Share sheet).
/// Nothing is claimed as installed unless the page is already running
/// as an installed app.
class InstallAppTile extends StatefulWidget {
  const InstallAppTile({super.key});
  @override
  State<InstallAppTile> createState() => _InstallAppTileState();
}

class _InstallAppTileState extends State<InstallAppTile> {
  String? _note;

  Future<void> _install() async {
    if (inst.canPromptInstall()) {
      final ok = await inst.promptInstall();
      if (!mounted) return;
      setState(() => _note = ok ? 'بدأ التثبيت.' : 'لم يكتمل التثبيت.');
    } else {
      setState(() => _note =
          'متصفحك لا يعرض نافذة التثبيت مباشرة. من قائمة المتصفح (⋮) اختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية». في آيفون: زر المشاركة ثم «إضافة إلى الشاشة الرئيسية».');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    if (inst.isStandalone()) {
      return MqCard(
        child: Row(children: [
          MqIconTile(icon: Icons.check_circle_outline, tone: MqTone.ok, size: 44),
          const SizedBox(width: 12),
          Expanded(
              child: Text('التطبيق يعمل كتطبيق مثبَّت.',
                  style: MqType.body.copyWith(color: p.ink))),
        ]),
      );
    }
    return MqCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('تثبيت التطبيق', style: MqType.h3.copyWith(color: p.ink)),
        const SizedBox(height: 4),
        Text('افتحه من الشاشة الرئيسية كأي تطبيق.',
            style: MqType.caption.copyWith(color: p.ink3)),
        const SizedBox(height: 10),
        MqButton(
            label: 'تثبيت التطبيق',
            icon: Icons.install_mobile_rounded,
            block: true,
            onPressed: _install),
        if (_note != null) ...[
          const SizedBox(height: 10),
          Text(_note!, style: MqType.caption.copyWith(color: p.ink2)),
        ],
      ]),
    );
  }
}
