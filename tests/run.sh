#!/usr/bin/env bash
#
# Run every suite and print one summary.
#
#   ./tests/run.sh              all suites
#   ./tests/run.sh nerd-font    only the suites whose name contains this
#
# Nothing here needs the network, root, or a particular platform: releases are
# local fixtures served over file://, and anything that writes writes into a
# throwaway HOME. See tests/README.md for what that leaves uncovered.

set -uo pipefail

here=$(cd -P "$(dirname "$0")" && pwd)
filter="${1:-}"

total_pass=0
total_fail=0
failed_suites=""

for suite in "$here"/test-*.sh; do
  name=$(basename "$suite" .sh)
  name=${name#test-}
  case "$name" in
    *"$filter"*) ;;
    *) continue ;;
  esac

  printf '\n=== %s ===\n' "$name"
  output=$(bash "$suite" 2>&1)
  status=$?
  printf '%s\n' "$output"

  # Every suite ends with "<n> passed, <m> failed" from lib.sh.
  line=$(printf '%s\n' "$output" | grep -E '^[0-9]+ passed, [0-9]+ failed$' | tail -1)
  if [ -n "$line" ]; then
    total_pass=$((total_pass + $(printf '%s' "$line" | cut -d' ' -f1)))
    total_fail=$((total_fail + $(printf '%s' "$line" | cut -d' ' -f3)))
  fi
  if [ "$status" -ne 0 ]; then
    failed_suites="$failed_suites $name"
    # A suite that dies before printing its summary still has to count.
    [ -n "$line" ] || total_fail=$((total_fail + 1))
  fi
done

printf '\n===============================\n'
printf 'Total: %s passed, %s failed\n' "$total_pass" "$total_fail"
if [ -n "$failed_suites" ]; then
  printf 'Failing suites:%s\n' "$failed_suites"
  exit 1
fi
printf 'All suites passed.\n'
