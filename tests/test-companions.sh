#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either. SC2016 is
# off because the rc line under test must contain a literal $HOME, not this
# process's expansion of it — that is the thing being asserted.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
#
# How the scripts reach each other, and the two places a helper has to be
# honest about what it did.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

temp_home; H="$TEST_HOME"
trap 'rm -rf "$H"' EXIT

# A stub nvim so --with-nvim-config gets past the "is it installed" gate, and
# a stub git so lazy.nvim looks fetchable.
STUB="$H/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\ncase "$1" in --version) echo "NVIM v0.11.0";; *) exit 0;; esac\n' > "$STUB/nvim"
printf '#!/bin/sh\nexit 0\n' > "$STUB/git"
chmod +x "$STUB/nvim" "$STUB/git"

# README tells people to link bin/nanolander onto PATH, so the handoff has to
# survive $0 being a symlink: a bare dirname would look for nvim-land beside
# the link instead of beside the real script.
LINK="$H/bin"; mkdir -p "$LINK"
ln -sf "$REPO_ROOT/bin/nanolander" "$LINK/nanolander"

out=$(PATH="$STUB:$PATH" "$LINK/nanolander" --only tree --with-nvim-config 2>&1)
chk "handoff survives a symlinked \$0" "$(printf '%s' "$out" | grep -c 'bin/nvim-land --apply')" "1"
chk "helper is not reported missing"   "$(printf '%s' "$out" | grep -c 'Cannot find bin/nvim-land')" "0"
chk "the config actually lands"        "$(exists "$H/.config/nvim/init.vim")" "y"
chk "and the run still succeeds"       "$(printf '%s' "$out" | grep -c 'Neovim configuration installed')" "1"

# Without Neovim there is nothing to configure, and that is a warning rather
# than a failure of the whole run.
H2=$(mktemp -d)
out=$(HOME="$H2" "$REPO_ROOT/bin/nanolander" --only tree --with-nvim-config 2>&1)
chk "no nvim is a warning, not a stop" "$(printf '%s' "$out" | grep -c 'Neovim is not installed, so there is no configuration')" "1"
chk "the tool run still exits 0"       "$?" "0"
rm -rf "$H2"

# Layer 2 has no call graph to offer. grep answers c and d with the same word
# search as s, so the mapping has to say that rather than let the letter imply
# an answer it did not give.
INIT="$REPO_ROOT/share/nvim/init.vim"
chk "callers mapping warns"  "$(grep -c "NoCallGraph('c callers')" "$INIT")" "1"
chk "callees mapping warns"  "$(grep -c "NoCallGraph('d callees')" "$INIT")" "1"
chk "the notice names the cause" "$(grep -c 'no call graph without a language server' "$INIT")" "1"
# Layer 3 does have one, and must not be reduced to the same word search.
KEYS="$REPO_ROOT/share/nvim/lua/hikovim/keys.lua"
chk "layer 3 uses incoming calls" "$(grep -c 'lsp_incoming_calls' "$KEYS")" "1"
chk "layer 3 uses outgoing calls" "$(grep -c 'lsp_outgoing_calls' "$KEYS")" "1"

finish
