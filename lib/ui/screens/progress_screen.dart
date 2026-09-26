import 'package:drift/drift.dart' show OrderingTerm, OrderingMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../repositories/content_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';

/// "الإتقان والذاكرة والمراجعة" — shows real MasteryState and MemoryState
/// rows. These tables are populated only once the Mastery(BKT)/Memory
/// (FSRS) engines are actually invoked from a task-completion pipeline
/// (Track D integration, not part of this UI pass — see
/// task_repository.dart's doc comment). Until then this screen correctly,
/// honestly shows the empty state rather than fabricated numbers.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
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
    final appState = context.watch<AppState>();
    final db = appState.db;
    final studentId = appState.studentId!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقدم والإتقان'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'الإتقان'),
            Tab(text: 'المراجعة (الذاكرة)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MasteryTab(db: db, studentId: studentId),
          _MemoryTab(db: db, studentId: studentId),
        ],
      ),
    );
  }
}

class _MasteryTab extends StatelessWidget {
  const _MasteryTab({required this.db, required this.studentId});
  final AppDatabase db;
  final String studentId;

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<MasteryState>>(
      future: () => (db.select(db.masteryStates)
            ..where((t) => t.studentId.equals(studentId))
            ..orderBy([(t) => OrderingTerm(expression: t.probability)]))
          .get(),
      isEmpty: (d) => d.isEmpty,
      emptyIcon: Icons.psychology_alt_outlined,
      emptyMessage: 'لا توجد بيانات إتقان بعد.\n'
          'يبدأ حساب الإتقان تلقائيًا بعد إنجاز مهامك.',
      builder: (context, states) => ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: states.length,
        itemBuilder: (context, i) {
          final s = states[i];
          return Card(
            child: FutureBuilder<String>(
              future: ContentRepository(db).nameForNode(s.knowledgeNodeId),
              builder: (context, snap) => ListTile(
                title: Text(snap.data ?? '...'),
                subtitle: LinearProgressIndicator(
                  value: s.probability.clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  color: _colorFor(s.probability),
                ),
                trailing: Text('${(s.probability * 100).round()}%'),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _colorFor(double p) {
    if (p < 0.4) return AppColors.danger;
    if (p < 0.7) return AppColors.warning;
    return AppColors.success;
  }
}

class _MemoryTab extends StatelessWidget {
  const _MemoryTab({required this.db, required this.studentId});
  final AppDatabase db;
  final String studentId;

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<MemoryState>>(
      future: () => (db.select(db.memoryStates)
            ..where((t) =>
                t.studentId.equals(studentId) &
                t.nextReviewDate.isSmallerOrEqualValue(DateTime.now().toUtc()))
            ..orderBy([(t) => OrderingTerm(expression: t.nextReviewDate)]))
          .get(),
      isEmpty: (d) => d.isEmpty,
      emptyIcon: Icons.event_available,
      emptyMessage: 'لا مراجعات مستحقة الآن. أحسنت! ✅',
      builder: (context, states) => ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: states.length,
        itemBuilder: (context, i) {
          final s = states[i];
          return Card(
            child: FutureBuilder<String>(
              future: ContentRepository(db).nameForNode(s.knowledgeNodeId),
              builder: (context, snap) => ListTile(
                leading: const Icon(Icons.refresh, color: AppColors.primary),
                title: Text(snap.data ?? '...'),
                subtitle: Text('مستحقة منذ ${DateTime.now().toUtc().difference(s.nextReviewDate).inDays} يومًا'),
              ),
            ),
          );
        },
      ),
    );
  }
}
