import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'teacher_actions.dart';
import 'teacher_widgets.dart';

/// T05 · الحساب والصلاحيات. The name is an unverified label, the PIN a
/// comfort lock on this device. Identity verification / server-side
/// permissions are NOT available in this version (open point O-1).
class TeacherAccountTab extends StatefulWidget {
  const TeacherAccountTab(
      {super.key, required this.rev, required this.onChanged});

  final int rev;
  final VoidCallback onChanged;

  @override
  State<TeacherAccountTab> createState() => _TeacherAccountTabState();
}

class _TeacherAccountTabState extends State<TeacherAccountTab> {
  Future<void> _rename() async {
    final session = context.read<AppState>().teacherSession;
    final controller = TextEditingController(text: await session.savedName());
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم الأستاذ'),
        content: TextField(
          controller: controller,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(labelText: 'الاسم'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('احفظ')),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (ok != true || !mounted) return;
    try {
      await session.rename(text);
      widget.onChanged();
      if (mounted) {
        showSnack(context,
            'تم تغيير الاسم. الدروس المكتوبة سابقًا تبقى باسمها القديم.');
      }
    } catch (_) {
      if (mounted) showSnack(context, 'اسم الأستاذ مطلوب.');
    }
  }

  Future<void> _changePin(bool hasPin) async {
    final session = context.read<AppState>().teacherSession;
    final current = TextEditingController();
    final next = TextEditingController();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hasPin ? 'تغيير رمز PIN' : 'تفعيل رمز PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasPin)
              TextField(
                controller: current,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'الرمز الحالي'),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: next,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: hasPin ? 'رمز جديد (اتركه فارغًا للإلغاء)' : 'الرمز'),
            ),
            const SizedBox(height: 8),
            const Text('راحة على هذا الجهاز، وليس حماية.',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: const Text('احفظ')),
        ],
      ),
    );
    final cur = current.text;
    final nw = next.text;
    current.dispose();
    next.dispose();
    if (action != 'save' || !mounted) return;
    final ok = await session.changePin(currentPin: cur, newPin: nw);
    if (!mounted) return;
    if (ok) {
      widget.onChanged();
      showSnack(
          context,
          nw.isEmpty
              ? 'أُلغي رمز PIN.'
              : 'حُفظ رمز PIN.');
    } else {
      showSnack(context,
          'الرمز الحالي خاطئ، أو الرمز الجديد أقل من 4 أرقام أو فيه غير الأرقام.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<AppState>().teacherSession;
    final repo = teacherRepo(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FutureBuilder<String>(
          future: session.savedName(),
          builder: (context, snap) => Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(
                  (snap.data ?? '').isEmpty ? 'اسم الأستاذ' : snap.data!,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('يظهر كتسمية غير موثّقة على دروسك'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _rename,
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              FutureBuilder<bool>(
                future: session.hasPin(),
                builder: (context, snap) {
                  final has = snap.data ?? false;
                  return ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('رمز PIN'),
                    subtitle: const Text('راحة على هذا الجهاز، وليس حماية'),
                    trailing: Chip(label: Text(has ? 'مفعّل' : 'غير مفعّل')),
                    onTap: () => _changePin(has),
                  );
                },
              ),
              const Divider(height: 1),
              FutureBuilder<({int packages, DateTime? last})>(
                future: repo.exportSummary(),
                builder: (context, snap) {
                  final s = snap.data;
                  final last = s?.last;
                  return ListTile(
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Text('الحزم المصدّرة'),
                    subtitle: Text(s == null
                        ? '...'
                        : s.packages == 0
                            ? 'لم تُصدَّر حزمة بعد'
                            : '${s.packages} حزم · آخرها '
                                '${last == null ? '' : _ago(last)}'),
                  );
                },
              ),
            ],
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('من يرى ماذا',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                _Rule('المحتوى يذهب في اتجاه واحد: من الأستاذ إلى التلميذ.'),
                _Rule('لا تصل إليك بيانات أي تلميذ: لا إتقان ولا أخطاء ولا هوية.'),
                _Rule('ما تنشره لا يغيّر المنهج الرسمي ولا المعاملات ولا '
                    'محركات التلميذ.'),
                _Rule('التلميذ يحذف ما استورده متى شاء دون أثر على بقية '
                    'بياناته.'),
              ],
            ),
          ),
        ),
        const InfoBox(
          'تحقق الهوية وصلاحيات الخادم: غير متاح في هذه النسخة. قرار مفتوح (O-1).',
          icon: Icons.lock_outline,
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          // Back to the student app: pop every teacher route.
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Text('اخرج من وضع الأستاذ'),
        ),
      ],
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inMinutes < 1) return 'الآن';
    if (d.inHours < 1) return 'قبل ${d.inMinutes} دقيقة';
    if (d.inDays < 1) return 'قبل ${d.inHours} ساعة';
    return 'قبل ${d.inDays} يوم';
  }
}

class _Rule extends StatelessWidget {
  const _Rule(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check, size: 18, color: Color(0xFF2E8B57)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }
}
