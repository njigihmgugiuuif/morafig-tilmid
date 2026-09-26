import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../engines/time_estimation_engine.dart';

/// TimeEstimateState is DERIVED — like MasteryState, the only legitimate
/// way to change a row is recomputeFrom(), which takes TimeEstimationEngine
/// output directly. observedSamplesJson is persisted so the next
/// recomputation doesn't need to re-derive the sample list from raw
/// StudySession history every time (the schema doc's own field for this
/// purpose) — this repository treats it as an opaque cache of
/// `List<{minutes:int, daysAgo:double}>`, written and read back only by
/// this class.
class TimeEstimationRepository {
  TimeEstimationRepository(this._db);
  final AppDatabase _db;

  Future<TimeEstimate?> read(
    String studentId,
    String subjectId,
    String sessionType,
  ) =>
      (_db.select(_db.timeEstimates)
            ..where((t) =>
                t.studentId.equals(studentId) &
                t.subjectId.equals(subjectId) &
                t.sessionType.equals(sessionType)))
          .getSingleOrNull();

  List<ObservedDuration> decodeSamples(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => ObservedDuration(
              minutes: (e as Map<String, dynamic>)['minutes'] as int,
              daysAgo: (e['daysAgo'] as num).toDouble(),
            ))
        .toList();
  }

  String encodeSamples(List<ObservedDuration> samples) => jsonEncode(
        samples.map((s) => {'minutes': s.minutes, 'daysAgo': s.daysAgo}).toList(),
      );

  /// Called by the (future) integration layer after appending a newly
  /// observed duration to the sample list and re-running
  /// TimeEstimationEngine.compute(). `samplesUsed` is exactly the list
  /// the engine was called with, persisted verbatim so the next call can
  /// decode + extend it.
  Future<void> recomputeFrom({
    required String studentId,
    required String subjectId,
    required String sessionType,
    required TimeEstimateResult result,
    required List<ObservedDuration> samplesUsed,
  }) async {
    final existing = await read(studentId, subjectId, sessionType);
    final companion = TimeEstimatesCompanion(
      studentId: Value(studentId),
      subjectId: Value(subjectId),
      sessionType: Value(sessionType),
      estimatedDurationMinutes: Value(result.estimatedDurationMinutes),
      confidenceLevel: Value(result.confidenceLevel.name),
      confidenceValue: Value(result.confidenceValue),
      basis: Value(_basisToDb(result.basis)),
      observedSamplesJson: Value(encodeSamples(samplesUsed)),
      updatedAt: Value(DateTime.now().toUtc()),
    );

    if (existing == null) {
      await _db.into(_db.timeEstimates).insert(
            TimeEstimatesCompanion.insert(
              studentId: studentId,
              subjectId: subjectId,
              sessionType: sessionType,
              estimatedDurationMinutes: result.estimatedDurationMinutes,
              confidenceLevel: result.confidenceLevel.name,
              confidenceValue: result.confidenceValue,
              basis: _basisToDb(result.basis),
              observedSamplesJson: Value(encodeSamples(samplesUsed)),
            ),
          );
    } else {
      await (_db.update(_db.timeEstimates)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }
  }

  /// The TimeEstimates.basis column is documented (derived_state_tables.dart)
  /// as the snake_case vocabulary 'curriculum_default|observed_history|
  /// hybrid' — NOT the engine enum's camelCase .name — so this mapping is
  /// deliberate, not a shortcut.
  String _basisToDb(TimeEstimateBasis basis) {
    switch (basis) {
      case TimeEstimateBasis.curriculumDefault:
        return 'curriculum_default';
      case TimeEstimateBasis.observedHistory:
        return 'observed_history';
      case TimeEstimateBasis.hybrid:
        return 'hybrid';
    }
  }
}
