// Platform picker + single entry point for opening the production database
// connection. Import this file (not connection_native.dart / connection_web.dart
// / connection_stub.dart directly) from anywhere that needs to open a real
// connection.
//
// This file replaces an earlier version (written outside this project's own
// history) that called a function named `connect()` — which was never
// defined anywhere in this project; the real function, in both
// connection_native.dart and connection_web.dart, has always been named
// `openConnection()`. That earlier version also declared its own top-level
// `openConnection()` in the same file it conditionally imported
// connection_native.dart/connection_web.dart into — both of which already
// declare a top-level `openConnection()` — which is a duplicate-declaration
// compile error. Both bugs are fixed here the standard way: the conditional
// import is given a prefix (`as _impl`), so the imported `openConnection()`
// is only ever reachable as `_impl.openConnection()`, never colliding with
// this file's own wrapper of the same name. See DEVIATIONS.md, DEVIATION-15.
import 'package:drift/drift.dart';

import 'connection_native.dart' as _impl
    if (dart.library.js_interop) 'connection_web.dart';

QueryExecutor openConnection() {
  return _impl.openConnection();
}
