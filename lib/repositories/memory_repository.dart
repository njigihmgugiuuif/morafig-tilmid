import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../engines/memory_engine.dart';

/// MemoryState is DERIVED, exactly like MasteryState (see
/// mastery_repository.dart's doc comment — the same reasoning applies
/// here verbatim). Its source of truth is the sequence of
/// MemoryReviewCompleted Events for a (student, knowledgeNode) pair, run
/// through the Memory Engine (FSRS) — NOT this table directly. There is
/// no `writeStability(...)` method on purpose: the only way to change a
/// MemoryState row is `recomputeFrom`, called by the (future) engine
/// orchestration layer immediately after it runs a MemoryEngine
/// computation, never by UI/import/sync code directly.
///
/// STATUS: UNVERIFIED. Written without a Flutter/Dart SDK available to
/// compile or run it — see FOUNDATION_PRE_VERIFICATION_AUDIT.md and this
/// project's standing rule that nothing here is VERIFIED until a real
/// Windows/Flutter/Dart pass confirms it compiles and its tests pass.
class MemoryRepository {
  MemoryRepository(this._db, {MemoryEngine? engine})
      : _engine = engine ?? const MemoryEngine();

  final AppDatabase _db;
  final MemoryEngine _engine;

  Future<MemoryState?> read(String studentId, String knowledgeNodeId) =>
      (_db.select(_db.memoryStates)
            ..where((t) =>
                t.studentId.equals(studentId) &
                t.knowledgeNodeId.equals(knowledgeNodeId)))
          .getSingleOrNull();

  /// Runs the Memory Engine against a MemoryReviewCompleted Event and
  /// persists the resulting (Difficulty, Stability) + derived
  /// Retrievability(now)=1-at-review-time + next review date.
  ///
  /// Expected `event.payloadJson` shape (produced by whatever calls the
  /// engine — the review-capture UI/flow, not built in this phase):
  /// `{"studentId": "...", "knowledgeNodeId": "...", "grade": "forgot|hard|good|easy",
  ///   "reviewedAt": "<ISO 8601 UTC>"}`
  /// `desiredRetention` defaults to the FSRS-conventional 0.9 (90%); a
  /// per-student override would come from ThresholdRegistryEntries in a
  /// later phase, not hard-coded here beyond this default.
  Future<void> recomputeFrom(
    Event event, {
    double desiredRetention = 0.9,
  }) async {
    final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
    final studentId = payload['studentId'] as String;
    final knowledgeNodeId = payload['knowledgeNodeId'] as String;
    final grade = _gradeFromString(payload['grade'] as String);
    final reviewedAt = DateTime.parse(payload['reviewedAt'] as String).toUtc();

    final existing = await read(studentId, knowledgeNodeId);

    final MemoryDsr newDsr;
    final double retrievabilityAtReview;
    if (existing == null || existing.difficulty == null) {
      // First-ever review of this knowledge node (or a pre-v2 row with
      // no difficulty recorded yet — treated the same way: no prior DSR
      // state to update from).
      newDsr = _engine.initialState(grade);
      retrievabilityAtReview = 1.0; // R(0, S) = 1 by definition.
    } else {
      final elapsedDays = reviewedAt
              .difference(existing.updatedAt)
              .inMilliseconds /
          Duration.millisecondsPerDay;
      if (elapsedDays < 0) {
        throw ArgumentError(
            'reviewedAt ($reviewedAt) is before the existing MemoryState\'s '
            'updatedAt (${existing.updatedAt}) — events must be processed '
            'in chronological order for a given (student, knowledgeNode).');
      }
      final previous = MemoryDsr(
        difficulty: existing.difficulty!,
        stability: existing.stability,
      );
      retrievabilityAtReview =
          _engine.retrievability(elapsedDays, previous.stability);
      newDsr = _engine.reviewFrom(
        previous: previous,
        elapsedDaysSincePreviousReview: elapsedDays,
        grade: grade,
      );
    }

    final intervalDays = _engine.intervalForDesiredRetention(
      desiredRetention: desiredRetention,
      stability: newDsr.stability,
    );
    final nextReviewDate =
        reviewedAt.add(Duration(days: intervalDays.round()));

    if (existing == null) {
      await _db.into(_db.memoryStates).insert(
            MemoryStatesCompanion.insert(
              studentId: studentId,
              knowledgeNodeId: knowledgeNodeId,
              stability: newDsr.stability,
              retrievability: retrievabilityAtReview,
              nextReviewDate: nextReviewDate,
              difficulty: Value(newDsr.difficulty),
              lastUpdatedFromEventId: Value(event.id),
            ),
          );
    } else {
      await (_db.update(_db.memoryStates)
            ..where((t) => t.id.equals(existing.id)))
          .write(MemoryStatesCompanion(
        stability: Value(newDsr.stability),
        retrievability: Value(retrievabilityAtReview),
        nextReviewDate: Value(nextReviewDate),
        difficulty: Value(newDsr.difficulty),
        lastUpdatedFromEventId: Value(event.id),
        updatedAt: Value(reviewedAt),
      ));
    }
  }

  MemoryGrade _gradeFromString(String s) {
    switch (s) {
      case 'forgot':
        return MemoryGrade.forgot;
      case 'hard':
        return MemoryGrade.hard;
      case 'good':
        return MemoryGrade.good;
      case 'easy':
        return MemoryGrade.easy;
      default:
        throw ArgumentError.value(
            s, 'grade', 'must be one of forgot|hard|good|easy');
    }
  }
}
