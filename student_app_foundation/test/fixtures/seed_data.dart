import 'package:drift/drift.dart' as drift;
import 'package:student_app/database/app_database.dart';

/// All data here is SYNTHETIC / invented for testing purposes only.
/// None of these subject names, coefficients, or document numbers are real
/// Algerian ministry data — using real unverified curriculum numbers as
/// test fixtures was explicitly prohibited for this phase. Anything that
/// looks like a real decree number below ("TEST-DECREE-0001") is
/// deliberately fake-looking so it can never be mistaken for a citation.

class MinimalCurriculumSeed {
  MinimalCurriculumSeed({
    required this.studentId,
    required this.academicYearId,
    required this.curriculumVersionId,
    required this.subjectId,
    required this.subjectLoadId,
    required this.knowledgeNodeId,
  });

  final String studentId;
  final String academicYearId;
  final String curriculumVersionId;
  final String subjectId;
  final String subjectLoadId;
  final String knowledgeNodeId;
}

Future<MinimalCurriculumSeed> seedMinimalCurriculum(
  AppDatabase db, {
  String subjectLoadStatus = 'active',
}) async {
  final year = await db.into(db.academicYears).insertReturning(
        AcademicYearsCompanion.insert(
          label: 'TEST-YEAR-0000',
          startDate: DateTime.utc(2000, 9, 1),
          endDate: DateTime.utc(2001, 6, 30),
        ),
      );

  final level = await db.into(db.educationLevels).insertReturning(
        EducationLevelsCompanion.insert(name: 'TEST-LEVEL', order: 1),
      );

  final student = await db.into(db.students).insertReturning(
        StudentsCompanion.insert(
          fullNameOrNickname: 'Test Student',
          currentAcademicYearId: year.id,
        ),
      );

  final doc = await db.into(db.policyDocuments).insertReturning(
        PolicyDocumentsCompanion.insert(
          documentNumber: 'TEST-DECREE-0001',
          documentType: 'test-fixture',
          issuingAuthority: 'test-fixture',
          verificationStatus: 'unverified',
        ),
      );

  final curriculumVersion = await db.into(db.curriculumVersions).insertReturning(
        CurriculumVersionsCompanion.insert(
          academicYearId: year.id,
          status: 'active',
          sourcePolicyDocumentId: doc.id,
        ),
      );

  final subject = await db.into(db.subjects).insertReturning(
        SubjectsCompanion.insert(
          name: 'TEST-SUBJECT',
          educationLevelId: level.id,
        ),
      );

  final subjectLoad = await db.into(db.subjectLoads).insertReturning(
        SubjectLoadsCompanion.insert(
          curriculumVersionId: curriculumVersion.id,
          subjectId: subject.id,
          status: subjectLoadStatus,
          coefficient: drift.Value(5.0),
        ),
      );

  final unit = await db.into(db.units).insertReturning(
        UnitsCompanion.insert(subjectId: subject.id, name: 'TEST-UNIT', order: 1),
      );
  final lesson = await db.into(db.lessons).insertReturning(
        LessonsCompanion.insert(unitId: unit.id, name: 'TEST-LESSON', order: 1),
      );
  final node = await db.into(db.knowledgeNodes).insertReturning(
        KnowledgeNodesCompanion.insert(lessonId: lesson.id, name: 'TEST-NODE'),
      );

  return MinimalCurriculumSeed(
    studentId: student.id,
    academicYearId: year.id,
    curriculumVersionId: curriculumVersion.id,
    subjectId: subject.id,
    subjectLoadId: subjectLoad.id,
    knowledgeNodeId: node.id,
  );
}
