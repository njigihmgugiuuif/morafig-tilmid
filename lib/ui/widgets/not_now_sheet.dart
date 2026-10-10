import 'package:flutter/material.dart';

import '../../database/app_database.dart';
import '../../repositories/explanation_and_override_repositories.dart';
import '../../repositories/priority_repository.dart';
import '../design/primitives.dart';
import '../design/sheet.dart';
import '../design/tokens.dart';

/// A03: the student answers a suggestion with «ليس الآن» or «هذا غير مناسب».
/// The answer is written to HumanOverrides (append-only, pointing at the
/// explanation that was on screen). It changes no priority and no plan: the
/// engines that may learn from it are not wired yet, and the sheet says so.
/// Returns true when the answer was recorded.
Future<bool> showNotNowSheet(
  BuildContext context, {
  required AppDatabase db,
  required Task task,
}) async {
  final done = await showMqSheet<bool>(
    context,
    title: 'ليست مناسبة الآن؟',
    subtitle: 'نسجّل جوابك مع سبب الاقتراح. لا يتغير ترتيبك تلقائيًا.',
    builder: (ctx) => _NotNowBody(db: db, task: task),
  );
  return done == true;
}

class _NotNowBody extends StatefulWidget {
  const _NotNowBody({required this.db, required this.task});
  final AppDatabase db;
  final Task task;

  @override
  State<_NotNowBody> createState() => _NotNowBodyState();
}

class _NotNowBodyState extends State<_NotNowBody> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save(String action) async {
    final state = await PriorityRepository(widget.db).read(widget.task.id);
    if (state == null) {
      setState(() => _error = 'لا اقتراح محسوب لهذه المهمة بعد، فلا شيء يُسجَّل.');
      return;
    }
    final text = _reason.text.trim();
    await HumanOverrideRepository(widget.db).record(
      taskId: widget.task.id,
      action: action,
      explanationId: state.explanationId,
      reportedReason: text.isEmpty ? null : text,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('سجّلنا جوابك.')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _reason,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'السبب (اختياري)'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: MqType.small.copyWith(color: context.mq.overdue)),
        ],
        const SizedBox(height: 14),
        MqButton(
          label: 'ليس الآن',
          icon: Icons.schedule_rounded,
          kind: MqButtonKind.secondary,
          block: true,
          onPressed: () => _save('postpone'),
        ),
        const SizedBox(height: 10),
        MqButton(
          label: 'هذا غير مناسب',
          icon: Icons.thumb_down_alt_outlined,
          kind: MqButtonKind.secondary,
          block: true,
          onPressed: () => _save('reject'),
        ),
      ],
    );
  }
}
