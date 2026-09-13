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
MEDIA_LUA="$SRC_DIR/lua/hikovim/media.lua"

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
# Opening a picture has to show the picture rather than the bytes — through
# picture.lua's BufReadCmd now, so image.nvim must not also take the read.
chk "image.nvim does not hijack"  "$(grep -c 'hijack_file_patterns = {},' "$PLUGINS")" "1"
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
chk "no layout hands back" \
  "$(grep -c 'if not open_in_editor(args.path, args.bufnr, true) then return nil end' "$IDE")" "1"
# Both places that put a buffer in the editor pane check the pane is there:
# show_in_editor for enforce, open_in_editor for a file chosen in the tree.
chk "and both check for the pane" \
  "$(grep -c 'if not alive(state.editor) then return false end' "$IDE")" "2"
# A buffer number has nothing to escape; a path handed to :edit does.
chk "the path is not re-escaped"   "$(grep -c 'vim.fn.bufadd(path)' "$IDE")" "1"
# Taking the open away from neo-tree took its buflisted with it, and the tab
# for an image went with that: image.nvim sets buftype=nowrite during the very
# BufWinEnter that displays the buffer, so show_in_editor's `buftype == ''`
# rule — which is right for enforce, moving buffers nobody asked for — declines
# to list it. A file asked for by name is listed here instead.
chk "an opened file is listed" \
  "$(grep -c '^ *vim\.bo\[buf\]\.buflisted = true$' "$IDE")" "1"
chk "and enforce keeps its own rule" \
  "$(grep -c "if vim.bo\[buf\].buftype == '' then vim.bo\[buf\].buflisted = true end" "$IDE")" "1"
# enforce is still the backstop for every other route into a panel — fzf-lua, a
# quickfix jump, gf, :bnext.
chk "enforce is still there"       "$(grep -c 'function M.enforce' "$IDE")" "1"

# --- choosing a video hands it to the system player -------------------------
# video.lua previews and deliberately plays nothing: 24 fps of sixel is 14 MB/s
# of escape sequences and the statusline tears through every frame. What it says
# to do instead is hand the file to something that watches files.
#
# <CR> and the double click both mean "I have chosen this one", so both are
# bound. A single click means "show me this one" and still previews. Only
# binding the double click left Enter opening the preview and nothing else,
# which is half the feature.
chk "the double click is claimed" \
  "$(grep -c "\['<2-LeftMouse>'\] = choose" "$PLUGINS")" "1"
chk "and so is Enter"              "$(grep -c "\['<CR>'\] = choose" "$PLUGINS")" "1"
chk "the layout answers both"      "$(grep -c 'ide.tree_open(state)' "$PLUGINS")" "1"
chk "the handler exists"           "$(grep -c 'function M.tree_open(' "$IDE")" "1"
# Bound on the filesystem source, not globally: the fall-through calls that
# source's own open, so it must not reach a source that would be handed the
# wrong one. The global window block staying a one-liner is what says so.
chk "the global window has none" \
  "$(grep -c "window = { position = 'current' }," "$PLUGINS")" "1"
# vim.ui.open is `open` on macOS and `xdg-open` on a Linux desktop, so the file
# goes to whatever owns the type. Naming VLC here as well as in vlc-default is
# how the two come apart: the binding belongs to the system.
chk "it goes through the system"   "$(grep -c 'vim.ui.open(path)' "$IDE")" "1"
chk "and names no player itself" \
  "$(grep -vE '^[[:space:]]*--' "$IDE" | grep -cE "'(vlc|mpv|ffplay|open|xdg-open)'")" "0"
# One owner for both extension lists, or a format gets a preview and no viewer.
chk "it asks media.lua"            "$(grep -c 'media.opens_externally(path)' "$IDE")" "1"
chk "which exports the answer" \
  "$(grep -c 'function M.opens_externally' "$MEDIA_LUA")" "1"
# One branch answers both kinds, and says which of the two opens externally,
# rather than a picture branch and a video branch drifting apart.
chk "one branch for both kinds"    "$(grep -c 'local function media_path' "$IDE")" "1"
chk "and no video-only branch"     "$(grep -c 'video_path' "$IDE")" "0"
# A directory to expand and every other file keep doing what neo-tree
# documents, so neither key is taken away from them.
chk "anything else falls through" \
  "$(grep -c "require('neo-tree.sources.filesystem.commands').open(tree_state)" "$IDE")" "1"
# vim.ui.open answers nil and a reason rather than throwing, and a box with no
# desktop is that case. Silence there is indistinguishable from a missed click.
chk "a box with no desktop is told" "$(grep -c 'cannot open %s' "$IDE")" "1"
chk "and pointed at mpv"            "$(grep -c 'mpv --vo=tct' "$IDE")" "1"

# A mouse mapping is looked up in the buffer that is current when the key is
# processed. The first click of a double click once opened a preview and jumped
# to the editor pane, where <2-LeftMouse> is not mapped — so the second click
# reached nothing. A single click on a picture or a video now only asks for the
# thumbnail above, and never touches the editor pane or the cursor.
chk "a single click on media only peeks" \
  "$(awk '/^local function tree_click/,/^end/' "$IDE" | grep -c 'M.peek_now()')" "1"
chk "and opens nothing in the editor" \
  "$(awk '/^local function tree_click/,/^end/' "$IDE" | grep -c 'open_in_editor')" "0"

# ---------------------------------------------------------------------------
# The thumbnail in the outline's pane (peek.lua)
# ---------------------------------------------------------------------------
PEEK="$REPO_ROOT/share/nvim/lua/hikovim/peek.lua"
chk "peek.lua ships" "$(exists "$PEEK")" "y"

# <CR> means "I have chosen this one": a picture opens in the editor pane, a
# video goes to the system's player, since the editor pane shows one frame.
chk "<CR> on a picture opens it here" \
  "$(awk '/^function M.tree_open\(/,/^end/' "$IDE" | grep -c 'open_in_editor(path, nil, true)')" "1"
chk "<CR> on a video goes to the system" \
  "$(awk '/^function M.tree_open\(/,/^end/' "$IDE" | grep -c 'if external then return hand_to_system(path) end')" "1"
chk "media.lua: only a video opens externally" \
  "$(awk '/^function M.opens_externally/,/^end/' "$MEDIA_LUA" | grep -c 'return M.is_video(path)$')" "1"
# gx is the way to a system viewer for a picture now, bound through neo-tree's
# own mapping table for the same reason O is.
chk "gx is bound through neo-tree"  "$(grep -c "\['gx'\] = system_open" "$PLUGINS")" "1"

# The pane rule. Without it enforce sees a buffer that is not aerial, restores
# the outline and hands the thumbnail's buffer to the editor pane — loading on
# every keypress, which the thumbnail exists to avoid.
chk "the outline pane may hold the thumbnail" \
  "$(grep -c "kind == 'aerial' and vim.bo\[buf\].filetype == 'hikovim_peek'" "$IDE")" "1"
chk "and peek.lua names that filetype" "$(grep -c "M.FILETYPE = 'hikovim_peek'" "$PEEK")" "1"

# Giving the pane back reopens the outline rather than restoring an old aerial
# buffer: aerial keeps one buffer per source buffer, and the editor may have
# moved on while the thumbnail was up.
chk "hiding reopens the outline" \
  "$(awk '/^local function peek_hide/,/^end/' "$IDE" | grep -c "restore_pane(state.outline, 'aerial')")" "1"
chk "and forgets the thumbnail buffer first" \
  "$(awk '/^local function peek_hide/,/^end/' "$IDE" | grep -c 'state.pane_buf\[state.outline\] = nil')" "1"

# Built for moving fast: a debounce, and a generation number so a result that
# arrives after the cursor has moved on is dropped instead of drawn.
chk "cursor moves are debounced"  "$(grep -c '^local PEEK_DELAY_MS = ' "$IDE")" "1"
chk "stale results are dropped"   "$(grep -c 'mine == generation' "$PEEK")" "1"
chk "leaving the tree gives the pane back" \
  "$(grep -c "vim.api.nvim_create_autocmd('WinLeave'" "$IDE")" "1"
# A thumbnail is picture.lua's normalise at a small box, cached the same way,
# and a video's frame comes from video.lua's own command — no second copy.
chk "a thumbnail is a small normalise" "$(grep -c 'picture.normalise(path, M.PEEK_BOX, done)' "$PEEK")" "1"
chk "a video frame is video.lua's"     "$(grep -c 'video.frame_argv(path, video.frame_at(duration), frame)' "$PEEK")" "1"
chk "and peek keeps no ffmpeg argv"    "$(grep -c "'-frames:v'" "$PEEK")" "0"
# The callbacks go on to use vim.fn, so they run on the main loop, and none of
# the autocmd callbacks returns a truthy value.
chk "every vim.system in peek is scheduled" \
  "$(grep -c 'vim.system(' "$PEEK")" "$(grep -c 'vim.schedule_wrap(function' "$PEEK")"

# The thumbnail paints its own sixel. image.nvim's sixel backend answers any
# image change with a :mode full-screen clear and a repaint of every image, so a
# thumbnail drawn through it cleared the screen and repainted the picture in the
# editor pane on every move in the tree — measured from the terminal's byte
# stream: one to two clears and a repaint of that picture per move, even onto a
# text file. Afterwards: no clears, no repaint, one small sixel.
chk "peek draws nothing through image.nvim" \
  "$(grep -cE "require\('image'\)|from_file|:render\(\)" "$PEEK")" "0"
chk "and never clears the screen itself" \
  "$(( $(grep -c "'mode'" "$PEEK") + $(grep -cF '[2J' "$PEEK") ))" "0"
# Neovim does not rewrite unchanged cells even for nvim__redraw valid=false, so
# taking a thumbnail off means spaces in the editor background over exactly the
# rectangle it covered.
chk "a thumbnail is erased by its rectangle" "$(grep -c '^function M.erase' "$PEEK")" "1"
chk "in the editor's background"             "$(grep -c "48;2;%d;%d;%dm" "$PEEK")" "1"
# When image.nvim does clear the screen, the thumbnail is painted again. The hook
# is on the module image.nvim loads — the slash spelling; the dotted one is a
# different cache entry — and a shallow clear, which never flushes, is ignored.
chk "the repaint hook is on image.nvim's own module" \
  "$(grep -c "require, 'image/backends/sixel'" "$PEEK")" "1"
chk "a shallow clear does not repaint" "$(grep -c 'if last and not shallow then' "$PEEK")" "1"
chk "focus is restored, not moved"  "$(grep -c 'if not focus and alive(here)' "$IDE")" "1"
# get_state('filesystem') returns the state held for the *tab*, and this tree is
# at position 'current', whose state is held per window. That call answered a
# freshly created empty state, tree_click found no node, and every single click
# fell through to <CR> and started a player. get_state_for_window reads
# neo_tree_position off the buffer and picks the right one of the two.
chk "the state is asked per window" "$(grep -c 'manager.get_state_for_window' "$IDE")" "1"
chk "and never per tab"             "$(grep -c "get_state, 'filesystem'" "$IDE")" "0"

LOCK="$SRC_DIR/lazy-lock.json"
for plugin in neo-tree.nvim flatten.nvim nui.nvim plenary.nvim oil.nvim image.nvim; do
  chk "lockfile pins $plugin" "$(grep -c "\"$plugin\":" "$LOCK")" "1"
done
chk "and pins no luarocks bootstrap" "$(grep -c '"hererocks":' "$LOCK")" "0"

# ---------------------------------------------------------------------------
# The explorer pane's root picker: the button on the first line, and <C-r>.
# ---------------------------------------------------------------------------
IDE="$REPO_ROOT/share/nvim/lua/hikovim/ide.lua"
PLUG="$REPO_ROOT/share/nvim/lua/hikovim/plugins.lua"

# One owner for the icon. plugins.lua renders it into the root name and
# ide.root_click searches the rendered line for it again, so a second copy is
# how the button appears and clicking it does nothing — the same failure
# media.lua's single extension list exists to prevent.
chk "the icon is declared once" "$(grep -c "^M.ROOT_PICK_ICON = " "$IDE")" "1"
chk "and plugins.lua goes through ide" "$(grep -c 'ide.root_label(' "$PLUG")" "1"
chk "plugins.lua keeps no copy" "$(grep -c "ROOT_PICK_ICON = '" "$PLUG")" "0"

# The icon has to be a Nerd Font glyph the shipped font actually carries, and
# one that is not already on that line: the left-hand icon is a plain folder.
chk "the icon is folder-search" \
  "$(grep "^M.ROOT_PICK_ICON = " "$IDE" | grep -c "$(printf '\xf3\xb0\xa5\xa8')")" "1"

# Overriding the one component, not the whole renderer: neo-tree owns the
# layout of that line, and copying its `directory` renderer in here would go
# stale the first time upstream changed it.
chk "only the name component is overridden" "$(grep -c "name = function(config, node, state)" "$PLUG")" "1"
chk "the default renderer is not copied"    "$(grep -c "renderers = {" "$PLUG")" "0"
chk "and it calls neo-tree's own name"      "$(grep -c "common.name(config, node, state)" "$PLUG")" "1"
chk "only the root line gets it"            "$(grep -c 'node:get_depth() == 1' "$PLUG")" "1"

# The click region is found, never counted. Everything before the icon on that
# line is neo-tree's — an indent, a folder icon, the root name, and a sort
# arrow that exists only at position 'current' — so column arithmetic would be
# wrong the first time one of them changed width.
chk "the click finds the icon in the line" "$(grep -c "line:find(M.ROOT_PICK_ICON, 1, true)" "$IDE")" "1"
chk "and it only acts on line 1"           "$(grep -c 'pos.line ~= 1' "$IDE")" "1"

# Re-rooting has to put the tree window back first. The pane is neo-tree at
# position 'current', so :Neotree renders into whichever window is focused,
# and the picker is a float — without this the editor pane becomes a second
# tree, which is the same trap README warns about for :Neotree dir=.
chk "the tree window is restored first" \
  "$(awk '/^local function root_set/, /^end/' "$IDE" | grep -c 'nvim_set_current_win(win)')" "1"

# The picker is a folder browser. It used to be a flat list that closed on the
# first Enter, so anything two levels away took a reopen per level. Choosing a
# row walks into it and the list redraws in place; the root is set only from
# the "use this folder" row or Ctrl-Y.
chk "rows are use / up / down"        "$(grep -cE "^local ROW_(USE|UP|DOWN) " "$IDE")" "3"
chk "walking is a reload, not a close" "$(grep -c 'reload = true' "$IDE")" "1"
chk "Enter walks"                     "$(grep -c "\['enter'\] = walk" "$IDE")" "1"
chk "a double click walks too"        "$(grep -c "\['double-click'\] = walk" "$IDE")" "1"
chk "Ctrl-Y uses the folder browsed"  "$(grep -c "\['ctrl-y'\] = function() root_set(win, browsing)" "$IDE")" "1"
# After every step the filter is cleared and the cursor goes back to "use this
# folder": a query typed to find one subfolder would hide the next folder's
# rows, and Enter again is how you say "here".
chk "each step clears the query and goes to the top" "$(grep -c "postfix = 'clear-query+first'" "$IDE")" "1"
# A reload action is one fzf does not close, so the use row closes it itself.
chk "the use row closes the picker"   "$(grep -c 'close_fzf()' "$IDE")" "2"

# The path is never read back out of a row's text: up is the parent of the
# folder being browsed, down is that folder joined with the name. A folder
# literally named "..   x", or the ~ in a displayed path, cannot redirect it.
chk "up is computed, not parsed"      "$(awk '/^local function browse_step/,/^end/' "$IDE" | grep -c 'vim.fs.dirname(dir)')" "1"
chk "down is joined, not parsed"      "$(awk '/^local function browse_step/,/^end/' "$IDE" | grep -c "dir .. '/' .. name")" "1"
chk "and must exist to be entered"    "$(awk '/^local function browse_step/,/^end/' "$IDE" | grep -c 'isdirectory(target)')" "1"

# fzf-lua when it is there; vim.ui.select cannot stay open, so it reopens after
# each step instead, and still never commits a root until "use this folder".
chk "fzf-lua is preferred"            "$(grep -c 'fzf.fzf_exec(function(cb)' "$IDE")" "1"
chk "the fallback reopens per step"   "$(grep -c 'vim.schedule(ask)' "$IDE")" "1"

# Row markers are plain Unicode, not Nerd Font glyphs: the prompt has to read on
# a terminal that has not had the font selected yet.
chk "the row markers need no patched font" \
  "$(grep -cE "^local ROW_(USE|UP|DOWN) *= '(✓|↑|↓)  '" "$IDE")" "3"

# The key goes through neo-tree's own mappings. neo-tree resets buffer mappings
# on render, so a FileType binding is lost whenever neo-tree binds the same key
# — which is what happened to <C-r>, neo-tree's clear_clipboard, in the version
# before this one. The check that let it ship asked only whether *something*
# was mapped to <C-r>.
chk "O is bound through neo-tree"     "$(grep -c "\['O'\] = root_pick" "$PLUG")" "1"
chk "no FileType binding for it"      "$(grep -c "'<C-r>', M.root_pick" "$IDE")" "0"
chk "and <C-r> is left to neo-tree"   "$(grep -cE "\['<C-r>'\] *=" "$PLUG")" "0"

# The first line fits the pane. The button used to be appended after neo-tree's
# text, and neo-tree truncates a line from the right, so in a 34-column pane a
# root like ~/Coding/nanolander/share/nvim lost the arrow and the button — the
# button vanished after its first use. The path gives way instead, from the left.
chk "the root line is fitted to the pane" "$(grep -c '^function M.root_label' "$IDE")" "1"
chk "it shortens from the left"            "$(awk '/^function M.root_label/,/^end/' "$IDE" | grep -c "name = '…' .. keep")" "1"
chk "and measures the real window"         "$(awk '/^function M.root_label/,/^end/' "$IDE" | grep -c 'nvim_win_get_width(win)')" "1"

# ,sp writes session.nvim and shada.nvim into whatever directory it is run in,
# so working on this repository and saving a session drops both into its root.
# They reached a commit once, through git add -A. Ignored now, and asserted
# here because the next such commit would look just as ordinary.
IGNORE="$REPO_ROOT/.gitignore"
for f in session.nvim shada.nvim session.vim viminfo.vim; do
  chk "$f is ignored" "$(grep -cx "$f" "$IGNORE")" "1"
done
chk "and none is tracked" \
  "$(cd "$REPO_ROOT" && git ls-files session.nvim shada.nvim session.vim viminfo.vim | wc -l | tr -d ' ')" "0"
# The pair init.vim actually writes has to be the pair that is ignored.
chk "init.vim writes what is ignored" \
  "$(grep -cE 'mksession! session\.nvim|wshada! shada\.nvim' "$REPO_ROOT/share/nvim/init.vim")" "2"

finish
