import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/teacher_content_domain.dart';
import '../../repositories/teacher_content_repository.dart';
import '../design/tokens.dart';

/// «أستاذ · غير رسمي»: shown on EVERY piece of teacher content on the
/// student side (D-2 L01–L04, T09). The text is the domain constant, so it
/// cannot be reworded or hidden per screen.
class TeacherBadge extends StatelessWidget {
  const TeacherBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: p.accentSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.accent),
      ),
      child: Text(
        kTeacherBadge,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: p.accentInk,
        ),
      ),
    );
  }
}

class LessonStatusChip extends StatelessWidget {
  const LessonStatusChip(this.status, {super.key});
  final LessonStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final (bg, fg) = switch (status) {
      LessonStatus.draft => (p.surface2, p.ink2),
      LessonStatus.inReview => (p.accentSoft, p.accentInk),
      LessonStatus.published => (p.okSoft, p.ok),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.label,
          style:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// Small grey explanatory box (the «قرار مفتوح» notes of D-2).
class InfoBox extends StatelessWidget {
  const InfoBox(this.text, {super.key, this.icon = Icons.info_outline});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: p.ink2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, color: p.ink2)),
          ),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Shows the Arabic reason(s) of a refused write.
void showRefusal(BuildContext context, Object error) {
  final text = error is TeacherContentException
      ? error.message
      : 'تعذّر تنفيذ العملية: $error';
  showSnack(context, text);
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'تراجع',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel)),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel)),
      ],
    ),
  );
  return result ?? false;
}

/// One page image with its stored rotation. Never re-encodes the bytes.
class PageImage extends StatelessWidget {
  const PageImage({
    super.key,
    required this.bytes,
    this.quarterTurns = 0,
    this.fit = BoxFit.contain,
  });
  final Uint8List bytes;
  final int quarterTurns;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: Image.memory(
        bytes,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (ctx, __, ___) => Center(
          child: Icon(Icons.broken_image_outlined, color: ctx.mq.ink2),
        ),
      ),
    );
  }
}

/// One lesson in a list (teacher side, and — with [showBadge] — student side).
class LessonRow extends StatelessWidget {
  const LessonRow({
    super.key,
    required this.item,
    this.onTap,
    this.trailing,
    this.showStatus = true,
    this.showBadge = false,
  });

  final LessonListItem item;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showStatus;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final l = item.lesson;
    final section = (l.sectionLabel ?? '').trim();
    final track = (l.trackLabel ?? '').trim();
    final p = context.mq;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: p.brandSoft,
        child: Icon(Icons.menu_book_outlined, color: p.brand),
      ),
      title: Text(l.title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The class number and the stream are shown LARGE: this is what
            // the student looks for first.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (showBadge) const TeacherBadge(),
                _BigTag(
                  section.isEmpty ? 'القسم: غير محدد' : 'القسم: $section',
                  strong: section.isNotEmpty,
                ),
                if (track.isNotEmpty) _BigTag(track),
              ],
            ),
            const SizedBox(height: 6),
            Text('${l.subjectName} · ${internalLevelLabel(l.internalLevel)}',
                style: const TextStyle(fontSize: 13.5)),
            const SizedBox(height: 2),
            Text(
                'الأستاذ: ${l.teacherName.trim().isEmpty ? 'غير مذكور' : l.teacherName}'
                ' · ${pagesLabel(item.pageCount)}',
                style: TextStyle(fontSize: 13, color: p.ink2)),
          ],
        ),
      ),
      trailing: trailing ??
          (showStatus
              ? LessonStatusChip(LessonStatus.fromDb(l.status))
              : null),
    );
  }
}

/// «صفحة واحدة / صفحتان / 5 صفحات / 12 صفحة» — correct Arabic number forms.
String pagesLabel(int n) {
  if (n == 1) return 'صفحة واحدة';
  if (n == 2) return 'صفحتان';
  if (n >= 3 && n <= 10) return '$n صفحات';
  return '$n صفحة';
}

class _BigTag extends StatelessWidget {
  const _BigTag(this.text, {this.strong = true});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: strong ? p.brandSoft : p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: strong ? p.brand : p.line),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: strong ? 17 : 14,
              fontWeight: FontWeight.w800,
              color: strong ? p.brandDeep : p.ink2)),
    );
  }
}
