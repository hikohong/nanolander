#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either. SC2016 is
# off because the rc line under test must contain a literal $HOME, not this
# process's expansion of it — that is the thing being asserted.
# shellcheck disable=SC1090,SC1091,SC2016,SC2034,SC2317
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
# Counted from the source tree rather than written down here, so adding a
# module to share/nvim/lua/hikovim does not break the suite that ships it.
chk "every shipped lua file lands" \
  "$(find "$T" -name '*.lua' -path '*hikovim*' | wc -l | tr -d ' ')" \
  "$(find "$REPO_ROOT/share/nvim/lua/hikovim" -name '*.lua' | wc -l | tr -d ' ')"
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

# The lockfile assertions need to add and remove one, so they run against a
# throwaway copy of the checkout rather than the repository. An earlier version
# wrote straight into share/nvim and removed it again on the way out, which
# deleted the lockfile the repository actually ships: ./tests/run.sh silently
# unpinned the plugin set, and the next --apply took each project's head.
# nvim-land finds share/nvim relative to $0, so a copied script is all it takes.
FAKE="$H/checkout"
mkdir -p "$FAKE/bin" "$FAKE/share"
cp "$REPO_ROOT/bin/nvim-land" "$FAKE/bin/nvim-land"
chmod +x "$FAKE/bin/nvim-land"
cp -R "$REPO_ROOT/share/nvim" "$FAKE/share/nvim"
NL="$FAKE/bin/nvim-land"
SRC="$FAKE/share/nvim"
rm -f "$SRC/lazy-lock.json"
trap 'rm -rf "$H" "$H2"' EXIT
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
rm -f "$SRC/lazy-lock.json"
chk "report says it is unpinned"   "$(PATH="$STUB:$PATH" "$NL" | grep -c 'unpinned')" "1"

# --freeze refuses to pin a tree that does not match what we ship, or the
# lockfile would record something other than the configuration in the repo.
printf 'drifted\n' > "$T/init.vim"
out=$(PATH="$STUB:$PATH" "$NL" --freeze 2>&1)
chk "--freeze refuses a drifted tree" "$?" "1"
chk "and says to apply first"         "$(printf '%s' "$out" | grep -c 'apply first')" "1"

# ---------------------------------------------------------------------------
# The language server tables. nvim-land parses both out of lua/hikovim/lsp.lua
# rather than repeating them, so the shape is what these assert — and so is the
# thing the shape is for: several Python servers answer for the same files, and
# a report that showed two of them as running would be wrong.
# ---------------------------------------------------------------------------
LSP="$REPO_ROOT/share/nvim/lua/hikovim/lsp.lua"
NVIM_LAND_LIB=1 . "$NL"
SOURCE_DIR="$REPO_ROOT/share/nvim"

chk "the server list parses"    "$(lsp_servers | wc -l | tr -d ' ')" "9"
chk "the PREFER list parses"    "$(lsp_preferred | wc -l | tr -d ' ')" "1"
chk "python is the group"       "$(lsp_preferred | awk '{print $1}')" "python"
chk "four python servers"       "$(lsp_preferred | awk '{print NF - 1}')" "4"

# The binary has to be the one nvim-lspconfig's cmd runs, not the one you type
# to install it: pyright's cmd is `pyright-langserver --stdio`, and checking
# `pyright` enabled a server whose cmd then did not exist.
chk "pyright checks its own cmd" "$(lsp_servers | awk '$1 == "pyright" { print $2 }')" "pyright-langserver"
chk "basedpyright likewise"      "$(lsp_servers | awk '$1 == "basedpyright" { print $2 }')" "basedpyright-langserver"
chk "pylsp is listed"            "$(lsp_servers | awk '$1 == "pylsp" { print $2 }')" "pylsp"

# Every name in PREFER must be a name in SERVERS, or the Lua side looks up a
# nil binary and the report stands a server down that it never listed.
unknown=""
for name in $(lsp_preferred | cut -d' ' -f2-); do
  lsp_servers | awk -v n="$name" '$1 == n { found = 1 } END { exit !found }' \
    || unknown="$unknown $name"
done
chk "every preferred server is a known one" "$unknown" ""

# ruff is a Python language server and is deliberately not in PREFER: it
# declares no completionProvider, so it complements a type server rather than
# replacing one, and listing it would make it exclude one.
chk "ruff is not in the preference list" "$(lsp_preferred | grep -c ruff)" "0"

# preferred_winner walks the list in order, which is the whole point: with two
# installed, the first one wins and the other is stood down.
STUB2="$H/stub-lsp"
stub_tools "$STUB2" pylsp
chk "only pylsp installed -> pylsp wins" \
  "$(preferred_winner python basedpyright pyright pylsp jedi_language_server)" "pylsp"
stub_tools "$STUB2" pyright-langserver
chk "pyright installed too -> pyright wins" \
  "$(preferred_winner python basedpyright pyright pylsp jedi_language_server)" "pyright"
chk "and the report stands the other down" \
  "$("$NL" | grep -c 'another server answers')" "1"
stub_tools "$STUB2" basedpyright-langserver
chk "basedpyright outranks both" \
  "$(preferred_winner python basedpyright pyright pylsp jedi_language_server)" "basedpyright"
chk "none installed -> no winner" \
  "$(PATH=$(path_without pylsp pyright-langserver basedpyright-langserver jedi-language-server) \
     preferred_winner python basedpyright pyright pylsp jedi_language_server)" ""

finish
