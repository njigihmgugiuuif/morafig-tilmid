import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/task_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';
import '../widgets/debounced_button.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppState>().db;
    final taskRepo = TaskRepository(db);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المهام'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'نشطة'),
            Tab(text: 'منجزة'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _TaskStreamList(
            stream: taskRepo.watchActive(''),
            db: db,
            showComplete: true,
          ),
          _TaskStreamList(
            stream: taskRepo.watchCompleted(),
            db: db,
            showComplete: false,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('مهمة جديدة'),
        onPressed: () => _openAddTaskSheet(context),
      ),
    );
  }

  Future<void> _openAddTaskSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _AddTaskSheet(),
    );
  }
}

class _TaskStreamList extends StatelessWidget {
  const _TaskStreamList({
    required this.stream,
    required this.db,
    required this.showComplete,
  });

  final Stream<List<Task>> stream;
  final AppDatabase db;
  final bool showComplete;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Task>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('خطأ: ${snapshot.error}'));
        }
        final tasks = snapshot.data ?? [];
        if (tasks.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.task_alt, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    showComplete
                        ? 'لا توجد مهام حاليًا. اضغط + لإضافة مهمة جديدة.'
                        : 'لا توجد مهام منجزة بعد.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: tasks.length,
          itemBuilder: (context, i) => _TaskCard(
            task: tasks[i],
            db: db,
            showComplete: showComplete,
          ),
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.db,
    required this.showComplete,
  });

  final Task task;
  final AppDatabase db;
  final bool showComplete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: FutureBuilder<String>(
        future: ContentRepository(db).nameForNode(task.knowledgeNodeId),
        builder: (context, snapshot) {
          final title = snapshot.data ?? '...';
          return ListTile(
            title: Text(title),
            subtitle: Text(
              '${task.estimatedDurationMinutes} دقيقة'
              '${task.isSplittable ? " • قابلة للتقسيم" : ""}',
            ),
            trailing: showComplete
                ? IconButton(
                    icon: const Icon(Icons.check_circle_outline,
                        color: AppColors.success),
                    tooltip: 'وضع علامة إنجاز',
                    onPressed: () async {
                      await TaskRepository(db).markComplete(task);
                    },
                  )
                : const Icon(Icons.check_circle, color: AppColors.success),
          );
        },
      ),
    );
  }
}

class _AddTaskSheet extends StatefulWidget {
  const _AddTaskSheet();
  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _titleController = TextEditingController();
  final _durationController = TextEditingController(text: '30');
  bool _isSplittable = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _titleController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final db = context.read<AppState>().db;
    final content = ContentRepository(db);
    final level = await content.getOrCreateDefaultLevel();
    final node = await content.quickCreateNode(
      educationLevelId: level.id,
      subjectName: _subjectController.text,
      nodeName: _titleController.text,
    );
    await TaskRepository(db).createTask(
      knowledgeNodeId: node.id,
      estimatedDurationMinutes: int.parse(_durationController.text),
      isSplittable: _isSplittable,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('مهمة جديدة',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _subjectController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'المادة'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'أدخل اسم المادة' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'عنوان المهمة/الدرس'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'أدخل عنوان المهمة' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _durationController,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المدة (بالدقائق)'),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) return 'أدخل مدة صحيحة';
                return null;
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('قابلة للتقسيم إلى جلسات أقصر'),
              value: _isSplittable,
              onChanged: (v) => setState(() => _isSplittable = v),
            ),
            const SizedBox(height: 8),
            DebouncedButton(label: 'إضافة', onPressed: _submit),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
