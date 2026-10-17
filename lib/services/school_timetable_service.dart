import '../database/app_database.dart';
import '../domain/school_timetable_domain.dart';
import '../engines/weekly_timeline_engine.dart';
import '../repositories/weekly_template_repository.dart';
import 'teacher_session.dart' show KeyValueStore;

/// Where the SHAPE of the school grid (which days, which slots) is kept: on
/// the device, like the student's year and stream. The filled cells are rows
/// of the weekly template in the database (kind `school`), which is what the
/// planner reads. Both are local: no connection is needed to read or change
/// any of it.
class SchoolTimetableStore {
  SchoolTimetableStore(this._kv);
  final KeyValueStore _kv;

  static const key = 'school_timetable_layout_v1';

  Future<SchoolTimetableLayout?> read() async =>
      SchoolTimetableLayout.decode(await _kv.getString(key));

  Future<void> save(SchoolTimetableLayout layout) =>
      _kv.setString(key, layout.encode());

  Future<void> clear() => _kv.remove(key);
}

/// Everything the timetable screen shows.
class SchoolTimetableState {
  const SchoolTimetableState({
    required this.layout,
    required this.entries,
    required this.outsideGrid,
  });

  final SchoolTimetableLayout layout;
  final List<SchoolEntry> entries;

  /// Stored school rows that sit outside the grid (for instance a block
  /// typed in «واقعي» at times that are not a slot). They are kept and are
  /// still used by the planner.
  final int outsideGrid;

  bool get isConfigured => layout.isConfigured;

  int get filledCells {
    var n = 0;
    for (final d in layout.days) {
      for (final s in layout.periods) {
        if (SchoolTimetableLayout.cellAt(entries, d, s) != null) n++;
      }
    }
    return n;
  }

  int get totalCells => layout.days.length * layout.periods.length;
}

/// Reads and edits the school timetable. Every row is typed by the student
/// (WeeklyTemplateRepository.insertFromUser is the only write path), so the
/// planner's rule «no default timetable» holds here too.
class SchoolTimetableService {
  SchoolTimetableService(this._db, this._store);

  final AppDatabase _db;
  final SchoolTimetableStore _store;

  WeeklyTemplateRepository get _repo => WeeklyTemplateRepository(_db);

  Future<List<SchoolEntry>> _readEntries(String studentId) async {
    final rows = await _repo.readForStudent(studentId);
    return [
      for (final r in rows)
        if (r.kind == TimelineBlockKind.school.name)
          SchoolEntry(
            id: r.id,
            dayStored: r.dayOfWeek,
            startMinutes: r.startMinutes,
            endMinutes: r.endMinutes,
            label: r.label ?? '',
          ),
    ];
  }

  Future<SchoolTimetableState> load(String studentId) async {
    final entries = await _readEntries(studentId);
    final stored = await _store.read();
    // No stored layout (never set up, or the device storage was cleared):
    // rebuild it from the cells that exist, never from a default.
    final base = stored ?? SchoolTimetableLayout.empty;
    final layout = entries.isEmpty ? base : base.mergedWith(entries);
    return SchoolTimetableState(
      layout: layout,
      entries: entries,
      outsideGrid: layout.outsideGridCount(entries),
    );
  }

  /// Saves only the shape (no cells change). Used to start from a model.
  Future<void> saveLayout(SchoolTimetableLayout layout) async {
    final problem = SchoolTimetableLayout.validate(layout.days, layout.slots);
    if (problem != null) throw ArgumentError(problem);
    await _store.save(layout);
  }

  /// Writes [label] into the cell of [slot] for each of [dayIndexes]
  /// (Sunday-first). An existing cell at the same place is replaced.
  Future<void> setCells({
    required String studentId,
    required SchoolSlot slot,
    required Iterable<int> dayIndexes,
    required String label,
  }) async {
    final problem = SchoolTimetableLayout.validateLabel(label);
    if (problem != null) throw ArgumentError(problem);
    final text = label.trim();
    await _db.transaction(() async {
      final existing = await _readEntries(studentId);
      for (final d in dayIndexes.toSet()) {
        final old = SchoolTimetableLayout.cellAt(existing, d, slot);
        if (old != null) await _repo.deleteById(old.id);
        await _repo.insertFromUser(
          studentId: studentId,
          dayOfWeek: WeekCalendar.storedDayFromIndex(d),
          startMinutes: slot.startMinutes,
          endMinutes: slot.endMinutes,
          kind: TimelineBlockKind.school,
          label: text,
        );
      }
    });
  }

  Future<void> clearCell({
    required String studentId,
    required int dayIndex,
    required SchoolSlot slot,
  }) async {
    final existing = await _readEntries(studentId);
    for (final e in existing) {
      if (e.dayIndex == dayIndex &&
          e.startMinutes == slot.startMinutes &&
          e.endMinutes == slot.endMinutes) {
        await _repo.deleteById(e.id);
      }
    }
  }

  /// What would change in the stored cells if [next] replaced the current
  /// layout (shown to the student before anything is written).
  Future<LayoutChangePlan> previewLayout({
    required String studentId,
    required SchoolTimetableLayout current,
    required SchoolTimetableLayout next,
  }) async {
    final entries = await _readEntries(studentId);
    return SchoolTimetableLayout.planChange(
        oldLayout: current, next: next, entries: entries);
  }

  /// Applies a new shape and moves or deletes the affected cells in one
  /// transaction.
  Future<void> applyLayout({
    required String studentId,
    required SchoolTimetableLayout current,
    required SchoolTimetableLayout next,
  }) async {
    final problem = SchoolTimetableLayout.validate(next.days, next.slots);
    if (problem != null) throw ArgumentError(problem);
    await _db.transaction(() async {
      final entries = await _readEntries(studentId);
      final plan = SchoolTimetableLayout.planChange(
          oldLayout: current, next: next, entries: entries);
      for (final e in plan.removed) {
        await _repo.deleteById(e.id);
      }
      for (final r in plan.retimed) {
        await _repo.deleteById(r.entry.id);
        await _repo.insertFromUser(
          studentId: studentId,
          dayOfWeek: r.entry.dayStored,
          startMinutes: r.to.startMinutes,
          endMinutes: r.to.endMinutes,
          kind: TimelineBlockKind.school,
          label: r.entry.label.isEmpty ? null : r.entry.label,
        );
      }
    });
    await _store.save(next);
  }

  /// Deletes every school block of the student and forgets the grid shape.
  /// Other kinds of blocks (sleep, meals, commitments...) are not touched.
  /// Returns how many blocks were deleted.
  Future<int> clearAll(String studentId) async {
    var n = 0;
    await _db.transaction(() async {
      for (final e in await _readEntries(studentId)) {
        n += await _repo.deleteById(e.id);
      }
    });
    await _store.clear();
    return n;
  }
}
