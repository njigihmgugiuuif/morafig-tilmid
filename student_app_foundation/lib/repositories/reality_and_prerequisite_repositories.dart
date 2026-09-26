import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// RealityConstraint's `source` column is always 'USER_INPUT' at the schema
/// level (see planning_tables.dart), but that alone does not stop calling
/// code from writing a different string. This repository is the actual
/// enforcement: its insert method takes no `source` parameter at all — it
/// is hardcoded inside, so no engine can construct a RealityConstraint
/// that merely *claims* to be user input.
class RealityConstraintRepository {
  RealityConstraintRepository(this._db);
  final AppDatabase _db;

  Future<RealityConstraint> insertFromUser({
    required String studentId,
    required String type,
    required DateTime windowStart,
    required DateTime windowEnd,
    required bool isHard,
  }) {
    return _db.into(_db.realityConstraints).insertReturning(
          RealityConstraintsCompanion.insert(
            studentId: studentId,
            type: type,
            windowStart: windowStart,
            windowEnd: windowEnd,
            isHard: isHard,
            // source intentionally omitted from the parameter list above —
            // it uses the table's DB-level default ('USER_INPUT') and
            // cannot be overridden through this method's signature.
          ),
        );
  }

  Future<List<RealityConstraint>> readForStudent(String studentId) =>
      (_db.select(_db.realityConstraints)
            ..where((t) => t.studentId.equals(studentId)))
          .get();
}

class PrerequisiteCycleException implements Exception {
  PrerequisiteCycleException(this.path);
  final List<String> path;
  @override
  String toString() =>
      'PrerequisiteCycleException: inserting this edge would create a '
      'cycle: ${path.join(' -> ')}';
}

class PrerequisiteRepository {
  PrerequisiteRepository(this._db);
  final AppDatabase _db;

  /// DB-INV-4: no circular prerequisites. SQL has no portable way to check
  /// this at insert time, so it is enforced here via a depth-first search
  /// over existing edges BEFORE the new edge is written. If following
  /// `requiresNodeId` edges from the new edge's target ever leads back to
  /// its source, the insert is refused.
  Future<Prerequisite> insert({
    required String knowledgeNodeId,
    required String requiresNodeId,
    required bool isHard,
    required String relationType,
  }) async {
    if (knowledgeNodeId == requiresNodeId) {
      throw PrerequisiteCycleException([knowledgeNodeId, requiresNodeId]);
    }

    final wouldCycle =
        await _reaches(from: requiresNodeId, target: knowledgeNodeId, path: [requiresNodeId]);
    if (wouldCycle != null) {
      throw PrerequisiteCycleException([knowledgeNodeId, ...wouldCycle]);
    }

    return _db.into(_db.prerequisites).insertReturning(
          PrerequisitesCompanion.insert(
            knowledgeNodeId: knowledgeNodeId,
            requiresNodeId: requiresNodeId,
            isHard: isHard,
            relationType: relationType,
          ),
        );
  }

  /// Direct (one-edge-level) hard prerequisites of `knowledgeNodeId` —
  /// added for knowledge_graph_domain.dart (Track C, Cycle 2) so that
  /// domain layer never needs to query the Prerequisites table directly.
  /// Deliberately NOT transitive — walking the full closure is flagged as
  /// follow-up work, not silently assumed here.
  Future<List<Prerequisite>> readDirectHardPrerequisites(
    String knowledgeNodeId,
  ) =>
      (_db.select(_db.prerequisites)
            ..where((t) =>
                t.knowledgeNodeId.equals(knowledgeNodeId) &
                t.isHard.equals(true)))
          .get();

  /// Returns the path (list of node ids) if `target` is reachable from
  /// `from` by following existing `requiresNodeId` edges, else null.
  Future<List<String>?> _reaches({
    required String from,
    required String target,
    required List<String> path,
    Set<String>? visited,
  }) async {
    visited ??= {};
    if (from == target) return path;
    if (visited.contains(from)) return null;
    visited.add(from);

    final edges = await (_db.select(_db.prerequisites)
          ..where((t) => t.knowledgeNodeId.equals(from)))
        .get();

    for (final edge in edges) {
      final result = await _reaches(
        from: edge.requiresNodeId,
        target: target,
        path: [...path, edge.requiresNodeId],
        visited: visited,
      );
      if (result != null) return result;
    }
    return null;
  }
}
