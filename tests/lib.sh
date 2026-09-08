#!/usr/bin/env bash
# shellcheck shell=bash
# Shared assertions for the nanolander suites.
#
# Every suite sources this, counts with chk, and ends with finish. Nothing
# here needs network or root, and nothing writes outside a throwaway HOME —
# see tests/README.md for what that leaves uncovered.

REPO_ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export REPO_ROOT

PASSED=0
FAILED=0

# chk <name> <actual> <expected>
chk() {
  if [ "$2" = "$3" ]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$1" "$3" "$2"
  fi
}

# yn <command...> — "y" when the command succeeds, "n" when it does not.
# Keeps the assertions readable next to shell predicates.
yn() { if "$@" >/dev/null 2>&1; then printf 'y'; else printf 'n'; fi; }

# exists <path> — "y" for anything that is there, symlinks included.
exists() { if [ -e "$1" ] || [ -L "$1" ]; then printf 'y'; else printf 'n'; fi; }

# count_files <glob...> — how many of these paths exist. A glob that matches
# nothing stays literal, so the -e test filters it out. Avoids parsing ls.
count_files() {
  local n=0 f
  for f in "$@"; do
    [ -e "$f" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}

finish() {
  printf '%s passed, %s failed\n' "$PASSED" "$FAILED"
  [ "$FAILED" -eq 0 ]
}

# A throwaway HOME for suites that write anything. Sets TEST_HOME rather than
# printing the path: `H=$(temp_home)` would run the export in a subshell and
# leave the caller pointed at the real home directory.
temp_home() {
  TEST_HOME=$(mktemp -d)
  HOME="$TEST_HOME"
  export HOME
}
