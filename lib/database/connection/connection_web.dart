import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor openConnection() {
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
      databaseName: 'app_db',
      sqlite3Uri: sqlite3Uri,
      driftWorkerUri: driftWorkerUri,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception(
        'انتهت مهلة فتح قاعدة بيانات الويب بعد 10 ثوانٍ. عناوين الملفات '
        'المستخدَمة كانت: sqlite3Uri=$sqlite3Uri، '
        'driftWorkerUri=$driftWorkerUri',
      ),
    );
    return result.resolvedExecutor;
  });
}
