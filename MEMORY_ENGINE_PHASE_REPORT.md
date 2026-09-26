# PHASE REPORT — Memory Engine (FSRS)

Policy in effect: development continues without blocking on Flutter/Dart
availability; nothing below is claimed as running or passing — only as
written and reviewed. Foundation baseline (Static Audit PASSED, Runtime
Verification NOT EXECUTED, VERIFIED=NO) is unchanged and referenced, not
re-litigated.

## 1. What was built

The **Memory Engine** — the FSRS-4.5 (Difficulty/Stability/Retrievability)
spaced-repetition algorithm — per the Dependency Graph position agreed in
the build-ready plan ("Mastery/Memory/Error engines, buildable in parallel
right after the Data Foundation"). This phase covers Memory only; Mastery
already has its repository shell from the Foundation phase (recompute-only
pattern, BKT integration itself still pending); Error Engine is next.

- `lib/engines/memory_engine.dart` — pure, dependency-free FSRS-4.5 math
  (retrievability, interval-for-desired-retention, initial state, stability
  update on success/failure, difficulty update with mean-reversion).
  Formulas transcribed from the public FSRS-4.5 specification, cross-checked
  against a reference implementation with full source
  (https://borretti.me/article/implementing-fsrs-in-100-lines, itself
  citing the official fsrs4anki wiki). No Drift/Flutter import — testable
  in complete isolation.
- `lib/repositories/memory_repository.dart` — recompute-only wrapper,
  mirroring `MasteryRepository`'s pattern exactly (no
  `writeStability(...)` method; the only mutation path is
  `recomputeFrom(Event)`, driven by a `MemoryReviewCompleted` event's
  payload).
- `test/memory_engine_test.dart` — property-based unit tests (14 test
  cases) checking invariants the formulas must satisfy (R(0,S)=1,
  monotonic decay, interval(0.9,S)=S by definition, difficulty stays in
  [1,10] under a long mixed-grade sequence, forgetting never increases
  stability, etc.) — not hand-computed numeric oracles, since I have no
  way to execute Dart here to confirm exact numbers against a reference
  run.

## 2. A real gap found during this phase, and the fix (DEVIATION-6)

`MemoryStates` (as designed in the Data Foundation Schema, v1) had no
column for Difficulty — only stability, retrievability, and
nextReviewDate. FSRS's DSR model requires D to persist across reviews; it
is not derivable from S or R alone. This is a genuine implementation-time
finding, not a redesign-for-convenience.

Fix (smallest safe addition, following the project's own documented
migration policy):
- `lib/database/tables/derived_state_tables.dart`: added
  `difficulty` (nullable `RealColumn`) and `lastUpdatedFromEventId`
  (nullable, references `Events` — for the same audit-traceability
  `MasteryStates` already has) to `MemoryStates`.
- `lib/database/app_database.dart`: `schemaVersion` 1 → 2.
- `lib/database/migrations/migration_strategy.dart`: added the `from < 2`
  `onUpgrade` branch (`addColumn` × 2 — additive only, no data
  transform, no existing rows to migrate since v1 was never released).
- `DEVIATIONS.md`: DEVIATION-6, documenting all of the above.

No table removed/renamed, no other schema element touched, no feature
scope changed.

## 3. What was actually verified (vs. reviewed only)

Actually checked, without needing Dart:
- Brace/paren balance on all 6 touched/created files — verified with a
  string-literal-aware parser this time (the earlier naive grep-based
  check used elsewhere in this project gives false positives on files
  whose string literals contain parentheses, which this test file's
  descriptions do — confirmed by rechecking properly). Result: balanced
  on all 6 files.
- Cross-referenced every identifier the new code uses against the
  existing codebase's own conventions rather than assuming Drift's
  behavior: confirmed `Event` (not `Events`) is the actual generated data
  class name by reading `event_repository.dart`'s own existing, working
  code; confirmed the `_db.memoryStates` / `MemoryStatesCompanion`
  naming convention matches `MasteryRepository`'s already-established,
  identical pattern.
- Caught and fixed one real bug myself on review: an early draft of
  `test/memory_engine_test.dart` used a wrong named parameter
  (`s:` instead of `stability:`) that would have failed to compile —
  found by rereading the method signature against the test calls, fixed
  before this report.

NOT verified (needs a real Flutter/Dart run — same standing limitation as
the whole codebase):
- That the FSRS formulas were transcribed correctly (the source is
  authoritative, but transcription errors are still possible and only a
  real test run proves otherwise).
- That the migration actually applies cleanly to a real database.
- That `dart analyze` finds no type errors.
- All 14 test cases actually passing.

## 4. Files created/modified this phase

Created:
- `lib/engines/memory_engine.dart`
- `lib/repositories/memory_repository.dart`
- `test/memory_engine_test.dart`
- `MEMORY_ENGINE_PHASE_REPORT.md` (this file)

Modified:
- `lib/database/tables/derived_state_tables.dart` (MemoryStates: +2 columns)
- `lib/database/app_database.dart` (schemaVersion 1→2)
- `lib/database/migrations/migration_strategy.dart` (+v2 upgrade branch)
- `DEVIATIONS.md` (+DEVIATION-6)

## 5. Next step

Error Engine next (per the same parallel-buildable group as Mastery/Memory
in the Dependency Graph), then wiring Mastery's BKT computation itself
(the repository shell existed since the Foundation phase, but the actual
BKT math was never implemented — same situation Memory was in before this
phase). All of it stays UNVERIFIED until the single real Windows 11
Flutter/Dart verification pass you're planning at the end of this
development stretch.
