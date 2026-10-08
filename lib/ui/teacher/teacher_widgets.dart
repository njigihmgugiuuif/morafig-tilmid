import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/teacher_content_domain.dart';
import '../../repositories/teacher_content_repository.dart';
import '../theme/app_theme.dart';

/// «أستاذ · غير رسمي»: shown on EVERY piece of teacher content on the
/// student side (D-2 L01–L04, T09). The text is the domain constant, so it
/// cannot be reworded or hidden per screen.
class TeacherBadge extends StatelessWidget {
  const TeacherBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1D6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.secondary),
      ),
      child: const Text(
        kTeacherBadge,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF7A4F00),
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
    final (bg, fg) = switch (status) {
      LessonStatus.draft => (const Color(0xFFE9EEF0), AppColors.textSecondary),
      LessonStatus.inReview => (const Color(0xFFFFF1D6), const Color(0xFF7A4F00)),
      LessonStatus.published => (const Color(0xFFDDF3E6), AppColors.success),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary)),
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
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined,
              color: AppColors.textSecondary),
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
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFE3EEF2),
        child: Icon(Icons.menu_book_outlined, color: AppColors.primary),
      ),
      title: Text(l.title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showBadge) const TeacherBadge(),
            Text('${l.subjectName} · ${internalLevelLabel(l.internalLevel)}',
                style: const TextStyle(fontSize: 12.5)),
            Text(section.isEmpty ? 'القسم: غير محدد' : 'القسم: $section',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            Text('${item.pageCount} صفحات',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
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
