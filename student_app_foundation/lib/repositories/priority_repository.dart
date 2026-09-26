import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../engines/priority_engine.dart';

/// PriorityState is DERIVED, one row per Task (unique key: taskId) — same
/// recompute-only contract as Mastery/TimeEstimate/Workload.
///
/// PriorityStates.explanationId is NOT nullable (see
/// derived_state_tables.dart): the schema requires every priority score to
/// point at the Explanation record produced alongside it (INV-7 —
/// determinism/auditability, "never compute a score without recording
/// why"). This repository does not create that Explanation itself — per
/// explanation_and_override_repositories.dart, ExplanationRepository is a
/// separate append-only repository, and wiring "PriorityEngine result ->
/// Explanation content -> ExplanationRepository.insertRow -> this
/// repository" end-to-end is Track D (Integration) work. This repository
/// therefore takes an already-created `explanationId` as a required
/// parameter rather than silently creating a placeholder Explanation,
/// which would violate INV-7 far more seriously than an explicit
/// parameter requirement does.
class PriorityRepository {
  PriorityRepository(this._db);
  final AppDatabase _db;

  Future<PriorityState?> read(String taskId) =>
      (_db.select(_db.priorityStates)..where((t) => t.taskId.equals(taskId)))
          .getSingleOrNull();

  Future<void> recomputeFrom({
    required String taskId,
    required PriorityResult result,
    required String explanationId,
  }) async {
    final weightsJson = jsonEncode({
      for (final e in result.weightsUsed.entries) e.key.name: e.value,
    });

    final existing = await read(taskId);
    if (existing == null) {
      await _db.into(_db.priorityStates).insert(
            PriorityStatesCompanion.insert(
              taskId: taskId,
              score: result.score,
              confidenceLevel: _levelFor(result.confidenceValue),
              confidenceValue: result.confidenceValue,
              weightsUsedJson: weightsJson,
              explanationId: explanationId,
            ),
          );
    } else {
      await (_db.update(_db.priorityStates)
            ..where((t) => t.id.equals(existing.id)))
          .write(PriorityStatesCompanion(
        score: Value(result.score),
        confidenceLevel: Value(_levelFor(result.confidenceValue)),
        confidenceValue: Value(result.confidenceValue),
        weightsUsedJson: Value(weightsJson),
        explanationId: Value(explanationId),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
    }
  }

  /// PriorityStates.confidenceLevel has no engine-side enum yet (the
  /// foundation-layer PriorityResult only exposes the continuous
  /// confidenceValue — see priority_engine.dart's doc comment on why the
  /// full confidence formula is deferred to Track D). This bucketing
  /// reuses the same three-tier low/medium/high vocabulary as
  /// TimeEstimates.confidenceLevel for consistency across the schema,
  /// with the same INITIAL HEURISTIC boundaries.
  String _levelFor(double v) {
    if (v < 0.35) return 'low';
    if (v < 0.7) return 'medium';
    return 'high';
  }
}
