#!/usr/bin/env bash
#
# The read-only entry points: what every script prints when asked to explain
# itself, and what it does with an option it does not know.
#
# This suite exists because of a shipped bug no other check could see.
# print_tool_catalog ended with
#
#   printf '--without-nvim-config, or run ./bin/nvim-land on its own.\n'
#
# and a format string that starts with a dash is an option to bash's printf
# builtin, so on every platform --list-tools wrote "printf: --: invalid
# option" to stderr, stopped mid-sentence, and still exited 0. Nothing looked
# at stderr and nothing looked at the last line, so it went unnoticed through
# sixteen merged pull requests.
#
# The assertions are therefore about the streams rather than the words: an
# informational command prints on stdout, says nothing on stderr, and exits 0.
# bin/* rather than a list of names, for the same reason ci.yml globs — a
# helper added without being added here would go unchecked, and helpers are
# meant to keep arriving.
# SC1091: lib.sh is sourced at run time and is not an input to this file's
# own analysis; every suite here disables it the same way.
# shellcheck disable=SC1091
set -uo pipefail
. "$(dirname "$0")/lib.sh"

temp_home; H="$TEST_HOME"
trap 'rm -rf "$H"' EXIT

out="$H/out"
err="$H/err"

# run <script> <args...> — captures both streams and the status. Sets RUN_OUT,
# RUN_ERR and RUN_STATUS rather than printing, so an assertion can look at one
# stream without the other reaching the terminal.
run() {
  local script="$1"
  shift
  "$script" "$@" >"$out" 2>"$err" </dev/null
  RUN_STATUS=$?
  RUN_OUT=$(cat "$out")
  RUN_ERR=$(cat "$err")
}

# nonempty <string> — "y" when there is anything at all in it.
nonempty() { if [ -n "$1" ]; then printf 'y'; else printf 'n'; fi; }

for script in "$REPO_ROOT"/bin/*; do
  name=$(basename "$script")

  # --help and --version are the two things every script in bin/ answers, and
  # neither touches the machine, so they are safe to run anywhere.
  for opt in --help --version; do
    run "$script" "$opt"
    chk "$name $opt exits 0"        "$RUN_STATUS"            "0"
    chk "$name $opt prints"         "$(nonempty "$RUN_OUT")" "y"
    # The whole point of the suite. An informational command has nothing to
    # report, so anything on stderr is a defect in the script itself.
    chk "$name $opt is silent on stderr" "$RUN_ERR"          ""
  done

  # --version prints a version and nothing else: one line, and it carries a
  # digit. A script whose version string went missing would otherwise pass the
  # "prints something" assertion above on its name alone.
  run "$script" --version
  chk "$name --version is one line" "$(printf '%s\n' "$RUN_OUT" | wc -l | tr -d ' ')" "1"
  chk "$name --version has a number" "$(yn expr "$RUN_OUT" : '.*[0-9]')" "y"

  # An option nobody recognises is EXIT_USAGE across all four scripts, and
  # that number is API — README documents it.
  run "$script" --nanolander-no-such-option
  chk "$name rejects a bad option with 64" "$RUN_STATUS" "64"
  chk "$name says why"                     "$(nonempty "$RUN_OUT$RUN_ERR")" "y"
done

# --list-tools is the command the printf bug broke, so it gets the same stream
# assertions plus one about where the text ends. The last line is the one that
# vanished; checking the catalog is "long enough" would not have caught it,
# because everything up to that sentence printed fine.
run "$REPO_ROOT/bin/nanolander" --list-tools
chk "--list-tools exits 0"            "$RUN_STATUS"            "0"
chk "--list-tools prints"             "$(nonempty "$RUN_OUT")" "y"
chk "--list-tools is silent on stderr" "$RUN_ERR"              ""
chk "--list-tools finishes its last sentence" \
  "$(yn grep -Fq -- '--without-nvim-config, or run ./bin/nvim-land on its own.' "$out")" "y"

# Every catalog row reaches the screen. The count comes from the script's own
# header line, so this stays true when a tool is added.
listed=$(printf '%s\n' "$RUN_OUT" | grep -cE '^  [a-z0-9]')
claimed=$(printf '%s\n' "$RUN_OUT" | head -1 | grep -oE '[0-9]+ installable' | grep -oE '[0-9]+')
chk "--list-tools prints every row it claims" "$listed" "$claimed"

# No line of the catalog is a stray format string. A % that reached printf as
# a format rather than an argument would print as a conversion or an error;
# neither belongs in a tool description.
chk "--list-tools has no unexpanded conversions" \
  "$(yn grep -qE '%[-0-9]*[sd]' "$out")" "n"

# Every companion is named in the main script's help. bin/vlc-default was in
# README, in docs/index.html and in CLAUDE.md's helper table, and not in
# --help — the one place a person who ran the installer would look. Same rule
# as README's keys reference: the list is checked, not trusted, because
# helpers are meant to keep arriving and the help text is where they go stale.
run "$REPO_ROOT/bin/nanolander" --help
for script in "$REPO_ROOT"/bin/*; do
  name=$(basename "$script")
  [ "$name" = "nanolander" ] && continue
  chk "--help names $name" "$(yn grep -Fq "bin/$name" "$out")" "y"
done

finish
