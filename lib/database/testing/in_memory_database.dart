// Test-only database factory.
//
// This file is deliberately the ONLY place in the whole project that
// imports `package:drift/native.dart` for an in-memory database. It must
// never be imported by app_database.dart or by any file reachable from the
// app's production entry point (main.dart), because `package:drift/native.dart`
// pulls in sqlite3's FFI bindings (`external` functions), which cannot be
// compiled for Flutter Web ("Only JS interop members may be 'external'").
//
// Import this file directly from test/ files only:
//   import 'package:student_app/database/testing/in_memory_database.dart';
//
// See DEVIATIONS.md, DEVIATION-13, for the root-cause history.
import 'package:drift/native.dart';

import '../app_database.dart';

/// Fully in-memory AppDatabase, never touches disk, never touches the
/// network. Used by every test file in test/ so the test suite has zero
/// filesystem dependency of its own.
AppDatabase createInMemoryTestDatabase() {
  return AppDatabase(NativeDatabase.memory(
    setup: (rawDb) => rawDb.execute('PRAGMA foreign_keys = ON;'),
  ));
}
