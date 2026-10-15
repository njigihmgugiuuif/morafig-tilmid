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
/// When the shared server is configured, entry needs the teacher's OWN number,
/// verified ON THE SERVER (the server also tells the teacher's name, and each
/// lesson belongs to the teacher who sent it). The number can be remembered on
/// this device so an update never asks for it again. When the server is not
/// configured, the old local
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
  String? _savedCode;
  String _savedName = '';
  bool _remember = true;

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
    final access = context.read<AppState>().teacherAccess;
    final code = await access.code();
    final savedName = await access.name();
    if (!mounted) return;
    setState(() {
      _name.text = name;
      _hasPin = hasPin;
      _savedCode = code;
      _savedName = savedName.isNotEmpty ? savedName : name;
      _loaded = true;
    });
  }

  final _password = TextEditingController();
  bool _busy = false;

  Future<void> _openPanel({required bool keepSignedIn}) async {
    final state = context.read<AppState>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TeacherShell()),
    );
    // Without «ابقَ مسجّلًا» leaving the panel signs out.
    if (!keepSignedIn) state.teacherRemote.signOut();
    if (mounted) _load();
  }

  Future<void> _enterOnline() async {
    final state = context.read<AppState>();
    final code = _password.text.trim();
    if (code.isEmpty) {
      showSnack(context, 'أدخل رقمك الخاص.');
      return;
    }
    setState(() => _busy = true);
    try {
      final who = await state.lessonRemote.verifyCode(code);
      if (!mounted) return;
      if (who == null) {
        showSnack(context, kWrongTeacherCode);
        return;
      }
      // The server's name wins: nobody can publish under another's name.
      final name = who.teacherName ?? _name.text.trim();
      if (name.isEmpty) {
        showSnack(context, 'اكتب اسمك كما سيظهر على دروسك.');
        return;
      }
      await state.teacherSession.rename(name);
      state.teacherRemote.signIn(code, name: who.teacherName);
      if (_remember) {
        await state.teacherAccess.save(code, name: name);
      } else {
        await state.teacherAccess.clear();
      }
      _password.clear();
      await _openPanel(keepSignedIn: _remember);
    } on RemoteException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One tap with the remembered number: no typing after an update.
  Future<void> _continueSaved() async {
    final state = context.read<AppState>();
    final code = _savedCode;
    if (code == null) return;
    setState(() => _busy = true);
    try {
      String name = _savedName;
      try {
        final who = await state.lessonRemote.verifyCode(code);
        if (!mounted) return;
        if (who == null) {
          await state.teacherAccess.clear();
          showSnack(context, 'رقمك لم يعد صالحًا. أدخل رقمك الجديد.');
          await _load();
          return;
        }
        name = who.teacherName ?? name;
        state.teacherRemote.signIn(code, name: who.teacherName);
      } on RemoteException {
        // No connection: the panel still opens for writing lessons; sending
        // them needs the internet and says so when tried.
        state.teacherRemote.signIn(code, name: null);
        if (mounted) {
          showSnack(context,
              'لا اتصال الآن: تعمل على دروسك، والإرسال للتلاميذ يحتاج الإنترنت.');
        }
      }
      if (name.isNotEmpty) await state.teacherSession.rename(name);
      if (!mounted) return;
      await _openPanel(keepSignedIn: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOutHere() async {
    final state = context.read<AppState>();
    await state.teacherAccess.clear();
    state.teacherRemote.signOut();
    if (mounted) await _load();
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
                ? 'أدخل الرمز السري.'
                : 'الرمز يجب أن يكون ${TeacherSession.minPinLength} أرقام على الأقل.');
      case EntryResult.pinWrong:
        showSnack(context, 'الرمز السري غير صحيح.');
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
        if (online && _savedCode != null) ...[
          MqCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const MqIconTile(icon: Icons.verified_user_outlined, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            _savedName.isEmpty
                                ? 'مرحبًا بك'
                                : 'مرحبًا، $_savedName',
                            style: MqType.h3.copyWith(color: p.ink)),
                        Text('أنت مسجَّل(ة) على هذا الجهاز.',
                            style: MqType.caption.copyWith(color: p.ink3)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                MqButton(
                  label: _busy ? 'جارٍ الدخول…' : 'متابعة',
                  icon: Icons.arrow_back_rounded,
                  block: true,
                  onPressed: _busy ? null : _continueSaved,
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _busy ? null : _signOutHere,
                  child: const Text('خروج من هذا الجهاز / الدخول برقم آخر'),
                ),
              ],
            ),
          ),
        ] else
        MqCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('دخول الأستاذ', style: MqType.h3.copyWith(color: p.ink)),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: online
                      ? 'اسمك (يُملأ تلقائيًا من رقمك إن كان معروفًا)'
                      : 'اسمك كما سيظهر على دروسك',
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              if (online)
                TextField(
                  controller: _password,
                  obscureText: true,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: const InputDecoration(
                    labelText: 'رقمك الخاص',
                    hintText: 'الرقم الذي أعطاك إياه المسؤول',
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
                    labelText: 'الرمز السري',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                )
              else
                TextField(
                  controller: _newPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الرمز السري (اختياري)',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
              if (online)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: p.brand,
                  title: Text('ابقَ مسجّلًا على هذا الجهاز',
                      style: MqType.body.copyWith(color: p.ink)),
                  subtitle: Text('لا يطلب رقمك بعد كل تحديث للتطبيق.',
                      style: MqType.caption.copyWith(color: p.ink3)),
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v),
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
            'لكل أستاذ(ة) رقمه الخاص، يُتحقَّق منه على الخادم، ولا يُنشر درس '
            'للتلاميذ إلا به. لا يستطيع أحد تعديل درسك أو سحبه برقم آخر. '
            'ابقَ مسجّلًا على جهازك الخاص فقط، واخرج منه إن كان الجهاز مشتركًا.',
            icon: Icons.verified_user_outlined,
          )
        else ...const [
          InfoBox(
            'إرسال الدروس للتلاميذ عبر الإنترنت غير مفعّل بعد في هذه النسخة. '
            'يمكنك كتابة الدروس وحفظ نسخة منها كملف. الرمز راحة على هذا الجهاز وليس حماية.',
            icon: Icons.warning_amber_rounded,
          ),
        ],
      ],
    );
  }
}
