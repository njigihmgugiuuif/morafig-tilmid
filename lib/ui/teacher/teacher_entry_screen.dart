import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/teacher_session.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/debounced_button.dart';
import 'teacher_shell.dart';
import 'teacher_widgets.dart';

/// T01 · مدخل الأستاذ. A separate entry, reached from «المزيد» (student) or
/// from the first-run screen. It does NOT verify identity (no server): the
/// name is a label and the PIN is a convenience lock on this device (O-1).
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
    return Scaffold(
      appBar: AppBar(title: const Text('مدخل الأستاذ')),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 8),
                  const Center(
                    child: Text('ثانوية رابح بطاط',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text('مرافق التلميذ',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 4),
                  const Center(
                    child: Text('المرافقة والتنظيم الدراسي طوال العام',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('دخول الأستاذ',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _name,
                            textAlign: TextAlign.right,
                            decoration: const InputDecoration(
                              labelText: 'اسمك كما سيظهر على دروسك',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_hasPin)
                            TextField(
                              controller: _pin,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.right,
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
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                labelText: 'رمز PIN (اختياري)',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                            ),
                          const SizedBox(height: 16),
                          DebouncedButton(
                            label: 'ادخل وضع الأستاذ',
                            icon: Icons.shield_outlined,
                            onPressed: _enter,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const InfoBox(
                    'في هذه النسخة لا يوجد خادم، فلا نستطيع التحقق من هويتك. '
                    'الرمز راحة على هذا الجهاز وليس حماية.',
                    icon: Icons.warning_amber_rounded,
                  ),
                  const SizedBox(height: 8),
                  const InfoBox(
                    'حساب أستاذ محمي بتحقق الهوية: غير متاح في هذه النسخة. '
                    'قرار مفتوح (O-1).',
                    icon: Icons.lock_outline,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('العودة'),
                  ),
                ],
              ),
      ),
    );
  }
}
