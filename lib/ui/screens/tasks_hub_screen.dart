import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/task_repository.dart';
import '../../services/intelligence_service.dart';
import '../design/motion.dart';
import '../design/page.dart';
import '../design/primitives.dart';
import '../design/sheet.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';
import '../state/home_data.dart';
import '../widgets/priority_views.dart';
import 'task_detail_screen.dart';

/// «المهام» (D-1 DS3): active tasks · completed tasks · the ranked priorities
/// (which used to be a tab of its own). Rows open the task detail (S14); the
/// check button runs the same completion pipeline as everywhere else; the
/// «+» creates a task exactly as the old form did.
///
/// The old TasksScreen / PrioritiesScreen files are no longer used by the
/// shell; their behaviour is covered here (add, complete, list, explanation).
class TasksHubScreen extends StatefulWidget {
  const TasksHubScreen({super.key, this.active = true});
  final bool active;

  @override
  State<TasksHubScreen> createState() => _TasksHubScreenState();
}

class _TasksHubScreenState extends State<TasksHubScreen> {
  int _page = 0;
  int _tick = 0;

  @override
  void didUpdateWidget(TasksHubScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _tick++;
  }

  Future<void> _openDetail(Task task) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => TaskDetailScreen(task: task)),
    );
    if (mounted) setState(() => _tick++);
  }

  Future<void> _addTask() async {
    final added = await showMqSheet<bool>(
      context,
      title: 'مهمة جديدة',
      builder: (ctx) => const _AddTaskBody(),
    );
    if (added == true && mounted) setState(() => _tick++);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final db = context.watch<AppState>().db;
    final repo = TaskRepository(db);
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  MqSpace.screen, 12, MqSpace.screen, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('المهام',
                    style: MqType.h1.copyWith(color: p.ink, fontSize: 24)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MqSpace.screen),
              child: MqSegmented<int>(
                options: const {0: 'نشطة', 1: 'الأولويات', 2: 'منجزة'},
                selected: _page,
                onChanged: (v) => setState(() => _page = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: MqTabStack(
                index: _page,
                children: [
                  _TaskList(
                      stream: repo.watchActive(''),
                      db: db,
                      completed: false,
                      onOpen: _openDetail),
                  _PriorityList(db: db, reloadKey: _tick, onOpen: _openDetail),
                  _TaskList(
                      stream: repo.watchCompleted(),
                      db: db,
                      completed: true,
                      onOpen: _openDetail),
                ],
              ),
            ),
          ],
        ),
        PositionedDirectional(
          end: MqSpace.screen,
          bottom: 16,
          child: MqFab(
              label: 'مهمة جديدة', icon: Icons.add_rounded, onPressed: _addTask),
        ),
      ],
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.stream,
    required this.db,
    required this.completed,
    required this.onOpen,
  });
  final Stream<List<Task>> stream;
  final AppDatabase db;
  final bool completed;
  final Future<void> Function(Task) onOpen;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Task>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: MqErrorState(
              title: 'تعذّر عرض المهام',
              message: 'لم تتغير بياناتك.',
              detail: '${snap.error}',
            ),
          );
        }
        if (!snap.hasData) {
          return ListView(
            padding: const EdgeInsets.all(MqSpace.screen),
            children: const [MqLoadingCard(lines: 2), SizedBox(height: 10), MqLoadingCard(lines: 2)],
          );
        }
        final tasks = snap.data!;
        if (tasks.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(MqSpace.screen),
            children: [
              MqEmptyState(
                icon: completed ? Icons.history_rounded : Icons.task_alt_rounded,
                title: completed ? 'لا مهام منجزة بعد' : 'لا مهام الآن',
                message: completed
                    ? 'ستظهر هنا المهام التي تنجزها.'
                    : 'أضف مهمة بزر «مهمة جديدة» وسنرتّبها لك حسب الأولوية.',
              ),
            ],
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(MqSpace.screen, 4, MqSpace.screen, 96),
          itemCount: tasks.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TaskRow(
                task: tasks[i], db: db, completed: completed, onOpen: onOpen),
          ),
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.db,
    required this.completed,
    required this.onOpen,
  });
  final Task task;
  final AppDatabase db;
  final bool completed;
  final Future<void> Function(Task) onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    final content = ContentRepository(db);
    return FutureBuilder<List<String>>(
      future: Future.wait([
        content.nameForNode(task.knowledgeNodeId),
        content.subjectNameForNode(task.knowledgeNodeId),
      ]),
      builder: (context, snap) {
        final title = snap.data?[0] ?? '…';
        final subject = snap.data?[1] ?? '';
        final tone = p.toneFor(subject);
        return MqCard(
          padding: const EdgeInsets.all(12),
          onTap: () => onOpen(task),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MqType.body
                            .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                    Text(
                      [
                        if (subject.isNotEmpty) subject,
                        '${task.estimatedDurationMinutes} دقيقة',
                        if (task.isSplittable) 'قابلة للتقسيم',
                        if (task.completionStatus == 'partial') 'بدأتَها',
                      ].join(' · '),
                      style: MqType.caption.copyWith(color: p.ink3),
                    ),
                  ],
                ),
              ),
              if (completed)
                Icon(Icons.check_circle_rounded, color: p.ok)
              else
                MqIconButton(
                  icon: Icons.check_rounded,
                  label: 'وضع علامة إنجاز',
                  onTap: () => completeTaskWithFeedback(context, db, task),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PriorityList extends StatelessWidget {
  const _PriorityList({
    required this.db,
    required this.reloadKey,
    required this.onOpen,
  });
  final AppDatabase db;
  final int reloadKey;
  final Future<void> Function(Task) onOpen;

  @override
  Widget build(BuildContext context) {
    return MqAsync<List<PrioritizedTask>>(
      reloadKey: reloadKey,
      load: () => HomeData(db).readRanked(limit: 50),
      loading: const Padding(
          padding: EdgeInsets.all(MqSpace.screen), child: MqLoadingCard(lines: 3)),
      errorTitle: 'تعذّر عرض الأولويات',
      builder: (context, items) {
        if (items.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(MqSpace.screen),
            children: const [
              MqEmptyState(
                icon: Icons.flag_outlined,
                title: 'لا أولويات بعد',
                message:
                    'تُحسب الأولوية للمهام المفتوحة عند معالجتها. أضف مهمة أو أنجز واحدة.',
              ),
            ],
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(MqSpace.screen, 4, MqSpace.screen, 96),
          itemCount: items.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 28,
                  child: Center(
                    child: MqNum('${i + 1}',
                        style: MqType.label, color: context.mq.ink3),
                  ),
                ),
                Expanded(
                  child: RankedTaskRow(
                    item: items[i],
                    onTap: () => onOpen(items[i].task),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AddTaskBody extends StatefulWidget {
  const _AddTaskBody();
  @override
  State<_AddTaskBody> createState() => _AddTaskBodyState();
}

class _AddTaskBodyState extends State<_AddTaskBody> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _title = TextEditingController();
  final _duration = TextEditingController(text: '30');
  bool _splittable = false;

  @override
  void dispose() {
    _subject.dispose();
    _title.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final db = context.read<AppState>().db;
    final content = ContentRepository(db);
    final level = await content.getOrCreateDefaultLevel();
    final node = await content.quickCreateNode(
      educationLevelId: level.id,
      subjectName: _subject.text,
      nodeName: _title.text,
    );
    await TaskRepository(db).createTask(
      knowledgeNodeId: node.id,
      estimatedDurationMinutes: int.parse(_duration.text),
      isSplittable: _splittable,
    );
    await IntelligenceService(db).processPendingEvents();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mq;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'المادة'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'أدخل اسم المادة' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'عنوان المهمة / الدرس'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'أدخل عنوان المهمة' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'المدة (بالدقائق)'),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n <= 0) return 'أدخل مدة صحيحة';
              return null;
            },
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: p.brand,
            title: Text('قابلة للتقسيم إلى جلسات أقصر',
                style: MqType.body.copyWith(color: p.ink)),
            value: _splittable,
            onChanged: (v) => setState(() => _splittable = v),
          ),
          const SizedBox(height: 8),
          MqButton(label: 'إضافة', icon: Icons.add_rounded, block: true, onPressed: _submit),
        ],
      ),
    );
  }
}
