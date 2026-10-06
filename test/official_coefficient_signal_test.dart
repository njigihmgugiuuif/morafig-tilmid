import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/curriculum_domain.dart';
import 'package:student_app/domain/enums.dart';
import 'package:student_app/repositories/curriculum_repository.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// A-1 (DEVIATION-21): the official-coefficient signal for one subject,
/// normalised against the highest usable coefficient of the same stream and
/// curriculum version. All data is SYNTHETIC test data; nothing here is an
/// official Algerian value.
void main() {
  late AppDatabase db;
  late MinimalCurriculumSeed seed;
  late CurriculumRepository curriculum;
  late CurriculumDomainService domain;
  late String levelId;
  late String streamId;
  late String versionId;
  var docCounter = 0;

  setUp(() async {
    db = createInMemoryTestDatabase();
    seed = await seedMinimalCurriculum(db);
    curriculum = CurriculumRepository(db);
    domain = CurriculumDomainService(curriculum);

    final level = await db.into(db.educationLevels).insertReturning(
        EducationLevelsCompanion.insert(name: 'TEST-LEVEL-A1', order: 9));
    levelId = level.id;
    streamId = (await makeStream('TEST-STREAM-1')).id;
    versionId = (await makeVersion(PolicyStatus.active)).id;
  });
  tearDown(() => db.close());

  Future<StudyStream> makeStream(String name) =>
      db.into(db.streams).insertReturning(
          StreamsCompanion.insert(name: name, educationLevelId: levelId));

  Future<CurriculumVersion> makeVersion(PolicyStatus status,
      {DateTime? effectiveFrom, DateTime? effectiveTo}) async {
    final doc = await db.into(db.policyDocuments).insertReturning(
          PolicyDocumentsCompanion.insert(
            documentNumber: 'TEST-DOC-A1-${docCounter++}',
            documentType: 'test-fixture',
            issuingAuthority: 'test-fixture',
            verificationStatus: 'primaryVerified',
          ),
        );
    return curriculum.createVersion(
      academicYearId: seed.academicYearId,
      status: status,
      sourcePolicyDocumentId: doc.id,
      effectiveFrom: effectiveFrom,
      effectiveTo: effectiveTo,
    );
  }

  Future<Subject> makeSubject(String name) =>
      db.into(db.subjects).insertReturning(
          SubjectsCompanion.insert(name: name, educationLevelId: levelId));

  Future<SubjectLoad> makeLoad(
    Subject subject, {
    String? stream,
    String? version,
    double? coefficient,
    PolicyStatus status = PolicyStatus.active,
  }) =>
      curriculum.ingestSubjectLoad(
        curriculumVersionId: version ?? versionId,
        subjectId: subject.id,
        streamId: stream ?? streamId,
        coefficient: coefficient,
        status: status,
      );

  Future<double?> signalFor(Subject s,
          {String? stream, String? version, DateTime? asOf}) =>
      domain.officialCoefficientSignalForSubject(
        subjectId: s.id,
        curriculumVersionId: version ?? versionId,
        streamId: stream ?? streamId,
        asOf: asOf,
      );

  group('officialCoefficientSignalForSubject', () {
    test('highest = 1.0, others proportional to the highest of the stream',
        () async {
      final a = await makeSubject('TEST-A');
      final b = await makeSubject('TEST-B');
      final c = await makeSubject('TEST-C');
      await makeLoad(a, coefficient: 6.0);
      await makeLoad(b, coefficient: 3.0);
      await makeLoad(c, coefficient: 2.0);

      expect(await signalFor(a), closeTo(1.0, 1e-12));
      expect(await signalFor(b), closeTo(0.5, 1e-12));
      expect(await signalFor(c), closeTo(1.0 / 3.0, 1e-12));
    });

    test('a single usable load in the stream -> null', () async {
      final a = await makeSubject('TEST-A');
      await makeLoad(a, coefficient: 6.0);
      expect(await signalFor(a), isNull);
    });

    test('a load without a stream never enters the comparison', () async {
      final a = await makeSubject('TEST-A');
      final b = await makeSubject('TEST-B');
      final x = await makeSubject('TEST-X');
      await makeLoad(a, coefficient: 4.0);
      await makeLoad(b, coefficient: 2.0);
      // Highest coefficient overall, but it has NO stream.
      await curriculum.ingestSubjectLoad(
        curriculumVersionId: versionId,
        subjectId: x.id,
        coefficient: 10.0,
        status: PolicyStatus.active,
      );

      expect(await signalFor(a), closeTo(1.0, 1e-12)); // 4 / 4, not 4 / 10
      expect(await signalFor(b), closeTo(0.5, 1e-12));
      expect(await signalFor(x), isNull); // no stream load matches it
    });

    test('loads of another stream do not count', () async {
      final other = (await makeStream('TEST-STREAM-2')).id;
      final a = await makeSubject('TEST-A');
      final b = await makeSubject('TEST-B');
      final c = await makeSubject('TEST-C');
      await makeLoad(a, coefficient: 2.0);
      await makeLoad(b, coefficient: 1.0);
      await makeLoad(c, coefficient: 10.0, stream: other);

      expect(await signalFor(a), closeTo(1.0, 1e-12));
      expect(await signalFor(c, stream: other), isNull); // alone in its stream
    });

    test('two loads for the same subject and stream -> null (ambiguous)',
        () async {
      final a = await makeSubject('TEST-A');
      final b = await makeSubject('TEST-B');
      await makeLoad(a, coefficient: 6.0);
      await makeLoad(a, coefficient: 5.0);
      await makeLoad(b, coefficient: 3.0);

      expect(await signalFor(a), isNull);
    });

    test('own coefficient null or zero -> null', () async {
      final a = await makeSubject('TEST-A');
      final b = await makeSubject('TEST-B');
      final c = await makeSubject('TEST-C');
      await makeLoad(a, coefficient: null);
      await makeLoad(b, coefficient: 0.0);
      await makeLoad(c, coefficient: 4.0);

      expect(await signalFor(a), isNull);
      expect(await signalFor(b), isNull);
      expect(await signalFor(c), isNull); // only one load with a usable value
    });

    test('a FROZEN load is excluded from the ceiling and has no signal',
        () async {
      final a = await makeSubject('TEST-A');
      final b = await makeSubject('TEST-B');
      final c = await makeSubject('TEST-C');
      await makeLoad(a, coefficient: 6.0, status: PolicyStatus.frozen);
      await makeLoad(b, coefficient: 3.0);
      await makeLoad(c, coefficient: 2.0);

      expect(await signalFor(a), isNull);
      expect(await signalFor(b), closeTo(1.0, 1e-12)); // ceiling is 3, not 6
      expect(await signalFor(c), closeTo(2.0 / 3.0, 1e-12));
    });

    test('a REPEALED load is treated as null and does not throw or stop '
        'the others', () async {
      final a = await makeSubject('TEST-A');
      final b = await makeSubject('TEST-B');
      final c = await makeSubject('TEST-C');
      final repealed = await makeLoad(a,
          coefficient: 6.0, status: PolicyStatus.repealed);
      await makeLoad(b, coefficient: 3.0);
      await makeLoad(c, coefficient: 2.0);

      expect(await signalFor(a), isNull);
      expect(await signalFor(b), closeTo(1.0, 1e-12));
      expect(await signalFor(c), closeTo(2.0 / 3.0, 1e-12));
      // Guard #2 itself is unchanged: the direct read still throws.
      expect(() => curriculum.getUsableCoefficient(repealed.id),
          throwsA(isA<PolicyDataGuardViolation>()));
    });

    test('loads inside a non-ACTIVE version give no signal', () async {
      final frozen = await makeVersion(PolicyStatus.frozen);
      final a = await makeSubject('TEST-A');
      final b = await makeSubject('TEST-B');
      await makeLoad(a, coefficient: 6.0, version: frozen.id);
      await makeLoad(b, coefficient: 3.0, version: frozen.id);

      expect(await signalFor(a, version: frozen.id), isNull);
      expect(await signalFor(b, version: frozen.id), isNull);
    });

    test('outside the version\'s effective dates -> null when asOf is given',
        () async {
      final future = await makeVersion(PolicyStatus.active,
          effectiveFrom: DateTime.utc(2040, 1, 1));
      final a = await makeSubject('TEST-A');
      final b = await makeSubject('TEST-B');
      await makeLoad(a, coefficient: 6.0, version: future.id);
      await makeLoad(b, coefficient: 3.0, version: future.id);

      expect(
          await signalFor(a,
              version: future.id, asOf: DateTime.utc(2026, 10, 1)),
          isNull);
      // Without asOf the dates are not checked (unchanged Guard #2 behaviour).
      expect(await signalFor(a, version: future.id), closeTo(1.0, 1e-12));
    });
  });
}
