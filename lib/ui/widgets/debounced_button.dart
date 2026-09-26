import 'package:flutter/material.dart';

/// Prevents the classic "tapped Save twice, got two records" bug. Wraps
/// any async action: the button disables itself and shows a small
/// spinner the instant it's tapped, and re-enables only after the action
/// finishes (success or error). Use this for every button that writes to
/// the database (add task, save onboarding, mark complete, etc).
class DebouncedButton extends StatefulWidget {
  const DebouncedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final Future<void> Function() onPressed;

  @override
  State<DebouncedButton> createState() => _DebouncedButtonState();
}

class _DebouncedButtonState extends State<DebouncedButton> {
  bool _busy = false;

  Future<void> _handleTap() async {
    if (_busy) return; // hard guard against double/rapid taps
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _busy ? null : _handleTap,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(widget.icon ?? Icons.check),
      label: Text(_busy ? 'جارٍ الحفظ...' : widget.label),
    );
  }
}
