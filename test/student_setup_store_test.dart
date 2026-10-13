import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/engines/weekly_timeline_engine.dart';
import 'package:student_app/repositories/reset_repository.dart';
import 'package:student_app/repositories/student_repository.dart';
import 'package:student_app/repositories/weekly_template_repository.dart';
import 'package:student_app/services/lesson_auto_sync.dart';
import 'package:student_app/services/student_setup_store.dart';
import 'package:student_app/services/teacher_session.dart';

/// Registration journey (Batch 2): year/stream storage, the saved draft, and
/// the commitments that reach the planner's weekly template. Synthetic data.
void main() {
  group('year and stream', () {
    test('save then read after a "restart" (new store, same storage)', () async {
      final kv = MemoryKeyValueStore();
      await StudentSetupStore(kv)
          .save(const StudentSetup(year: 2, track: 'علوم تجريبية'));
      final again = await StudentSetupStore(kv).read();
      expect(again.year, 2);
      expect(again.track, 'علوم تجريبية');
    });

    test('saving the year also sets the lesson path used by the library',
        () async {
      final kv = MemoryKeyValueStore();
      await StudentSetupStore(kv).save(const StudentSetup(year: 3));
      expect(await kv.getString(kStudentLessonLevelKey), '3');
    });

    test('editing replaces the old value', () async {
      final kv = MemoryKeyValueStore();
      final s = StudentSetupStore(kv);
      await s.save(const StudentSetup(year: 1, track: 'أ'));
      await s.save(const StudentSetup(year: 3, track: 'ب'));
      final r = await s.read();
      expect([r.year, r.track], [3, 'ب']);
      expect(await kv.getString(kStudentLessonLevelKey), '3');
    });

    test('out-of-range year and damaged storage read as "not set"', () async {
      final kv = MemoryKeyValueStore();
      await kv.setString(StudentSetupStore.key, '{"year": 9, "track": " x "}');
      final r = await StudentSetupStore(kv).read();
      expect(r.year, isNull);
      expect(r.track, 'x');
      await kv.setString(StudentSetupStore.key, '{not json');
      expect((await StudentSetupStore(kv).read()).isEmpty, isTrue);
    });

    test('year-only reset clears year, stream and lesson path, nothing else',
        () async {
      final kv = MemoryKeyValueStore();
      await kv.setString('other_key', 'keep');
      await OnboardingDraftStore(kv).write(const OnboardingDraft(name: 'س'));
      final s = StudentSetupStore(kv);
      await s.save(const StudentSetup(year: 2, track: 'ج'));
      await s.clear();
      expect((await s.read()).isEmpty, isTrue);
      expect(await kv.getString(kStudentLessonLevelKey), isNull);
      expect(await kv.getString('other_key'), 'keep');
      expect(await OnboardingDraftStore(kv).read(), isNotNull);
    });
  });

  group('unfinished registration (draft)', () {
    test('round trip keeps every field, including commitments', () async {
      final kv = MemoryKeyValueStore();
      final store = OnboardingDraftStore(kv);
      await store.write(OnboardingDraft(
        step: 3,
        name: 'تلميذ',
        sleepHours: 8,
        year: 2,
        track: 'آداب',
        commitments: const [
          DraftCommitment(
              day: 0, startMinutes: 480, endMinutes: 720, label: 'مدرسة'),
        ],
        goalKind: 'general',
        subject: 'رياضيات',
        goalTitle: 'مراجعة',
        goalDate: DateTime(2026, 12, 1),
      ));
      final d = (await OnboardingDraftStore(kv).read())!;
      expect(d.step, 3);
      expect(d.name, 'تلميذ');
      expect(d.sleepHours, 8);
      expect(d.year, 2);
      expect(d.track, 'آداب');
      expect(d.commitments.single.label, 'مدرسة');
      expect(d.goalKind, 'general');
      expect(d.goalDate, DateTime(2026, 12, 1));
    });

    test('clear removes it; damaged draft is ignored', () async {
      final kv = MemoryKeyValueStore();
      final store = OnboardingDraftStore(kv);
      await store.write(const OnboardingDraft(name: 'x'));
      await store.clear();
      expect(await store.read(), isNull);
      await kv.setString(OnboardingDraftStore.key, '][');
      expect(await store.read(), isNull);
    });

    test('invalid commitments and out-of-range values are dropped', () {
      expect(DraftCommitment.fromJson({'day': 7, 'start': 0, 'end': 60}), isNull);
      expect(DraftCommitment.fromJson({'day': 1, 'start': 600, 'end': 600}),
          isNull);
      expect(DraftCommitment.fromJson({'day': 1, 'start': 0, 'end': 1441}),
          isNull);
      final d = OnboardingDraft.fromJson({
        'step': 99,
        'sleepHours': 1,
        'year': 5,
        'goalKind': 'zzz',
        'commitments': [
          {'day': 2, 'start': 60, 'end': 120},
          {'day': 9, 'start': 60, 'end': 120},
        ],
      });
      expect(d.step, 0);
      expect(d.sleepHours, 7);
      expect(d.year, isNull);
      expect(d.goalKind, 'exam');
      expect(d.commitments.length, 1);
    });
  });

  group('commitments reach the planner and reset scope', () {
    late AppDatabase db;
    setUp(() => db = createInMemoryTestDatabase());
    tearDown(() => db.close());

    test('Sunday (0) is stored as day 7; commitments are read back and '
        'edited by delete + add', () async {
      final s = await StudentRepository(db)
          .createInitialStudent(fullNameOrNickname: 'A', sleepFloorMinMinutes: 420);
      final repo = WeeklyTemplateRepository(db);
      const c = DraftCommitment(
          day: 0, startMinutes: 480, endMinutes: 720, label: 'مدرسة');
      final row = await repo.insertFromUser(
        studentId: s.id,
        dayOfWeek: c.day == 0 ? 7 : c.day,
        startMinutes: c.startMinutes,
        endMinutes: c.endMinutes,
        kind: TimelineBlockKind.commitment,
        label: c.label,
      );
      var all = await repo.readForStudent(s.id);
      expect(all.single.dayOfWeek, 7);
      expect(all.single.label, 'مدرسة');

      await repo.deleteById(row.id);
      await repo.insertFromUser(
        studentId: s.id,
        dayOfWeek: 2,
        startMinutes: 600,
        endMinutes: 660,
        kind: TimelineBlockKind.commitment,
      );
      all = await repo.readForStudent(s.id);
      expect(all.single.dayOfWeek, 2);
    });

    test('full reset removes the commitments; device keys are cleared '
        'separately by the settings screen', () async {
      final s = await StudentRepository(db)
          .createInitialStudent(fullNameOrNickname: 'A', sleepFloorMinMinutes: 420);
      await WeeklyTemplateRepository(db).insertFromUser(
        studentId: s.id,
        dayOfWeek: 1,
        startMinutes: 0,
        endMinutes: 60,
        kind: TimelineBlockKind.commitment,
      );
      await ResetRepository(db).wipeAllData();
      expect(await db.select(db.weeklyTemplateEntries).get(), isEmpty);
      expect(await db.select(db.students).get(), isEmpty);
    });
  });
}
