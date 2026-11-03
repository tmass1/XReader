#!/usr/bin/env bash
# Runs the deploy check's own tests: scripts/tests/run.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
passed=0 failed=0 out=""
for test in "$HERE"/test-*.sh; do
  echo "$(basename "$test")"
  out="$(bash "$test" 2>&1)"
  printf '%s\n' "$out" | sed '$d'
  read -r p _ f _ <<<"$(printf '%s\n' "$out" | tail -1)"
  passed=$((passed + ${p:-0})) failed=$((failed + ${f:-1}))
done
echo "$passed passed, $failed failed"
((failed == 0))
