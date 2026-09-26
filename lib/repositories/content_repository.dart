import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// CRUD for the raw content graph (Subjects → Units → Lessons →
/// KnowledgeNodes). Previous phases built the *policy/coefficient* layer
/// (CurriculumRepository, guarded) but nothing yet let a student actually
/// enter their own subjects/lessons — without this, the UI would have no
/// real content to attach Tasks/Exams/Mastery to. This repository is
/// deliberately unguarded (plain CRUD): unlike SubjectLoads, a Subject's
/// name or a Lesson's title is not a legally-sourced fact, so none of the
/// PolicyStatus machinery applies here.
class ContentRepository {
  ContentRepository(this._db);
  final AppDatabase _db;

  Stream<List<Subject>> watchSubjects(String educationLevelId) {
    return (_db.select(_db.subjects)
          ..where((t) => t.educationLevelId.equals(educationLevelId)))
        .watch();
  }

  Future<Subject> getOrCreateSubject({
    required String educationLevelId,
    required String name,
  }) async {
    final existing = await (_db.select(_db.subjects)
          ..where((t) =>
              t.educationLevelId.equals(educationLevelId) &
              t.name.equals(name.trim())))
        .getSingleOrNull();
    if (existing != null) return existing;
    return _db.into(_db.subjects).insertReturning(
          SubjectsCompanion.insert(
            name: name.trim(),
            educationLevelId: educationLevelId,
          ),
        );
  }

  Future<Unit> _getOrCreateDefaultUnit(String subjectId) async {
    const label = 'عام';
    final existing = await (_db.select(_db.units)
          ..where((t) => t.subjectId.equals(subjectId) & t.name.equals(label)))
        .getSingleOrNull();
    if (existing != null) return existing;
    return _db.into(_db.units).insertReturning(
          UnitsCompanion.insert(subjectId: subjectId, name: label, order: 0),
        );
  }

  Future<Lesson> _getOrCreateDefaultLesson(String unitId) async {
    const label = 'عام';
    final existing = await (_db.select(_db.lessons)
          ..where((t) => t.unitId.equals(unitId) & t.name.equals(label)))
        .getSingleOrNull();
    if (existing != null) return existing;
    return _db.into(_db.lessons).insertReturning(
          LessonsCompanion.insert(unitId: unitId, name: label, order: 0),
        );
  }

  /// Creates a new, distinct KnowledgeNode for a task/topic name under a
  /// subject, auto-creating a default Unit/Lesson container if the
  /// student hasn't organized their content into real units/lessons yet.
  /// (A dedicated "organize my curriculum into units and lessons" screen
  /// is a natural next-cycle addition — this keeps first use unblocked
  /// without hiding or faking that structure; the real tables are used.)
  Future<KnowledgeNode> quickCreateNode({
    required String educationLevelId,
    required String subjectName,
    required String nodeName,
  }) async {
    return _db.transaction(() async {
      final subject = await getOrCreateSubject(
        educationLevelId: educationLevelId,
        name: subjectName,
      );
      final unit = await _getOrCreateDefaultUnit(subject.id);
      final lesson = await _getOrCreateDefaultLesson(unit.id);
      return _db.into(_db.knowledgeNodes).insertReturning(
            KnowledgeNodesCompanion.insert(
              lessonId: lesson.id,
              name: nodeName.trim(),
            ),
          );
    });
  }

  Future<String> nameForNode(String knowledgeNodeId) async {
    final node = await (_db.select(_db.knowledgeNodes)
          ..where((t) => t.id.equals(knowledgeNodeId)))
        .getSingleOrNull();
    return node?.name ?? 'محتوى محذوف';
  }

  Future<String> subjectNameForNode(String knowledgeNodeId) async {
    final node = await (_db.select(_db.knowledgeNodes)
          ..where((t) => t.id.equals(knowledgeNodeId)))
        .getSingleOrNull();
    if (node == null) return '';
    final lesson = await (_db.select(_db.lessons)
          ..where((t) => t.id.equals(node.lessonId)))
        .getSingleOrNull();
    if (lesson == null) return '';
    final unit = await (_db.select(_db.units)
          ..where((t) => t.id.equals(lesson.unitId)))
        .getSingleOrNull();
    if (unit == null) return '';
    final subject = await (_db.select(_db.subjects)
          ..where((t) => t.id.equals(unit.subjectId)))
        .getSingleOrNull();
    return subject?.name ?? '';
  }

  /// Ensures a default EducationLevel exists so onboarding/first content
  /// creation never blocks on the (currently unbuilt) level-picker UI.
  /// Real level selection (جذع مشترك / سنة ثانية / سنة ثالثة + مسار) is
  /// flagged as a follow-up screen — this keeps the app usable meanwhile
  /// without inventing fake data (the row created here is a real,
  /// student-editable EducationLevels row, not a hidden hardcoded value
  /// read from Dart code elsewhere).
  Future<EducationLevel> getOrCreateDefaultLevel() async {
    final existing = await _db.select(_db.educationLevels).getSingleOrNull();
    if (existing != null) return existing;
    return _db.into(_db.educationLevels).insertReturning(
          EducationLevelsCompanion.insert(name: 'المستوى الدراسي', order: 0),
        );
  }
}
