import 'package:drift/drift.dart' show OrderingTerm, OrderingMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/explanation_and_override_repositories.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/async_section.dart';

/// "الأولويات والجدولة" — shows real PriorityState rows (one per Task),
/// ordered by score. Populated once the Priority Engine's Track D
/// integration runs; correctly empty until then (see priority_repository
/// .dart's doc comment — explanationId is a required FK, so a score can
/// never exist here without its Explanation also existing).
class PrioritiesScreen extends StatelessWidget {
  const PrioritiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppState>().db;
    return Scaffold(
      appBar: AppBar(title: const Text('الأولويات')),
      body: AsyncSection<List<PriorityState>>(
        future: () => (db.select(db.priorityStates)
              ..orderBy([(t) => OrderingTerm(expression: t.score, mode: OrderingMode.desc)]))
            .get(),
        isEmpty: (d) => d.isEmpty,
        emptyIcon: Icons.flag_outlined,
        emptyMessage: 'لا توجد أولويات محسوبة بعد.\n'
            'تُحسب الأولوية تلقائيًا اعتمادًا على الإتقان والمعامل '
            'والامتحانات القريبة والوقت المتبقي.',
        builder: (context, states) => ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: states.length,
          itemBuilder: (context, i) {
            final s = states[i];
            return Card(
              child: FutureBuilder<Task?>(
                future: (db.select(db.tasks)..where((t) => t.id.equals(s.taskId)))
                    .getSingleOrNull(),
                builder: (context, taskSnap) {
                  final task = taskSnap.data;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.secondary.withOpacity(0.2),
                      child: Text('${(s.score * 100).round()}'),
                    ),
                    title: task == null
                        ? const Text('...')
                        : FutureBuilder<String>(
                            future: ContentRepository(db)
                                .nameForNode(task.knowledgeNodeId),
                            builder: (context, snap) =>
                                Text(snap.data ?? '...'),
                          ),
                    subtitle: Text('مستوى الثقة: ${_arLevel(s.confidenceLevel)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.info_outline),
                      tooltip: 'لماذا هذه الأولوية؟',
                      onPressed: () => _showExplanation(context, db, s.explanationId),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  String _arLevel(String level) {
    switch (level) {
      case 'high':
        return 'عالية';
      case 'medium':
        return 'متوسطة';
      default:
        return 'منخفضة';
    }
  }

  Future<void> _showExplanation(
      BuildContext context, AppDatabase db, String explanationId) async {
    final explanation = await ExplanationRepository(db).readById(explanationId);
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('تفسير الأولوية',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (explanation == null)
              const Text('لا يتوفر تفسير مسجّل لهذه المهمة.')
            else ...[
              Text('العامل الأهم: ${explanation.dominantFactor}'),
              const SizedBox(height: 8),
              Text(
                explanation.factorsJson,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
