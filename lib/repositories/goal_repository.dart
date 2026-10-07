import 'package:drift/drift.dart';

import '../database/app_database.dart';

class InvalidGoal implements Exception {
  InvalidGoal(this.reason);
  final String reason;
  @override
  String toString() => 'InvalidGoal: $reason';
}

/// Goals the student types in (B, DEVIATION-22). This is a plain repository:
/// it validates and stores, nothing more.
///
/// It does NOT feed the Priority Engine. `longTermGoalAlignment` stays null
/// until the owner approves a definition of "alignment" (open decision,
/// DEVIATION-21); no formula is invented here. The only consumers in B are
/// the exam-linking read (which goals concern an exam's subject).
class GoalRepository {
  GoalRepository(this._db);
  final AppDatabase _db;

  static const String statusActive = 'active';
  static const String statusAchieved = 'achieved';
  static const String statusDropped = 'dropped';
  static const Set<String> validStatuses = {
    statusActive,
    statusAchieved,
    statusDropped,
  };

  Future<Goal> insertFromUser({
    required String studentId,
    required String title,
    String? subjectId,
    DateTime? targetDate,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw InvalidGoal('title must not be empty');
    }
    return _db.into(_db.goals).insertReturning(
          GoalsCompanion.insert(
            studentId: studentId,
            title: trimmed,
            subjectId: Value(subjectId),
            targetDate: Value(targetDate),
          ),
        );
  }

  Future<void> setStatus(String goalId, String status) async {
    if (!validStatuses.contains(status)) {
      throw InvalidGoal('status must be one of $validStatuses, got "$status"');
    }
    final updated = await (_db.update(_db.goals)
          ..where((t) => t.id.equals(goalId)))
        .write(GoalsCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
    if (updated == 0) {
      throw InvalidGoal('unknown goal $goalId');
    }
  }

  Future<List<Goal>> readForStudent(String studentId) =>
      (_db.select(_db.goals)..where((t) => t.studentId.equals(studentId)))
          .get();

  Future<List<Goal>> readActiveForStudent(String studentId) =>
      (_db.select(_db.goals)
            ..where((t) =>
                t.studentId.equals(studentId) & t.status.equals(statusActive)))
          .get();

  /// Active goals attached to one subject.
  Future<List<Goal>> readActiveForSubject(
    String studentId,
    String subjectId,
  ) =>
      (_db.select(_db.goals)
            ..where((t) =>
                t.studentId.equals(studentId) &
                t.status.equals(statusActive) &
                t.subjectId.equals(subjectId)))
          .get();
}
