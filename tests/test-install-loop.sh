#!/usr/bin/env bash
# The suite overrides functions the sourced script owns, which ShellCheck
# cannot see through.
# shellcheck disable=SC1091,SC2317
# install_all_tools visits every catalog entry, even when a tool eats stdin.
#
# This suite exists because of a shipped bug. install_all_tools fed the catalog
# in on stdin, and the loop body runs package managers — dnf reads stdin to ask
# about importing a repository GPG key. The first tool that actually installed
# something consumed the rest of the heredoc, the loop ended there, and the
# summary reported success because every tool it had reached did pass. Six runs
# on one machine installed seven of the fifty-four tools, one more each time.
#
# The stub below is that failure in miniature: it drains stdin exactly as dnf
# does. With the catalog on stdin only the first entry is ever visited.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
NANOLANDER_LIB=1 . "$REPO_ROOT/bin/nanolander"

temp_home; W="$TEST_HOME"
trap 'rm -rf "$W"' EXIT

VISITED="$W/visited"
: > "$VISITED"

# Stands in for ensure_tool, and drains stdin the way an install does.
ensure_tool() {
  printf '%s\n' "$1" >> "$VISITED"
  cat > /dev/null
}
ensure_nerd_font() { printf '%s\n' "$1" >> "$VISITED"; cat > /dev/null; }

install_all_tools

want=$(tool_count)
got=$(grep -c . "$VISITED")
chk "every catalog entry is visited"  "$got" "$want"
chk "the run does not stop at one"    "$(yn test "$got" -gt 1)" "y"
chk "the first entry is reached"      "$(head -1 "$VISITED")" "btop"
chk "the last entry is reached"       "$(tail -1 "$VISITED")" "unzip"
chk "the font entry is routed apart"  "$(grep -c '^nerd-font$' "$VISITED")" "1"

# --only must still filter, and filtering must not truncate the walk either:
# a skipped tool is recorded by ensure_tool itself, so every entry is offered.
: > "$VISITED"
ONLY_LIST="rg"
install_all_tools
chk "a filter does not shorten the walk" "$(grep -c . "$VISITED")" "$want"

# A tool the user filtered out and a tool with no build for this platform are
# both SKIPPED in the table, and they used to share one counter — so a run with
# no filter at all reported "Skipped by filter: 5".
RESULTS=""; COUNT_SUCCESS=0; COUNT_FAILED=0; COUNT_SKIPPED=0; COUNT_ABSENT=0
record_result rg      SUCCESS "GitHub release" /x/rg
record_result bat     SKIPPED filter          -
record_result resvg   SKIPPED platform        -
record_result ncdu    SKIPPED platform        -
record_result nothing FAILED  -               -
chk "successes are counted"        "$COUNT_SUCCESS" "1"
chk "filtered tools are counted"   "$COUNT_SKIPPED" "1"
chk "platform gaps count apart"    "$COUNT_ABSENT"  "2"
chk "failures are counted"         "$COUNT_FAILED"  "1"

finish
