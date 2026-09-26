import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/app_database.dart';

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

    return AppState._(db, verifiedId);
  }

  Future<void> setStudentId(String id) async {
    _studentId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_studentIdKey, id);
    notifyListeners();
  }
}
