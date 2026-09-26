// Web (Flutter Web / PWA) database connection using Drift's WASM backend.
//
// ============================================================================
// UNVERIFIED / HIGH-RISK — requires a one-time manual asset setup step
// ============================================================================
// Drift on the web needs two extra binary/JS assets placed under web/ that
// this sandbox cannot download (no network access here):
//   1. sqlite3.wasm
//   2. drift_worker.js
//
// Official Drift web setup guide (do this once on your own machine, after
// `flutter pub get`): https://drift.simonbinder.eu/platforms/web/
// It documents how to copy these two files from your pub cache into web/.
// Until that step is done, `flutter build web` for this project will
// compile, but opening the app in a browser will fail when the database
// tries to initialize.
// This is DEVIATION-8 in DEVIATIONS.md — flagged as the top item to verify
// in the eventual real Flutter/Dart pass.
// ============================================================================
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'student_app',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );

    if (result.missingFeatures.isNotEmpty) {
      // Non-fatal: the browser lacks some optimal storage feature (e.g.
      // OPFS) and Drift fell back to a slower-but-working option (e.g.
      // IndexedDB). The app keeps running; only large-database performance
      // is affected.
      // ignore: avoid_print
      print(
        'Drift web: running with reduced storage features: '
        '${result.missingFeatures}',
      );
    }

    return result.resolvedExecutor;
  });
}
