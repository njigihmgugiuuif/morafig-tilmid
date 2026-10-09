import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../database/app_database.dart';
import '../../repositories/task_repository.dart';
import '../../services/intelligence_service.dart';
import '../design/primitives.dart';
import '../design/progress.dart';
import '../design/sheet.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/home_data.dart';

IconData prioritySignalIcon(String key) {
  switch (key) {
    case 'masteryGap':
      return Icons.track_changes_rounded;
    case 'forgettingRisk':
      return Icons.layers_outlined;
    case 'officialCoefficient':
      return Icons.scale_outlined;
    case 'examProximity':
      return Icons.school_outlined;
    case 'deadlinePressure':
      return Icons.timer_outlined;
    case 'longTermGoalAlignment':
      return Icons.flag_outlined;
    default:
      return Icons.circle_outlined;
  }
}

MqTone prioritySignalTone(String key) {
  switch (key) {
    case 'masteryGap':
      return MqTone.brand;
    case 'forgettingRisk':
      return MqTone.info;
    case 'examProximity':
    case 'deadlinePressure':
      return MqTone.accent;
    default:
      return MqTone.neutral;
  }
}

String confidenceLabel(String level) {
  switch (level) {
    case 'high':
      return 'عالية';
    case 'medium':
      return 'متوسطة';
    default:
      return 'منخفضة';
  }
}

/// «الآن»: the one thing to do, on the deep-teal hero. It carries the score,
/// the strongest reasons and the two actions — start and «لماذا؟».
class NowHero extends StatelessWidget {
  const NowHero({
    super.key,
    required this.item,
    required this.onStart,
    required this.onWhy,
    this.startLabel = 'ابدأ',
  });

  final PrioritizedTask item;
  final VoidCallback onStart;
  final VoidCallback onWhy;
  final String startLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final top = item.factors.take(3).toList();
    final ground = Color.lerp(p.brandDeep, p.brand, p.isDark ? 0.18 : 0.12)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(MqSpace.radiusHero),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [ground, p.brandDeep],
          ),
        ),
        child: CustomPaint(
          painter: _ArchPainter(),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    const MqChip(
                        label: 'الآن', icon: Icons.bolt_rounded, onHero: true),
                    MqChip(
                      label:
                          'أولوية ${item.priority.score.toStringAsFixed(2)}',
                      onHero: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  item.nodeName,
                  style: MqType.h2.copyWith(color: Colors.white, fontSize: 21),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (item.subjectName.isNotEmpty) item.subjectName,
                    '${item.task.remainingDurationMinutes} دقيقة تقريبًا',
                  ].join(' · '),
                  style: MqType.small.copyWith(color: const Color(0xC7FFFFFF)),
                ),
                if (top.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final f in top)
                        MqChip(label: prioritySignalLabel(f.key), onHero: true),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: MqButton(
                        label: startLabel,
                        icon: Icons.play_arrow_rounded,
                        kind: MqButtonKind.onHero,
                        block: true,
                        onPressed: onStart,
                      ),
                    ),
                    const SizedBox(width: 10),
                    MqButton(
                      label: 'لماذا؟',
                      icon: Icons.help_outline_rounded,
                      kind: MqButtonKind.outlineOnHero,
                      onPressed: onWhy,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The arch of the logo, very large and very faint, behind the hero.
class _ArchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / 64 * 1.5;
    canvas.save();
    canvas.translate(-s * 6, size.height - s * 40);
    canvas.scale(s, s);
    final path = Path()
      ..moveTo(10, 46)
      ..cubicTo(10, 32, 18, 20, 32, 20)
      ..cubicTo(46, 20, 54, 32, 54, 46);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x12FFFFFF),
    );
    canvas.restore();
    // A single amber point, the «now» of the mark.
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.14),
      math.min(size.width, size.height) * 0.025,
      Paint()..color = const Color(0x66F5A524),
    );
  }

  @override
  bool shouldRepaint(_ArchPainter old) => false;
}

/// «لماذا هذه المهمة؟» (D-1 S16): the signals that took part with their
/// weights, the ones that were left out and why, and how sure the system is.
/// Everything is what the Priority Engine stored — nothing is recomputed.
Future<void> showWhySheet(BuildContext context, PrioritizedTask item) {
  return showMqSheet<void>(
    context,
    title: 'لماذا هذه المهمة؟',
    subtitle: item.nodeName,
    builder: (ctx) => _WhyBody(item: item),
  );
}

class _WhyBody extends StatelessWidget {
  const _WhyBody({required this.item});
  final PrioritizedTask item;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            MqChip(
              label: 'الدرجة ${item.priority.score.toStringAsFixed(2)}',
              tone: MqTone.brand,
              large: true,
            ),
            const SizedBox(width: 8),
            MqChip(
              label: 'الثقة: ${confidenceLabel(item.priority.confidenceLevel)}',
              large: true,
              outline: true,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (item.factors.isEmpty)
          const MqBanner(
            text: 'لا يتوفر تفسير مسجّل لهذه المهمة.',
            icon: Icons.info_outline,
          )
        else ...[
          Text('ما أثّر في الترتيب',
              style: MqType.h3.copyWith(color: p.ink)),
          const SizedBox(height: 8),
          for (final f in item.factors) _FactorRow(factor: f),
        ],
        if (item.excluded.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('لم يدخل في الحساب (لا توجد بيانات)',
              style: MqType.h3.copyWith(color: p.ink)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in item.excluded)
                MqChip(label: prioritySignalLabel(k), outline: true),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'لا نخمّن قيمة غير موجودة؛ أوزان هذه العناصر وُزّعت على العناصر '
            'المتاحة.',
            style: MqType.caption.copyWith(color: p.ink3),
          ),
        ],
      ],
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.factor});
  final PriorityFactorView factor;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final tone = prioritySignalTone(factor.key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MqIconTile(icon: prioritySignalIcon(factor.key), tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(prioritySignalLabel(factor.key),
                          style: MqType.small.copyWith(
                              color: p.ink, fontWeight: FontWeight.w700)),
                    ),
                    MqNum(factor.value.toStringAsFixed(2),
                        style: MqType.small
                            .copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                MqBar(value: factor.value, tone: tone, height: 6),
                const SizedBox(height: 4),
                Text(
                  '${prioritySignalHint(factor.key)} الوزن '
                  '${factor.weight.toStringAsFixed(2)}.',
                  style: MqType.caption.copyWith(color: p.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks how well the student understood and for how long they worked, then
/// completes the task and lets IntelligenceService turn that evidence into
/// Mastery / Memory / Priority (the same pipeline as before; only the sheet
/// is new). Dismissing the sheet completes nothing. Returns true when the
/// task was completed.
Future<bool> completeTaskWithFeedback(
  BuildContext context,
  AppDatabase db,
  Task task,
) async {
  final result = await showMqSheet<_Completion>(
    context,
    title: 'كيف كان فهمك؟',
    subtitle: 'نستعمل إجابتك لتحديث إتقانك وذاكرتك. التخطي لا يغيّر شيئًا.',
    builder: (ctx) => _CompletionBody(
      initialMinutes: task.estimatedDurationMinutes,
    ),
  );
  if (result == null) return false; // dismissed: the task stays open

  await TaskRepository(db).markComplete(
    task,
    understanding: result.understanding,
    actualMinutes: result.minutes,
  );
  final run = await IntelligenceService(db).processPendingEvents();
  if (context.mounted) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(run.hasErrors
          ? 'أُنجزت المهمة، لكن تعذّر تحديث التحليل: ${run.errors.first}'
          : 'أُنجزت المهمة وحُدّثت أولوياتك.'),
    ));
  }
  return true;
}

class _Completion {
  const _Completion(this.understanding, this.minutes);
  final String understanding;
  final int minutes;
}

class _CompletionBody extends StatefulWidget {
  const _CompletionBody({required this.initialMinutes});
  final int initialMinutes;

  @override
  State<_CompletionBody> createState() => _CompletionBodyState();
}

class _CompletionBodyState extends State<_CompletionBody> {
  late int _minutes = widget.initialMinutes;

  void _pick(String understanding) =>
      Navigator.of(context).pop(_Completion(understanding, _minutes));

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    Widget option(IconData icon, MqTone tone, String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: MqCard(
          kind: MqCardKind.flat,
          padding: const EdgeInsets.all(12),
          onTap: () => _pick(value),
          child: Row(
            children: [
              MqIconTile(icon: icon, tone: tone),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: MqType.label.copyWith(color: p.ink, fontSize: 15)),
              ),
              Icon(Icons.chevron_right_rounded, color: p.ink3),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MqCard(
          kind: MqCardKind.soft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, size: 20, color: p.ink2),
              const SizedBox(width: 8),
              Expanded(
                child: Text('المدة الفعلية',
                    style: MqType.small.copyWith(color: p.ink2)),
              ),
              MqIconButton(
                icon: Icons.remove_rounded,
                label: 'أنقص خمس دقائق',
                onTap: _minutes > 5 ? () => setState(() => _minutes -= 5) : null,
              ),
              SizedBox(
                width: 76,
                child: Center(
                  child: MqNum('$_minutes د',
                      style: MqType.h3.copyWith(fontSize: 16)),
                ),
              ),
              MqIconButton(
                icon: Icons.add_rounded,
                label: 'زِد خمس دقائق',
                onTap: _minutes < 480 ? () => setState(() => _minutes += 5) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        option(Icons.sentiment_very_satisfied_rounded, MqTone.ok, 'فهمته جيدًا',
            Understanding.good),
        option(Icons.sentiment_neutral_rounded, MqTone.accent,
            'فهمت جزءًا منه', Understanding.partial),
        option(Icons.sentiment_dissatisfied_rounded, MqTone.overdue,
            'لم أفهمه', Understanding.notUnderstood),
        const SizedBox(height: 4),
        MqButton(
          label: 'تخطي (لا تحديث للتحليل)',
          kind: MqButtonKind.ghost,
          block: true,
          onPressed: () => _pick(Understanding.unknown),
        ),
      ],
    );
  }
}

/// A row for a ranked task: subject tone, name, short reason, score.
class RankedTaskRow extends StatelessWidget {
  const RankedTaskRow({super.key, required this.item, required this.onTap});
  final PrioritizedTask item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final tone = p.toneFor(item.subjectName);
    final reason = item.factors.isEmpty
        ? null
        : prioritySignalLabel(item.factors.first.key);
    return MqCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          MqIconTile(
            icon: Icons.menu_book_outlined,
            colors: MqToneColors(tone.soft, tone.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nodeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MqType.small
                        .copyWith(color: p.ink, fontWeight: FontWeight.w700)),
                Text(
                  [
                    if (item.subjectName.isNotEmpty) item.subjectName,
                    '${item.task.remainingDurationMinutes} د',
                    if (reason != null) reason,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MqType.caption.copyWith(color: p.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MqNum(item.priority.score.toStringAsFixed(2),
              style: MqType.small.copyWith(fontWeight: FontWeight.w700)),
          Icon(Icons.chevron_right_rounded, color: p.ink3),
        ],
      ),
    );
  }
}
