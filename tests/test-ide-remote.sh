#!/usr/bin/env bash
# Assertions read variables the sourced script owns and override its functions
# with fixtures; ShellCheck sees through neither. SC2016 is off because the rc
# line under test must reach the file with a literal $NVIM in it — that is the
# thing being asserted.
# SC2030/SC2031 are off because a PATH set inside ( ) is exactly the scope
# wanted: the stub nvim must be visible to the one call under test and to
# nothing after it.
# shellcheck disable=SC1091,SC2016,SC2030,SC2031,SC2034,SC2317
# Opening a file from the terminal pane, and the tree that replaced oil there.
#
# Two shipped mistakes are pinned here:
#
#   * --remote-wait. Neovim does not implement the wait commands at all and
#     answers E5600, so the first version of this wrapper printed an error
#     instead of opening anything. Only --remote works.
#   * pending_count counting lazy-lock.json. --freeze exists to rewrite that
#     file, and adding a plugin necessarily makes the target's copy differ, so
#     the guard refused to run in exactly the case it is for and no plugin
#     could ever be added.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
NANOLANDER_LIB=1 . "$REPO_ROOT/bin/nanolander"

temp_home; H="$TEST_HOME"
trap 'rm -rf "$H"' EXIT

WRAP=$(shell_line nvimremote)

# --- the rc line ------------------------------------------------------------
chk "the wrapper is defined"  "$([ -n "$WRAP" ] && echo y || echo n)" "y"

# add_line_once compares whole lines and the uninstaller removes by exact
# match, so a wrapper spread over several lines could be written twice and
# removed never.
chk "it is a single line"     "$(printf '%s' "$WRAP" | wc -l | tr -d ' ')" "0"

# Neovim answers E5600 to every wait command. Using one printed an error into
# the terminal pane and opened nothing.
chk "it does not use --remote-wait" "$(printf '%s' "$WRAP" | grep -c -- '--remote-wait')" "0"
chk "it does use --remote"          "$(printf '%s' "$WRAP" | grep -c -- '--remote')" "1"

# $NVIM is what makes it a no-op outside a :terminal, and ${NVIM:-} is what
# keeps it from aborting a shell running with set -u.
chk "it keys off \$NVIM"            "$(printf '%s' "$WRAP" | grep -c 'NVIM')" "1"
chk "unset is handled"              "$(printf '%s' "$WRAP" | grep -c '\${NVIM:-}')" "1"
chk "it defers to the real nvim"    "$(printf '%s' "$WRAP" | grep -c 'command nvim')" "1"

# It lands in a bash rc or a zsh rc, so it has to parse as both.
printf '%s\n' "$WRAP" > "$H/wrap.sh"
chk "valid bash" "$(yn bash -n "$H/wrap.sh")" "y"
if command -v zsh >/dev/null 2>&1; then
  chk "valid zsh" "$(yn zsh -n "$H/wrap.sh")" "y"
fi

# A shell with no $NVIM must get the real nvim, not a remote call. The stub
# records how it was invoked.
STUB="$H/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/called"\n' "$H" > "$STUB/nvim"
chmod +x "$STUB/nvim"
( PATH="$STUB:$PATH"; unset NVIM; . "$H/wrap.sh"; nvim file.txt ) >/dev/null 2>&1
chk "no \$NVIM means a plain nvim" "$(cat "$H/called" 2>/dev/null)" "file.txt"
: > "$H/called"
( PATH="$STUB:$PATH"; NVIM="/tmp/fake.sock"; export NVIM; . "$H/wrap.sh"; nvim file.txt ) >/dev/null 2>&1
chk "inside a pane it goes remote" \
  "$(cat "$H/called" 2>/dev/null)" "--server /tmp/fake.sock --remote file.txt"
: > "$H/called"
# Bare `nvim` has no file to hand over, so it must not become an empty --remote.
( PATH="$STUB:$PATH"; NVIM="/tmp/fake.sock"; export NVIM; . "$H/wrap.sh"; nvim ) >/dev/null 2>&1
chk "bare nvim is not sent remote" "$(cat "$H/called" 2>/dev/null)" ""

# --- it is a managed line, so --uninstall takes it away ---------------------
chk "managed_lines carries it" "$(managed_lines | grep -Fxc "$WRAP")" "1"

# --- written once, and removed cleanly -------------------------------------
NL="$REPO_ROOT/bin/nanolander"
stub_tools "$H/pm" apt-get brew dnf yum sudo
# A working nvim, because configure_shell only writes the line when there is one.
printf '#!/bin/sh\ncase "$1" in --version) echo "NVIM v0.12.0";; *) exit 0;; esac\n' > "$H/pm/nvim"
chmod +x "$H/pm/nvim"

RC_STATE=$("$NL" --only nvim 2>&1 | sed -n 's/^\[INFO\] Shell config: \([^ ]*\) .*/\1/p' | head -1)
RC="${RC_STATE:-$H/.bashrc}"
chk "the wrapper reached the rc file" "$(grep -Fxc "$WRAP" "$RC" 2>/dev/null)" "1"
"$NL" --only nvim >/dev/null 2>&1
chk "and is not written twice"        "$(grep -Fxc "$WRAP" "$RC" 2>/dev/null)" "1"

printf '%s\n' 'export MY_OWN_THING=1' >> "$RC"
"$NL" --uninstall >/dev/null 2>&1
chk "--uninstall removes it"    "$(grep -Fxc "$WRAP" "$RC" 2>/dev/null)" "0"
chk "and leaves my line alone"  "$(grep -c 'MY_OWN_THING' "$RC" 2>/dev/null)" "1"

# --- nvim-land: --freeze has to be able to add a plugin ---------------------
NVIM_LAND_LIB=1 . "$REPO_ROOT/bin/nvim-land"
SRC_DIR="$REPO_ROOT/share/nvim"
SOURCE_DIR="$SRC_DIR"
TARGET_DIR="$H/target"
mkdir -p "$TARGET_DIR/lua/hikovim"
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  mkdir -p "$TARGET_DIR/$(dirname "$rel")"
  cp "$SOURCE_DIR/$rel" "$TARGET_DIR/$rel"
done <<FILES
$(source_files)
FILES
chk "a matching tree has nothing pending" "$(pending_count)" "0"
# Adding a plugin makes lazy rewrite the target's lockfile. That must not be
# what stops --freeze from running.
printf '{"new.nvim": { "branch": "main", "commit": "deadbeef" }}\n' > "$TARGET_DIR/$LOCKFILE"
chk "a changed lockfile is pending"       "$(pending_count)" "1"
chk "but --freeze ignores the lockfile"   "$(pending_count "$LOCKFILE")" "0"
# Anything else drifting still has to stop it.
printf 'drifted\n' > "$TARGET_DIR/init.vim"
chk "real drift still counts"             "$(pending_count "$LOCKFILE")" "1"

# --- the panes, as data ----------------------------------------------------
IDE="$SRC_DIR/lua/hikovim/ide.lua"
PLUGINS="$SRC_DIR/lua/hikovim/plugins.lua"

chk "the explorer pane is the tree"  "$(grep -c "state.explorer then return 'neo-tree'" "$IDE")" "1"
chk "the tree pane is recognised"    "$(grep -c "kind == 'neo-tree'" "$IDE")" "2"
chk "flatten can find the editor"    "$(grep -c 'function M.editor_win' "$IDE")" "1"
chk "neo-tree is installed"          "$(grep -c 'nvim-neo-tree/neo-tree.nvim' "$PLUGINS")" "1"
chk "flatten is installed"           "$(grep -c 'willothy/flatten.nvim' "$PLUGINS")" "1"
# oil is not replaced, only moved out of the pane: <F5> and :e of a directory
# still belong to it.
chk "oil is still installed"         "$(grep -c 'stevearc/oil.nvim' "$PLUGINS")" "1"
# neo-tree must not fight oil for netrw, or a directory opens in whichever
# one loaded last.
chk "netrw is left to oil"           "$(grep -c "hijack_netrw_behavior = 'disabled'" "$PLUGINS")" "1"
# flatten's README documents the handler as returning window, buffer. core.lua
# destructures bufnr, winnr. Returning them the README's way makes flatten
# treat a window id as a buffer number and throw on every open.
chk "the handler returns buffer first" "$(grep -c 'return focus.bufnr, target' "$PLUGINS")" "1"

LOCK="$SRC_DIR/lazy-lock.json"
for plugin in neo-tree.nvim flatten.nvim nui.nvim plenary.nvim oil.nvim; do
  chk "lockfile pins $plugin" "$(grep -c "\"$plugin\":" "$LOCK")" "1"
done

finish
