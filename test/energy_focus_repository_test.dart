import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/repositories/energy_focus_repository.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// E (A04): the thin EnergyFocusLogs repository. All data is SYNTHETIC.
void main() {
  late AppDatabase db;
  late MinimalCurriculumSeed seed;

  setUp(() async {
    db = createInMemoryTestDatabase();
    seed = await seedMinimalCurriculum(db);
  });
  tearDown(() => db.close());

  test('stores a valid entry and reads it back newest first', () async {
    final repo = EnergyFocusRepository(db);
    await repo.insertFromUser(
        studentId: seed.studentId,
        loggedAt: DateTime(2030, 1, 1, 9),
        energyLevel: 3,
        focusLevel: 4);
    await repo.insertFromUser(
        studentId: seed.studentId,
        loggedAt: DateTime(2030, 1, 2, 9),
        energyLevel: 5,
        focusLevel: 2);
    final rows = await repo.readForStudent(seed.studentId);
    expect(rows.length, 2);
    expect(rows.first.energyLevel, 5);
    expect(rows.last.focusLevel, 4);
  });

  test('refuses a level outside 1..5 and stores nothing', () async {
    final repo = EnergyFocusRepository(db);
    expect(
      () => repo.insertFromUser(
          studentId: seed.studentId,
          loggedAt: DateTime(2030, 1, 1),
          energyLevel: 6,
          focusLevel: 3),
      throwsA(isA<InvalidEnergyFocusEntry>()),
    );
    expect(await repo.readForStudent(seed.studentId), isEmpty);
  });
}
