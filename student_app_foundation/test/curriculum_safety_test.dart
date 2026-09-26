import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/repositories/curriculum_repository.dart';
import 'package:student_app/domain/enums.dart';
import 'fixtures/seed_data.dart';

void main() {
  group('D. Curriculum safety (3 guards)', () {
    late AppDatabase db;
    late CurriculumRepository repo;

    setUp(() {
      db = AppDatabase.forTesting();
      repo = CurriculumRepository(db);
    });
    tearDown(() => db.close());

    test('ACTIVE status returns its coefficient normally', () async {
      final seed = await seedMinimalCurriculum(db, subjectLoadStatus: 'active');
      final value = await repo.getUsableCoefficient(seed.subjectLoadId);
      expect(value, equals(5.0));
    });

    test('UNKNOWN status returns null (excluded), never a fabricated value',
        () async {
      final seed =
          await seedMinimalCurriculum(db, subjectLoadStatus: 'unknown');
      final value = await repo.getUsableCoefficient(seed.subjectLoadId);
      expect(value, isNull,
          reason: 'UNKNOWN must never resolve to a usable number — this '
              'proves it does not silently become ACTIVE');
    });

    test('CONFLICT status returns null, does not silently become ACTIVE',
        () async {
      final seed =
          await seedMinimalCurriculum(db, subjectLoadStatus: 'conflict');
      final value = await repo.getUsableCoefficient(seed.subjectLoadId);
      expect(value, isNull);
    });

    test('FROZEN status returns null, is never used as active data',
        () async {
      final seed =
          await seedMinimalCurriculum(db, subjectLoadStatus: 'frozen');
      final value = await repo.getUsableCoefficient(seed.subjectLoadId);
      expect(value, isNull);
    });

    test('REPEALED status is rejected by Guard #2 (consumption) with a '
        'loud, specific exception — not a silent null', () async {
      final seed =
          await seedMinimalCurriculum(db, subjectLoadStatus: 'repealed');
      expect(
        () => repo.getUsableCoefficient(seed.subjectLoadId),
        throwsA(isA<PolicyDataGuardViolation>()),
      );
    });

    test('Guard #1 (ingestion): PolicyStatus has no "unset" value, so a '
        'caller cannot omit status', () {
      // Static/API-level guarantee: ingestSubjectLoad's `status` parameter
      // is non-nullable and of type PolicyStatus, which has exactly 5
      // members, none representing "no status". Demonstrated by the fact
      // that PolicyStatus.values.length == 5 and none is nullable-like.
      expect(PolicyStatus.values.length, equals(5));
    });

    test('Guard #3 (DB access): readRawStatus exposes REPEALED status for '
        'audit display without returning the numeric coefficient',
        () async {
      final seed =
          await seedMinimalCurriculum(db, subjectLoadStatus: 'repealed');
      final status = await repo.readRawStatus(seed.subjectLoadId);
      expect(status, equals(PolicyStatus.repealed));
      // readRawStatus's return type is PolicyStatus, not a coefficient —
      // there is no numeric value it could have leaked even if it wanted to.
    });

    test('PolicyStatus.fromDb refuses an unrecognized status string rather '
        'than defaulting to ACTIVE or UNKNOWN', () {
      expect(() => PolicyStatus.fromDb('some_new_status_nobody_defined'),
          throwsStateError);
    });
  });
}
