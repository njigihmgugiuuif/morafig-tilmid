import 'package:flutter/material.dart';

/// Uniform loading / error / empty / data handling for every screen that
/// reads from the database. Every list-driven screen in this app goes
/// through this widget instead of hand-rolling its own FutureBuilder, so
/// the "what does a beginner forget" cases (stuck spinners, silent
/// failures, blank screens with no explanation) are handled once, in one
/// place, correctly.
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({
    super.key,
    required this.future,
    required this.builder,
    this.isEmpty,
    this.emptyMessage = 'لا توجد بيانات بعد.',
    this.emptyIcon = Icons.inbox_outlined,
  });

  final Future<T> Function() future;
  final Widget Function(BuildContext context, T data) builder;
  final bool Function(T data)? isEmpty;
  final String emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      // A fresh Future per build would restart the spinner on every
      // rebuild (e.g. keyboard opening) — future is created once by the
      // caller and passed in, not created here.
      future: future(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Column(
              children: [
                const Icon(Icons.error_outline, size: 40, color: Colors.red),
                const SizedBox(height: 12),
                const Text(
                  'تعذّر تحميل البيانات',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        }
        final data = snapshot.data;
        if (data == null || (isEmpty != null && isEmpty!(data))) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(emptyIcon, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 10),
                Text(
                  emptyMessage,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }
        return builder(context, data);
      },
    );
  }
}
