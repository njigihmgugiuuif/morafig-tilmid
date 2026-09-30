import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final probed = await WasmDatabase.probe(
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
      databaseName: 'app_db',
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception(
        'انتهت مهلة فحص إمكانيات المتصفح (WasmDatabase.probe) بعد 10 ثوانٍ.',
      ),
    );

    // Deliberately skip drift's own "best available" auto-selection and
    // go straight to unsafeIndexedDb. Confirmed live (2026-09-29, see
    // DEVIATIONS.md) that on Chrome for Android — which does not
    // implement SharedWorker at all — letting drift pick automatically
    // can select a SharedWorker-based tier (sharedIndexedDb / opfsShared)
    // that then hangs forever instead of failing, because the
    // SharedWorker handshake never completes on that platform. This page
    // is served without COOP/COEP headers (GitHub Pages default), so the
    // OPFS-with-locks tier (opfsLocks) isn't reachable either way.
    // unsafeIndexedDb needs no worker-to-worker coordination at all, so
    // it works on every browser without exception. Its one limitation —
    // not safe if the same database is opened in two browser tabs at
    // the same moment — is an acceptable trade-off for this single-
    // student, normally-one-tab app.
    const implementation = WasmStorageImplementation.unsafeIndexedDb;

    final connection = await probed.open(implementation, 'app_db').timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception(
        'انتهت مهلة فتح قاعدة البيانات عبر unsafeIndexedDb بعد 10 ثوانٍ.',
      ),
    );

    return connection;
  });
}
