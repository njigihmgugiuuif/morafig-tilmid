import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/lesson_remote_service.dart';
import '../../services/teacher_session.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/states.dart';
import '../state/app_state.dart';
import '../design/tokens.dart';
import 'teacher_shell.dart';
import 'teacher_widgets.dart';

/// T01 · مدخل الأستاذ: the door of the SEPARATE teacher panel (`#/teacher`).
/// When the shared server is configured, entry needs the teachers' shared
/// password, verified ON THE SERVER. When it is not configured, the old local
/// mode remains (name + optional PIN lock on this device) and the screen says
/// plainly that it is not protection (O-1).
class TeacherEntryScreen extends StatefulWidget {
  const TeacherEntryScreen({super.key});

  @override
  State<TeacherEntryScreen> createState() => _TeacherEntryScreenState();
}

class _TeacherEntryScreenState extends State<TeacherEntryScreen> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _newPin = TextEditingController();
  bool _loaded = false;
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _password.dispose();
    _newPin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = context.read<AppState>().teacherSession;
    final name = await session.savedName();
    final hasPin = await session.hasPin();
    if (!mounted) return;
    setState(() {
      _name.text = name;
      _hasPin = hasPin;
      _loaded = true;
    });
  }

  final _password = TextEditingController();
  bool _busy = false;

  Future<void> _enterOnline() async {
    final state = context.read<AppState>();
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'اكتب اسمك كما سيظهر على دروسك.');
      return;
    }
    if (_password.text.isEmpty) {
      showSnack(context, 'أدخل كلمة مرور الأساتذة.');
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await state.lessonRemote.verifyPassword(_password.text);
      if (!mounted) return;
      if (!ok) {
        showSnack(context, 'كلمة مرور الأساتذة غير صحيحة.');
        return;
      }
      await state.teacherSession.rename(_name.text);
      state.teacherRemote.signIn(_password.text);
      _password.clear();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TeacherShell()),
      );
      // Leaving the panel signs out: the password is not kept.
      state.teacherRemote.signOut();
      if (mounted) _load();
    } on RemoteException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enter() async {
    final session = context.read<AppState>().teacherSession;
    final result = await session.enter(
      name: _name.text,
      pin: _pin.text,
      newPin: _hasPin ? null : _newPin.text,
    );
    if (!mounted) return;
    switch (result) {
      case EntryResult.ok:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TeacherShell()),
        );
        if (mounted) {
          _pin.clear();
          _load();
        }
      case EntryResult.nameRequired:
        showSnack(context, 'اكتب اسمك كما سيظهر على دروسك.');
      case EntryResult.pinRequired:
        showSnack(
            context,
            _hasPin
                ? 'أدخل رمز PIN.'
                : 'الرمز يجب أن يكون ${TeacherSession.minPinLength} أرقام على الأقل.');
      case EntryResult.pinWrong:
        showSnack(context, 'رمز PIN غير صحيح.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final online = context.read<AppState>().lessonRemote.configured;
    if (!_loaded) {
      return const MqPage(title: 'مدخل الأستاذ', children: [MqLoadingCard(lines: 3)]);
    }
    return MqPage(
      title: 'مدخل الأستاذ',
      children: [
        Center(
          child: Text('ثانوية رابح بطاط',
              style: MqType.small.copyWith(color: p.ink2)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('مرافق التلميذ',
              style: MqType.h1.copyWith(color: p.ink)),
        ),
        const SizedBox(height: 2),
        Center(
          child: Text('المرافقة والتنظيم الدراسي طوال العام',
              style: MqType.caption.copyWith(color: p.ink2)),
        ),
        const SizedBox(height: 20),
        MqCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('دخول الأستاذ', style: MqType.h3.copyWith(color: p.ink)),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'اسمك كما سيظهر على دروسك',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              if (online)
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة مرور الأساتذة',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                  onSubmitted: (_) => _busy ? null : _enterOnline(),
                )
              else if (_hasPin)
                TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'رمز PIN',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                )
              else
                TextField(
                  controller: _newPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'رمز PIN (اختياري)',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
              const SizedBox(height: 16),
              MqButton(
                label: _busy ? 'جارٍ التحقق…' : 'ادخل وضع الأستاذ',
                icon: Icons.shield_outlined,
                block: true,
                onPressed: _busy ? null : (online ? _enterOnline : _enter),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (online)
          const InfoBox(
            'كلمة المرور تُتحقَّق على الخادم، ولا يُنشر درس للتلاميذ '
            'إلا بها. تحتاج إلى اتصال بالإنترنت للدخول.',
            icon: Icons.verified_user_outlined,
          )
        else ...const [
          InfoBox(
            'المزامنة مع التلاميذ غير مفعّلة بعد في هذه النسخة. يمكنك كتابة '
            'الدروس وتصديرها كملف. الرمز راحة على هذا الجهاز وليس حماية.',
            icon: Icons.warning_amber_rounded,
          ),
        ],
      ],
    );
  }
}
