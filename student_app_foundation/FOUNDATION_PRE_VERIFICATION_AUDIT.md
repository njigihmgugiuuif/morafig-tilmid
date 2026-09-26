# FOUNDATION PRE-VERIFICATION AUDIT (Static-Only, No Flutter/Dart)

Scope: `student_app_foundation.zip`, as uploaded. No file was modified. No
feature added or removed. No Engine or UI started. No claim of Build or
Tests passing is made anywhere below.

---

## 1. What Was Actually Checked

Extracted and read all 30 files in the archive (24 `.dart` files + `pubspec.yaml`
+ `analysis_options.yaml` + 3 `.md` reports + 1 shell script), specifically:

- **pubspec.yaml**: dependency list, SDK constraints, package name.
- **Every import statement** in `lib/` and `test/` (cross-referenced against
  actual file paths and the package name).
- **All 6 Drift table files** (`core`, `curriculum`, `planning`,
  `derived_state`, `audit`, `config`): every table class, every column, every
  `.references()` foreign key target.
- **`app_database.dart`**: the `@DriftDatabase(tables: [...])` registration
  list, cross-checked 1:1 against every `class X extends Table` definition
  found in the 6 table files.
- **All 6 repository files**: method signatures, which tables/columns they
  touch, cross-checked against the table definitions.
- **`validators.dart`**, **`enums.dart`**, **`event_types.dart`**,
  **`export_import_service.dart`**, **`migration_strategy.dart`**.
- **All 5 test files + `fixtures/seed_data.dart`**: what each test actually
  asserts, and whether the code paths it exercises exist and are shaped the
  way the test expects.
- **`FOUNDATION_IMPLEMENTATION_REPORT.md`**, **`SOURCE_OF_TRUTH.md`**,
  **`DEVIATIONS.md`**: cross-checked their claims against the actual code
  (file lists, table counts, "future phase" disclosures).
- **`tools/check_repository_boundaries.sh`**: this one I could and did
  actually **execute** (it's a POSIX shell script, no Dart/Flutter needed).
- Independently re-verified, with my own tooling, the previous session's
  claim of balanced braces/parens across all 24 `.dart` files.

## 2. What Could NOT Be Checked (needs Flutter/Dart)

- Real compilation (`dart analyze`).
- Drift code generation (`build_runner`) — no `*.g.dart` files exist yet;
  this is expected/normal pre-generation, not a defect.
- Whether every Drift API call (`insertReturning`, `Companion.insert`,
  `TableInfo`, etc.) matches the exact method signatures of drift `^2.16.0`
  — I reasoned about this from documented Drift conventions, which is not
  the same as a compiler confirming it.
- Whether `flutter test` actually passes for any of the 5 test files.
- **Whether the Export/Import JSON-key-casing concern below is a real bug**
  — this is the single highest-priority thing to check first once
  Flutter/Dart is available, because if it is real it fails Test Category E
  entirely.

## 3. tools/check_repository_boundaries.sh — Actually Run, Not Just Read

```
$ sh tools/check_repository_boundaries.sh
Checking append-only table access boundary...
Checking curriculum/policy table access boundary...
OK: repository access boundaries respected.
$ echo $?
0
```
Passed. This re-confirms DEVIATIONS.md's account of the earlier fix.

## 4. Structural Cross-Check Results (Positive)

- **36/36 table classes** registered in `@DriftDatabase(tables: [...])`
  match exactly the 36 `class X extends Table` definitions across the 6
  table files — no table missing, none extra, none misspelled.
- **Every `.references(Target, #id)` foreign key** points at a table class
  that exists and is properly imported into the file that declares the
  reference.
- **Every table file's imports** resolve to files that exist in the archive;
  no dangling/broken relative import found anywhere in `lib/` or `test/`.
- **Test imports** all use `package:student_app/...`, consistent with
  `pubspec.yaml`'s `name: student_app`.
- **Brace/paren balance**: independently re-checked across all 24 `.dart`
  files — balanced, confirming the previous session's claim.
- **No files referenced by `pubspec.yaml` or by any import are missing**
  from the archive.

## 5. Real Issues Found (Static-Review-Provable)

### 5.1 — HIGH PRIORITY: likely Export/Import JSON key-casing mismatch

`export_import_service.dart`'s `exportAll()` produces each row's JSON via
Drift's generated `.toJson()`, and no `build.yaml` exists anywhere in the
archive to configure JSON key casing (no `@JsonKey`/`@UseRowClass` either).
Absent that configuration, Drift's default `toJson()` uses the **Dart field
names** as JSON keys — i.e. camelCase (`updatedAt`, `createdAt`,
`syncVersion`), not the snake_case SQL column names.

But `_mergeMutableRow()` explicitly reads `row['updated_at']` (snake_case)
to decide Last-Write-Wins and to detect a malformed row — and would treat
that key as absent for essentially every mutable-state row coming out of a
real `exportAll()` call, throwing `ImportValidationException('...is missing
id or updated_at')`.

If this is correct, `export_import_test.dart`'s first test ("export then
import into an empty database reproduces the same logical data") would fail
at runtime for every table except the three append-only ones (which only
check `id`, not `updated_at`).

**I cannot confirm this without a compiler/test run — flagging it as the
top-priority thing to verify first**, since if real it's a one-line fix
(read `row['updatedAt']`, or add `json_key_case: snake_case` to a
`build.yaml`) but currently untested either way.

### 5.2 — Dangling documentation/comment references (no compilation impact, but stale)

None of these affect whether the code compiles — they're comments pointing
at the wrong filename or a nonexistent file. Listed because they're
genuinely provable by static review and worth a cleanup pass:

| Location | Comment claims | Actual |
|---|---|---|
| `core_tables.dart:20` | single-Student-row rule enforced in `StudentRepository` | No `StudentRepository` class exists anywhere, and — unlike the `EmergencyRepository` gap — this one isn't disclosed as future work in DEVIATIONS.md/the implementation report. |
| `curriculum_tables.dart:107` | cycle check lives in `repositories/prerequisite_repository.dart` | The DFS cycle check does exist, but in `reality_and_prerequisite_repositories.dart`. |
| `migration_strategy.dart:22` | points to `test/migration_test.dart` | Actual file is `test/migration_and_sync_readiness_test.dart`. |
| `audit_tables.dart:14` | points to `domain/event_types.dart` | Actual file is `lib/events/event_types.dart` (confirmed by the implementation report's own file tree). |
| `enums.dart:10` | points to `CURRICULUM_GUARDS.md` | No such file exists anywhere in the archive. |
| `event_types.dart:1-8` | says the list has "17 values" | `kKnownEventTypes` actually has 18 entries — recounted directly. |
| `derived_state_tables.dart:7-13` (file header) | present-tense: "The Repository layer for each of these... exposes ONLY a recomputeFrom(...) write path" | True only for `MasteryStates`. The other 7 derived-state tables (Memory, Error, TimeEstimate, Workload, Priority, Recovery, Emergency) have no repository yet — correctly disclosed elsewhere (DEVIATIONS.md, the implementation report §4/§14, SOURCE_OF_TRUTH.md), but this specific file's own header overstates it. |

### 5.3 — Minor precision note

`append_only_repository.dart`'s docstring says no calling code can reach an
update/delete path through "this repository" because the method doesn't
exist on the type. That's true of the abstract base class itself, but its
concrete subclass `EventRepository` does add one narrow, single-purpose
`markProcessed()` method that calls `.update()` once (guarded to fire only
if `processedAt` was never set before). This is intentional and documented
in `EventRepository`'s own docstring — just noting the base-class claim is
slightly broader than the full picture across every subclass.

## 6. Missing Files

None found. Every file the pubspec, the imports, or the three `.md` reports
reference either exists in the archive or is an expected not-yet-generated
artifact (`app_database.g.dart`, produced by `build_runner`, which is
correctly absent pre-generation).

## 7. What Will Need Real (Runtime) Verification Later

In priority order:
1. §5.1 above — the Export/Import JSON-key-casing question. Run
   `export_import_test.dart` first; if it fails with "missing id or
   updated_at", that confirms it and the fix is in `_mergeMutableRow`
   (and `_mergeAppendOnlyRow` if it turns out to matter there too).
2. `dart analyze` for any type errors my manual review missed (there is no
   substitute for the compiler here).
3. `build_runner` code generation succeeding cleanly for all 36 tables.
4. The full test suite (`flutter test`), including the already-flagged test
   debt items disclosed in DEVIATIONS.md / the implementation report
   (the simplified LWW test, the skipped v1→v2 placeholder).
5. Re-running `check_repository_boundaries.sh` in the real CI environment
   (already confirmed to pass here, but worth re-running post-fix).

## 8. FINAL STATUS

**READY-FOR-RUNTIME-VERIFICATION**

No blocking structural defect was found by static review (no missing
tables, no broken imports, no dangling foreign keys, brace/paren balance
confirmed, repository-boundary script actually run and passing). One
likely-but-unconfirmed functional bug is flagged (§5.1) as the first thing
to check once Flutter/Dart is available, plus a handful of stale
comment/documentation references (§5.2) that don't block compilation but
are worth cleaning up. Nothing here required or received a code change —
per your instructions, issues are recorded, not fixed, in this pass.
