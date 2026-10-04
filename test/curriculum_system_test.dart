import 'package:drift/drift.dart' as drift;
import 'package:test/test.dart';

import 'package:student_app/database/app_database.dart';
import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/curriculum_domain.dart';
import 'package:student_app/domain/enums.dart';
import 'package:student_app/domain/knowledge_graph_domain.dart';
import 'package:student_app/repositories/curriculum_repository.dart';
import 'package:student_app/repositories/mastery_repository.dart';
import 'package:student_app/repositories/reality_and_prerequisite_repositories.dart';
import 'fixtures/seed_data.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Curriculum phase (DEVIATION-18). All data is SYNTHETIC test data (see
/// fixtures/seed_data.dart); nothing here is an official Algerian value.
void main() {
  late AppDatabase db;
  late CurriculumRepository repo;
  late MinimalCurriculumSeed seed;

  setUp(() async {
    db = createInMemoryTestDatabase();
    repo = CurriculumRepository(db);
    seed = await seedMinimalCurriculum(db);
  });
  tearDown(() => db.close());

  Future<PolicyDocument> makeDoc(String verificationStatus) =>
      db.into(db.policyDocuments).insertReturning(
            PolicyDocumentsCompanion.insert(
              documentNumber: 'TEST-DOC-$verificationStatus',
              documentType: 'test-fixture',
              issuingAuthority: 'test-fixture',
              verificationStatus: verificationStatus,
            ),
          );

  Future<CurriculumVersion> makeVersion(PolicyStatus status,
      {String docStatus = 'primaryVerified'}) async {
    final doc = await makeDoc(docStatus);
    return repo.createVersion(
      academicYearId: seed.academicYearId,
      status: status,
      sourcePolicyDocumentId: doc.id,
    );
  }

  group('versions (Guard #1)', () {
    test('ACTIVE is refused when the source document is unverified', () async {
      final doc = await makeDoc('unverified');
      expect(
        () => repo.createVersion(
          academicYearId: seed.academicYearId,
          status: PolicyStatus.active,
          sourcePolicyDocumentId: doc.id,
        ),
        throwsA(isA<PolicyDataGuardViolation>()),
      );
    });

    test('UNKNOWN is allowed with an unverified source; country and label '
        'stay NULL (nothing invented)', () async {
      final v = await makeVersion(PolicyStatus.unknown, docStatus: 'unverified');
      expect(v.status, equals('unknown'));
      expect(v.countryCode, isNull);
      expect(v.versionLabel, isNull);
      expect(v.effectiveFrom, isNull);
      expect(v.effectiveTo, isNull);
    });

    test('ACTIVE is accepted with a verified source; country is normalized '
        'and label trimmed', () async {
      final doc = await makeDoc('secondaryConfirmed');
      final v = await repo.createVersion(
        academicYearId: seed.academicYearId,
        status: PolicyStatus.active,
        sourcePolicyDocumentId: doc.id,
        countryCode: ' zz ',
        versionLabel: '  TEST-EDITION  ',
      );
      expect(v.status, equals('active'));
      expect(v.countryCode, equals('ZZ'));
      expect(v.versionLabel, equals('TEST-EDITION'));
    });

    test('a missing source document is refused', () async {
      expect(
        () => repo.createVersion(
          academicYearId: seed.academicYearId,
          status: PolicyStatus.unknown,
          sourcePolicyDocumentId: 'no-such-document',
        ),
        throwsA(isA<PolicyDataGuardViolation>()),
      );
    });

    test('effectiveTo before effectiveFrom is refused', () async {
      final doc = await makeDoc('primaryVerified');
      expect(
        () => repo.createVersion(
          academicYearId: seed.academicYearId,
          status: PolicyStatus.unknown,
          sourcePolicyDocumentId: doc.id,
          effectiveFrom: DateTime.utc(2027, 1, 1),
          effectiveTo: DateTime.utc(2026, 1, 1),
        ),
        throwsA(isA<PolicyDataGuardViolation>()),
      );
    });

    test('country code and label normalization (pure)', () {
      expect(CurriculumRepository.normalizeCountryCode(null), isNull);
      expect(CurriculumRepository.normalizeCountryCode('   '), isNull);
      expect(CurriculumRepository.normalizeCountryCode('zz'), equals('ZZ'));
      expect(() => CurriculumRepository.normalizeCountryCode('ZZZ'),
          throwsArgumentError);
      expect(() => CurriculumRepository.normalizeCountryCode('1a'),
          throwsArgumentError);
      expect(CurriculumRepository.normalizeLabel('  x '), equals('x'));
      expect(CurriculumRepository.normalizeLabel(''), isNull);
    });

    test('REPEALED is terminal; ACTIVE needs a verified source; other moves '
        'work', () async {
      final unverified =
          await makeVersion(PolicyStatus.unknown, docStatus: 'unverified');
      expect(
        () => repo.changeVersionStatus(
            curriculumVersionId: unverified.id, newStatus: PolicyStatus.active),
        throwsA(isA<PolicyDataGuardViolation>()),
      );

      final verified = await makeVersion(PolicyStatus.unknown);
      final active = await repo.changeVersionStatus(
          curriculumVersionId: verified.id, newStatus: PolicyStatus.active);
      expect(active.status, equals('active'));
      final frozen = await repo.changeVersionStatus(
          curriculumVersionId: verified.id, newStatus: PolicyStatus.frozen);
      expect(frozen.status, equals('frozen'));
      final repealed = await repo.changeVersionStatus(
          curriculumVersionId: verified.id, newStatus: PolicyStatus.repealed);
      expect(repealed.status, equals('repealed'));

      expect(
        () => repo.changeVersionStatus(
            curriculumVersionId: verified.id, newStatus: PolicyStatus.active),
        throwsA(isA<PolicyDataGuardViolation>()),
      );
      // Staying REPEALED is a no-op, not an error.
      final same = await repo.changeVersionStatus(
          curriculumVersionId: verified.id, newStatus: PolicyStatus.repealed);
      expect(same.status, equals('repealed'));
    });
  });

  group('effective status', () {
    test('PolicyStatus.mostRestrictive orders ACTIVE < UNKNOWN < FROZEN < '
        'CONFLICT < REPEALED', () {
      expect(
          PolicyStatus.mostRestrictive(
              PolicyStatus.active, PolicyStatus.unknown),
          PolicyStatus.unknown);
      expect(
          PolicyStatus.mostRestrictive(
              PolicyStatus.frozen, PolicyStatus.conflict),
          PolicyStatus.conflict);
      expect(
          PolicyStatus.mostRestrictive(
              PolicyStatus.repealed, PolicyStatus.active),
          PolicyStatus.repealed);
      expect(
          PolicyStatus.mostRestrictive(
              PolicyStatus.active, PolicyStatus.active),
          PolicyStatus.active);
    });

    test('a subject not linked to any version is UNKNOWN, never ACTIVE',
        () async {
      final s = await repo.effectiveStatusForSubject(seed.subjectId);
      expect(s.status, equals(PolicyStatus.unknown));
      expect(s.linkedToVersion, isFalse);
      expect(s.usableForCalculation, isFalse);
      final n = await repo.effectiveStatusForNode(seed.knowledgeNodeId);
      expect(n.status, equals(PolicyStatus.unknown));
    });

    test('a subject and its nodes take the status of the linked version',
        () async {
      await repo.linkSubjectToVersion(
          subjectId: seed.subjectId,
          curriculumVersionId: seed.curriculumVersionId);
      final s = await repo.effectiveStatusForSubject(seed.subjectId);
      expect(s.status, equals(PolicyStatus.active));
      expect(s.linkedToVersion, isTrue);
      final n = await repo.effectiveStatusForNode(seed.knowledgeNodeId);
      expect(n.status, equals(PolicyStatus.active));
      expect(n.usableForCalculation, isTrue);

      final repealed = await makeVersion(PolicyStatus.repealed);
      await repo.linkSubjectToVersion(
          subjectId: seed.subjectId, curriculumVersionId: repealed.id);
      final n2 = await repo.effectiveStatusForNode(seed.knowledgeNodeId);
      expect(n2.status, equals(PolicyStatus.repealed));
      expect(n2.usableForCalculation, isFalse);
    });

    test('linking to a missing version or subject is refused', () async {
      expect(
        () => repo.linkSubjectToVersion(
            subjectId: seed.subjectId, curriculumVersionId: 'nope'),
        throwsA(isA<PolicyDataGuardViolation>()),
      );
      expect(
        () => repo.linkSubjectToVersion(
            subjectId: 'nope', curriculumVersionId: seed.curriculumVersionId),
        throwsA(isA<PolicyDataGuardViolation>()),
      );
    });

    test('an ACTIVE load inside a REPEALED version is NOT usable (the more '
        'restrictive status wins) and Guard #2 is loud', () async {
      await repo.changeVersionStatus(
          curriculumVersionId: seed.curriculumVersionId,
          newStatus: PolicyStatus.repealed);
      final eff = await repo.effectiveStatusForSubjectLoad(seed.subjectLoadId);
      expect(eff.status, equals(PolicyStatus.repealed));
      expect(
        () => repo.getUsableCoefficient(seed.subjectLoadId),
        throwsA(isA<PolicyDataGuardViolation>()),
      );
      // Guard #3 still reports the load's own raw status, without a number.
      expect(await repo.readRawStatus(seed.subjectLoadId),
          equals(PolicyStatus.active));
    });

    test('an ACTIVE load inside a FROZEN version is excluded (null), not '
        'an error', () async {
      await repo.changeVersionStatus(
          curriculumVersionId: seed.curriculumVersionId,
          newStatus: PolicyStatus.frozen);
      expect(await repo.getUsableCoefficient(seed.subjectLoadId), isNull);
    });

    test('a non-ACTIVE load inside an ACTIVE version stays non-usable',
        () async {
      final cdb = createInMemoryTestDatabase();
      try {
        final cseed =
            await seedMinimalCurriculum(cdb, subjectLoadStatus: 'conflict');
        expect(
            await CurriculumRepository(cdb)
                .getUsableCoefficient(cseed.subjectLoadId),
            isNull);
      } finally {
        await cdb.close();
      }
    });
  });

  group('effective dates', () {
    test('windowStateOf (pure)', () {
      final asOf = DateTime.utc(2026, 10, 1);
      expect(CurriculumRepository.windowStateOf(asOf: asOf),
          VersionWindowState.unbounded);
      expect(
          CurriculumRepository.windowStateOf(
              effectiveFrom: DateTime.utc(2026, 11, 1), asOf: asOf),
          VersionWindowState.notYetEffective);
      expect(
          CurriculumRepository.windowStateOf(
              effectiveTo: DateTime.utc(2026, 9, 1), asOf: asOf),
          VersionWindowState.ended);
      expect(
          CurriculumRepository.windowStateOf(
              effectiveFrom: DateTime.utc(2026, 9, 1),
              effectiveTo: DateTime.utc(2027, 6, 30),
              asOf: asOf),
          VersionWindowState.inEffect);
    });

    test('getUsableCoefficient honours asOf only when given; a version with '
        'no dates is never expired by inference', () async {
      // No dates: usable with or without asOf.
      expect(await repo.getUsableCoefficient(seed.subjectLoadId), equals(5.0));
      expect(
          await repo.getUsableCoefficient(seed.subjectLoadId,
              asOf: DateTime.utc(2099, 1, 1)),
          equals(5.0));

      await (db.update(db.curriculumVersions)
            ..where((t) => t.id.equals(seed.curriculumVersionId)))
          .write(CurriculumVersionsCompanion(
        effectiveFrom: drift.Value(DateTime.utc(2026, 9, 1)),
        effectiveTo: drift.Value(DateTime.utc(2027, 6, 30)),
      ));
      expect(
          await repo.getUsableCoefficient(seed.subjectLoadId,
              asOf: DateTime.utc(2026, 10, 1)),
          equals(5.0));
      expect(
          await repo.getUsableCoefficient(seed.subjectLoadId,
              asOf: DateTime.utc(2026, 8, 1)),
          isNull);
      expect(
          await repo.getUsableCoefficient(seed.subjectLoadId,
              asOf: DateTime.utc(2027, 9, 1)),
          isNull);
      // Without asOf the stored dates are not applied (backward compatible).
      expect(await repo.getUsableCoefficient(seed.subjectLoadId), equals(5.0));
    });

    test('CurriculumDomainService passes asOf through', () async {
      final service = CurriculumDomainService(repo);
      expect(
          await service.officialCoefficientSignal(
              subjectLoadId: seed.subjectLoadId, maxPlausibleCoefficient: 10),
          closeTo(0.5, 1e-9));
      await (db.update(db.curriculumVersions)
            ..where((t) => t.id.equals(seed.curriculumVersionId)))
          .write(CurriculumVersionsCompanion(
        effectiveTo: drift.Value(DateTime.utc(2026, 1, 1)),
      ));
      expect(
          await service.officialCoefficientSignal(
              subjectLoadId: seed.subjectLoadId,
              maxPlausibleCoefficient: 10,
              asOf: DateTime.utc(2026, 10, 1)),
          isNull);
    });
  });

  group('hierarchy', () {
    test('ingestSubject is idempotent and needs an existing version',
        () async {
      final level = await db.select(db.educationLevels).getSingle();
      final a = await repo.ingestSubject(
          curriculumVersionId: seed.curriculumVersionId,
          educationLevelId: level.id,
          name: '  TEST-INGESTED  ');
      final b = await repo.ingestSubject(
          curriculumVersionId: seed.curriculumVersionId,
          educationLevelId: level.id,
          name: 'TEST-INGESTED');
      expect(a.id, equals(b.id));
      expect(a.name, equals('TEST-INGESTED'));
      expect(a.curriculumVersionId, equals(seed.curriculumVersionId));
      expect(
        () => repo.ingestSubject(
            curriculumVersionId: 'nope',
            educationLevelId: level.id,
            name: 'X'),
        throwsA(isA<PolicyDataGuardViolation>()),
      );
      expect(
        () => repo.ingestSubject(
            curriculumVersionId: seed.curriculumVersionId,
            educationLevelId: level.id,
            name: '   '),
        throwsArgumentError,
      );
    });

    test('readTreeForVersion returns version -> subject -> unit -> lesson '
        '-> node with prerequisites, only for that version', () async {
      await repo.linkSubjectToVersion(
          subjectId: seed.subjectId,
          curriculumVersionId: seed.curriculumVersionId);
      final level = await db.select(db.educationLevels).getSingle();
      // A second subject that is NOT linked must not appear in the tree.
      await db.into(db.subjects).insert(SubjectsCompanion.insert(
          name: 'TEST-UNLINKED', educationLevelId: level.id));

      final lesson = await db.select(db.lessons).getSingle();
      final nodeB = await db.into(db.knowledgeNodes).insertReturning(
          KnowledgeNodesCompanion.insert(
              lessonId: lesson.id, name: 'TEST-NODE-B'));
      await PrerequisiteRepository(db).insert(
        knowledgeNodeId: nodeB.id,
        requiresNodeId: seed.knowledgeNodeId,
        isHard: true,
        relationType: PrerequisiteRelationType.official.name,
      );

      final tree = await repo.readTreeForVersion(seed.curriculumVersionId);
      expect(tree.version.id, equals(seed.curriculumVersionId));
      expect(tree.subjects, hasLength(1));
      expect(tree.subjects.single.subject.id, equals(seed.subjectId));
      final unit = tree.subjects.single.units.single;
      expect(unit.unit.name, equals('TEST-UNIT'));
      final nodes = unit.lessons.single.nodes;
      expect(nodes.map((n) => n.node.name).toList(),
          equals(['TEST-NODE', 'TEST-NODE-B']));
      expect(nodes[0].prerequisites, isEmpty);
      expect(nodes[1].prerequisites, hasLength(1));
      expect(nodes[1].prerequisites.single.requiresNodeId,
          equals(seed.knowledgeNodeId));

      expect(() => repo.readTreeForVersion('nope'),
          throwsA(isA<PolicyDataGuardViolation>()));
    });
  });

  group('Knowledge Graph link', () {
    late String nodeBId;
    late KnowledgeGraphDomainService graph;

    Future<void> addEdge(String relationType, {bool isHard = true}) =>
        PrerequisiteRepository(db).insert(
          knowledgeNodeId: nodeBId,
          requiresNodeId: seed.knowledgeNodeId,
          isHard: isHard,
          relationType: relationType,
        );

    setUp(() async {
      final lesson = await db.select(db.lessons).getSingle();
      final nodeB = await db.into(db.knowledgeNodes).insertReturning(
          KnowledgeNodesCompanion.insert(
              lessonId: lesson.id, name: 'TEST-NODE-B'));
      nodeBId = nodeB.id;
      graph = KnowledgeGraphDomainService(
        PrerequisiteRepository(db),
        MasteryRepository(db),
        curriculum: repo,
      );
    });

    Future<PrerequisiteSatisfactionResult> check() =>
        graph.checkDirectHardPrerequisites(
          studentId: seed.studentId,
          knowledgeNodeId: nodeBId,
          masteryThreshold: 0.5,
        );

    test('an official edge under an ACTIVE version is consumed (unobserved '
        'prerequisite blocks)', () async {
      await repo.linkSubjectToVersion(
          subjectId: seed.subjectId,
          curriculumVersionId: seed.curriculumVersionId);
      await addEdge('official');
      final r = await check();
      expect(r.satisfied, isFalse);
      expect(r.blockingNodeIds, equals([seed.knowledgeNodeId]));
      expect(r.ignoredEdges, isEmpty);
    });

    test('an official edge under a REPEALED version is never consumed, and '
        'is reported', () async {
      final repealed = await makeVersion(PolicyStatus.repealed);
      await repo.linkSubjectToVersion(
          subjectId: seed.subjectId, curriculumVersionId: repealed.id);
      await addEdge('official');
      final r = await check();
      expect(r.satisfied, isTrue);
      expect(r.blockingNodeIds, isEmpty);
      expect(r.ignoredEdges, hasLength(1));
      expect(r.ignoredEdges.single.status, equals(PolicyStatus.repealed));
      expect(r.ignoredEdges.single.requiresNodeId, equals(seed.knowledgeNodeId));
    });

    test('an official edge on content with no curriculum version is '
        'UNKNOWN: ignored and reported', () async {
      await addEdge('official');
      final r = await check();
      expect(r.satisfied, isTrue);
      expect(r.ignoredEdges, hasLength(1));
      expect(r.ignoredEdges.single.status, equals(PolicyStatus.unknown));
    });

    test('a proposed edge is the student\'s own and is still consumed, even '
        'under a REPEALED version', () async {
      final repealed = await makeVersion(PolicyStatus.repealed);
      await repo.linkSubjectToVersion(
          subjectId: seed.subjectId, curriculumVersionId: repealed.id);
      await addEdge('proposed');
      final r = await check();
      expect(r.satisfied, isFalse);
      expect(r.blockingNodeIds, equals([seed.knowledgeNodeId]));
      expect(r.ignoredEdges, isEmpty);
    });

    test('a soft (non-hard) edge is not considered, as before', () async {
      await addEdge('official', isHard: false);
      final r = await check();
      expect(r.satisfied, isTrue);
      expect(r.ignoredEdges, isEmpty);
    });
  });
}
