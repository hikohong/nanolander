#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either. SC2016 is
# off because the rc line under test must contain a literal $HOME, not this
# process's expansion of it — that is the thing being asserted.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
# bin/nvim-land: report, --apply and --restore against a throwaway HOME.
#
# --no-sync everywhere: fetching plugins needs the network, and none of what
# is asserted here depends on it.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
temp_home; H="$TEST_HOME"; NL="$REPO_ROOT/bin/nvim-land"
T="$H/.config/nvim"

# An existing configuration of the user's, including a file we do not ship
# and therefore must never touch.
mkdir -p "$T/lua/mine"
printf 'my own init\n' > "$T/init.vim"
printf 'return {}\n' > "$T/lua/mine/private.lua"
ORIG_FOREIGN=$(cat "$T/lua/mine/private.lua")

out=$("$NL" 2>&1)
chk "report exit" "$?" "0"
chk "report writes nothing" "$(cat "$T/init.vim")" "my own init"
chk "a foreign file is reported" "$(printf '%s' "$out" | grep -c 'lua/mine/private.lua')" "1"

out=$("$NL" --apply --no-sync 2>&1); chk "apply exit" "$?" "0"
chk "a backup is written" "$(count_files "$H/.nanolander-backups/config-nvim."*)" "1"
chk "the backup holds the original" "$(cat "$H/.nanolander-backups/config-nvim."*/init.vim)" "my own init"
chk "init.vim is replaced" "$([ "$(cat "$T/init.vim")" = "my own init" ] && echo no || echo yes)" "yes"
chk "every shipped lua file lands" "$(find "$T" -name '*.lua' -path '*hikovim*' | wc -l | tr -d ' ')" "4"
chk "the foreign file is untouched" "$(cat "$T/lua/mine/private.lua")" "$ORIG_FOREIGN"

# Already up to date: no second backup.
out=$("$NL" --apply --no-sync 2>&1)
chk "no backup when nothing changes" "$(count_files "$H/.nanolander-backups/config-nvim."*)" "1"
chk "reports already up to date" "$(printf '%s' "$out" | grep -c 'already up to date')" "1"

# restore
out=$("$NL" --restore 2>&1); chk "restore exit" "$?" "0"
chk "init.vim comes back" "$(cat "$T/init.vim")" "my own init"
chk "the files we installed are gone" "$([ -e "$T/lua/hikovim/init.lua" ] && echo y || echo n)" "n"
chk "the foreign file survives a restore" "$(cat "$T/lua/mine/private.lua")" "$ORIG_FOREIGN"
chk "the pre-restore snapshot is kept" "$(count_files "$H/.nanolander-backups/pre-restore/config-nvim."*)" "1"

# Restoring twice must land on the same content, not toggle.
"$NL" --restore >/dev/null 2>&1
chk "restore is idempotent" "$(cat "$T/init.vim")" "my own init"

# Same-second runs must not overwrite each other's backups.
for _ in 1 2 3; do "$NL" --apply --no-sync >/dev/null 2>&1; "$NL" --restore >/dev/null 2>&1; done
chk "same-second cycles lose nothing" "$(cat "$T/init.vim")" "my own init"
chk "the foreign file is still there" "$(cat "$T/lua/mine/private.lua")" "$ORIG_FOREIGN"

# With no backup at all, restore fails rather than doing something odd.
H2=$(mktemp -d)
HOME="$H2" XDG_CONFIG_HOME="$H2/.config" "$NL" --restore >/dev/null 2>&1
chk "restore with no backup fails" "$?" "1"

# Bad arguments.
"$NL" --nope >/dev/null 2>&1; chk "unknown option exits 64" "$?" "64"

rm -rf "$H" "$H2"
# --- plugin pinning -------------------------------------------------------
# A shipped lockfile has to change what --apply does: `restore` checks out the
# pinned commits, `sync` would ignore the lockfile and take each project's
# head, which is exactly the reproducibility the lockfile exists to keep.
STUB="$H/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\ncase "$1" in --version) echo "NVIM v0.11.0";; *) echo "$@" >> "$NVIM_ARGS";; esac\n' > "$STUB/nvim"
printf '#!/bin/sh\nexit 0\n' > "$STUB/git"
chmod +x "$STUB/nvim" "$STUB/git"
export NVIM_ARGS="$H/nvim-args"

# This block writes a lockfile into the repository, which is the one thing any
# suite does outside a throwaway HOME. A trap removes it however the suite
# ends: leaving it behind makes the next run start from the wrong state, which
# is exactly how this suite once failed in CI and passed on its own.
SRC="$REPO_ROOT/share/nvim"
trap 'rm -f "$SRC/lazy-lock.json"; rm -rf "$H" "$H2"' EXIT
chk "no stale lockfile to start from" "$(exists "$SRC/lazy-lock.json")" "n"
: > "$NVIM_ARGS"
PATH="$STUB:$PATH" "$NL" --apply >/dev/null 2>&1
chk "no lockfile means sync" "$(grep -c 'Lazy! sync' "$NVIM_ARGS")" "1"

# Ship one, and the same command has to become restore.
printf '{"lazy.nvim":{"commit":"deadbeef"}}\n' > "$SRC/lazy-lock.json"
: > "$NVIM_ARGS"
PATH="$STUB:$PATH" "$NL" --apply >/dev/null 2>&1
chk "a lockfile means restore"     "$(grep -c 'Lazy! restore' "$NVIM_ARGS")" "1"
chk "sync is not used with a lock" "$(grep -c 'Lazy! sync' "$NVIM_ARGS")" "0"
chk "the lockfile is installed"    "$(exists "$T/lazy-lock.json")" "y"
chk "report says it is pinned"     "$(PATH="$STUB:$PATH" "$NL" | grep -c 'pinned by lazy-lock.json')" "1"
rm -f "$SRC/lazy-lock.json"   # also removed by the trap
chk "report says it is unpinned"   "$(PATH="$STUB:$PATH" "$NL" | grep -c 'unpinned')" "1"

# --freeze refuses to pin a tree that does not match what we ship, or the
# lockfile would record something other than the configuration in the repo.
printf 'drifted\n' > "$T/init.vim"
out=$(PATH="$STUB:$PATH" "$NL" --freeze 2>&1)
chk "--freeze refuses a drifted tree" "$?" "1"
chk "and says to apply first"         "$(printf '%s' "$out" | grep -c 'apply first')" "1"

finish
