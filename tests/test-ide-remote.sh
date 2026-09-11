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
# neo-tree binds <2-LeftMouse> and nothing else, so one click only moved the
# cursor and the pane read as dead. The mapping delegates to whatever <CR> is
# bound to rather than calling neo-tree's command modules, so a rename behind
# its keymaps cannot break it.
chk "one click opens in the tree"    "$(grep -c "'<LeftRelease>', tree_click" "$IDE")" "1"
chk "and it is switchable"           "$(grep -c 'local CLICK_OPENS' "$IDE")" "1"
chk "the click delegates to <CR>"    "$(grep -c "maparg('<CR>', 'n', false, true)" "$IDE")" "1"

# startinsert sets a flag that is spent when control returns to the main loop,
# not where it is called. Firing it while open() still had the terminal pane
# focused therefore put the *editor* pane into insert mode, and every mapping in
# the panels is normal-mode — so the whole right column answered nothing until
# Esc. The autocmd has to defer and then re-check what it is looking at.
chk "startinsert is called once"     "$(grep -c "vim.cmd('startinsert')" "$IDE")" "1"
chk "and only behind a buftype check" \
  "$(grep -A1 "buftype == 'terminal' then" "$IDE" | grep -c "vim.cmd('startinsert')")" "1"
# The panes fill asynchronously and neo-tree focuses itself when its scan
# lands, after open() has returned, so one scheduled fix-up runs too early.
chk "focus is settled, not assumed"  "$(grep -c 'local function settle_focus' "$IDE")" "1"
chk "the settle is bounded"          "$(grep -c 'tries < 4' "$IDE")" "1"
chk "and leaves normal mode set"     "$(grep -c "vim.cmd('stopinsert')" "$IDE")" "1"

# lualine builds the tabline from listed buffers and then invents a tab for the
# current one if it was not among them — so focusing a panel put the outline in
# as [No Name], the tree as neo-tree filesystem [1002] and the terminal as zsh,
# each with a ✕ that closed the pane. is_current is answered for the editor's
# buffer while the cursor is in a panel, so nothing is invented; and the ✕ only
# ever acts on a listed buffer, so it cannot dismantle the layout either way.
chk "panels stay out of the tabline" "$(grep -c 'function Buffer:is_current' "$IDE")" "1"
chk "the X is a tab-only action"     "$(grep -c 'function M.close_tab' "$IDE")" "1"
chk "and it refuses the unlisted"    "$(grep -c 'buflisted then return end' "$IDE")" "1"
chk "the tabline calls close_tab"    "$(grep -c "hikovim.ide'.close_tab" "$IDE")" "1"
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

# --- images in the editor pane ----------------------------------------------
INIT="$SRC_DIR/lua/hikovim/init.lua"
chk "image.nvim is installed"     "$(grep -c "3rd/image.nvim" "$PLUGINS")" "1"
# The backend is the whole point. Every Neovim image plugin draws with the Kitty
# graphics protocol, which iTerm2 does not speak — it has its own inline-images
# protocol, which is why yazi can show an image where these plugins cannot.
# Sixel is the one language both sides know.
chk "the backend is sixel"        "$(grep -c "backend = 'sixel'" "$PLUGINS")" "1"
# Comments excluded: the kitty backend is named in prose as the upgrade path
# for anyone who moves to a terminal that speaks the protocol.
chk "not the kitty default" \
  "$(grep -v '^[[:space:]]*--' "$PLUGINS" | grep -c "backend = 'kitty'")" "0"
# magick_cli shells out to the ImageMagick nanolander installs; the other
# processor wants a LuaRocks build of the magick rock.
chk "no luarock is needed"        "$(grep -c "processor = 'magick_cli'" "$PLUGINS")" "1"
# Opening one of these has to show the picture rather than the bytes.
chk "image files are hijacked"    "$(grep -c 'hijack_file_patterns' "$PLUGINS")" "1"
# A sixel image is painted on the terminal, not owned by a buffer, so in a
# four-pane layout it has to be cleared when a window moves over it.
chk "overlap is cleared"          "$(grep -c 'window_overlap_clear_enabled = true' "$PLUGINS")" "1"
# image.nvim's rockspec asks for the magick rock, and lazy answers it by
# bootstrapping hererocks — a LuaRocks build wanting Python and a compiler, on a
# box whose whole point is that it just lands.
chk "lazy's rocks are off"        "$(grep -c 'rocks = { enabled = false' "$INIT")" "1"
# Headless printed "cannot query terminal size" on every start, which put a line
# into :messages that scripts and the clean-load check both read.
chk "it is gated on a terminal"   "$(grep -c 'nvim_list_uis() > 0' "$PLUGINS")" "1"
# Erring toward loading: a missing warning line costs nothing, a silently
# missing feature costs the whole thing.
chk "and errs toward loading"     "$(grep -c "has('ttyout')" "$PLUGINS")" "1"

# A picture appeared in the explorer pane as well as the editor pane, and only
# sometimes. neo-tree sits in that pane at position 'current', and its open_file
# reads that literally: for 'current' it skips the window search — so
# open_files_do_not_replace_types never gets a say — and runs :buffer in the
# window it is already in. Every file opened from the tree was therefore
# displayed in the explorer pane first, with enforce moving it a turn of the
# loop later. Invisible for text; for an image, image.nvim hijacks on
# BufWinEnter, so it bound an image to the *explorer* window and started
# drawing, and a sixel is painted on the terminal rather than owned by a buffer
# — its renderer bails out of a window that no longer shows the buffer without
# clearing what it already painted. Which of the two won the race is why it was
# intermittent.
#
# So the layout answers file_open_requested and opens the file in the editor
# pane itself, and the buffer is never displayed in a panel at all.
chk "the tree asks before it opens" \
  "$(grep -c "event = 'file_open_requested'" "$PLUGINS")" "1"
chk "and the layout answers"       "$(grep -c 'ide.tree_open_request(args)' "$PLUGINS")" "1"
chk "the handler exists"           "$(grep -c 'function M.tree_open_request' "$IDE")" "1"
# handled = true is neo-tree's documented contract for "do nothing further".
# Without it neo-tree opens the file again, in its own window, and the bug is
# back with an extra buffer switch in front of it.
chk "it claims the open"           "$(grep -c 'return { handled = true }' "$IDE")" "1"
# show_in_editor is what makes the editor pane current for the BufWinEnter it
# fires, and that event is the one image.nvim reads to decide where to draw.
chk "through the editor pane"      "$(grep -c 'pcall(show_in_editor, buf)' "$IDE")" "1"
# S, s and t still split and open tabs: only the plain open is taken.
chk "splits are left alone"        "$(grep -c "open_cmd or 'edit') ~= 'edit'" "$IDE")" "1"
# With the layout off there is no editor pane to aim at, and neo-tree's own
# logic is right.
chk "no layout hands back"         "$(grep -c 'if not alive(state.editor) then return nil end' "$IDE")" "1"
# A buffer number has nothing to escape; a path handed to :edit does.
chk "the path is not re-escaped"   "$(grep -c 'vim.fn.bufadd(args.path)' "$IDE")" "1"
# enforce is still the backstop for every other route into a panel — fzf-lua, a
# quickfix jump, gf, :bnext.
chk "enforce is still there"       "$(grep -c 'function M.enforce' "$IDE")" "1"

LOCK="$SRC_DIR/lazy-lock.json"
for plugin in neo-tree.nvim flatten.nvim nui.nvim plenary.nvim oil.nvim image.nvim; do
  chk "lockfile pins $plugin" "$(grep -c "\"$plugin\":" "$LOCK")" "1"
done
chk "and pins no luarocks bootstrap" "$(grep -c '"hererocks":' "$LOCK")" "0"

finish
