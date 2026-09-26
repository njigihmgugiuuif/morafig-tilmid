# Track A — Cycle 1 Report (Error / Time Estimation / Workload / Priority-Foundation)

Date: 2026-09-24
Scope requested: Error Engine, Time Estimation Engine, Workload Engine,
Priority Engine foundation — built together in one cycle, per the
FULL-PRODUCT + SHORTEST-BUILD-PATH parallel-track reorganization.

Foundation and Memory Engine (FSRS) were **not** touched, re-read for
changes, or rebuilt — this cycle only added new files on top of them.

## 1. What was actually built

- **Error Engine** — pure Dart, recency-weighted (14-day half-life),
  per-type-weighted (careless < conceptual < missingPrerequisite),
  saturating [0,1) signal from a window of ErrorRecords, plus
  `prerequisiteRiskFlag` / `conceptualRiskFlag` structured flags for the
  future Recovery Engine.
- **Time Estimation Engine** — pure Dart, produces exactly the fields
  TimeEstimates already has columns for (estimate, confidenceLevel,
  confidenceValue, basis = curriculum_default | observed_history |
  hybrid), blending a curriculum default with recency-weighted observed
  durations, confidence built from sample-count + consistency (variance).
- **Workload Engine** — pure Dart, classifies needed-vs-available minutes
  into underload/balanced/overload/impossible via ratio thresholds;
  handles the zero-available edge case explicitly (never throws,
  `ratio` can be `double.infinity`).
- **Priority Engine — foundation layer** — pure Dart signal-merge only
  (6 signal kinds, nullable-signal exclusion + mandatory renormalization
  to sum 1.0, degenerate-weights fallback to defaults, score clamped to
  [0,1], a completeness-based partial confidence value). Deliberately
  NOT wired to Mastery/Memory/ErrorEngine/curriculum/exam-date/reality
  data yet — that wiring is Track D (Integration), by design, so this
  layer is unit-testable as pure signal-merge logic first.
- Matching repositories for all four (Error/TimeEstimation/Workload/
  Priority), following the exact patterns already established by
  `mastery_repository.dart` (recompute-only, "no way to write an
  arbitrary value in" for derived state) and `event_repository.dart` /
  `explanation_and_override_repositories.dart` (append-only, for
  ErrorRecords).
- Property-based test files for all four engines, same style as
  `test/memory_engine_test.dart`.

**Explicitly not done (correctly, per Track D boundary):** wiring these
four engines' inputs to real Mastery/Memory/Curriculum/Reality data, and
wiring PriorityRepository's required `explanationId` to a real generated
Explanation. Both are Track D (Integration) work.

## 2. Files created

```
lib/engines/error_engine.dart
lib/engines/time_estimation_engine.dart
lib/engines/workload_engine.dart
lib/engines/priority_engine.dart
lib/repositories/error_repository.dart
lib/repositories/time_estimation_repository.dart
lib/repositories/workload_repository.dart
lib/repositories/priority_repository.dart
test/error_engine_test.dart
test/time_estimation_engine_test.dart
test/workload_engine_test.dart
test/priority_engine_test.dart
```

No existing file was modified. No schema/table changes were needed —
ErrorRecords, TimeEstimates, WorkloadStates and PriorityStates already
had exactly the columns these engines/repositories needed from the Data
Foundation Schema phase.

## 3. What was actually static-checked (genuinely run, not claimed)

- `tools/check_repository_boundaries.sh` — re-run after adding the new
  repositories. **PASSED** (exit 0): only `lib/repositories/` imports the
  raw Drift table files these new repositories touch.
- Brace/paren/bracket balance — independently scanned per-file with a
  line-by-line stack scanner (not just a raw character count, which gives
  false positives on prose like "[0, 1)" — two such false positives were
  found and fixed by rewording the comments, not the code). All 12 new
  files are now genuinely balanced.
- Manual review of every Companion `.insert()` / update call against each
  table's actual Drift column definitions (nullable vs required, exact
  names) — done by reading `derived_state_tables.dart` directly, not from
  memory of the schema doc.
- `TimeEstimates.basis` and `WorkloadStates.status` string values were
  checked against the exact vocabulary documented in the column comments
  in `derived_state_tables.dart` (snake_case for `basis`, e.g.
  `curriculum_default`, not the engine enum's camelCase `.name`).

## 4. What remains UNVERIFIED

Everything above — like every other line of code in this project so far
— has **not** been run through a real Dart compiler, `dart analyze`, or
`flutter test`. No Flutter/Dart SDK is available in this sandbox. This
is the same standing status as Foundation (STATIC-AUDIT-PASSED /
RUNTIME-UNVERIFIED) and Memory Engine (DEVELOPMENT-COMPLETE /
RUNTIME-UNVERIFIED), extended to these four new components. Nothing here
should be read as "tests passing" — only as "logic manually traced
against the test assertions and found consistent," which is a lower bar
than an actual test run.

The weights/thresholds inside all four engines (recency half-lives,
type-severity weights, workload ratio ceilings, the Priority Engine's
equal-weight default) are INITIAL HEURISTIC values, explicitly labeled as
such in each file's doc comments — same status as the FSRS defaults and
the original w1-w6 discussion. The Priority Engine's default weights are
specifically an equal-weight (1/6 each) placeholder, not a reproduction
of the original w1-w6 values from `algeria-intelligence-final-spec.md`,
because that document's exact numbers were not available to re-read in
this session — re-deriving/confirming them against the real document is
flagged as follow-up, not silently guessed here.

## 5. What can be built in parallel in the next cycle

All of the following are independent of each other and of anything not
yet built, so any subset (or all of them) can go in one cycle:

- **Mastery/BKT Engine** — the repository shell (`mastery_repository.dart`)
  has existed since the Foundation phase; the actual BKT computation was
  never implemented. Independent of this cycle's four engines.
- **Memory/FSRS** — already DEVELOPMENT-COMPLETE, nothing to do here.
- **Track B foundations** (Scheduling / Dynamic Replanning / Recovery /
  Emergency Mode) can begin their own pure-logic layers the same way
  Priority Engine's foundation was built — independent of Track A wiring,
  as long as they consume already-defined result types
  (WorkloadResult, PriorityResult, etc.) rather than raw DB rows.
- **Track C** (Curriculum/Knowledge Graph/Examination/Long-Term-Bac/
  Reality Layer) — these are data-layer/domain concerns independent of
  Track A's engines and can be built in the same cycle as Mastery/BKT or
  Track B foundations.
- **Track D (Integration)** is the one track that does depend on this
  cycle: wiring Priority Engine's six signals to real Mastery/Memory/
  ErrorEngine/curriculum/exam/reality data, and wiring PriorityRepository
  to a real generated Explanation, cannot start until Mastery/BKT exists
  (for `learningPriority`) — so Track D should wait for Mastery/BKT, not
  for Runtime Verification.
