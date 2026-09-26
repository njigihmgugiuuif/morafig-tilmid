#!/bin/sh
# check_repository_boundaries.sh
#
# Enforces the organizational half of the append-only and curriculum-guard
# guarantees: only lib/repositories/ (and lib/database/app_database.dart,
# which must register every table) may import the raw Drift table files
# for the append-only tables and the curriculum/policy tables.
#
# Run this in CI before `flutter test`. Exits non-zero (failing the build)
# if any violation is found. This is intentionally a blunt grep-based
# check rather than a custom_lint plugin — simple enough to audit by
# reading it, no extra build-time dependency.
#
# Usage: sh check_repository_boundaries.sh   (run from the project root)

set -e

fail=0

# lib/database/tables/ is exempt as a WHOLE directory, not just
# app_database.dart: table files legitimately cross-reference each other
# via .references(OtherTable, #id) for foreign keys (e.g. planning_tables
# .dart's Tasks table references curriculum_tables.dart's KnowledgeNodes).
# That is a structural FK relationship, not a guard bypass — the guard is
# about business-logic code (engines, UI, import/export) reaching the raw
# table objects, not about the schema files declaring their own relations.
echo "Checking append-only table access boundary..."
violations=$(grep -rl "audit_tables.dart" lib --include="*.dart" \
  | grep -v "^lib/repositories/" \
  | grep -v "^lib/database/" || true)
if [ -n "$violations" ]; then
  echo "VIOLATION: files outside lib/repositories/ and lib/database/ import audit_tables.dart:"
  echo "$violations"
  fail=1
fi

echo "Checking curriculum/policy table access boundary..."
violations=$(grep -rl "curriculum_tables.dart" lib --include="*.dart" \
  | grep -v "^lib/repositories/" \
  | grep -v "^lib/database/" || true)
if [ -n "$violations" ]; then
  echo "VIOLATION: files outside lib/repositories/ and lib/database/ import curriculum_tables.dart:"
  echo "$violations"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "OK: repository access boundaries respected."
fi

exit $fail
