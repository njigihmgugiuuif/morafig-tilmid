import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'app_db',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception(
        'انتهت مهلة فتح قاعدة بيانات الويب بعد 10 ثوانٍ (WasmDatabase.open '
        'لم يستجب). الاحتمالات الأكثر شيوعًا: المتصفح يمنع تشغيل '
        'drift_worker.js كعامل ويب (Web Worker) في هذا السياق، أو خطأ '
        'داخل ذلك العامل لم يصل إلى الخيط الرئيسي.',
      ),
    );
    return result.resolvedExecutor;
  });
}
