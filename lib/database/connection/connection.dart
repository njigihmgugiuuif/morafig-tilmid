// Platform picker + single entry point for opening the production database
// connection. Import this file (not connection_native.dart / connection_web.dart
// / connection_stub.dart directly) from anywhere that needs to open a real
// connection.
//
// The conditional import is given a prefix (`as _impl`) so the imported
// `openConnection()` is only reachable as `_impl.openConnection()`, never
// colliding with this file's own wrapper of the same name.
// In Dart the prefix must come AFTER the `if (...)` configuration.
// See DEVIATIONS.md, DEVIATION-15.
import 'package:drift/drift.dart';

import 'connection_native.dart'
    if (dart.library.js_interop) 'connection_web.dart' as _impl;

QueryExecutor openConnection() {
  return _impl.openConnection();
}
