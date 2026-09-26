import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../repositories/student_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/debounced_button.dart';

/// First-run screen. Shown only when no Student row exists yet ("أول
/// تشغيل" / "عدم وجود بيانات بعد التثبيت"). Collects the two pieces of
/// information the whole app structurally needs before it can do
/// anything (name, minimum sleep floor — the hard constraint the
/// Emergency Engine is architecturally forbidden from ever violating).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  double _sleepHours = 7;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final appState = context.read<AppState>();
    final repo = StudentRepository(appState.db);
    try {
      final student = await repo.createInitialStudent(
        fullNameOrNickname: _nameController.text.trim(),
        sleepFloorMinMinutes: (_sleepHours * 60).round(),
      );
      await appState.setStudentId(student.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر إنشاء الملف: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // PopScope here: leaving onboarding mid-way via system back would
    // strand the user with no app to return to (no Student yet, so the
    // home shell can't render). We intercept and ask for confirmation
    // instead of silently exiting.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('الخروج من الإعداد الأولي؟'),
            content: const Text(
              'لم يتم إنشاء ملفك الدراسي بعد. سيتعين عليك إكمال هذه '
              'الخطوة عند فتح التطبيق مرة أخرى.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('البقاء'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  SystemNavigator.pop();
                },
                child: const Text('خروج'),
              ),
            ],
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('إعداد أولي')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.school,
                          size: 56, color: AppColors.primary),
                      const SizedBox(height: 12),
                      const Text(
                        'مرحبًا بك في مرافق التلميذ',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'قبل البدء، نحتاج بعض المعلومات الأساسية لضبط '
                        'خطتك الدراسية.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _nameController,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          labelText: 'الاسم أو اللقب',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'الرجاء إدخال اسمك'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'الحد الأدنى لساعات النوم يوميًا: '
                          '${_sleepHours.round()} ساعات',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Slider(
                        value: _sleepHours,
                        min: 5,
                        max: 10,
                        divisions: 10,
                        label: '${_sleepHours.round()}',
                        onChanged: (v) => setState(() => _sleepHours = v),
                      ),
                      Text(
                        'هذا الحد لا يتم كسره أبدًا عند إعادة التخطيط، '
                        'حتى في وضع الطوارئ قبل الامتحانات.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 28),
                      DebouncedButton(
                        label: 'ابدأ',
                        icon: Icons.arrow_back,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
