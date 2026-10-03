import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../engines/weekly_timeline_engine.dart';

class InvalidWeeklyTemplateEntry implements Exception {
  InvalidWeeklyTemplateEntry(this.reason);
  final String reason;
  @override
  String toString() => 'InvalidWeeklyTemplateEntry: $reason';
}

/// Student-entered recurring weekly template (school timetable etc.).
/// There is no insert path for engines: only [insertFromUser], and it
/// takes no `source` parameter (the column defaults to USER_INPUT).
class WeeklyTemplateRepository {
  WeeklyTemplateRepository(this._db);
  final AppDatabase _db;

  /// Validates then inserts. Rejects bad input instead of storing it, so the
  /// planner can trust what it reads.
  Future<WeeklyTemplateEntry> insertFromUser({
    required String studentId,
    required int dayOfWeek,
    required int startMinutes,
    required int endMinutes,
    required TimelineBlockKind kind,
    String? label,
    String? subjectId,
    bool isHard = true,
  }) async {
    if (dayOfWeek < 1 || dayOfWeek > 7) {
      throw InvalidWeeklyTemplateEntry(
          'dayOfWeek must be 1..7, got $dayOfWeek');
    }
    if (startMinutes < 0 || startMinutes >= 1440) {
      throw InvalidWeeklyTemplateEntry(
          'startMinutes must be 0..1439, got $startMinutes');
    }
    if (endMinutes <= startMinutes || endMinutes > 2880) {
      throw InvalidWeeklyTemplateEntry(
          'endMinutes must be after startMinutes and at most 2880, '
          'got $endMinutes');
    }
    if (!kTemplateKinds.contains(kind)) {
      throw InvalidWeeklyTemplateEntry(
          'kind ${kind.name} is not allowed in a weekly template');
    }
    return _db.into(_db.weeklyTemplateEntries).insertReturning(
          WeeklyTemplateEntriesCompanion.insert(
            studentId: studentId,
            dayOfWeek: dayOfWeek,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            kind: kind.name,
            label: Value(label),
            subjectId: Value(subjectId),
            isHard: Value(isHard),
          ),
        );
  }

  Future<List<WeeklyTemplateEntry>> readForStudent(String studentId) =>
      (_db.select(_db.weeklyTemplateEntries)
            ..where((t) => t.studentId.equals(studentId)))
          .get();

  Future<int> deleteById(String id) => (_db.delete(_db.weeklyTemplateEntries)
        ..where((t) => t.id.equals(id)))
      .go();

  /// The stored template as engine input. Rows whose stored kind is not a
  /// valid template kind are skipped (never guessed at).
  Future<List<WeeklyTemplateSlot>> readSlotsForStudent(
      String studentId) async {
    final rows = await readForStudent(studentId);
    final slots = <WeeklyTemplateSlot>[];
    for (final r in rows) {
      TimelineBlockKind? kind;
      for (final k in kTemplateKinds) {
        if (k.name == r.kind) kind = k;
      }
      if (kind == null) continue;
      slots.add(WeeklyTemplateSlot(
        dayOfWeek: r.dayOfWeek,
        startMinutes: r.startMinutes,
        endMinutes: r.endMinutes,
        kind: kind,
        label: r.label,
        refId: r.id,
        isHard: r.isHard,
      ));
    }
    return slots;
  }
}
