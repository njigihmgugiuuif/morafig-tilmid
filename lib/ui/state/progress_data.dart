import 'dart:convert';

import '../../database/app_database.dart';
import '../../engines/mastery_engine.dart';
import '../../engines/memory_engine.dart';
import '../../repositories/content_repository.dart';
import '../../repositories/event_repository.dart';
import '../../services/intelligence_service.dart' show Understanding;

/// One answer in the story of a topic, with the mastery the Mastery engine
/// reaches after it.
class MasteryStep {
  const MasteryStep({
    required this.at,
    required this.understoodWell,
    required this.probability,
    required this.confidence,
  });
  final DateTime at;
  final bool understoodWell;
  final double probability;
  final double confidence;
}

/// A point of the forgetting curve: `day` counts from the last review.
class RecallPoint {
  const RecallPoint(this.day, this.recall);
  final double day;
  final double recall;
}

class ForgettingCurve {
  const ForgettingCurve({
    required this.points,
    required this.daysSinceReview,
    required this.recallNow,
    required this.daysToNextReview,
  });
  final List<RecallPoint> points;
  final double daysSinceReview;
  final double recallNow;
  final double daysToNextReview;
}

class SubjectProgress {
  const SubjectProgress(this.name, this.done, this.open);
  final String name;
  final int done;
  final int open;
}

class WeekCount {
  const WeekCount(this.weekStart, this.count);
  final DateTime weekStart;
  final int count;
}

/// Read-only computations for the progress charts. Everything is derived from
/// what was recorded (events, stored states) by the SAME engines the app uses
/// to decide; nothing is estimated here and no value is invented.
class ProgressData {
  ProgressData(this._db);
  final AppDatabase _db;

  /// Replays the topic's recorded answers (good / not understood) through the
  /// Mastery engine with the same starting values the Intelligence service
  /// uses. «Partly understood» and «skipped» give no evidence, as in the
  /// service, so they do not appear.
  Future<List<MasteryStep>> masteryTrajectory(String knowledgeNodeId) async {
    final tasks = await (_db.select(_db.tasks)
          ..where((t) => t.knowledgeNodeId.equals(knowledgeNodeId)))
        .get();
    final ids = {for (final t in tasks) t.id};
    if (ids.isEmpty) return const [];
    final events = await EventRepository(_db).readByType('TaskCompleted');
    final params = BktParameters.defaults();
    const engine = MasteryEngine();
    var prior = params.initialProbability;
    var n = 0;
    final out = <MasteryStep>[];
    for (final e in events) {
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(e.payloadJson) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (!ids.contains(payload['taskId'])) continue;
      final u = payload['understanding'];
      if (u != Understanding.good && u != Understanding.notUnderstood) continue;
      final r = engine.compute(
        priorProbability: prior,
        correct: u == Understanding.good,
        params: params,
        priorObservationCount: n,
      );
      prior = r.probability;
      n = r.observationCount;
      out.add(MasteryStep(
        at: e.createdAt,
        understoodWell: u == Understanding.good,
        probability: r.probability,
        confidence: r.confidence,
      ));
    }
    return out;
  }

  /// R(t) from the FSRS memory engine for the stored stability, from the last
  /// review forward. Horizon: at least 30 days, and enough to show the next
  /// review date.
  /// Null when the stored stability is not usable (the engine cannot draw it).
  ForgettingCurve? forgettingCurve(MemoryState m, DateTime now) {
    if (m.stability <= 0) return null;
    const engine = MemoryEngine();
    final since = now.difference(m.updatedAt).inMilliseconds /
        Duration.millisecondsPerDay;
    final elapsed = since < 0 ? 0.0 : since;
    final toNext = m.nextReviewDate.difference(m.updatedAt).inMilliseconds /
        Duration.millisecondsPerDay;
    var horizon = 30.0;
    if (toNext > horizon) horizon = toNext + 2;
    if (elapsed > horizon) horizon = elapsed + 2;
    final pts = <RecallPoint>[];
    final step = horizon / 30;
    for (var i = 0; i <= 30; i++) {
      final d = step * i;
      pts.add(RecallPoint(d, engine.retrievability(d, m.stability)));
    }
    return ForgettingCurve(
      points: pts,
      daysSinceReview: elapsed,
      recallNow: engine.retrievability(elapsed, m.stability),
      daysToNextReview: toNext,
    );
  }

  /// Memory reviews recorded for a topic (grades by date), oldest first.
  Future<List<({DateTime at, String grade})>> reviewHistory(
      String knowledgeNodeId) async {
    final events =
        await EventRepository(_db).readByType('MemoryReviewCompleted');
    final out = <({DateTime at, String grade})>[];
    for (final e in events) {
      try {
        final p = jsonDecode(e.payloadJson) as Map<String, dynamic>;
        if (p['knowledgeNodeId'] == knowledgeNodeId) {
          out.add((at: e.createdAt, grade: '${p['grade']}'));
        }
      } catch (_) {}
    }
    return out;
  }

  /// Finished and open tasks per subject.
  Future<List<SubjectProgress>> subjectProgress() async {
    final tasks = await _db.select(_db.tasks).get();
    final content = ContentRepository(_db);
    final done = <String, int>{};
    final open = <String, int>{};
    for (final t in tasks) {
      var s = await content.subjectNameForNode(t.knowledgeNodeId);
      if (s.isEmpty) s = 'بدون مادة';
      if (t.completionStatus == 'complete') {
        done[s] = (done[s] ?? 0) + 1;
      } else {
        open[s] = (open[s] ?? 0) + 1;
      }
    }
    final names = {...done.keys, ...open.keys}.toList()..sort();
    return [for (final n in names) SubjectProgress(n, done[n] ?? 0, open[n] ?? 0)];
  }

  /// Completed tasks per week for the last [weeks] weeks (Sunday-first),
  /// counted from the recorded TaskCompleted events.
  Future<List<WeekCount>> weeklyCompletions(DateTime now, {int weeks = 8}) async {
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);
    final thisWeek = today.subtract(Duration(days: today.weekday % 7));
    final starts = [
      for (var i = weeks - 1; i >= 0; i--)
        thisWeek.subtract(Duration(days: 7 * i)),
    ];
    final counts = List<int>.filled(weeks, 0);
    final events = await EventRepository(_db).readByType('TaskCompleted');
    for (final e in events) {
      final d = e.createdAt.toLocal();
      for (var i = weeks - 1; i >= 0; i--) {
        if (!d.isBefore(starts[i])) {
          counts[i]++;
          break;
        }
      }
    }
    return [for (var i = 0; i < weeks; i++) WeekCount(starts[i], counts[i])];
  }
}
