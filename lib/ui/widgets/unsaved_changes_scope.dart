import 'package:flutter/material.dart';

/// Protects a form against being closed by accident (system back button,
/// browser back, or a tap outside a sheet). When [isDirty] says there are
/// unsaved changes the student is asked first; otherwise it closes at once.
/// A deliberate close by code (`Navigator.pop`, e.g. after saving) is never
/// blocked.
class UnsavedChangesScope extends StatelessWidget {
  const UnsavedChangesScope({
    super.key,
    required this.isDirty,
    required this.child,
  });

  final bool Function() isDirty;
  final Widget child;

  Future<void> _onBack(BuildContext context) async {
    if (!isDirty()) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تجاهل التغييرات؟'),
        content: const Text('أدخلتَ بيانات لم تُحفظ بعد. إن خرجتَ الآن ستضيع.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('أكمل التعديل')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('تجاهل وخروج')),
        ],
      ),
    );
    if (leave == true && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _onBack(context);
        },
        child: child,
      );
}
