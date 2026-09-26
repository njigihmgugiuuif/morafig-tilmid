import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'append_only_repository.dart';

class EventRepository extends AppendOnlyRepository<Events, Event> {
  EventRepository(AppDatabase db) : super(db, db.events);

  AppDatabase get _db => db as AppDatabase;

  Future<Event?> readById(String id) =>
      (_db.select(_db.events)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<List<Event>> readUnprocessed() =>
      (_db.select(_db.events)..where((t) => t.processedAt.isNull())).get();

  /// The ONLY mutation this repository allows besides insert: marking an
  /// event processed. This is intentionally NOT a generic update() — it
  /// only ever sets processedAt, and only forward in time (see the guard
  /// below), so it cannot be used to rewrite an event's actual content.
  Future<void> markProcessed(String id, DateTime processedAt) async {
    final existing = await readById(id);
    if (existing == null) {
      throw StateError('Cannot mark unknown event $id as processed.');
    }
    if (existing.processedAt != null) {
      throw StateError(
          'Event $id was already processed at ${existing.processedAt}; '
          'processedAt may only be set once (append-only semantics).');
    }
    await (_db.update(_db.events)..where((t) => t.id.equals(id)))
        .write(EventsCompanion(processedAt: Value(processedAt)));
  }
}
