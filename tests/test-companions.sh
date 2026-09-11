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

# Package-manager work is not what this suite is about, and on a runner it
# means network and minutes. This dir goes on PATH for every run below.
STUB="$H/stub"
stub_tools "$STUB" git apt-get brew dnf yum sudo

# command_works requires the version query to print something, so a stub that
# only exits 0 is reported as a failed tool and the run ends in EXIT_PARTIAL.
# git is the tool these runs ask for, so its stub has to answer like the real
# one or the exit code below says 2 for a reason that is not under test.
printf '#!/bin/sh\ncase "$1" in --version) echo "git version 2.43.0";; *) exit 0;; esac\n' > "$STUB/git"
chmod +x "$STUB/git"

# A stub nvim, kept in its own directory so the second case below can run
# without it. Putting it in $STUB would leave it on PATH for every run and the
# "Neovim is missing" branch would never be reached.
NVIM_STUB="$H/stub-nvim"; mkdir -p "$NVIM_STUB"
printf '#!/bin/sh\ncase "$1" in --version) echo "NVIM v0.11.0";; *) exit 0;; esac\n' > "$NVIM_STUB/nvim"
chmod +x "$NVIM_STUB/nvim"

# README tells people to link bin/nanolander onto PATH, so the handoff has to
# survive $0 being a symlink: a bare dirname would look for nvim-land beside
# the link instead of beside the real script.
LINK="$H/bin"; mkdir -p "$LINK"
ln -sf "$REPO_ROOT/bin/nanolander" "$LINK/nanolander"

out=$(PATH="$NVIM_STUB:$PATH" "$LINK/nanolander" --only git,nvim --with-nvim-config 2>&1); rc=$?
chk "the whole run exits 0"            "$rc" "0"
chk "handoff survives a symlinked \$0" "$(printf '%s' "$out" | grep -c 'bin/nvim-land --apply')" "1"
chk "helper is not reported missing"   "$(printf '%s' "$out" | grep -c 'Cannot find bin/nvim-land')" "0"
chk "the config actually lands"        "$(exists "$H/.config/nvim/init.vim")" "y"
chk "and the run still succeeds"       "$(printf '%s' "$out" | grep -c 'Neovim configuration installed')" "1"

# The configuration is installed by DEFAULT: the owner's ask was that landing
# the toolkit leaves a configured editor, not a stock one. A test that always
# passes the flag cannot see the default, so this one must not pass it — and
# --with-nvim-config has to keep being accepted, since notes and scripts still
# carry it.
rm -rf "$H/.config/nvim"
out=$(PATH="$NVIM_STUB:$PATH" "$LINK/nanolander" --only git,nvim 2>&1); rc=$?
chk "no flag still installs it"        "$(exists "$H/.config/nvim/init.vim")" "y"
chk "the default run exits 0"          "$rc" "0"

# ...and --without-nvim-config is the way out. This is the assertion that fails
# if the opt-out is ever wired to the wrong variable.
rm -rf "$H/.config/nvim"
out=$(PATH="$NVIM_STUB:$PATH" "$LINK/nanolander" --only git,nvim --without-nvim-config 2>&1); rc=$?
chk "the opt-out leaves nvim alone"    "$(exists "$H/.config/nvim/init.vim")" "n"
chk "and it does not hand off"         "$(printf '%s' "$out" | grep -c 'bin/nvim-land --apply')" "0"
chk "the opt-out run exits 0"          "$rc" "0"

# --only tmux promises to touch only tmux. Rewriting ~/.config/nvim on a run
# that filtered Neovim out would contradict that, and the flag defaulting to on
# is exactly what could make it happen — nvim is present on any machine that
# has landed the toolkit, so command_works would not stop it.
rm -rf "$H/.config/nvim"
out=$(PATH="$NVIM_STUB:$PATH" "$LINK/nanolander" --only git 2>&1); rc=$?
chk "--only without nvim skips it"     "$(exists "$H/.config/nvim/init.vim")" "n"
chk "and it does not hand off either"  "$(printf '%s' "$out" | grep -c 'bin/nvim-land --apply')" "0"

# The --skip side of the same gate. It cannot be driven through the whole
# script: --only and --skip are refused together, and a bare `--skip nvim` run
# would install the other 50-odd tools over the network. The run above proves
# the gate asks wants_tool; this proves wants_tool answers for --skip too.
chk "wants_tool honours --skip nvim" \
  "$(NANOLANDER_LIB=1 bash -c '. "$0"; SKIP_LIST=nvim; ONLY_LIST=""; wants_tool nvim Neovim && echo y || echo n' \
     "$REPO_ROOT/bin/nanolander" 2>&1)" "n"

# Without Neovim there is nothing to configure, and that is a warning rather
# than a stop. NVIM_STUB is deliberately not on PATH here — and neither is the
# real one, which a machine that has landed the toolkit has.
#
# This calls the function rather than running the whole script, because on
# macOS the whole script cannot reach this branch: setup_homebrew ends in
# `eval "$(brew shellenv)"`, which puts /opt/homebrew/bin back on PATH and with
# it the very nvim that has to be missing. The assertion held on a Linux runner
# and could not hold on a Mac that had landed the toolkit — the machine the
# toolkit is for. `bash -c '...' <path>` makes $0 the script, which is what
# script_dir reads to find bin/nvim-land beside it.
H2=$(mktemp -d)
out=$(NANOLANDER_LIB=1 HOME="$H2" XDG_CONFIG_HOME="$H2/.config" \
  XDG_DATA_HOME="$H2/.local/share" PATH="$(path_without nvim)" \
  bash -c '. "$0"; install_nvim_config; printf "rc=%s\\n" "$?"' \
  "$REPO_ROOT/bin/nanolander" 2>&1)
chk "no nvim is a warning, not a stop" "$(printf '%s' "$out" | grep -c 'Neovim is not installed, so there is no configuration')" "1"
chk "the helper is not blamed"         "$(printf '%s' "$out" | grep -c 'Cannot find bin/nvim-land')" "0"
chk "and it reports that it skipped"   "$(printf '%s' "$out" | grep -c '^rc=1$')" "1"
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
