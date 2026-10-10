import 'package:flutter/material.dart';

import '../design/primitives.dart';

/// Prevents the classic "tapped Save twice, got two records" bug. Wraps an
/// async action: the button disables itself and shows a spinner the instant
/// it is tapped, and re-enables only after the action finishes.
///
/// Kept for the screens that still use it; it is now a thin wrapper over
/// [MqButton], which has the same guard built in.
class DebouncedButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MqButton(
      label: label,
      icon: icon ?? Icons.check,
      block: true,
      onPressed: onPressed,
    );
  }
}
