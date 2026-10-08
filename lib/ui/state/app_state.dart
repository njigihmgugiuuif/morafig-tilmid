import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/app_database.dart';
import '../../database/teacher_content_database.dart';
import '../../repositories/teacher_content_repository.dart';
import '../../services/planning_service.dart';
import '../../services/teacher_session.dart';

/// App-wide state: holds the single open database connection and the
/// current student's id (this is a single-user personal app — one
/// student per install — so we do not build a multi-student picker).
///
/// Also tracks first-run / onboarding status. Nothing here touches the
/// network; SharedPreferences is local device storage only.
class AppState extends ChangeNotifier {
  AppState._(this.db, this._studentId);

  final AppDatabase db;
  String? _studentId;

  String? get studentId => _studentId;
  bool get hasStudent => _studentId != null;

  /// The teacher entry of this version (phase C). Local only; see
  /// TeacherSession for what it does NOT do (it cannot verify identity).
  /// The separate teacher-content database (DEVIATION-23), opened on first
  /// use so a student who never opens the library pays nothing for it.
  late final TeacherContentDatabase teacherDb = TeacherContentDatabase.open();

  TeacherContentRepository get teacherRepository =>
      TeacherContentRepository(teacherDb, mainDb: db);

  late final TeacherSession teacherSession =
      TeacherSession(SharedPrefsKeyValueStore());

  static const _studentIdKey = 'current_student_id';

  static Future<AppState> bootstrap() async {
    final db = AppDatabase.open();
    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString(_studentIdKey);

    // Defensive check: the id was saved locally but the row may not
    // actually exist anymore (e.g. app data partially cleared, or a
    // future "reset app" feature ran). Never trust the cached id blindly.
    String? verifiedId;
    if (storedId != null) {
      final row = await (db.select(db.students)
            ..where((t) => t.id.equals(storedId)))
          .getSingleOrNull();
      verifiedId = row?.id;
      if (verifiedId == null) {
        await prefs.remove(_studentIdKey);
      }
    }

    // B: the app-open trigger of the planning service (there is no
    // background work without a server). Fire-and-forget: it never delays
    // start-up and never throws (errors are collected inside the result).
    if (verifiedId != null) {
      unawaited(PlanningService(db).onAppOpen());
    }

    return AppState._(db, verifiedId);
  }

  Future<void> setStudentId(String id) async {
    _studentId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_studentIdKey, id);
    notifyListeners();
  }

  /// Forgets the current student (used by "reset all data"): the app
  /// returns to first-run onboarding.
  Future<void> clearStudent() async {
    _studentId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_studentIdKey);
    notifyListeners();
  }
}
