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

## DEVIATION-13 — `app_database.dart` imported `package:drift/native.dart` unconditionally, breaking `flutter build web`

Root cause of the Web build error `Only JS interop members may be
'external'` inside `sqlite3 .../ffi/generated/native.dart`: the
native/web connection split in `connection/connection_stub.dart` was
correct (`if (dart.library.js_interop)` is the right, Wasm-ready
condition and was never the problem), but `app_database.dart` itself
carried a second, unconditional import — `package:drift/native.dart` —
used only to build the `AppDatabase.forTesting()` in-memory factory.
Because `app_database.dart` is part of every build target including
Web, that import (and the sqlite3 FFI bindings it pulls in) was always
compiled for Web too, regardless of the connection split.

Fix: `AppDatabase.forTesting()` removed from `app_database.dart`;
replaced by a standalone `createInMemoryTestDatabase()` function in the
new file `lib/database/testing/in_memory_database.dart`, which is
imported only by files under `test/` and is unreachable from
`main.dart` or any other production/Web code path. `app_database.dart`
now has zero `drift/native.dart` / FFI / sqlite3 dependency.

Still open (separate issue, not part of this fix, and unverifiable in
this sandbox — no network access): DEVIATION-8's `sqlite3.wasm` and
`drift_worker.js` assets are still not present under `web/`. This fix
makes `flutter build web` able to *compile*; the app will still fail
at runtime to open its database in a browser until those two files are
added to `web/` per Drift's web setup guide
(https://drift.simonbinder.eu/platforms/web/).

## DEVIATION-14 — `drift` and `drift_dev` pinned to an exact version (2.34.4) to remove the sqlite3.wasm/drift_worker.js version ambiguity

Root problem: no `pubspec.lock` has ever existed in this project (no
Flutter/Dart SDK or network access has been available in any sandbox
session to run `flutter pub get`), so the *exact* resolved `drift`
version was genuinely unknown — and per drift's own maintainer
guidance, the `sqlite3.wasm`/`drift_worker.js` web assets must come
from a `drift` release at or below your resolved `drift`/`sqlite3`
package versions (upgrading drift without upgrading the assets is
fine; the reverse is not, and the 2.x/3.x `sqlite3` line is a hard
boundary — see https://github.com/simolus3/drift/discussions/3721).

Fix: `drift: ^2.16.0` → `drift: 2.34.4` and `drift_dev: ^2.16.0` →
`drift_dev: 2.34.4` in `pubspec.yaml` (exact pins, no caret). 2.34.4
is a real, released version (confirmed via pub.dev's own analysis log
for that exact version, dated 2026-09-18) that satisfies the original
`^2.16.0` constraint, and every drift release from 2.34.2 onward ships
`sqlite3.wasm` and the worker JS file directly as GitHub release
assets, making them simple to obtain without guessing.

Still requires one manual, one-time step this sandbox cannot perform
(no network access): download `sqlite3.wasm` and the worker JS file
from https://github.com/simolus3/drift/releases/tag/drift-2.34.4
("Assets" section on that page), place `sqlite3.wasm` in `web/` as-is,
and place the worker file in `web/` renamed to exactly `drift_worker.js`
(the name `connection_web.dart` already expects — no code change
needed there). `sqlite3: ^2.4.0` was left unchanged: it already
satisfies drift 2.34.4's own requirement of `sqlite3: ^2.4.0`.

## DEVIATION-15 — `connection.dart` rewritten to fix two real compile errors introduced outside this project's own history

An externally-produced edit introduced `lib/database/connection/connection.dart`
with two independently fatal compile errors, confirmed against this
project's actual files (not assumed):

1. It called a function named `connect()`. No file in this project —
   not `connection_native.dart`, not `connection_web.dart`, not the
   original `connection_stub.dart` — has ever defined a function with
   that name. The real name, in both platform files, has always been
   `openConnection()`.
2. It declared its own top-level `openConnection()` in the same file
   that conditionally imported `connection_native.dart` /
   `connection_web.dart` — both of which already declare a top-level
   `openConnection()` of their own. Importing a library that declares
   a name identical to one already declared in the importing file is
   a duplicate-declaration compile error, independent of bug 1.

A third, related error in the same batch of external edits: `app_database.dart`'s
test factory was rewritten to call `DatabaseConnection.inMemory()` —
confirmed against drift's own published API
(https://drift.simonbinder.eu/api/drift/databaseconnection-class) to
not exist; `DatabaseConnection`'s only constructors are the unnamed
one (taking a `QueryExecutor`), `.delayed(...)`, and
`.fromExecutor(...)`. This is superseded by DEVIATION-13's existing
fix (`createInMemoryTestDatabase()` in
`lib/database/testing/in_memory_database.dart`), which was already
correct and untouched by this fix.

Fix: `connection.dart` rewritten to conditionally import
`connection_native.dart`/`connection_web.dart` with an `as _impl`
prefix, then wrap it as `QueryExecutor openConnection() => _impl.openConnection();`
— the standard Dart pattern for this exact situation, eliminating both
bugs at once. `app_database.dart` now imports `connection/connection.dart`
instead of `connection/connection_stub.dart` (one-line change; the old
`connection_stub.dart` file is left in place, untouched, and simply
unused now — deleting it was out of scope for this fix). No table,
DAO, repository, or test was removed or renamed.

---

## DEVIATION-16 — Sunday-first week, weekly template table (schema v3), and the Weekly Timeline / Gap Detection / Weekly Planner engines (2026-10-02, Phase 2)

**What was added (all additive; nothing removed or renamed):**
- `lib/engines/weekly_timeline_engine.dart` — `WeekCalendar` (Sunday-first week arithmetic), `WeekTimelineEngine` (expand a template into a dated week, build the 7-day timeline, free gaps, hard-block conflicts, planned-vs-actual comparison, plan diff).
- `lib/engines/gap_detection_engine.dart` — time-side Gap Detection (free time, unused-while-backlog, overload, conflicts, insufficient time, unplaced tasks with the scheduler's reason, backlog, deadline/late risk) with Arabic descriptions.
- `lib/engines/weekly_planner.dart` — pure orchestration: study windows − hard fixed blocks → `SchedulingEngine` → timeline → gap findings; `replan()` returns the new plan plus a `ReplanExplanation` (reason, per-task changes, remaining gaps).
- `WeeklyTemplateEntries` table (the 37th table) + `WeeklyTemplateRepository`: the student's recurring weekly template (school timetable, commute, sleep, meals, commitments, extra classes). Rows are user input only (`source` is not settable); the repository validates before writing; **no default timetable is ever created**.
- `schemaVersion` 2 → 3, with an `onUpgrade` branch `if (from < 3) m.createTable(db.weeklyTemplateEntries)`. `export_import_service.dart`'s table-name set gained `weekly_template_entries`; `schema_integrity_test.dart` now expects 37 tables.

**Week convention.** The product decision is "the week starts on Sunday". It is applied as a *boundary/ordering* rule by `WeekCalendar` only. Stored `dayOfWeek` values (both `Availabilities` and `WeeklyTemplateEntries`) keep Dart's native 1 = Monday … 7 = Sunday, which is the convention already adopted in DEVIATION-7, so no existing meaning changes.

**Not done / not claimed (still open):**
- Gap Detection's knowledge-side findings (unstudied or unmastered lessons, weak prerequisites, overdue reviews, repeated errors, neglected subjects) need Mastery/Memory/Error/KnowledgeGraph wiring (integration phase).
- Nothing reads the database into the planner yet beyond `WeeklyTemplateRepository.readSlotsForStudent`; a service will feed the planner from tasks, exams, priorities and availabilities (integration phase). No UI uses these engines yet.
- The v2 → v3 migration is covered by `test/migration_v3_test.dart` (a real file database made to look like v2, reopened with the current code). It has not been run yet; only a GitHub Actions run can confirm it.
- Daily/monthly/yearly planning, Recovery/Emergency wrapping, Workload ceilings and Subject Balance are not part of this batch.

**Status:** UNVERIFIED locally — no Dart/Flutter SDK in the authoring environment. Verified only by the GitHub Actions run of `flutter-test.yml`.

---

## DEVIATION-17 — Phase 1 data model = schema v4; WeekCalendar is the official conversion layer; export format 2 (2026-10-03)

**Why v4, not v3.** Phase 1's data-model additions were planned earlier as "schema v3". Phase 2 then used v3 for `WeeklyTemplateEntries` (DEVIATION-16). Reusing v3 would have meant two different shapes sharing one version number and would have broken the migration chain, so Phase 1 is renumbered **v4**. No requirement was dropped; no dependency version was touched. The chain is now `v1 → v2 → v3 → v4`, one `if (from < N)` branch per step in `migration_strategy.dart`.

**What v4 adds (all additive; nothing removed or renamed):**
- 4 new tables (the 38th–41st), in `lib/database/tables/calendar_and_goal_tables.dart`, every one with `AuditColumns`:
  - `EnergyFocusLogs(studentId, loggedAt, energyLevel, focusLevel)`
  - `AcademicTerms(academicYearId, name, startDate, endDate)`
  - `Holidays(academicYearId, name, startDate, endDate, source='USER_INPUT')`
  - `Goals(studentId, title, subjectId?, targetDate?, status='active')`
- 3 new **nullable** columns: `MasteryStates.confidence` (real), `MasteryStates.observationCount` (int), `Subjects.curriculumVersionId` (FK → `CurriculumVersions`).
- `schemaVersion` 3 → 4; `kMutableStateTables` gained the 4 table names.

**Decisions taken here (documented, not official numbers):**
- Column sets of the 4 new tables were chosen as the minimum consistent with the rest of the schema; nothing beyond what the Phase 1 list names was added.
- `energyLevel` / `focusLevel` use a 1 (lowest) … 5 (highest) integer scale. It is an application-level convention validated by the future writing repository (Workload + Energy phase), not a SQL CHECK (DEVIATION-2).
- The 3 new columns are NULLABLE and old rows get NULL — **NULL means "unknown", never 0 and never an invented value.** Phase 1 only provides the columns; the Mastery phase decides how `confidence` (which is not accuracy) and `observationCount` are computed and written. `MasteryRepository.recomputeFrom` is intentionally unchanged.
- Status vocabularies for `Goals.status` (active | achieved | dropped) are Dart-level, not SQL CHECKs (DEVIATION-2).

**WeekCalendar.** `WeekCalendar` (weekly_timeline_engine.dart) is now the single conversion layer between the stored day number (Dart weekday, 1 = Monday … 7 = Sunday — storage is unchanged, old rows keep their meaning) and the Sunday-first index (Sunday = 0 … Saturday = 6): `indexFromStoredDay`, `storedDayFromIndex`, `storedDayOf`, `storedDayMatches`, `addDays`. `expandTemplate` and `RealityLayerDomainService` (`resolveAvailabilityForDay`, the day loop) use it instead of hand-written `% 7` / `weekday` / `Duration(days: 1)`. Behavior for valid rows is unchanged; an out-of-range stored day was silently ignored before and is still ignored by the Reality Layer (`storedDayMatches` returns false).

**Export / import.**
- Export FORMAT is now `2` (it contains the v4 tables/columns). Import accepts formats `{1, 2}`; a newer or non-integer version is rejected. A format-1 file (written at schema ≤ v3) imports: tables it lacks are skipped, columns it lacks become NULL/default. One consequence worth knowing: for a row that exists locally and is older than the file's row, Last-Write-Wins replaces the whole row, so a v4 value (e.g. a local `confidence`) is replaced by NULL if the older-format file's row wins.
- `importAll` now sets `PRAGMA defer_foreign_keys = ON` inside its transaction. Reason: tables are visited in `allTables` order and rows may reference tables visited later (Students → AcademicYears, and now Subjects → CurriculumVersions). A truly dangling reference still fails at COMMIT and the whole import rolls back. (`restoreReplacingAll` already did this.) This also removes an ordering hazard that existed before v4 for plain `importAll` into an empty database.
- UUID, LWW for mutable tables, append-only union: unchanged.

**Tests.** `test/week_calendar_test.dart`, `test/phase1_v4_test.dart` (new tables, FKs, NULL defaults, export 2, format-1 import, rejection, Reality Layer on the Sunday-first week), `test/migration_v4_test.dart` (v3 → v4 on a real SQLite file), `test/fixtures/legacy_shapes.dart` (helpers that make a fresh DB look like v3/v2). `test/migration_v3_test.dart` was updated: it used to assert `user_version == 3`, which is no longer the end state of a v2 file (it asserts the current `schemaVersion`) and it now builds its "v2 file" through the shared helper. `test/schema_integrity_test.dart` expects 41 tables.

**What the migration tests are and are not.** They emulate an old file (tables dropped, added columns removed by rebuilding the table with only its old columns, `user_version` set). That is not a file that was ever shipped, and the rebuilt tables lose their constraints. They do not replace a test on a real old browser (WASM/IndexedDB) database.

**Not changed:** Weekly Timeline / Gap Detection / Weekly Planner (DEVIATION-16, including the Saturday → Sunday carry-in) are kept as they were. No dependency, workflow or UI file changed.

**Status:** UNVERIFIED — no Dart/Flutter SDK in the authoring environment. Verified only by a GitHub Actions run (build_runner, analyze, tests).

## DEVIATION-18 — Curriculum phase = schema v5; effective status; Knowledge Graph guard (2026-10-04)

**Why this phase.** The Curriculum hierarchy (year → level → stream → subject → unit → lesson → knowledge node → prerequisite, with coefficient, source, effective dates, version and status) already existed in the schema. The two real gaps were (1) no place to record WHICH COUNTRY an edition describes and the edition's label as its source names it, and (2) the guards only looked at a `SubjectLoad`'s own status: an ACTIVE load inside a REPEALED/FROZEN version still leaked its coefficient, and the content graph (subjects/units/lessons/nodes/prerequisites) had no guard at all.

**Schema v5 (additive; nothing removed or renamed).** `CurriculumVersions` gains two NULLABLE columns, `countryCode` and `versionLabel`. No new table. Old rows get NULL = unknown; nothing is pre-filled and no country is defaulted. Migration chain is `v1 → v2 → v3 → v4 → v5`, one `if (from < N)` branch per step. Export FORMAT stays `2` (export is column-generic; a format-2 file written before v5 imports with the two columns NULL, as for any missing column).

**Decisions (documented, not official facts):**
- Effective status = the MOST RESTRICTIVE of the load's status and its version's status (`PolicyStatus.severity`: ACTIVE < UNKNOWN < FROZEN < CONFLICT < REPEALED). Guard #2 behaviour is otherwise unchanged (REPEALED throws, other non-ACTIVE → null).
- Content (subject → unit → lesson → node) takes the status of the version its subject is linked to. A subject linked to no version has no official provenance → UNKNOWN, never ACTIVE. This only affects *official* signals; the student's own content and tasks keep working.
- Guard #1 for versions: `createVersion` / `changeVersionStatus` refuse ACTIVE unless the source `PolicyDocument` is `primaryVerified` or `secondaryConfirmed`; REPEALED is terminal. (Rows inserted directly, as the test seed does, bypass this by design — repositories are the choke point.)
- `getUsableCoefficient(..., asOf:)`: when `asOf` is given, a version not yet effective or already ended yields null; a version with NO dates is never expired by inference. Without `asOf`, behaviour is as before.
- Knowledge Graph: `KnowledgeGraphDomainService` now REQUIRES a `CurriculumRepository`. A hard prerequisite edge with `relationType = official` is consumed only if its node's effective status is ACTIVE; otherwise it is EXCLUDED and REPORTED in `PrerequisiteSatisfactionResult.ignoredEdges` (not thrown — one stale official edge must not break scheduling for the whole student). `derived` / `proposed` edges are the student's / engineering's own and are consumed as before. Transitive closure is still follow-up.
- «الأولوية» (priority) is NOT stored as a curriculum column: it is computed by the Priority Engine from the official coefficient, `isExaminable`, and the other signals, merged once. Storing one would invent an official-looking number. Awaiting the owner's decision.
- Country/label/dates are never seeded. No official Algerian value was added anywhere; anything undocumented stays UNKNOWN.

**New API (CurriculumRepository):** `createVersion`, `changeVersionStatus`, `ingestSubject`, `linkSubjectToVersion`, `effectiveStatusForSubject / ForNode / ForSubjectLoad`, `readTreeForVersion`, static `windowStateOf`, `normalizeCountryCode`, `normalizeLabel`.

**Tests.** `test/curriculum_system_test.dart` (new), `test/migration_v5_test.dart` (new, real SQLite file). `test/fixtures/legacy_shapes.dart` gained `makeLookLikeV4` (and `makeLookLikeV3` now goes through it). `test/migration_v4_test.dart`: the single assertion on the current schema version changed 4 → 5 (the schema is now v5); the v3 → v4 data checks are untouched. No test was removed.

**Not changed:** UI, Student, Mastery, Memory, Weekly Timeline, Gap Detection, Scheduling, dependencies, workflows.

**Status:** UNVERIFIED — no Dart/Flutter SDK in the authoring environment. Verified only by a GitHub Actions run (build_runner, analyze, tests).

## DEVIATION-19 — Student Integration phase = schema v6; Student → Core gate (2026-10-04)

**Why this phase.** The student row only knew its name, its academic year and its sleep floor. It had no place to say which education level / stream the student is in, nor which `CurriculumVersion` they follow, so the Core could not tell *which* curriculum belongs to *this* student, and several services read `students` directly.

**Schema v6 (additive; nothing removed or renamed).** `Students` gains three NULLABLE foreign keys: `educationLevelId → EducationLevels`, `streamId → Streams`, `curriculumVersionId → CurriculumVersions`. Old rows get NULL = unknown; nothing is pre-filled. Migration chain is `v1 → … → v5 → v6`, one `if (from < 6)` branch with three `addColumn`. Export FORMAT stays `2` (column-generic). No other table changed.

**Decisions (documented, not official facts):**
- `StudentRepository` is the single door to student data for the Core: `readProfile`, `setAcademicTrack` (stream must belong to the level; omitting the stream clears it), `setCurrentAcademicYear` (unlinks the curriculum version if it belongs to another year), `setCurriculumVersion` (refuses a missing version, a version of another academic year, and any version whose status is not ACTIVE — `PolicyDataGuardViolation`), `clearCurriculumVersion`.
- `StudentContextService` (domain) answers "may the Core consume the student's curriculum?": not linked / version missing / version from another year → UNKNOWN; otherwise the version's status; effective dates are checked only when `asOf` is given. `usableCurriculumVersionId` returns null unless ACTIVE (and inside its window); REPEALED throws, as in Guard #2. A version existing in the DB is therefore never enough on its own.
- A link is accepted only when the version is ACTIVE *now*; if the version is later frozen/repealed the stored link stays, but the gate stops the Core from using it (the status is read live, not copied).
- `ContentRepository.getOrCreateDefaultLevel` prefers the student's own level; it also no longer crashes when more than one level exists (it used `getSingleOrNull`).
- `IntelligenceService` reads the student through `StudentRepository` instead of `students` directly.

**Linked now:** student ↔ academic year ↔ level ↔ stream ↔ curriculum version (gated); default level for new content; Mastery/Memory/Priority keep working for a student with a full profile.

**Gaps (not invented, left for later phases):** `officialCoefficient` / `learningPriority` / `urgencyImportance` priority signals stay null (wiring needs a verified normalisation ceiling and SubjectLoad data); no UI captures level/stream/version (onboarding unchanged); Knowledge Graph does not yet check that an official edge's node belongs to the student's own version; Exams stay global (not per level); `AppState` bootstrap still reads `students` directly (UI-state layer untouched).

**Tests.** `test/student_integration_test.dart` (new), `test/migration_v6_test.dart` (new, real SQLite file). `legacy_shapes.dart` gained `makeLookLikeV5` (v4/v3/v2 chain goes through it). `migration_v4_test.dart` / `migration_v5_test.dart`: schema-version assertions now compare with `db.schemaVersion` and `>= 5`. No test removed.

**Not changed:** UI, Curriculum v5 logic, Weekly Timeline, Gap Detection, Scheduling, dependencies, workflows, `pubspec.yaml`.

**Status:** UNVERIFIED — no Dart/Flutter SDK in the authoring environment. Verified only by a GitHub Actions run (build_runner, analyze, tests).

## DEVIATION-20 — A-0: Priority signals aligned with the approved spec (2026-10-05)

**Why.** The first foundation layer named and weighted the six Priority signals differently from the approved final intelligence spec: it stored the mastery gap (1 - mastery) under `personalWeakness`, kept an unused `learningPriority` in the sixth slot instead of long-term-goal alignment, and used a 1/6 equal-weight placeholder.

**Changes (no schema change, no migration).**
- Signal names: `personalWeakness` -> `masteryGap`, `examPriority` -> `examProximity`, `urgencyImportance` -> `deadlinePressure`, `learningPriority` -> `longTermGoalAlignment`. `forgettingRisk` and `officialCoefficient` keep their names.
- `PriorityWeights.defaults()`: masteryGap 0.30, forgettingRisk 0.20, officialCoefficient 0.20, examProximity 0.15, deadlinePressure 0.10, longTermGoalAlignment 0.05 (sum 1.0). These are the spec's INITIAL values, not official facts.
- `legacyPrioritySignalNames`, `canonicalPrioritySignalName`, `prioritySignalKindFromStoredName` (priority_engine.dart): readers understand both generations of stored names.
- The error pattern is not a Priority signal (comments in error_engine.dart corrected).

**Existing records.** `Explanations` (append-only) and old `factorsJson` / `excludedFactorsJson` / `dominantFactor` keep their original names and are never rewritten. `PriorityStates` rows are derived and are recomputed with the new names and weights on the next processing run. Old backups import unchanged (the JSON text is carried verbatim). Old scores are not comparable with new ones because the weights changed.

**Open items (not invented).** (1) The spec's AMPLIFIED forgetting formula is not in the repository, so `forgettingRisk` is still 1 - retrievability under its old name. (2) Calibration bounds for w2..w6 are not in the repository. (3) `deadlinePressure` needs a task deadline source (to verify in A-1). (4) `longTermGoalAlignment` needs a goal source (Goals repository does not exist yet).

**Tests.** `priority_engine_test.dart`, `emergency_engine_test.dart`, `intelligence_service_test.dart` renamed to the new names; new A-0 group in `priority_engine_test.dart` (exact default weights, exact name set, renormalisation of three live signals, legacy-name mapping). No test removed.

**Not changed:** UI (including `priorities_screen.dart`), schema, migrations, pubspec, workflows, other engines' logic.

**Status:** UNVERIFIED — no Dart/Flutter SDK in the authoring environment. Verified only by a GitHub Actions run.

## DEVIATION-21 — A-1: officialCoefficient and deadlinePressure wired to real sources (2026-10-06)

**Why.** After A-0 the Priority Engine had six correctly named signals, but `officialCoefficient` and `deadlinePressure` were hard-wired to null although the schema already holds their sources. A-1 wires them to those sources and to nothing else. It adds no schema, no writer and no UI.

**officialCoefficient.**
- Source: `SubjectLoads.coefficient`, read ONLY through `CurriculumRepository.getUsableCoefficient` (Guard #2, unchanged). The student's curriculum is taken from `StudentContextService` (it already refuses UNKNOWN / CONFLICT / FROZEN / REPEALED, stale and out-of-window versions) and the student's `streamId`.
- Normalisation (an ENGINEERING DESIGN decision approved by the owner, not an official rule): the subject's coefficient divided by the highest usable coefficient among loads of the SAME stream and the SAME curriculum version. No coefficient value or ceiling is embedded anywhere.
- Safeguards (approved): fewer than 2 usable loads (> 0) in the stream -> null; loads without a stream never take part; more than one load matching the subject in that stream -> null (ambiguous); own coefficient null or <= 0 -> null.
- A REPEALED load is caught PER LOAD and treated as null for this signal only, so one withdrawn row cannot stop the priority refresh of every task. The direct read `getUsableCoefficient` still throws for REPEALED, exactly as before.
- New API: `CurriculumRepository.readLoadsForVersionAndStream` (read-only; rows are raw, coefficients must still pass the guard), `CurriculumDomainService.normalizeAgainstStreamMax` (pure), `CurriculumDomainService.officialCoefficientSignalForSubject`, constant `minimumUsableLoads = 2`. The existing `normalizeCoefficient` / `officialCoefficientSignal` are untouched.
- Real-data reality: the repository contains no official coefficient and no screen to enter one, so in the live app this signal stays null until a documented curriculum version is created, linked to the student and given loads with a stream. Nothing is seeded.

**deadlinePressure.**
- Sources (read-only, nothing else): `Deadlines` rows of type 'Task' for the task; `Deadlines` rows of type 'Assignment' and `Assignments.dueDate` for the task's `sourceAssignmentId`. 'Exam' deadlines are NOT read (examProximity owns exam dates; reading them twice would double-count). Hard and soft deadlines both count; Recovery's separate `hoursUntilHardDeadline` input is untouched.
- Formula (INITIAL HEURISTIC approved by the owner, NOT an official rule): linear ramp `1 - days / 21`, 0.0 at 21 days or more; a due date that has passed on a task that is still open -> 1.0; no due date -> null (never 0). With several due dates the highest pressure decides.
- New: `DeadlineRepository.readDueDatesForTask` (read-only), `DeadlineDomainService` (`deadlinePressureSignal` pure, `pressureForTask`, `defaultHorizonDays = 21`).
- Real-data reality: nothing in the app writes Deadlines or Assignments and `TaskRepository.createTask` accepts no due date, so for real users this signal is null until a later phase adds a writer. Not added here.

**longTermGoalAlignment — OPEN DECISION, stays null.** The `Goals` table exists (schema v4) but there is no repository, no writer, no UI, and no approved definition of "alignment" (how a goal becomes a number). Inventing a formula or a Goals repository is out of scope. To open it, the owner must approve (1) the definition of alignment and (2) the source/UI that writes goals (the first-goal onboarding step of the D-1 design belongs to phase E).

**Existing records.** No schema change and no migration (`schemaVersion` stays 6). Explanations (append-only) are never rewritten; PriorityStates are derived and are recomputed on the next processing run, so scores of tasks that now have these signals can change. A-0 weights are untouched; unknown signals are still excluded and the remaining weights renormalised.

**Tests.** `test/curriculum_domain_test.dart` (new pure group), `test/official_coefficient_signal_test.dart` (new, database), `test/deadline_domain_test.dart` (new, pure and database), `test/intelligence_service_test.dart` (new A-1 group). No test removed or weakened.

**Not changed:** UI, schema, migrations, pubspec, workflows, A-0 weights, `forgettingRisk` (amplified-forgetting formula still not in the repository), Error / Time / Workload / Energy wiring, Human Override, Goals, every earlier guard.

**Status:** UNVERIFIED — no Dart/Flutter SDK in the authoring environment. Verified only by a GitHub Actions run.
