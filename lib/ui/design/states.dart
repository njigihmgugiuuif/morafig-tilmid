import 'package:flutter/material.dart';

import 'primitives.dart';
import 'tokens.dart';

/// Placeholder block while data loads. A slow breathing, not a spinner, so
/// the screen already has the shape of what is coming (D-1 S17).
class MqSkeleton extends StatefulWidget {
  const MqSkeleton({super.key, this.width, this.height = 14, this.radius = 10});
  final double? width;
  final double height;
  final double radius;

  @override
  State<MqSkeleton> createState() => _MqSkeletonState();
}

class _MqSkeletonState extends State<MqSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final still = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: still ? 0.8 : 0.5 + 0.5 * _c.value,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// A card of skeleton lines: the loading state of a list or a panel.
class MqLoadingCard extends StatelessWidget {
  const MqLoadingCard({super.key, this.lines = 3});
  final int lines;

  @override
  Widget build(BuildContext context) {
    const widths = [0.7, 0.9, 0.5, 0.8];
    return MqCard(
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines; i++) ...[
              MqSkeleton(width: box.maxWidth * widths[i % widths.length]),
              if (i != lines - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline message. Tone says what kind: information, caution, lateness (never
/// blame), success.
class MqBanner extends StatelessWidget {
  const MqBanner({
    super.key,
    required this.text,
    this.title,
    this.icon = Icons.info_outline,
    this.tone = MqTone.info,
    this.action,
  });

  final String text;
  final String? title;
  final IconData icon;
  final MqTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final c = p.tone(tone);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: c.fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(title!,
                      style: MqType.small
                          .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
                Text(text,
                    style: MqType.small.copyWith(color: p.ink, height: 1.65)),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «فارغ»: a message and, when there is something to do, the action.
class MqEmptyState extends StatelessWidget {
  const MqEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqCard(
      kind: MqCardKind.flat,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          MqIconTile(icon: icon, size: 52),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: MqType.h3.copyWith(color: p.ink)),
          const SizedBox(height: 4),
          Text(message,
              textAlign: TextAlign.center,
              style: MqType.small.copyWith(color: p.ink2)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            MqButton(
                label: actionLabel!,
                icon: Icons.add,
                small: true,
                onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

/// «خطأ»: what failed, that the data is not touched, and a way to retry.
class MqErrorState extends StatelessWidget {
  const MqErrorState({
    super.key,
    required this.title,
    required this.message,
    this.detail,
    this.onRetry,
  });

  final String title;
  final String message;

  /// The raw error, shown small, so a problem can be reported precisely.
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqCard(
      color: p.overdueSoft,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 20, color: p.overdue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: MqType.small
                        .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(message, style: MqType.caption.copyWith(color: p.ink2)),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: MqType.caption.copyWith(color: p.ink3, fontSize: 11)),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            MqButton(
              label: 'إعادة المحاولة',
              icon: Icons.refresh,
              small: true,
              kind: MqButtonKind.secondary,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// «غير متاح»: a value that has no documented source. Shown as a dotted
/// box with a lock — never a number, never a guess (D-1 S17).
class MqLockBox extends StatelessWidget {
  const MqLockBox({super.key, required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return CustomPaint(
      painter: _DashedBorderPainter(color: p.ink3, radius: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 20, color: p.ink3),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: MqType.small
                          .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
                  Text(message,
                      style: MqType.caption.copyWith(color: p.ink3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
        d += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Loads once, then shows loading / error / data with a soft cross-fade.
///
/// Unlike building a new Future on every rebuild, the Future lives in the
/// state: it is created once and re-created only when [reloadKey] changes or
/// the retry button is pressed. So a keyboard opening or a theme change never
/// restarts a query (the old AsyncSection did).
class MqAsync<T> extends StatefulWidget {
  const MqAsync({
    super.key,
    required this.load,
    required this.builder,
    this.reloadKey,
    this.loading,
    this.errorTitle = 'تعذّر تحميل البيانات',
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final Object? reloadKey;
  final Widget? loading;
  final String errorTitle;

  @override
  State<MqAsync<T>> createState() => _MqAsyncState<T>();
}

class _MqAsyncState<T> extends State<MqAsync<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  void didUpdateWidget(MqAsync<T> old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) _reload();
  }

  void _reload() {
    setState(() => _future = widget.load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        final Widget child;
        if (snap.connectionState != ConnectionState.done) {
          child = KeyedSubtree(
            key: const ValueKey('loading'),
            child: widget.loading ?? const MqLoadingCard(),
          );
        } else if (snap.hasError) {
          child = KeyedSubtree(
            key: const ValueKey('error'),
            child: MqErrorState(
              title: widget.errorTitle,
              message: 'بياناتك لم تُمَس. جرّب إعادة المحاولة.',
              detail: '${snap.error}',
              onRetry: _reload,
            ),
          );
        } else {
          child = KeyedSubtree(
            key: const ValueKey('data'),
            child: widget.builder(context, snap.data as T),
          );
        }
        return AnimatedSwitcher(
          duration: MqMotion.of(context, MqMotion.base),
          switchInCurve: MqMotion.enter,
          child: child,
        );
      },
    );
  }
}
