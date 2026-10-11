import '../database/app_database.dart';
import '../engines/time_estimation_engine.dart';
import '../repositories/content_repository.dart';
import '../repositories/student_repository.dart';
import '../repositories/study_session_repository.dart';
import '../repositories/time_estimation_repository.dart';

/// Learns how long the student really needs for a subject, from the study
/// sessions whose real start and end were recorded. The calculation is the
/// Time Estimation engine's; this service only gathers the recorded
/// durations of the subject and stores the engine's result (a derived,
/// recomputable value). It does not change any task or plan by itself.
class TimeLearningService {
  TimeLearningService(this._db);
  final AppDatabase _db;

  static const sessionType = 'study';

  Future<void> learnFromSession(String sessionId) async {
    final student = await StudentRepository(_db).readExisting();
    final session = await StudySessionRepository(_db).readById(sessionId);
    if (student == null || session == null) return;
    final task = await (_db.select(_db.tasks)
          ..where((t) => t.id.equals(session.taskId)))
        .getSingleOrNull();
    if (task == null) return;
    final content = ContentRepository(_db);
    final subjectId = await content.subjectIdForNode(task.knowledgeNodeId);
    if (subjectId == null) return;

    final done = await (_db.select(_db.studySessions)
          ..where((t) => t.observedDurationMinutes.isNotNull()))
        .get();
    final now = DateTime.now().toUtc();
    final samples = <ObservedDuration>[];
    final subjectOfTask = <String, String?>{};
    for (final s in done) {
      final minutes = s.observedDurationMinutes;
      final end = s.actualEnd;
      if (minutes == null || minutes <= 0 || end == null) continue;
      if (!subjectOfTask.containsKey(s.taskId)) {
        final t = await (_db.select(_db.tasks)
              ..where((x) => x.id.equals(s.taskId)))
            .getSingleOrNull();
        subjectOfTask[s.taskId] =
            t == null ? null : await content.subjectIdForNode(t.knowledgeNodeId);
      }
      if (subjectOfTask[s.taskId] != subjectId) continue;
      final days = now.difference(end.toUtc()).inMinutes / 1440.0;
      samples.add(ObservedDuration(
          minutes: minutes, daysAgo: days < 0 ? 0.0 : days));
    }
    if (samples.isEmpty) return;
    final result = const TimeEstimationEngine()
        .compute(curriculumDefaultMinutes: null, observedSamples: samples);
    await TimeEstimationRepository(_db).recomputeFrom(
      studentId: student.id,
      subjectId: subjectId,
      sessionType: sessionType,
      result: result,
      samplesUsed: samples,
    );
  }
}
