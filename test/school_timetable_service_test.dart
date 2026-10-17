import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/school_timetable_domain.dart';
import 'package:student_app/engines/weekly_timeline_engine.dart';
import 'package:student_app/repositories/weekly_template_repository.dart';
import 'package:student_app/services/school_timetable_service.dart';
import 'package:student_app/services/teacher_session.dart'
    show MemoryKeyValueStore;

import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// The school timetable on a real (in-memory) database: the grid is typed by
/// the student, becomes fixed school blocks the planner reads, and nothing is
/// ever filled in by the app. All names below are SYNTHETIC.
void main() {
  late AppDatabase db;
  late String studentId;
  late MemoryKeyValueStore kv;
  late SchoolTimetableStore store;
  late SchoolTimetableService service;

  setUp(() async {
    db = createInMemoryTestDatabase();
    studentId = (await seedMinimalCurriculum(db)).studentId;
    kv = MemoryKeyValueStore();
    store = SchoolTimetableStore(kv);
    service = SchoolTimetableService(db, store);
  });
  tearDown(() => db.close());

  final model = SchoolTimetableLayout.photoModel();
  final first = model.slots.first; // 08:00..09:00

  test('starts empty: no layout and no cell is ever invented', () async {
    final s = await service.load(studentId);
    expect(s.isConfigured, isFalse);
    expect(s.entries, isEmpty);
    expect(await WeeklyTemplateRepository(db).readForStudent(studentId),
        isEmpty);
  });

  test('choosing the photo model saves a shape only, with zero cells',
      () async {
    await service.saveLayout(model);
    final s = await service.load(studentId);
    expect(s.isConfigured, isTrue);
    expect(s.layout.days, model.days);
    expect(s.entries, isEmpty);
    expect(s.filledCells, 0);
    expect(s.totalCells, 5 * 8);
    expect(await WeeklyTemplateRepository(db).readForStudent(studentId),
        isEmpty);
  });

  test('a cell becomes a hard school block the planner reads', () async {
    await service.saveLayout(model);
    await service.setCells(
      studentId: studentId,
      slot: first,
      dayIndexes: const [0, 2],
      label: 'مادة-تجريبية',
    );
    final rows = await WeeklyTemplateRepository(db).readForStudent(studentId);
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.kind == 'school'), isTrue);
    expect(rows.every((r) => r.isHard), isTrue);
    expect(rows.every((r) => r.source == 'USER_INPUT'), isTrue);
    expect(rows.map((r) => r.dayOfWeek).toSet(), {7, 2}); // Sunday, Tuesday

    // The planner's own input: slots expanded into a real week.
    final slots =
        await WeeklyTemplateRepository(db).readSlotsForStudent(studentId);
    final sunday = DateTime(2026, 10, 11); // a Sunday
    final blocks =
        WeekTimelineEngine.expandTemplate(weekStart: sunday, slots: slots);
    expect(blocks, hasLength(2));
    final onSunday = blocks.firstWhere((b) => b.start.day == 11);
    expect(onSunday.kind, TimelineBlockKind.school);
    expect(onSunday.start, DateTime(2026, 10, 11, 8));
    expect(onSunday.end, DateTime(2026, 10, 11, 9));
    expect(onSunday.isHard, isTrue);
  });

  test('writing a cell again replaces it (no duplicate rows)', () async {
    await service.saveLayout(model);
    await service.setCells(
        studentId: studentId, slot: first, dayIndexes: const [0], label: 'أ');
    await service.setCells(
        studentId: studentId, slot: first, dayIndexes: const [0], label: 'ب');
    final s = await service.load(studentId);
    expect(s.entries, hasLength(1));
    expect(s.entries.single.label, 'ب');
  });

  test('an empty or too long name is refused and nothing is written',
      () async {
    await service.saveLayout(model);
    await expectLater(
        service.setCells(
            studentId: studentId,
            slot: first,
            dayIndexes: const [0],
            label: '  '),
        throwsArgumentError);
    expect((await service.load(studentId)).entries, isEmpty);
  });

  test('clearCell empties one cell only', () async {
    await service.saveLayout(model);
    await service.setCells(
        studentId: studentId,
        slot: first,
        dayIndexes: const [0, 1],
        label: 'ج');
    await service.clearCell(studentId: studentId, dayIndex: 0, slot: first);
    final s = await service.load(studentId);
    expect(s.entries, hasLength(1));
    expect(s.entries.single.dayIndex, 1);
  });

  test('editing the times of a slot moves its cells', () async {
    await service.saveLayout(model);
    await service.setCells(
        studentId: studentId, slot: first, dayIndexes: const [0], label: 'د');
    final current = (await service.load(studentId)).layout;
    final next = SchoolTimetableLayout.normalized(current.days, [
      first.copyWith(startMinutes: 490, endMinutes: 550),
      ...current.slots.skip(1).where((s) => s.startMinutes >= 560),
    ]);
    await service.applyLayout(
        studentId: studentId, current: current, next: next);
    final s = await service.load(studentId);
    expect(s.entries, hasLength(1));
    expect(s.entries.single.startMinutes, 490);
    expect(s.entries.single.endMinutes, 550);
    expect(s.entries.single.label, 'د');
    expect(s.layout.slotForTimes(490, 550), isNotNull);
  });

  test('removing a day deletes its cells but keeps the other kinds',
      () async {
    await service.saveLayout(model);
    await service.setCells(
        studentId: studentId,
        slot: first,
        dayIndexes: const [0, 4],
        label: 'هـ');
    await WeeklyTemplateRepository(db).insertFromUser(
      studentId: studentId,
      dayOfWeek: 7,
      startMinutes: 1320,
      endMinutes: 1800,
      kind: TimelineBlockKind.sleep,
    );
    final current = (await service.load(studentId)).layout;
    final next = SchoolTimetableLayout.normalized(
        current.days.where((d) => d != 4), current.slots);

    final preview = await service.previewLayout(
        studentId: studentId, current: current, next: next);
    expect(preview.removed, hasLength(1));

    await service.applyLayout(
        studentId: studentId, current: current, next: next);
    final rows = await WeeklyTemplateRepository(db).readForStudent(studentId);
    expect(rows.where((r) => r.kind == 'school'), hasLength(1));
    expect(rows.where((r) => r.kind == 'sleep'), hasLength(1));
  });

  test('an invalid layout is refused and the stored one is untouched',
      () async {
    await service.saveLayout(model);
    await expectLater(
        service.saveLayout(const SchoolTimetableLayout(days: [], slots: [])),
        throwsArgumentError);
    expect((await service.load(studentId)).layout.days, model.days);
  });

  test('layout lost from device storage: rebuilt from the stored cells',
      () async {
    await service.saveLayout(model);
    await service.setCells(
        studentId: studentId, slot: first, dayIndexes: const [1], label: 'و');
    await kv.remove(SchoolTimetableStore.key); // storage cleared
    final s = await service.load(studentId);
    expect(s.isConfigured, isTrue);
    expect(s.layout.days, [1]);
    expect(s.layout.slotForTimes(480, 540), isNotNull);
    expect(s.outsideGrid, 0);
  });

  test('a school block typed in «واقعي» outside the slots is kept and counted',
      () async {
    await service.saveLayout(model);
    await WeeklyTemplateRepository(db).insertFromUser(
      studentId: studentId,
      dayOfWeek: 7,
      startMinutes: 500,
      endMinutes: 560, // overlaps slot 1: cannot become a slot
      kind: TimelineBlockKind.school,
      label: 'قبل-الحصة',
    );
    final s = await service.load(studentId);
    expect(s.entries, hasLength(1));
    expect(s.outsideGrid, 1);
  });

  test('clearAll removes school blocks and the shape, nothing else', () async {
    await service.saveLayout(model);
    await service.setCells(
        studentId: studentId,
        slot: first,
        dayIndexes: const [0, 1, 2],
        label: 'ز');
    await WeeklyTemplateRepository(db).insertFromUser(
      studentId: studentId,
      dayOfWeek: 7,
      startMinutes: 720,
      endMinutes: 780,
      kind: TimelineBlockKind.meal,
    );
    expect(await service.clearAll(studentId), 3);
    final s = await service.load(studentId);
    expect(s.isConfigured, isFalse);
    expect(await kv.getString(SchoolTimetableStore.key), isNull);
    final rows = await WeeklyTemplateRepository(db).readForStudent(studentId);
    expect(rows, hasLength(1));
    expect(rows.single.kind, 'meal');
  });
}
