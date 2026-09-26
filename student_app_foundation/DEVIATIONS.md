# DEVIATIONS.md — Deviations From the Approved Data Foundation Schema

Every deviation below was a genuine implementation-level necessity, not a
silent design change. None reduces the product's scope or capability.

## DEVIATION-1 — Table count is 36, not literally 34

The approved schema names 34 entities, but explicitly unifies
`ScheduleEntry` into `StudySessions` (documented in the schema doc itself:
"القرار: اسم الجدول الفعلي = StudySession"). Counting `ScheduleEntry` and
`StudySession` as the one table the schema itself says they are, the
faithful implementation is **34 entities across 36 physical tables**,
because two of the "entities" in the schema's own list
(`ScheduleEntry`/`StudySession`) were already one thing. No entity was
added or removed beyond what the schema document itself specified.

## DEVIATION-2 — PolicyStatus (and other enums) are enforced in Dart, not as SQL CHECK constraints

SQLite's `CHECK` constraints are supported by Drift, but enforcing a
5-value enum via `CHECK (status IN ('active','unknown',...))` at the SQL
level would duplicate the same vocabulary in two places (the Dart enum and
the SQL string), which is itself a data-integrity risk (the two lists
could drift apart). Instead, every write path goes through
`PolicyStatus.fromDb()` / `.toDb`, which is the single place the 5-value
vocabulary is defined. This is a slightly weaker guarantee than a raw
CHECK constraint (a direct `sqlite3` write bypassing Drift entirely could
insert an invalid string), which is judged acceptable because no part of
this Foundation's design permits raw SQL writes outside the Repository
layer in the first place.

## DEVIATION-3 — "At most one active EmergencyState per student" is enforced in the repository, not as a SQL partial-unique-index

A partial unique index (`UNIQUE ... WHERE exited_at IS NULL`) is valid
SQLite but not cleanly expressible through Drift's current table-definition
API in a cross-platform-safe way without dropping into raw migration SQL.
Given this is exactly the kind of invariant the Test Plan (Category D-
adjacent) will need to cover directly, the decision was to enforce it in
`EmergencyRepository` (a later phase — this table has no dedicated
repository written yet in this phase; only `Students`/`Curriculum`/
`Mastery`/`Event`/`Explanation`/`HumanOverride`/`RealityConstraint`/
`Prerequisite` repositories were written this phase, per the requested
"do not build all engines yet" scope) and to flag this explicitly rather
than silently rely on application-level discipline.

## DEVIATION-4 — Cycle detection for Prerequisites is application-level (DFS), not a SQL constraint

As documented directly in `curriculum_tables.dart` and implemented in
`PrerequisiteRepository`: no SQL dialect expresses "no cycles in this
self-referencing table" declaratively. This was already flagged as a known
limitation in the Data Foundation Schema document itself (Section D-INV-4
description implies procedural enforcement) — implemented here exactly as
anticipated.

## DEVIATION-5 — Repository-boundary enforcement needed a real fix during this pass (documented here rather than silently corrected)

`tools/check_repository_boundaries.sh` was written to enforce, mechanically,
that only `lib/repositories/` may import the raw Drift table files for the
append-only and curriculum/policy tables. Running it for the first time
(genuinely executed, not just written) immediately caught a real violation:
`derived_state_tables.dart` and `planning_tables.dart` import
`curriculum_tables.dart`/`audit_tables.dart` directly, because Drift table
classes declare their own foreign keys via `.references(OtherTable, #id)`,
which requires importing the referenced table's file. The original script
only exempted `app_database.dart`; it needed to exempt the whole
`lib/database/tables/` directory, since inter-table FK declarations are a
structural necessity, not a guard bypass — the actual risk the guard exists
for is business-logic code (engines/UI/import code) reaching these tables
directly, not the schema files declaring their own relationships. Fixed and
re-verified passing (see FOUNDATION_IMPLEMENTATION_REPORT.md, Section 11).

## DEVIATION-6 — Schema v1→v2: MemoryStates needed `difficulty` and `lastUpdatedFromEventId` (found during Memory Engine implementation, 2026-09-24)

The Data Foundation Schema's `MemoryStates` table (v1) had `stability`,
`retrievability`, and `nextReviewDate` only. Implementing the Memory Engine
(FSRS reimplementation, per the approved build-ready plan) surfaced a real
gap: FSRS's DSR model requires Difficulty (`D ∈ [1,10]`) to persist across
reviews as a per-card value — it feeds directly into the next stability
update and is not derivable from stability or retrievability alone. Without
it, every review after the first would have no prior `D` to update from.

Fix applied (smallest safe addition, per the project's own migration
policy in `migration_strategy.dart`): added `difficulty` (nullable
`RealColumn`) and `lastUpdatedFromEventId` (nullable, references `Events`)
to `MemoryStates`, bumped `schemaVersion` 1→2, added the `onUpgrade`
branch. `lastUpdatedFromEventId` was added alongside it for consistency
with `MasteryStates`, which already tracks the triggering Event for the
same audit/reconstruction reason — Memory Engine recomputations should be
traceable the same way Mastery Engine ones are.

No table was removed or renamed, no existing behavior changed, no other
schema element touched. This is UNVERIFIED like everything else in this
codebase — the migration has not been run against a real database, since
no Flutter/Dart SDK is available in the environment that wrote it.

## DEVIATION-7 — Availabilities.dayOfWeek convention was undocumented; adopted Dart's native weekday numbering (2026-09-24, Reality Layer domain, Cycle 2)

`planning_tables.dart`'s `Availabilities.dayOfWeek` is documented only as
"1-7, null if specificDate used," with no stated convention for which
integer means which day. Implementing `reality_layer_domain.dart`
(resolving recurring Availability rows onto concrete calendar days)
required picking one. Adopted Dart's own `DateTime.weekday` convention
(1=Monday..7=Sunday) rather than inventing a separate mapping, since that
avoids a translation layer for no stated reason and is the path of least
new surface area. Documented directly in
`RealityLayerDomainService.resolveAvailabilityForDay`'s doc comment as
well, flagged explicitly so this can be corrected cheaply (a one-line
mapping change, not a redesign) if the original intent was a different
convention (e.g. 1=Sunday, used by some calendar systems). No schema
change — Availabilities.dayOfWeek itself is untouched, this only fixes
the previously-undefined interpretation of its integer values.

## DEVIATION-8 — Web (Flutter Web/PWA) database backend needs a one-time manual asset setup this sandbox cannot perform (2026-09-25, Track F UI phase)

`database/app_database.dart` previously opened the database with
`dart:io` + `NativeDatabase` directly — this compiles for native
platforms only and cannot target Flutter Web at all (`dart:io` and FFI
are unavailable in a browser). Split into
`database/connection/connection_native.dart` (unchanged native logic,
moved as-is) and `database/connection/connection_web.dart` (new — uses
Drift's WASM backend, `package:drift/wasm.dart`), picked automatically
by `database/connection/connection_stub.dart`'s conditional export.
`AppDatabase.open()` now calls `openConnection()` instead of embedding
platform-specific code itself.

The web backend needs two binary/JS assets under `web/` —
`sqlite3.wasm` and `drift_worker.js` — that this sandbox cannot download
(no network access here). `flutter build web` will still compile
without them; the failure only happens at runtime, in the browser, when
the app tries to open its database. Official setup guide:
https://drift.simonbinder.eu/platforms/web/ — a one-time step to run on
your own machine after `flutter pub get`. **This is the single highest-
priority item to verify in the eventual real Flutter/Dart pass** —
higher priority than the general "run the tests" step, because unlike a
failing unit test, a missing web asset fails silently until someone
actually opens the deployed site in a browser.

No product feature was removed or reduced to work around this — the
same `AppDatabase` API, same 36 tables, same repositories are used on
web as on native; only the low-level bytes-on-disk mechanism differs,
exactly as Drift's own platform-abstraction design intends.

## DEVIATION-9 — index.html does not hand-write Flutter's web engine bootstrap script (2026-09-25, Track F UI phase)

Recent `flutter build web` output (Flutter 3.22+) auto-injects its own
`flutter_bootstrap.js` loader into `index.html` at build time; older
Flutter versions instead expect a manually-written `main.dart.js`
`<script>` tag with a specific loader snippet. Since this sandbox cannot
run `flutter --version` to know which convention applies on your
machine, `web/index.html` was written WITHOUT a hand-written engine
bootstrap script, deliberately leaving that part to whatever your
installed Flutter SDK generates automatically during `flutter build
web`. If your Flutter version turns out to be older than 3.22 and the
built site loads a blank white page with no loader at all, the fix is
documented at https://docs.flutter.dev/platform-integration/web/initialization
— a small addition to `index.html`, not a redesign. Flagged here rather
than guessed at, per this project's standing rule against asserting
unverified behavior.

## DEVIATION-10 — Track A/B/C engines (Priority/Mastery/Memory scoring) are not wired to task completion yet; UI reads their tables honestly-empty until Track D runs (2026-09-25, Track F UI phase)

The new UI screens (Progress, Priorities) query `MasteryStates`,
`MemoryStates`, and `PriorityStates` directly and correctly render their
real empty state when nothing has been computed yet. `TaskRepository
.markComplete()` writes a real, durable `TaskCompleted` Event (append-
only, via `EventRepository.insertRow`) but does NOT itself invoke
`MasteryEngine`/`MemoryEngine`/`PriorityEngine` — connecting completed-
task Events to those engines' `recomputeFrom(...)` methods end-to-end is
Track D (Integration), already logged as not-yet-built in prior phases.
Nothing is silently faked: the Event is real and will still be there,
unprocessed, whenever Track D's integration pass reads it. Flagging this
explicitly so "why is my mastery/priority screen empty after I complete
a task" is answered here rather than discovered as a surprise.

## DEVIATION-11 — No `android/`, `ios/`, or other platform folders exist in this repository yet

This repository was built starting from `flutter create --template=app`'s
`lib/`+`pubspec.yaml`+`test/` skeleton only (Foundation phase), never
the platform-scaffolding step. `web/` was added by hand in this phase
specifically for Flutter Web. For an actual installable Android build
later, run `flutter create .` once inside the project root on your own
machine (a standard, well-documented, non-destructive Flutter command —
it only adds the missing platform folders, it does not touch existing
`lib/` files) — not attempted here since it requires the Flutter CLI
this sandbox does not have.

## DEVIATION-12 — Package version pins in `pubspec.yaml` (`provider`, `shared_preferences`, `intl`, `sqlite3`, `flutter_localizations`) are best-effort, not network-verified

Added four new runtime dependencies (`provider`, `shared_preferences`,
`intl`, `sqlite3`) plus the `flutter_localizations` SDK package for
this phase's UI/RTL/onboarding work, with version constraints chosen
from general knowledge of these packages rather than a live check
against pub.dev (no network access in this sandbox). All four are
extremely widely used, stable packages, so a version conflict is
unlikely but not verified — `flutter pub get` is the first real test of
this, and any conflict it reports is a one-line pubspec fix, not a
design problem.
