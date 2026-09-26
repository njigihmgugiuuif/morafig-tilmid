import 'package:drift/drift.dart';

/// Base class for the three append-only tables (Event, Explanation,
/// HumanOverride). Deliberately exposes ONLY `insertRow` and read methods —
/// there is no `update`/`delete` method anywhere on this class or its
/// subclasses. This is what makes "append-only" a structural guarantee
/// instead of a convention: no calling code, however it is written, can
/// reach an update/delete path through this repository because the method
/// does not exist on the type.
///
/// A determined caller could still reach the underlying Drift table object
/// directly and call `.update()`/`.delete()` on it — Dart has no way to
/// seal that off at the language level. The mitigation is organizational,
/// not just technical: `analysis_options.yaml` forbids any import of
/// `database/tables/audit_tables.dart` outside `lib/repositories/`, so the
/// only code in the whole app allowed to even see those Drift table
/// objects is this file and its two subclasses.
abstract class AppendOnlyRepository<T extends Table, D> {
  AppendOnlyRepository(this.db, this.table);

  final GeneratedDatabase db;
  final TableInfo<T, D> table;

  Future<D> insertRow(Insertable<D> entry) {
    return db.into(table).insertReturning(entry);
  }

  Future<List<D>> readAll() => db.select(table).get();

  // Typed single-entity reads (e.g. readById) are implemented per-subclass
  // using the table's own generated column accessors, since a generic
  // `where` clause cannot be expressed portably at this base-class level
  // without losing type safety. See event_repository.dart for the pattern.

  // NO update(). NO delete(). This is not an oversight — see class doc.
}
