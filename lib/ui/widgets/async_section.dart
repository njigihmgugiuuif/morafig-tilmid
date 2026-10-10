import 'package:flutter/material.dart';

import '../design/primitives.dart';
import '../design/states.dart';
import '../design/tokens.dart';

/// Uniform loading / error / empty / data handling for every screen that
/// reads from the database. Every list-driven screen goes through this
/// widget (or [MqAsync]) instead of hand-rolling its own FutureBuilder, so
/// stuck spinners, silent failures and blank screens are handled once.
///
/// The public API is unchanged; only the look moved to the Mq* design system
/// (skeleton while loading, designed error with the raw detail, quiet empty
/// state), so it follows the light and dark themes.
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
    final p = context.mq;
    return FutureBuilder<T>(
      future: future(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: MqLoadingCard(),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: MqErrorState(
              title: 'تعذّر تحميل البيانات',
              message: 'بياناتك لم تُمَس.',
              detail: '${snapshot.error}',
            ),
          );
        }
        final data = snapshot.data;
        if (data == null || (isEmpty != null && isEmpty!(data))) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
            child: Column(
              children: [
                MqIconTile(icon: emptyIcon, tone: MqTone.neutral, size: 48),
                const SizedBox(height: 10),
                Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: MqType.small.copyWith(color: p.ink2),
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
