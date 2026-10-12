import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor openConnection() => _open('app_db');

/// The separate teacher-content database (DEVIATION-23): its own named
/// IndexedDB database, opened exactly like the main one.
QueryExecutor openTeacherConnection() => _open('teacher_content_db');

/// The student's own copy of the lessons that reached them. It is a DIFFERENT
/// database from the teacher panel's, so a teacher's drafts never sit inside
/// a student's storage and the two screens never fight over one database.
QueryExecutor openStudentLibraryConnection() => _open('student_library_db');

QueryExecutor _open(String databaseName) {
  return LazyDatabase(() async {
    // Resolve both asset URIs to ABSOLUTE URLs against the page's real
    // current location (Uri.base), instead of passing bare relative
    // strings ('sqlite3.wasm', 'drift_worker.js') straight to drift.
    //
    // Root cause (confirmed against drift's own GitHub issue tracker,
    // 2026-09-30): when a Flutter web app is deployed under a nested
    // subpath — exactly what GitHub Pages project sites always are
    // (https://<user>.github.io/<repo>/, not domain root) — a bare
    // relative Uri passed to WasmDatabase can be resolved differently
    // inside the dedicated worker drift spawns than it is on the main
    // page, silently pointing at the wrong location. Unlike a normal
    // 404, this doesn't surface as a thrown error: WasmDatabase.open()
    // simply never resolves, which is exactly the infinite loading-spinner
    // symptom observed live. See simolus3/drift issue #2559 ("Cannot use
    // drift web with nested paths") and discussion #3603, where the
    // documented workaround is to pass a fully-resolved absolute Uri
    // instead of a relative one. Uri.base.resolve(...) is used (rather
    // than a hardcoded leading-slash path like '/sqlite3.wasm') so this
    // keeps working correctly regardless of which subpath the app is
    // ever deployed under, including domain root.
    final sqlite3Uri = Uri.base.resolve('sqlite3.wasm');
    final driftWorkerUri = Uri.base.resolve('drift_worker.js');

    final result = await WasmDatabase.open(
      databaseName: databaseName,
      sqlite3Uri: sqlite3Uri,
      driftWorkerUri: driftWorkerUri,
    ).timeout(
      const Duration(seconds: 25),
      onTimeout: () => throw Exception(
        'تعذّر فتح قاعدة البيانات على هذا الجهاز خلال 25 ثانية. أغلق نوافذ '
        'التطبيق الأخرى (ولوحة الأستاذ إن كانت مفتوحة) ثم أعد المحاولة. '
        'الملفات المستخدمة: sqlite3Uri=$sqlite3Uri، '
        'driftWorkerUri=$driftWorkerUri',
      ),
    );
    return result.resolvedExecutor;
  });
}
