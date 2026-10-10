import 'package:drift/drift.dart'
    show OrderingTerm, OrderingMode, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../engines/error_engine.dart' show ErrorKind;
import '../../repositories/content_repository.dart';
import '../../repositories/error_repository.dart';
import '../design/motion.dart';
import '../design/primitives.dart';
import '../design/progress.dart';
import '../design/sheet.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';

class _NodeRow {
  const _NodeRow(this.mastery, this.nodeName, this.subjectName);
  final MasteryState mastery;
  final String nodeName;
  final String subjectName;
}

/// «التقدم» (D-1 S08–S10, A01): what the Mastery and Memory engines stored,
/// shown as stored. Accuracy (probability) and confidence are two numbers and
/// are never merged. Nothing is computed here, and an empty table says why it
/// is empty instead of showing invented figures.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int _page = 0;
  int _tick = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final app = context.watch<AppState>();
    if (app.studentId == null) return const SizedBox.shrink();
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.fromLTRB(MqSpace.screen, 12, MqSpace.screen, 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('التقدم',
                style: MqType.h1.copyWith(color: p.ink, fontSize: 24)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MqSpace.screen),
          child: MqSegmented<int>(
            options: const {0: 'الإتقان', 1: 'الذاكرة', 2: 'الأخطاء'},
            selected: _page,
            onChanged: (v) => setState(() => _page = v),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: MqTabStack(
            index: _page,
            children: [
              _MasteryPage(app: app, reloadKey: _tick),
              _MemoryPage(app: app, reloadKey: _tick),
              _ErrorsPage(
                  app: app,
                  reloadKey: _tick,
                  onChanged: () => setState(() => _tick++)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- mastery

class _MasteryPage extends StatelessWidget {
  const _MasteryPage({required this.app, required this.reloadKey});
  final AppState app;
  final int reloadKey;

  Future<List<_NodeRow>> _load() async {
    final db = app.db;
    final states = await (db.select(db.masteryStates)
          ..where((t) => t.studentId.equals(app.studentId!))
          ..orderBy([(t) => OrderingTerm(expression: t.probability)]))
        .get();
    final content = ContentRepository(db);
    return [
      for (final s in states)
        _NodeRow(s, await content.nameForNode(s.knowledgeNodeId),
            await content.subjectNameForNode(s.knowledgeNodeId)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqAsync<List<_NodeRow>>(
      reloadKey: reloadKey,
      load: _load,
      loading: const Padding(
          padding: EdgeInsets.all(MqSpace.screen), child: MqLoadingCard(lines: 4)),
      errorTitle: 'تعذّر عرض الإتقان',
      builder: (context, rows) {
        if (rows.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(MqSpace.screen),
            children: const [
              MqEmptyState(
                icon: Icons.psychology_alt_outlined,
                title: 'لا بيانات إتقان بعد',
                message:
                    'يبدأ حساب الإتقان بعد أن تنجز مهامك وتقيّم فهمك. لا نعرض أرقامًا قبل ذلك.',
              ),
            ],
          );
        }
        final bySubject = <String, List<_NodeRow>>{};
        for (final r in rows) {
          bySubject
              .putIfAbsent(r.subjectName.isEmpty ? 'بدون مادة' : r.subjectName,
                  () => [])
              .add(r);
        }
        return ListView(
          padding:
              const EdgeInsets.fromLTRB(MqSpace.screen, 4, MqSpace.screen, 28),
          children: [
            MqBanner(
              icon: Icons.info_outline_rounded,
              tone: MqTone.neutral,
              text:
                  'النسبة هي تقدير الإتقان، والثقة رقم منفصل عنها يخبرك كم نثق بالتقدير.',
            ),
            const SizedBox(height: 12),
            for (final e in bySubject.entries) ...[
              MqSectionTitle(e.key),
              for (final r in e.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MasteryRow(row: r, app: app),
                ),
            ],
          ],
        );
      },
    );
  }
}

MqTone _bandTone(double v) {
  if (v < 0.4) return MqTone.overdue;
  if (v < 0.7) return MqTone.accent;
  return MqTone.ok;
}

class _MasteryRow extends StatelessWidget {
  const _MasteryRow({required this.row, required this.app});
  final _NodeRow row;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final m = row.mastery;
    return MqCard(
      padding: const EdgeInsets.all(12),
      onTap: () => _showNodeSheet(context, app, row),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(row.nodeName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MqType.body
                        .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
              ),
              MqNum('${(m.probability * 100).round()}%', style: MqType.label),
            ],
          ),
          const SizedBox(height: 8),
          MqBar(value: m.probability.clamp(0.0, 1.0), tone: _bandTone(m.probability)),
          const SizedBox(height: 8),
          MqChip(
            label: m.confidence == null
                ? 'الثقة غير محسوبة'
                : 'ثقة ${(m.confidence! * 100).round()}%',
          ),
        ],
      ),
    );
  }
}

Future<void> _showNodeSheet(
    BuildContext context, AppState app, _NodeRow row) async {
  final db = app.db;
  final memory = await (db.select(db.memoryStates)
        ..where((t) =>
            t.studentId.equals(app.studentId!) &
            t.knowledgeNodeId.equals(row.mastery.knowledgeNodeId)))
      .getSingleOrNull();
  if (!context.mounted) return;
  await showMqSheet<void>(
    context,
    title: row.nodeName,
    subtitle: row.subjectName,
    builder: (ctx) {
      final p = ctx.mq;
      final m = row.mastery;
      String date(DateTime d) {
        final l = d.toLocal();
        return '${l.day}/${l.month}/${l.year}';
      }

      Widget line(String label, Widget value) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                    child: Text(label,
                        style: MqType.small.copyWith(color: p.ink2))),
                value,
              ],
            ),
          );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line('الإتقان', MqNum('${(m.probability * 100).round()}%', style: MqType.label)),
          line(
              'الثقة',
              m.confidence == null
                  ? Text('غير محسوبة',
                      style: MqType.small.copyWith(color: p.ink3))
                  : MqNum('${(m.confidence! * 100).round()}%', style: MqType.label)),
          if (m.observationCount != null)
            line('عدد الملاحظات',
                MqNum('${m.observationCount}', style: MqType.label)),
          const SizedBox(height: 6),
          if (memory == null)
            const MqBanner(
              icon: Icons.layers_outlined,
              tone: MqTone.neutral,
              text: 'لا حالة ذاكرة لهذا الموضوع بعد.',
            )
          else ...[
            line('الاستدعاء الحالي',
                MqNum('${(memory.retrievability * 100).round()}%', style: MqType.label)),
            line('الثبات (أيام)',
                MqNum(memory.stability.toStringAsFixed(1), style: MqType.label)),
            if (memory.difficulty != null)
              line('الصعوبة',
                  MqNum(memory.difficulty!.toStringAsFixed(1), style: MqType.label)),
            line('المراجعة القادمة',
                MqNum(date(memory.nextReviewDate), style: MqType.label)),
            const SizedBox(height: 4),
            Text(
                'خطر النسيان = 1 − الاستدعاء، كما هو مطبَّق الآن. صيغة «النسيان المضخّم» لم تُعتمد بعد.',
                style: MqType.caption.copyWith(color: p.ink3)),
          ],
        ],
      );
    },
  );
}

// ----------------------------------------------------------------- memory

class _MemoryRowData {
  const _MemoryRowData(this.state, this.nodeName, this.subjectName);
  final MemoryState state;
  final String nodeName;
  final String subjectName;
}

class _MemoryPage extends StatelessWidget {
  const _MemoryPage({required this.app, required this.reloadKey});
  final AppState app;
  final int reloadKey;

  Future<List<_MemoryRowData>> _load() async {
    final db = app.db;
    final states = await (db.select(db.memoryStates)
          ..where((t) => t.studentId.equals(app.studentId!))
          ..orderBy([(t) => OrderingTerm(expression: t.nextReviewDate)]))
        .get();
    final content = ContentRepository(db);
    return [
      for (final s in states)
        _MemoryRowData(s, await content.nameForNode(s.knowledgeNodeId),
            await content.subjectNameForNode(s.knowledgeNodeId)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqAsync<List<_MemoryRowData>>(
      reloadKey: reloadKey,
      load: _load,
      loading: const Padding(
          padding: EdgeInsets.all(MqSpace.screen), child: MqLoadingCard(lines: 3)),
      errorTitle: 'تعذّر عرض الذاكرة',
      builder: (context, rows) {
        if (rows.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(MqSpace.screen),
            children: const [
              MqEmptyState(
                icon: Icons.layers_outlined,
                title: 'لا مراجعات بعد',
                message:
                    'تظهر هنا المواضيع التي تحتاج مراجعة بعد أن تنجز مهامك الأولى.',
              ),
            ],
          );
        }
        final now = DateTime.now().toUtc();
        final due = rows.where((r) => !r.state.nextReviewDate.isAfter(now)).toList();
        final later = rows.where((r) => r.state.nextReviewDate.isAfter(now)).toList();
        return ListView(
          padding:
              const EdgeInsets.fromLTRB(MqSpace.screen, 4, MqSpace.screen, 28),
          children: [
            MqSectionTitle('مستحقة الآن (${due.length})'),
            if (due.isEmpty)
              const MqBanner(
                icon: Icons.check_circle_outline_rounded,
                tone: MqTone.ok,
                text: 'لا مراجعات مستحقة الآن.',
              ),
            for (final r in due)
              _MemoryTile(r: r, now: now, overdue: true),
            if (later.isNotEmpty) ...[
              const SizedBox(height: 6),
              MqSectionTitle('لاحقًا (${later.length})'),
              for (final r in later) _MemoryTile(r: r, now: now, overdue: false),
            ],
          ],
        );
      },
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({required this.r, required this.now, required this.overdue});
  final _MemoryRowData r;
  final DateTime now;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final days = r.state.nextReviewDate.difference(now).inDays;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MqCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            MqRing(
              value: r.state.retrievability.clamp(0.0, 1.0),
              size: 44,
              thickness: 5,
              color: overdue ? p.overdue : p.info,
              track: overdue ? p.overdueSoft : p.infoSoft,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.nodeName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MqType.body
                          .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                  Text(
                    overdue
                        ? 'مستحقة منذ ${-days} يومًا'
                        : 'بعد $days يومًا',
                    style: MqType.caption.copyWith(color: p.ink3),
                  ),
                ],
              ),
            ),
            MqNum('${(r.state.retrievability * 100).round()}%',
                style: MqType.label),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- errors

class _ErrorsPage extends StatelessWidget {
  const _ErrorsPage(
      {required this.app, required this.reloadKey, required this.onChanged});
  final AppState app;
  final int reloadKey;
  final VoidCallback onChanged;

  Future<Map<String, int>> _load() async {
    final db = app.db;
    final rows = await (db.select(db.errorRecords)
          ..where((t) => t.studentId.equals(app.studentId!)))
        .get();
    final out = <String, int>{};
    for (final r in rows) {
      out[r.errorType] = (out[r.errorType] ?? 0) + 1;
    }
    return out;
  }

  static const _labels = {
    'careless': 'خطأ من سهو',
    'conceptual': 'خطأ في الفهم',
    'missingPrerequisite': 'ينقصني متطلب سابق',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return MqAsync<Map<String, int>>(
      reloadKey: reloadKey,
      load: _load,
      loading: const Padding(
          padding: EdgeInsets.all(MqSpace.screen), child: MqLoadingCard(lines: 3)),
      errorTitle: 'تعذّر عرض الأخطاء',
      builder: (context, counts) => ListView(
        padding:
            const EdgeInsets.fromLTRB(MqSpace.screen, 4, MqSpace.screen, 28),
        children: [
          MqButton(
            label: 'سجّل خطأً',
            icon: Icons.add_rounded,
            block: true,
            onPressed: () async {
              final ok = await _recordError(context, app);
              if (ok) onChanged();
            },
          ),
          const SizedBox(height: 14),
          const MqSectionTitle('ما سجّلتَه'),
          if (counts.isEmpty)
            const MqEmptyState(
              icon: Icons.edit_note_rounded,
              title: 'لا أخطاء مسجّلة',
              message: 'سجّل خطأً عند وقوعه، وسيُحفظ كما أدخلته.',
            )
          else
            for (final e in counts.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MqCard(
                  kind: MqCardKind.soft,
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(_labels[e.key] ?? e.key,
                              style: MqType.body.copyWith(color: p.ink))),
                      MqNum('${e.value}', style: MqType.h3),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 10),
          const MqLockBox(
            title: 'أنماط الأخطاء والتحليلات',
            message:
                'تأتي بعد المرحلة A-2. إلى ذلك الحين نحفظ ما تسجّله فقط ولا نحلّله.',
          ),
        ],
      ),
    );
  }
}

Future<bool> _recordError(BuildContext context, AppState app) async {
  final db = app.db;
  final nodes = await (db.select(db.knowledgeNodes)
        ..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .get();
  if (!context.mounted) return false;
  if (nodes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف مهمة أولًا ليكون هناك موضوع تسجّل عليه.')));
    return false;
  }
  final saved = await showMqSheet<bool>(
    context,
    title: 'تسجيل خطأ',
    subtitle: 'اختر الموضوع ونوع الخطأ.',
    builder: (ctx) => _RecordErrorBody(db: db, studentId: app.studentId!, nodes: nodes),
  );
  return saved == true;
}

class _RecordErrorBody extends StatefulWidget {
  const _RecordErrorBody(
      {required this.db, required this.studentId, required this.nodes});
  final AppDatabase db;
  final String studentId;
  final List<KnowledgeNode> nodes;

  @override
  State<_RecordErrorBody> createState() => _RecordErrorBodyState();
}

class _RecordErrorBodyState extends State<_RecordErrorBody> {
  String? _nodeId;
  ErrorKind _kind = ErrorKind.conceptual;

  Future<void> _save() async {
    if (_nodeId == null) return;
    await ErrorRepository(widget.db).record(
      studentId: widget.studentId,
      knowledgeNodeId: _nodeId!,
      kind: _kind,
      timestamp: DateTime.now().toUtc(),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('سُجّل الخطأ.')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _nodeId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'الموضوع'),
          items: [
            for (final n in widget.nodes)
              DropdownMenuItem(value: n.id, child: Text(n.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _nodeId = v),
        ),
        const SizedBox(height: 14),
        MqSegmented<ErrorKind>(
          options: const {
            ErrorKind.careless: 'سهو',
            ErrorKind.conceptual: 'فهم',
            ErrorKind.missingPrerequisite: 'متطلب سابق',
          },
          selected: _kind,
          onChanged: (v) => setState(() => _kind = v),
        ),
        const SizedBox(height: 16),
        MqButton(
          label: 'سجّل',
          icon: Icons.check_rounded,
          block: true,
          onPressed: _nodeId == null ? null : _save,
        ),
      ],
    );
  }
}
