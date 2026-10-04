import 'enums.dart';
import '../repositories/curriculum_repository.dart';
import '../repositories/mastery_repository.dart';
import '../repositories/reality_and_prerequisite_repositories.dart';

/// Knowledge Graph domain layer — Track C, Cycle 2.
///
/// Produces exactly the `prerequisiteSatisfied` boolean
/// scheduling_engine.dart's SchedulableItem needs, from real Prerequisites
/// edges and real MasteryState rows — via PrerequisiteRepository and
/// MasteryRepository only, never a raw table query, keeping this file
/// consistent with the rest of the codebase's "database access only
/// through repositories" convention (even though the automated boundary
/// check only strictly enforces this for the append-only and
/// curriculum/policy tables specifically).
///
/// SCOPE NOTE: this checks DIRECT (one-edge) hard prerequisites only. A
/// node C that is only transitively required (A requires B, B requires C)
/// is NOT walked by this cycle's implementation — PrerequisiteRepository
/// already has cycle-safe traversal machinery (`_reaches`, private) that a
/// future transitive-closure version of this method could reuse; flagged
/// as follow-up, not silently assumed to already be handled.
/// An OFFICIAL prerequisite edge that was deliberately NOT consumed because
/// the curriculum status of the node it belongs to is not ACTIVE (UNKNOWN,
/// CONFLICT, FROZEN, REPEALED, or not linked to any curriculum version).
/// Reported, never silently dropped (DEVIATION-18).
class IgnoredPrerequisiteEdge {
  const IgnoredPrerequisiteEdge({
    required this.requiresNodeId,
    required this.status,
    required this.reason,
  });

  final String requiresNodeId;
  final PolicyStatus status;
  final String reason;
}

class PrerequisiteSatisfactionResult {
  const PrerequisiteSatisfactionResult({
    required this.satisfied,
    required this.blockingNodeIds,
    this.ignoredEdges = const [],
  });

  /// Official edges excluded by the curriculum guard (see
  /// [IgnoredPrerequisiteEdge]). Empty when nothing was excluded.
  final List<IgnoredPrerequisiteEdge> ignoredEdges;

  final bool satisfied;

  /// Every direct hard-prerequisite node whose mastery is below threshold
  /// (or entirely unobserved) — empty when satisfied is true. Never just
  /// a bool with the reason thrown away, per this codebase's running
  /// "always report why" convention.
  final List<String> blockingNodeIds;
}

class KnowledgeGraphDomainService {
  /// [curriculum] is REQUIRED (no default, no null): the curriculum guard
  /// cannot be skipped by forgetting to pass it. An edge whose relationType
  /// is `official` is only consumed when the node it belongs to has an
  /// ACTIVE effective curriculum status; `derived` / `proposed` edges are
  /// the student's / engineering's own and are consumed as before.
  const KnowledgeGraphDomainService(
    this._prerequisites,
    this._mastery, {
    required CurriculumRepository curriculum,
  }) : _curriculum = curriculum;

  final PrerequisiteRepository _prerequisites;
  final MasteryRepository _mastery;
  final CurriculumRepository _curriculum;

  Future<PrerequisiteSatisfactionResult> checkDirectHardPrerequisites({
    required String studentId,
    required String knowledgeNodeId,
    required double masteryThreshold,
  }) async {
    if (masteryThreshold < 0 || masteryThreshold > 1) {
      throw ArgumentError.value(
          masteryThreshold, 'masteryThreshold', 'must be in [0, 1].');
    }

    final edges =
        await _prerequisites.readDirectHardPrerequisites(knowledgeNodeId);

    final blocking = <String>[];
    final ignored = <IgnoredPrerequisiteEdge>[];
    EffectiveCurriculumStatus? ownerStatus;
    for (final edge in edges) {
      if (edge.relationType == PrerequisiteRelationType.official.name) {
        ownerStatus ??= await _curriculum.effectiveStatusForNode(knowledgeNodeId);
        if (!ownerStatus.usableForCalculation) {
          ignored.add(IgnoredPrerequisiteEdge(
            requiresNodeId: edge.requiresNodeId,
            status: ownerStatus.status,
            reason: ownerStatus.reason,
          ));
          continue;
        }
      }
      final state = await _mastery.read(studentId, edge.requiresNodeId);
      final probability = state?.probability;
      // Unobserved (state == null) is treated as NOT satisfied — an
      // unmeasured prerequisite is not the same as a confirmed one, and
      // defaulting it to "satisfied" would silently let the Scheduling
      // Engine place a task ahead of a dependency nobody has verified yet.
      if (probability == null || probability < masteryThreshold) {
        blocking.add(edge.requiresNodeId);
      }
    }

    return PrerequisiteSatisfactionResult(
      satisfied: blocking.isEmpty,
      blockingNodeIds: blocking,
      ignoredEdges: ignored,
    );
  }
}
