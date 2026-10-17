import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/primitives.dart';
import '../design/tokens.dart';
import 'install_stub.dart' if (dart.library.js_interop) 'install_web.dart'
    as inst;

/// «العمل دون إنترنت»: tells the student, from a real check, whether this
/// phone already holds the whole app (so the link or its QR code opens it
/// with no connection), and what to do when it does not.
///
/// A QR code only carries the address of the app. The very first opening on
/// a phone must download the app once; nothing can replace that. After that
/// the same address opens from the copy saved on the phone.
class OfflineReadyCard extends StatefulWidget {
  const OfflineReadyCard({super.key});

  @override
  State<OfflineReadyCard> createState() => _OfflineReadyCardState();
}

class _OfflineReadyCardState extends State<OfflineReadyCard> {
  bool? _ready; // null while checking
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (!kIsWeb) return;
    setState(() => _checking = true);
    final r = await inst.offlineReady();
    if (!mounted) return;
    setState(() {
      _ready = r;
      _checking = false;
    });
  }

  /// The address that opens offline: the app's folder address WITH the
  /// closing slash (without it the browser must ask the network to redirect).
  String _link() {
    final s = Uri.base.toString().split('#').first.split('?').first;
    return s.endsWith('/') ? s : '$s/';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _link()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('نُسخ رابط الدخول.')));
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    final p = context.mq;
    final ready = _ready == true;
    final title = _checking && _ready == null
        ? 'نتحقق من هاتفك...'
        : ready
            ? 'جاهز للعمل دون إنترنت'
            : 'لم يكتمل تحميل التطبيق على هذا الهاتف';
    final body = ready
        ? 'من الآن يفتح التطبيق دون إنترنت: من أيقونته إن ثبّتّه، أو من الرابط '
            'نفسه (أو رمزه) في المتصفح نفسه.'
        : 'افتح التطبيق مرة واحدة والإنترنت يعمل، وانتظر نحو دقيقة، ثم اضغط '
            '«تحقّق من جديد».';
    return MqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MqIconTile(
                icon: ready
                    ? Icons.offline_pin_rounded
                    : Icons.cloud_download_outlined,
                tone: ready ? MqTone.ok : MqTone.accent,
                size: 40,
              ),
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
          ),
          const SizedBox(height: 12),
          Text(
              'رمز الاستجابة السريعة يحمل رابط التطبيق فقط، فأول مسح على أي هاتف '
              'يحتاج إنترنت مرة واحدة ليُحمَّل التطبيق كله. بعدها يفتح الرابط نفسه '
              'دون إنترنت. اجعل الرمز يحمل هذا الرابط بالضبط، بما فيه الشرطة الأخيرة:',
              style: MqType.caption.copyWith(color: p.ink3)),
          const SizedBox(height: 6),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(_link(),
                style: MqType.small.copyWith(color: p.ink)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: MqButton(
                label: 'انسخ رابط الدخول',
                icon: Icons.copy_rounded,
                kind: MqButtonKind.secondary,
                small: true,
                onPressed: _copy,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MqButton(
                label: 'تحقّق من جديد',
                icon: Icons.refresh_rounded,
                kind: MqButtonKind.secondary,
                small: true,
                onPressed: _check,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
