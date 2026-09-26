# Cycle 2 — Parallel Build Report (Mastery/BKT, Track B foundations, Track C domain layer)

Date: 2026-09-24/25
Scope: everything requested in this cycle's instructions, built together —
Mastery Engine (real BKT), Scheduling/Dynamic-Replanning/Recovery/Emergency
foundations (Track B), and Curriculum/Knowledge-Graph/Examination/
Long-Term-Bac/Reality-Layer domain layers (Track C).

Foundation, Memory Engine, and every Cycle 1 component (Error/
TimeEstimation/Workload/Priority-foundation) were **not** rebuilt,
redesigned, or re-verified against Runtime — this cycle only reads them
where genuinely needed (e.g. WorkloadClassification, PriorityWeights) and
adds new files on top.

## 1. What was actually built

**Track A — Mastery Engine**
- `mastery_engine.dart`: real two-step BKT (Bayesian evidence update, then
  learning-transition step), pure Dart. P(L)/P(T)/P(G)/P(S) kept as
  separate, named parameters (`BktParameters`), never conflated. Confidence
  is returned as a field **separate** from the probability (accuracy) —
  driven purely by `observationCount`, so two runs can land on the exact
  same probability with different confidence, per this cycle's explicit
  requirement. No direct MasteryState writes — the engine returns a
  result; `mastery_repository.dart` (already existed, unmodified) remains
  the only write path via `recomputeFrom`.

**Track B — decision-logic foundations (no UI, no DB writes)**
- `scheduling_engine.dart`: fits priority-ordered items into caller-supplied
  free `TimeSlot`s. Atomic and splittable tasks are structurally distinct
  types throughout (an atomic task is never fragmented, a splittable task
  respects `minimumChunkDurationMinutes`/`maximumChunkDurationMinutes`).
  Items that don't fit go to `unscheduledQueue` with an explicit
  `UnscheduledReason` (`noSlotAvailable` / `partiallyScheduled` /
  `prerequisiteNotSatisfied`) — nothing is ever silently dropped. Priority
  only controls placement order; it never overrides a failed prerequisite
  check.
- `dynamic_replanning_engine.dart`: decides ONLY whether to replan, with a
  hysteresis band on `durationDeviation` (small overruns don't thrash the
  schedule) while missed sessions / new unavailability / workload-status
  changes / manual requests always trigger.
- `recovery_engine.dart`: per-task decision table over the six
  RecoveryDecision outcomes (keep/move/merge/defer/dropTemporarily/replan,
  matching `RecoveryRecords.decision`'s documented vocabulary exactly).
  Explicitly NOT a blanket "move everything to tomorrow" — two tasks
  missed at the same instant, differing only in priority, can land on two
  different decisions (asserted directly in the test suite). Always
  returns a `reasoning` string.
- `emergency_engine.dart`: detects `examProximity`/`workloadImpossible`
  (matching `EmergencyStates.triggerReason`'s vocabulary), and only ever
  returns adjusted **weights** (via `priority_engine.dart`'s own
  renormalization — not duplicated here) or adjusted **ratio ceilings**
  (via a new `WorkloadEngine` instance). It has no access to sleep-floor
  or prerequisite logic at all, so it cannot violate either — by
  architecture, not by a runtime check.

**Track C — domain layer (Curriculum/Knowledge-Graph/Examination/
Long-Term-Bac/Reality-Layer)**
- `curriculum_domain.dart`: normalizes `CurriculumRepository`'s raw
  coefficient into the `officialCoefficient` [0,1] Priority signal. Does
  NOT duplicate `CurriculumRepository` (already the single choke point).
  `maxPlausibleCoefficient` is a REQUIRED caller-supplied parameter with
  no default — no unverified Algerian coefficient ceiling is embedded as
  fact.
- `knowledge_graph_domain.dart`: turns real Prerequisites edges +
  MasteryState rows into the `prerequisiteSatisfied` boolean
  `scheduling_engine.dart` needs. Direct (one-edge) hard prerequisites
  only this cycle — transitive closure flagged as follow-up. An
  unobserved prerequisite (no MasteryState row) is treated as NOT
  satisfied, never defaulted to satisfied.
- `examination_domain.dart`: `daysUntilNearestExam` (feeds
  `emergency_engine.dart`) and `examPrioritySignal` (feeds
  `priority_engine.dart`'s examPriority signal), linear ramp over a
  configurable horizon.
- `long_term_domain.dart`: purely structural time-horizon classification
  (`immediate`/`thisMonth`/`thisTerm`/`fullYear`) and a schema-level
  (`examType == 'bac'`) check — deliberately embeds NO unverified official
  Algerian Bac weighting/coefficient facts, per this cycle's explicit
  rule.
- `reality_layer_domain.dart`: resolves Availabilities into per-day
  windows (a specificDate row overrides recurring rows for that day, never
  merged), then subtracts every **hard** RealityConstraint (sleep
  included, with no type-specific carve-out) via real interval-subtraction
  math, producing the free `TimeSlot`s `scheduling_engine.dart` consumes.
  **This is where "never break minimum sleep" is actually enforced** for
  the whole pipeline — `scheduling_engine.dart`'s own doc comment
  explicitly defers to this file rather than re-checking the same thing
  under a different name.

**Supporting repositories added** (no schema/table changes — all four
tables already existed from Foundation): `exam_repository.dart`,
`availability_repository.dart`, `recovery_repository.dart` (append-only,
mirrors `error_repository.dart`), `emergency_repository.dart` (enforces
the "at most one active EmergencyState per student" invariant the table's
own doc comment already called out as this repository's job). Also added
`PrerequisiteRepository.readDirectHardPrerequisites()` — one small method
on an existing repository, not a new table.

## 2. Files created / modified

New:
```
lib/engines/mastery_engine.dart
lib/engines/scheduling_engine.dart
lib/engines/dynamic_replanning_engine.dart
lib/engines/recovery_engine.dart
lib/engines/emergency_engine.dart
lib/repositories/exam_repository.dart
lib/repositories/availability_repository.dart
lib/repositories/recovery_repository.dart
lib/repositories/emergency_repository.dart
lib/domain/curriculum_domain.dart
lib/domain/knowledge_graph_domain.dart
lib/domain/examination_domain.dart
lib/domain/long_term_domain.dart
lib/domain/reality_layer_domain.dart
test/mastery_engine_test.dart
test/scheduling_engine_test.dart
test/dynamic_replanning_engine_test.dart
test/recovery_engine_test.dart
test/emergency_engine_test.dart
test/curriculum_domain_test.dart
test/examination_domain_test.dart
test/long_term_domain_test.dart
test/reality_layer_domain_test.dart
```

Modified (small, additive only):
```
lib/repositories/reality_and_prerequisite_repositories.dart
  — added readDirectHardPrerequisites() to PrerequisiteRepository.
DEVIATIONS.md
  — added DEVIATION-7 (see §4).
```

Nothing else was touched. `mastery_repository.dart`, all Cycle 1 files,
Foundation, and Memory Engine are byte-for-byte unchanged.

## 3. Dependencies that became ready this cycle

- Priority Engine's `learningPriority` and `examPriority` signals can now
  be sourced from real data (`mastery_engine.dart` + `mastery_repository
  .dart` for the former, `examination_domain.dart` for the latter) —
  previously only `curriculum_domain.dart`'s `officialCoefficient` was
  ready (from Cycle 1's Priority foundation + this cycle's Curriculum
  domain).
- `scheduling_engine.dart` can now be fed real `TimeSlot`s
  (`reality_layer_domain.dart`) and real `prerequisiteSatisfied` flags
  (`knowledge_graph_domain.dart`) — it no longer only accepts
  hand-constructed test data.
- `recovery_engine.dart` and `emergency_engine.dart` both consume
  `WorkloadClassification` from Cycle 1's `workload_engine.dart` directly
  — that wiring already works today, no Track D step needed for it
  specifically.
- Track D (Integration) can now start wiring Priority Engine's six
  signals end-to-end, since Mastery/BKT (the last missing signal source)
  exists.

## 4. Deviations

**DEVIATION-7** (full text in `DEVIATIONS.md`): `Availabilities.dayOfWeek`
had no documented day-numbering convention. Adopted Dart's native
`DateTime.weekday` (1=Monday..7=Sunday) in `reality_layer_domain.dart`,
flagged explicitly as a one-line fix if the originally-intended convention
turns out to differ. No schema/table change.

No schema changes were needed this cycle — every table this cycle's code
touches (ErrorRecords, TimeEstimates, WorkloadStates, PriorityStates from
Cycle 1; RecoveryRecords, EmergencyStates, Exams, Availabilities,
RealityConstraints, Prerequisites, MasteryStates this cycle) already
existed with the right columns from the Foundation/Cycle-1 phases.

## 5. Static checks actually run (not claimed)

- `tools/check_repository_boundaries.sh` — re-run after every new
  repository file. **PASSED** (exit 0) at the end of the cycle.
- Independent per-line bracket-balance scan (not a raw character count —
  see Cycle 1's report for why that gives false positives) across every
  new/modified `lib/` and `test/` file. Found and fixed 3 false-positive
  mismatches this cycle, all caused by half-open-interval notation like
  `[cutStart, cutEnd)` in prose doc comments (in `reality_layer_domain
  .dart` ×2 and `scheduling_engine.dart` ×1) — reworded to plain English,
  not touching any actual code logic. All new/modified files now
  genuinely balanced. (One PRE-EXISTING instance of the same
  false-positive pattern was found in `test/memory_engine_test.dart`,
  left untouched since Memory Engine and its tests are explicitly out of
  scope for this cycle — noted here rather than silently fixed.)
- Every new Companion `.insert()`/update call was checked by hand against
  the actual Drift column definitions in `derived_state_tables.dart` /
  `planning_tables.dart` (required vs nullable, exact enum-string
  vocabulary per column comment — e.g. `RecoveryDecisionKind.name` /
  `EmergencyTriggerKind.name` were verified to match
  `RecoveryDecision`/`EmergencyTrigger`'s DB vocabulary exactly).
- Every pure/static method that does not require a database (the bulk of
  Track A/B, plus the normalization/classification pieces of Track C —
  `CurriculumDomainService.normalizeCoefficient`,
  `ExaminationDomainService.examPrioritySignal`,
  `LongTermDomainService.classifyHorizon`,
  `RealityLayerDomainService.subtractOne`/`isSameDate`) was refactored to
  be `static` specifically so it has a real, traceable property/invariant
  test — this is a genuine design choice made *for* testability this
  cycle, not just a claim.

Classification: **VERIFIED-STATIC** for the two checks above (boundary
script, bracket balance) — these were genuinely executed with a real
tool/script and produced a real pass/fail result. Everything else
(whether the Dart itself compiles, whether the tests actually pass) is
**RUNTIME-UNVERIFIED** — see §6.

## 6. What remains RUNTIME-UNVERIFIED

Everything in this cycle, and every prior cycle, has not been run through
`dart analyze`, `dart test`, or `flutter test` — no Flutter/Dart SDK is
available in this sandbox. This includes:
- Whether every file in §2 actually compiles (manual review only, no
  compiler).
- Whether the ~90 new test assertions across the 9 new test files
  actually pass (each was hand-traced against the implementation's logic
  while writing it, not executed).
- The DB-dependent halves of `knowledge_graph_domain.dart`,
  `reality_layer_domain.dart`'s `computeFreeSlots`,
  `curriculum_domain.dart`'s `officialCoefficientSignal`,
  `examination_domain.dart`'s `daysUntilNearestExam`, and
  `long_term_domain.dart`'s `hasUpcomingBacExam` are **entirely
  untested even at the property level** this cycle — they require a real
  (or in-memory) Drift database via `build_runner` codegen, which this
  sandbox cannot run. Only their pure/static halves have tests. This is a
  real gap, not glossed over: a Track E (or earlier) task should stand up
  an in-memory-DB test harness once a real Dart environment is available,
  since no repository-layer test exists anywhere in this codebase yet
  (Cycle 1 and Cycle 2 both).

INITIAL HEURISTIC values introduced this cycle (all explicitly labeled as
such in their own files, not new territory): BKT's `P(T)=0.1, P(G)=0.2,
P(S)=0.1, P(L0)=0.3`; Mastery confidence's saturation constant (5.0);
Dynamic Replanning's duration-deviation threshold (15 min); Recovery's
priority/deadline thresholds (0.7 / 0.3 / 24h); Emergency Mode's exam
proximity window (3 days) and boost/loosen multipliers; Examination's
urgency horizon (21 days); Long-Term's horizon-bucket day counts
(7/30/120); Scheduling's default minimum chunk (15 min). None of these
are calibrated against real student data — all are follow-up work for
Track E (Calibration/Simulation), same status as Cycle 1's constants.

## 7. What can be built in parallel next cycle

- **Track D (Integration)** is now unblocked end-to-end for Priority: wire
  `curriculum_domain.dart` + `mastery_engine.dart`/`mastery_repository
  .dart` + `error_engine.dart`/`error_repository.dart` (Cycle 1) +
  `memory_engine.dart` (retrievability) + `examination_domain.dart` into
  real `PrioritySignals`, then `priority_repository.dart` (Cycle 1) with a
  real generated Explanation.
- **Track D**: wire `scheduling_engine.dart` to real `SchedulableItem`s
  (from Tasks + `priority_repository.dart` scores +
  `knowledge_graph_domain.dart`) and real `TimeSlot`s
  (`reality_layer_domain.dart`), producing real `StudySessions` rows —
  independent of the Priority wiring above, can happen in the same cycle.
- **Track D**: wire `dynamic_replanning_engine.dart` to real
  `StudySessions`/`RealityConstraints` change events, and
  `recovery_engine.dart`/`emergency_engine.dart` to
  `recovery_repository.dart`/`emergency_repository.dart` (both built this
  cycle, unused until wired).
- **Track E (can start independently of Track D)**: stand up an
  in-memory-DB (`NativeDatabase.memory()`) test harness and actually run
  every existing test file once a real Dart/Flutter SDK is available —
  this closes the single biggest gap this report calls out in §6, and
  does not require Track D to be finished first.
- Full transitive-closure prerequisite checking in
  `knowledge_graph_domain.dart` (currently direct-only) can be built
  independently of everything else in this list.
