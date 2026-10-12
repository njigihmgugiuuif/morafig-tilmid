import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Root-level Android/system back-button handling ("double back to exit").
/// Wrap the app's home shell with this. On the first back press it shows
/// a brief hint and does NOT exit; a second press within 2 seconds exits
/// the app. This prevents the single most common beginner mistake: the
/// system back button closing the whole app by accident from the home
/// screen.
///
/// [canPopNormally] lets the shell say "no, handle this back press
/// yourself" (e.g. to switch bottom-nav tabs back to Home first) before
/// the exit-confirmation logic even runs.
/// Closes the app where the platform lets an app close itself.
///
/// On the web (the PWA) this does nothing and returns false: asking the
/// browser engine to "pop" the last page tears down its history handling and
/// leaves the page alive but dead to the back button. On the web the user
/// leaves with the phone's home button or by closing the tab.
bool exitAppIfPossible() {
  if (kIsWeb) return false;
  SystemNavigator.pop();
  return true;
}

class ExitConfirmScope extends StatefulWidget {
  const ExitConfirmScope({
    super.key,
    required this.child,
    required this.onBackPressed,
  });

  final Widget child;

  /// Called on every system back press. Return true if this widget should
  /// treat it as "the user wants to exit the app" (double-press logic);
  /// return false if you already handled it (e.g. switched tabs) and the
  /// app must not exit or pop further.
  final bool Function() onBackPressed;

  @override
  State<ExitConfirmScope> createState() => _ExitConfirmScopeState();
}

class _ExitConfirmScopeState extends State<ExitConfirmScope> {
  DateTime? _lastBackPressTime;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        final wantsExit = widget.onBackPressed();
        if (!wantsExit) return;

        final now = DateTime.now();
        final last = _lastBackPressTime;
        if (last != null && now.difference(last) < const Duration(seconds: 2)) {
          if (exitAppIfPossible()) return;
          // Web/PWA: cannot close itself; say how to leave instead.
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'للخروج اضغط زر الصفحة الرئيسية في هاتفك أو أغلق التبويب. بياناتك محفوظة.'),
              duration: Duration(seconds: 3),
            ),
          );
          _lastBackPressTime = null;
          return;
        }

        _lastBackPressTime = now;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('اضغط رجوع مرة أخرى للخروج من التطبيق'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: widget.child,
    );
  }
}
