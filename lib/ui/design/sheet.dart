import 'package:flutter/material.dart';

import 'tokens.dart';

/// Bottom sheet (DS2): rises over a scrim, 28px top corners, a grabber, the
/// keyboard-aware padding, and content that scrolls when it is long. The
/// system back button closes it and leaves the screen underneath alone.
Future<T?> showMqSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
}) {
  final p = context.mq;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: p.surface,
    barrierColor: const Color(0x6B06101C),
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(MqSpace.radiusSheet)),
    ),
    builder: (sheetContext) {
      final q = sheetContext.mq;
      return Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: q.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null)
                Text(title, style: MqType.h2.copyWith(color: q.ink)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle,
                      style: MqType.small.copyWith(color: q.ink2)),
                ),
              if (title != null) const SizedBox(height: 14),
              builder(sheetContext),
            ],
          ),
        ),
      );
    },
  );
}
