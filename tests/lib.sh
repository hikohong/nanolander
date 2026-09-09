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

# path_without <name...> — the current PATH minus every directory that provides
# one of these commands.
#
# An assertion about a tool being *absent* cannot be arranged by prepending
# anything: `command -v` searches the whole PATH, so the directory has to go.
# Several suites turn on absence — nanolander warns instead of failing when
# there is no Neovim to configure, and make_compat_links only links 7z to 7zz
# when there is no 7zz — and they read the real PATH, so they passed on a bare
# CI runner and failed on a machine that had actually landed the toolkit. Which
# is the machine the toolkit is for.
path_without() {
  local wants="$*" dir want keep out="" oifs="$IFS"
  IFS=:
  for dir in $PATH; do
    IFS="$oifs"
    if [ -n "$dir" ]; then
      keep=y
      for want in $wants; do
        if [ -x "$dir/$want" ]; then keep=n; break; fi
      done
      [ "$keep" = y ] && out="${out:+$out:}$dir"
    fi
    IFS=:
  done
  IFS="$oifs"
  printf '%s' "$out"
}

# stub_tools <dir> <name...> — instant no-op executables on PATH.
#
# The suites drive the real ./bin/nanolander, which refreshes the package
# index before it installs anything. That means apt-get update or brew update:
# network, sudo, and minutes of runner time for a step none of these
# assertions are about. Stubbing the package managers keeps everything else
# real while making the claim in tests/README.md — no network, no root — true.
stub_tools() {
  local dir="$1" name
  shift
  mkdir -p "$dir" || return 1
  for name in "$@"; do
    printf '#!/bin/sh\nexit 0\n' > "$dir/$name"
    chmod +x "$dir/$name"
  done
  PATH="$dir:$PATH"
  export PATH
}

finish() {
  printf '%s passed, %s failed\n' "$PASSED" "$FAILED"
  [ "$FAILED" -eq 0 ]
}

# A throwaway HOME for suites that write anything. Sets TEST_HOME rather than
# printing the path: `H=$(temp_home)` would run the export in a subshell and
# leave the caller pointed at the real home directory.
#
# HOME alone is not isolation. bin/nvim-land targets
# "${XDG_CONFIG_HOME:-$HOME/.config}/nvim" and bin/nanolander puts its manifest
# and Linux fonts under "${XDG_DATA_HOME:-$HOME/.local/share}", so on any
# machine that sets those — GitHub's Linux runners do — the suites would write
# into the real configuration directory and assert against an empty one.
temp_home() {
  TEST_HOME=$(mktemp -d)
  HOME="$TEST_HOME"
  XDG_CONFIG_HOME="$TEST_HOME/.config"
  XDG_DATA_HOME="$TEST_HOME/.local/share"
  XDG_STATE_HOME="$TEST_HOME/.local/state"
  XDG_CACHE_HOME="$TEST_HOME/.cache"
  export HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
}
