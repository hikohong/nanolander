-- hikovim IDE layout — the VSCode arrangement, built from the plugins layer 3
-- already installs. Nothing new is fetched; this only decides where the
-- windows go.
--
--   ┌──────────────────────────┬───────────────┐
--   │ file content             │ function list │   aerial.nvim
--   │ (the editor)             │               │
--   │                          ├───────────────┤
--   ├──────────────────────────┤ file tree     │   neo-tree.nvim
--   │ shells, listed in its    │               │
--   │ winbar: 1 zsh ✕ 2 zsh ✕ +│               │
--   └──────────────────────────┴───────────────┘
--         left : right  =  4 : 1
--
-- The explorer pane is a whole-project tree, which is the one thing oil
-- cannot be: oil shows one directory at a time on purpose. oil is still the
-- directory *editor* and still answers <F5> and :e of any directory, so
-- nothing moved — a second plugin was added beside it.
--
--   :IDE        build the layout (or focus the editor when it is up)
--   :IDEClose   drop the three panels, keep the file you were editing
--   :BufClose   close the current tab, buffer and all — what :q now does,
--               and what the ✕ on each tab in the tabline does
--   <F4>        toggle, the key ~/.vimrc used to give taglist
--   <F6>        the terminal pane; pressed again, the next shell in it
--   <F7>        another shell — :IDETerm and :IDETerm! do the same
--
-- Only the editor pane ever shows file contents: <CR> or a double click in
-- the explorer opens the file up there and walks directories in place, and
-- anything else that opens a file inside a pane is moved out of it.
--
-- The panels are ordinary windows, so <C-w>hjkl moves between them and every
-- mapping you already have keeps working inside them.

local M = {}

-- The ratios. RIGHT is the whole right column against the screen, so 1/5
-- makes left:right 4:1 as asked. The other two split each column.
local RIGHT_RATIO   = 1 / 5
local OUTLINE_RATIO = 1 / 2    -- function list against the right column
local TERM_RATIO    = 1 / 4    -- terminal against the left column

-- The close button lualine's buffers component does not have. It becomes a
-- click region of its own on every tab in the tabline.
local CLOSE_ICON = '✕'

-- The root picker's button, on the explorer pane's first line after the sort
-- arrow. A folder with a magnifier: the left-hand icon on that line is already
-- a plain folder, so a second plain folder would read as decoration rather
-- than something to press.
--
-- One copy, exported, because plugins.lua renders it into the root name and
-- root_click has to find it again in the rendered line. Two copies is how the
-- button appears and clicking it does nothing. Same rule as media.lua's
-- extension lists.
M.ROOT_PICK_ICON = '󰥨'

-- How a tab is painted, in both strips: the files along the top and the shells
-- in the terminal pane's winbar.
--
-- badwolf's own inactive colours are blackestgravel on deepgravel — a dark
-- grey on a dark grey, which is legible in a status line and not in a strip of
-- filenames you are meant to read at a glance. The unfocused tabs use tardis,
-- badwolf's blue, on the same dark ground instead. Colours are from the
-- palette ported in hikovim/plugins.lua, so the two strips stay in step.
local TAB_HL = {
  HikovimTabSel  = { fg = '#141413', bg = '#aeee00', bold = true }, -- blackestgravel on lime
  HikovimTab     = { fg = '#0a9dff', bg = '#242321' },              -- tardis on darkgravel
  HikovimTabFill = { bg = '#242321' },
}

-- Highlight groups are cleared by every :colorscheme, so they are set again
-- from the one place that defines them.
local function apply_tab_highlights()
  for group, spec in pairs(TAB_HL) do
    vim.api.nvim_set_hl(0, group, spec)
  end
end

-- ~/.vimrc sets mouse=n, which is enough to click between the panes but not
-- to click back out of the terminal, because terminal mode is not normal
-- mode. 'a' covers every mode and is what makes the layout clickable. Set
-- this to nil to keep whatever ~/.vimrc chose; text selection in the
-- terminal pane then works as it did, and with 'a' you hold the terminal
-- emulator's own modifier (option in iTerm2 and Terminal.app) to select.
local MOUSE = 'a'

-- Start the layout on `nvim` and `nvim file`. Set this to false — or
-- `let g:hikovim_ide_auto = 0` in ~/.vimrc — to keep a plain single window
-- and reach the layout with <F4>.
local AUTO_START = true

-- One click on a file in the explorer pane opens it, the way it does in the
-- editor this layout is shaped after. neo-tree binds only <2-LeftMouse>, so
-- without this a single click moves the cursor and nothing else happens —
-- which reads as the pane being dead rather than as a deliberate default.
-- Set to false to need the double click.
local CLICK_OPENS = true

-- Which windows we built, so close/resize touch only ours. term_buf outlives
-- the window: toggling the layout keeps the same shell and its history.
local state = {
  editor = nil, outline = nil, explorer = nil, term = nil,
  -- The shells in the bottom-left pane, in strip order, and which of them
  -- that pane is showing. They outlive the window: closing the layout, or the
  -- pane itself, leaves every shell running.
  terms = {}, term_cur = nil,
  -- The buffer each pane is meant to be showing, so a file that lands in one
  -- by accident can be put back. Keyed by window id.
  pane_buf = {},
}

local function alive(win)
  return win and vim.api.nvim_win_is_valid(win)
end

-- is_open — the layout counts as up while the editor, the outline and the
-- explorer are there. The terminal pane is deliberately not in that list:
-- closing its last shell closes the pane, and the layout carries on without
-- it until <F6> asks for one again.
function M.is_open()
  return alive(state.editor) and alive(state.outline) and alive(state.explorer)
end

function M.panels()
  local wins = {}
  for _, win in ipairs({ state.outline, state.explorer, state.term }) do
    if alive(win) then table.insert(wins, win) end
  end
  return wins
end

-- editor_win — the one window in this layout that shows file contents, or nil
-- with the layout off. flatten.nvim asks for it: a `nvim file` typed in the
-- terminal pane is a separate process, so the only way its file reaches the
-- right window is for the host to be told which window that is.
function M.editor_win()
  return alive(state.editor) and state.editor or nil
end

-- resize — re-apply the ratios. Called after building and on every VimResized,
-- because a terminal that changed size otherwise leaves the panels wherever
-- Neovim's proportional resize happened to put them.
function M.resize()
  if not M.is_open() then return end

  vim.api.nvim_win_set_width(state.outline, math.floor(vim.o.columns * RIGHT_RATIO))

  local right = vim.api.nvim_win_get_height(state.outline)
              + vim.api.nvim_win_get_height(state.explorer)
  vim.api.nvim_win_set_height(state.outline, math.floor(right * OUTLINE_RATIO))

  if alive(state.term) then
    local left = vim.api.nvim_win_get_height(state.editor)
               + vim.api.nvim_win_get_height(state.term)
    vim.api.nvim_win_set_height(state.term, math.floor(left * TERM_RATIO))
  end
end

-- ---------------------------------------------------------------------------
-- The terminal strip
-- ---------------------------------------------------------------------------
--
-- The bottom-left pane holds any number of shells, listed across its winbar
-- the way the files are listed across the tabline:
--
--   1 zsh ✕  2 zsh ✕  +
--
-- Click a name to switch, the ✕ to close it, + for another one. <F6> and <F7>
-- do the same from the keyboard, and :q inside the pane closes the shell it
-- is showing rather than the window.

-- term_prune — forget shells whose buffer has gone.
local function term_prune()
  local live = {}
  for _, buf in ipairs(state.terms) do
    if vim.api.nvim_buf_is_valid(buf) then live[#live + 1] = buf end
  end
  state.terms = live
  if not (state.term_cur and vim.api.nvim_buf_is_valid(state.term_cur)) then
    state.term_cur = live[1]
  end
  return live
end

-- term_name — what a shell is called in the strip: the program that was
-- started, taken from the term:// name, which stays put where the terminal
-- title changes with every prompt.
local function term_name(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local cmd = name:match('term://.*//%d+:(.*)$') or name
  cmd = vim.fn.fnamemodify(vim.split(cmd, ' ')[1], ':t')
  if cmd == '' then cmd = 'shell' end
  if #cmd > 14 then cmd = cmd:sub(1, 13) .. '…' end
  return (cmd:gsub('%%', '%%%%'))
end

local function term_style(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].winfixheight = true
  -- %{% %} rather than %{ }: the result is itself statusline syntax, which is
  -- what makes the click regions and highlights in it work.
  vim.wo[win].winbar = "%{%v:lua.require'hikovim.ide'.term_winbar()%}"
end

-- term_create — a new shell at the end of the strip, in the given window.
local function term_create(win)
  vim.api.nvim_set_current_win(win)
  vim.cmd('terminal')
  local buf = vim.api.nvim_get_current_buf()
  -- The tabline along the top is for files; shells have a strip of their own.
  vim.bo[buf].buflisted = false
  -- Switching shells, or closing the layout, must not kill the job.
  vim.bo[buf].bufhidden = 'hide'
  state.terms[#state.terms + 1] = buf
  state.term_cur = buf
  return buf
end

-- open_terminal — fill the pane with the shell it was showing last, or start
-- the first one. Toggling the layout therefore comes back to the same shell,
-- history and all.
local function open_terminal(win)
  term_prune()
  vim.api.nvim_set_current_win(win)
  local buf = state.term_cur
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_win_set_buf(win, buf)
  else
    term_create(win)
  end
  term_style(win)
end

---The winbar of the terminal pane. Called on every redraw of that window.
---@return string
function M.term_winbar()
  local strip = {}
  for i, buf in ipairs(term_prune()) do
    strip[#strip + 1] = table.concat({
      buf == state.term_cur and '%#HikovimTabSel#' or '%#HikovimTab#',
      ('%%%d@HikovimTermGo@ %d %s %%T'):format(buf, i, term_name(buf)),
      ('%%%d@HikovimTermClose@%s %%T'):format(buf, CLOSE_ICON),
      '%#HikovimTabFill# ',
    })
  end
  strip[#strip + 1] = '%#HikovimTab#%0@HikovimTermNew@ + %T%#HikovimTabFill#'
  return table.concat(strip)
end

---Show one of the shells, and put the cursor in it.
---@param buf integer
function M.term_go(buf)
  if not (alive(state.term) and vim.api.nvim_buf_is_valid(buf)) then return end
  state.term_cur = buf
  vim.api.nvim_win_set_buf(state.term, buf)
  state.pane_buf[state.term] = buf
  vim.api.nvim_set_current_win(state.term)
end

---Step through the strip.
---@param step integer|nil default 1
function M.term_next(step)
  local list = term_prune()
  if #list < 2 then return end
  local at = 1
  for i, buf in ipairs(list) do
    if buf == state.term_cur then at = i end
  end
  M.term_go(list[(at - 1 + (step or 1)) % #list + 1])
end

---Go to the terminal pane, building it again if its last shell closed it.
---Pressing the key while already there steps to the next shell.
function M.term_focus()
  if alive(state.term) then
    if vim.api.nvim_get_current_win() == state.term then
      M.term_next()
    else
      vim.api.nvim_set_current_win(state.term)
    end
    return
  end
  if not alive(state.editor) then return end
  vim.api.nvim_set_current_win(state.editor)
  vim.cmd('belowright split')
  state.term = vim.api.nvim_get_current_win()
  open_terminal(state.term)
  state.pane_buf[state.term] = vim.api.nvim_win_get_buf(state.term)
  M.resize()
end

---One more shell, at the end of the strip.
function M.term_new()
  if not alive(state.term) then
    M.term_focus()
    if not alive(state.term) then return end
  end
  term_create(state.term)
  term_style(state.term)
  state.pane_buf[state.term] = state.term_cur
end

---Close one shell: the ✕, :q in the pane, and the shell exiting on its own
---all end up here. The job is killed, the pane moves on to the next shell in
---the strip, and closing the last one closes the pane — <F6> brings it back.
---
---Neovim closes a terminal buffer, and the window around it, as soon as the
---job exits (its own nvim.terminal TermClose handler, which runs before ours).
---So by the time an `exit` reaches this function the pane may already be gone,
---and showing the next shell means building the pane again rather than just
---swapping its buffer.
---@param buf integer|nil the shell to close, the visible one when nil
---@param _force boolean|nil accepted so :q! can call this, unused: a shell has
---                          nothing unsaved to lose
function M.term_close(buf, _force)
  buf = buf or state.term_cur
  if not buf then return end

  local at
  for i, b in ipairs(state.terms) do
    if b == buf then at = i break end
  end
  if not at then return end   -- not one of ours
  table.remove(state.terms, at)
  term_prune()

  local following = state.terms[at] or state.terms[at - 1] or state.terms[#state.terms]
  state.term_cur = following

  if following then
    if alive(state.term) then
      vim.api.nvim_win_set_buf(state.term, following)
      state.pane_buf[state.term] = following
    else
      -- The pane came down with the buffer. Put it back, without dragging the
      -- cursor out of wherever it actually is.
      local here = vim.api.nvim_get_current_win()
      M.term_focus()
      if alive(here) and here ~= state.term then vim.api.nvim_set_current_win(here) end
    end
  elseif alive(state.term) then
    local pane = state.term
    state.term = nil
    state.pane_buf[pane] = nil
    pcall(vim.api.nvim_win_close, pane, true)
    if alive(state.editor) then vim.api.nvim_set_current_win(state.editor) end
  else
    state.term = nil
  end

  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  M.resize()
end

vim.cmd([[
  function! HikovimTermGo(bufnr, clicks, button, modifiers) abort
    call v:lua.require'hikovim.ide'.term_go(a:bufnr)
  endfunction
  function! HikovimTermClose(bufnr, clicks, button, modifiers) abort
    call v:lua.require'hikovim.ide'.term_close(a:bufnr)
  endfunction
  function! HikovimTermNew(minwid, clicks, button, modifiers) abort
    call v:lua.require'hikovim.ide'.term_new()
  endfunction
]])

-- ---------------------------------------------------------------------------
-- The file tree
-- ---------------------------------------------------------------------------

-- open_tree — render neo-tree into a window this layout already built.
--
-- neo-tree's `current` position means "the window that is focused right now",
-- and it reads that when the command runs. So the window has to be genuinely
-- focused rather than borrowed through nvim_win_call, which restores focus
-- before neo-tree's own scheduled work has looked. Focus is put back after.
local function open_tree(win)
  if not alive(win) then return false end
  local ok, cmd = pcall(require, 'neo-tree.command')
  if not ok then
    vim.notify('[nanolander] neo-tree.nvim is not installed yet (:Lazy sync).',
      vim.log.levels.WARN)
    return false
  end

  local here = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(win)
  local done = pcall(cmd.execute, {
    action = 'show',
    source = 'filesystem',
    position = 'current',
    dir = vim.fn.getcwd(),
  })
  if alive(here) then vim.api.nvim_set_current_win(here) end
  return done
end

-- ---------------------------------------------------------------------------
-- Keeping each pane to its own job
-- ---------------------------------------------------------------------------
--
-- The panes are ordinary windows, so anything that opens a file — <CR> in the
-- explorer, a quickfix jump, an fzf-lua pick, gf — puts it in whichever window
-- the cursor happened to be in. In this layout only one window shows file
-- contents: the editor pane. Everything below is about enforcing that.

-- What each pane is allowed to hold.
local function pane_kind(win)
  if win == state.outline then return 'aerial' end
  if win == state.explorer then return 'neo-tree' end
  if win == state.term then return 'terminal' end
  return nil
end

local function buf_fits(kind, buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return false end
  if kind == 'terminal' then return vim.bo[buf].buftype == 'terminal' end
  if kind == 'neo-tree' then
    -- A tree neo-tree is still building is a neo-tree:// buffer before its
    -- filetype is set, so the name is the reliable half of this test — the
    -- same trap oil had here before it.
    return vim.bo[buf].filetype == 'neo-tree'
      or vim.api.nvim_buf_get_name(buf):match('^neo%-tree') ~= nil
  end
  -- The outline pane lends itself to the explorer's thumbnail while the cursor
  -- is on a picture or a video (peek.lua). Without this, enforce would see a
  -- buffer that is not aerial, restore the outline, and hand the thumbnail's
  -- buffer to the editor pane — which is exactly the loading-on-every-keypress
  -- the thumbnail exists to avoid.
  if kind == 'aerial' and vim.bo[buf].filetype == 'hikovim_peek' then return true end
  return vim.bo[buf].filetype == kind
end

-- show_in_editor — put a buffer where file contents belong and go there.
local function show_in_editor(buf)
  if not alive(state.editor) then return false end
  vim.api.nvim_win_set_buf(state.editor, buf)
  if vim.bo[buf].buftype == '' then vim.bo[buf].buflisted = true end
  vim.api.nvim_set_current_win(state.editor)
  return true
end

-- restore_pane — give a pane its own buffer back. The remembered one usually
-- still exists; when it does not (someone :bwipeout the explorer) the pane is
-- rebuilt from scratch rather than left holding a file.
local function restore_pane(win, kind)
  local keep = state.pane_buf[win]
  if keep and vim.api.nvim_buf_is_valid(keep) and keep ~= vim.api.nvim_win_get_buf(win) then
    vim.api.nvim_win_set_buf(win, keep)
    return
  end
  local here = vim.api.nvim_get_current_win()
  if kind == 'neo-tree' then
    open_tree(win)
  elseif kind == 'aerial' then
    pcall(function() require('aerial').open_in_win(win, state.editor) end)
  elseif kind == 'terminal' then
    open_terminal(win)
  end
  if alive(here) then vim.api.nvim_set_current_win(here) end
  if alive(win) then state.pane_buf[win] = vim.api.nvim_win_get_buf(win) end
end

-- enforce — run after anything displayed a buffer. A pane showing what it
-- should just has its buffer remembered; a pane showing a file hands that
-- file to the editor pane and takes its own buffer back.
local enforcing = false
function M.enforce()
  if enforcing or not M.is_open() then return end
  enforcing = true
  for _, win in ipairs({ state.outline, state.explorer, state.term }) do
    local kind = alive(win) and pane_kind(win)
    if kind then
      local buf = vim.api.nvim_win_get_buf(win)
      if buf_fits(kind, buf) then
        state.pane_buf[win] = buf
      else
        restore_pane(win, kind)
        show_in_editor(buf)
      end
    end
  end
  enforcing = false
end

-- relocate_quickfix — :copen, :lopen and :make open a window across the full
-- width of the screen, which is the one shape this layout cannot absorb: the
-- rows have to come out of every column, so winfixheight on the panels cannot
-- save them and the terminal ends up one line tall. Move that window inside
-- the editor column instead, between the file and the terminal, where it is
-- the editor pane that gives up the rows.
local function relocate_quickfix(buf)
  if not M.is_open() or not alive(state.editor) then return end

  local qwin
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then qwin = win break end
  end
  if not qwin or pane_kind(qwin) or qwin == state.editor then return end
  -- Already inside the column — nothing to do, and nothing to loop over.
  if vim.api.nvim_win_get_width(qwin) <= vim.api.nvim_win_get_width(state.editor) then
    return
  end

  local here = vim.api.nvim_get_current_win()
  local follow = (here == qwin)
  local height = math.min(vim.api.nvim_win_get_height(qwin), 10)

  vim.api.nvim_win_close(qwin, true)
  vim.api.nvim_set_current_win(state.editor)
  vim.cmd('belowright sbuffer ' .. buf)
  local moved = vim.api.nvim_get_current_win()
  vim.wo[moved].winfixheight = true
  vim.api.nvim_win_set_height(moved, height)

  if not follow and alive(here) then vim.api.nvim_set_current_win(here) end
end

-- tree_open_request — where a file opened from the explorer pane goes.
--
-- neo-tree sits in that pane at position 'current', which is what makes it
-- render into a window the layout built instead of opening a sidebar of its
-- own. Its open_file takes that literally: for 'current' it skips the window
-- search — open_files_do_not_replace_types and all — and runs `:buffer` in the
-- window it is already in. So every file opened from the tree appeared in the
-- explorer pane first and enforce moved it a turn of the loop later.
--
-- Invisible for text, and not for an image. image.nvim hijacks on BufWinEnter,
-- so it built an image bound to the *explorer* window and started drawing
-- there; by the time that finished the buffer had moved, and its renderer
-- bails out of a window that no longer shows the buffer without clearing what
-- it had already painted. A sixel is painted on the terminal rather than owned
-- by a buffer, so the picture stayed on the tree — showing in both panes, and
-- only sometimes, since it depends on which of the two won the race.
--
-- neo-tree fires file_open_requested first and documents the answer: return
-- `{ handled = true }` and it does nothing further. So the layout opens the
-- file in the editor pane itself and the buffer is never displayed anywhere
-- else. Only the plain open is taken — S, s and t still split and open tabs —
-- and with the layout off this hands straight back to neo-tree.
--
-- enforce stays the backstop for anything that still lands in a panel.
--
-- open_in_editor does the placing. `focus` is false for the click that only
-- previews: see tree_click.
---@param path string
---@param bufnr number|nil an existing buffer for that path, when there is one
---@param focus boolean leave the cursor in the editor pane
---@return boolean placed
local function open_in_editor(path, bufnr, focus)
  if not alive(state.editor) then return false end

  local buf = bufnr
  if not (type(buf) == 'number' and buf > 0 and vim.api.nvim_buf_is_valid(buf)) then
    -- bufadd rather than :edit: a buffer number has nothing to escape, which is
    -- the trap neo-tree's own comment on this warns about.
    buf = vim.fn.bufadd(path)
  end
  if buf <= 0 then return false end

  local here = vim.api.nvim_get_current_win()
  -- show_in_editor sets the editor pane's buffer, which is also what makes that
  -- window current for the BufWinEnter it fires — and that event is the one
  -- image.nvim reads to decide where to draw.
  local ok, placed = pcall(show_in_editor, buf)
  if not (ok and placed) then return false end

  -- neo-tree lists whatever it opened, and taking the open away from it took
  -- that with it. A file asked for by name belongs in the tabline even when a
  -- preview plugin has made the buffer nowrite — and image.nvim does exactly
  -- that, during the very BufWinEnter that displays it, so an image clicked in
  -- the tree came up with no tab. show_in_editor's own rule is deliberately
  -- left alone: it also serves enforce, which moves buffers nobody asked for.
  vim.bo[buf].buflisted = true

  if not focus and alive(here) then vim.api.nvim_set_current_win(here) end
  return true
end

---@param args table neo-tree's event argument: path, open_cmd, bufnr, state
---@return table|nil result `{ handled = true }` when the file was placed here
function M.tree_open_request(args)
  if not (type(args) == 'table' and type(args.path) == 'string' and args.path ~= '') then
    return nil
  end
  if (args.open_cmd or 'edit') ~= 'edit' then return nil end
  if not open_in_editor(args.path, args.bufnr, true) then return nil end
  return { handled = true }
end

-- media_path — the file under a tree node when it is a picture or a video, and
-- whether <CR> hands it to the system (a video) or opens it here (a picture).
--
-- media.lua owns both extension lists and both answers, because a second copy
-- means a format gets a thumbnail and no viewer, or the reverse.
local function media_path(node)
  local path = (node and node.type == 'file') and node.path or nil
  if not path then return nil end
  local ok, media = pcall(require, 'hikovim.media')
  if not (ok and media.is_media(path)) then return nil end
  return path, media.opens_externally(path)
end

-- node_of — the node under the cursor in a neo-tree state.
local function node_of(tree_state)
  if not (type(tree_state) == 'table' and tree_state.tree) then return nil end
  local ok, node = pcall(function() return tree_state.tree:get_node() end)
  return ok and node or nil
end

-- tree_state — neo-tree's state for the explorer pane.
--
-- neo-tree hands its own commands a state to read; a plain keymap like
-- tree_click has to go and ask for one, and ask the right way: an empty state
-- meant tree_click saw no node and every click fell through to <CR>. Wrapped,
-- because a neo-tree that is not loaded must cost a click rather than an error.
--
-- get_state('filesystem') returns the state held for the *tab*, and this tree
-- is at position 'current', whose state is held per window; that call creates
-- and returns an empty one. So this is the only place the question is asked,
-- and tree_node and root_pick both come through here rather than each asking
-- in its own way.
local function tree_state()
  local ok, manager = pcall(require, 'neo-tree.sources.manager')
  if not ok then return nil end
  local got, state_for_window = pcall(manager.get_state_for_window)
  if not got then return nil end
  return state_for_window
end

local function tree_node()
  return node_of(tree_state())
end

-- hand_to_system — what to do with a video or a picture, which is not to show
-- it properly here.
--
-- The preview is the point of the boundary, not a shortfall of it. video.lua
-- draws one frame and plays nothing: a sixel image is painted on the terminal
-- rather than owned by a buffer, so 24 fps would be 14 MB/s of escape sequences
-- with the statusline tearing through every one. A picture has the same ceiling
-- from the other side — sixel in a pane a third of the screen wide is a
-- thumbnail, not a look at the image. Both say the same thing: hand the file to
-- the application that does this.
--
-- vim.ui.open is `open` on macOS and `xdg-open` on a Linux desktop, so the file
-- goes to whatever owns the type — VLC for a video on a machine that has run
-- bin/vlc-default, and whatever the system already opens pictures with. Nothing
-- here names an application: that binding belongs to the system, and saying it
-- twice is how the two come apart.
local function hand_to_system(path)
  -- vim.ui.open answers nil and a reason rather than throwing, and a box with
  -- no desktop is exactly that case — over SSH there is nothing to hand a file
  -- to. Say so; silence here is indistinguishable from a click that missed.
  local opened, err = vim.ui.open(path)
  if opened then return end

  local why = err or 'no handler for this file type'
  -- The remote answer differs by kind, so only offer the one that applies.
  local ok, media = pcall(require, 'hikovim.media')
  local hint = (ok and media.is_video(path))
    and '\nOver SSH, try mpv --vo=tct'
    or '\nOver SSH, the preview in the editor pane is what there is.'
  vim.notify(('cannot open %s: %s%s'):format(
    vim.fn.fnamemodify(path, ':t'), why, hint), vim.log.levels.WARN)
end

-- tree_open — <CR> and the double click in the explorer pane: "I have chosen
-- this one". A picture opens in the editor pane, drawn from its full normalised
-- copy; a video goes to the system's player, since the editor pane can only show
-- one frame of it. Everything else — a directory to expand, any other file —
-- goes to neo-tree's own open, so both keys keep doing what neo-tree documents.
--
-- A single click means "show me this one", which is tree_click below, and moving
-- onto a file does the same: the thumbnail in the pane above.
---@param tree_state table neo-tree's state for the source the mapping fired in
function M.tree_open(tree_state)
  local path, external = media_path(node_of(tree_state))
  if not path then
    pcall(function()
      require('neo-tree.sources.filesystem.commands').open(tree_state)
    end)
    return
  end
  if external then return hand_to_system(path) end
  open_in_editor(path, nil, true)
end

-- tree_system_open — gx in the explorer pane: this file, to whatever the system
-- opens it with. The way to a system viewer for a picture now that <CR> opens it
-- here, and the same meaning gx has in oil and in Neovim itself.
---@param tree_state table
function M.tree_system_open(tree_state)
  local node = node_of(tree_state)
  if node and node.type == 'file' and node.path then hand_to_system(node.path) end
end

-- The explorer pane needs no <CR> of its own for anything but a video or a
-- picture: neo-tree expands and collapses a directory in place, and a file goes
-- through tree_open_request above.
--
-- It does need a single click. neo-tree binds <2-LeftMouse> and nothing else,
-- so one click only moved the cursor, which is indistinguishable from a pane
-- that does not work.
--
-- For anything the system does not own, tree_click delegates to whatever <CR> is
-- bound to in that buffer rather than calling into neo-tree's own command
-- modules. The click has already moved the cursor by the time <LeftRelease> is
-- processed, so <CR>'s handler is looking at the line that was clicked, and this
-- keeps working if neo-tree renames anything behind its keymaps.
--
-- A video and a picture are the exception, and for two reasons that point the
-- same way. One click means "show me this one", so it previews rather than
-- starting an application. And it must leave the cursor in the tree, because a
-- mouse mapping is looked up in the buffer that is current when the key is
-- processed: the first click of a double click used to open the preview *and*
-- jump to the editor pane, where <2-LeftMouse> is not mapped, so the second
-- click reached nothing and the double click did nothing at all.
-- ---------------------------------------------------------------------------
-- The thumbnail in the outline's pane
-- ---------------------------------------------------------------------------
--
-- While the cursor is on a picture or a video in the explorer, the pane above
-- lends itself to a thumbnail of it (peek.lua), and gives the outline back the
-- moment the cursor is on anything else or leaves the tree. Nothing reaches the
-- editor pane until <CR> or a double click says so.

-- How long the cursor has to rest before a thumbnail is asked for. Short enough
-- to feel immediate, long enough that holding j through a folder does not start
-- a conversion per row it passes.
local PEEK_DELAY_MS = 90

local peek_request = 0

-- peek_hide — give the outline its pane back, if the thumbnail has it.
--
-- The outline is reopened rather than the old aerial buffer put back: aerial
-- keeps one buffer per source buffer, so while the thumbnail was up the editor
-- may have moved on to a file whose outline is a different buffer.
local function peek_hide()
  if not alive(state.outline) then return end
  local ok, peek = pcall(require, 'hikovim.peek')
  if not (ok and peek.is_peek(vim.api.nvim_win_get_buf(state.outline))) then return end
  peek.cancel()
  state.pane_buf[state.outline] = nil
  restore_pane(state.outline, 'aerial')
end

-- peek_update — show the file under the explorer's cursor above it, or hide.
local function peek_update()
  if not (M.is_open() and alive(state.outline) and alive(state.explorer)) then return end
  if vim.api.nvim_get_current_win() ~= state.explorer then return end
  local path = media_path(tree_node())
  if not path then return peek_hide() end
  local ok, peek = pcall(require, 'hikovim.peek')
  if not ok then return end
  local buf = peek.buffer()
  if vim.api.nvim_win_get_buf(state.outline) ~= buf then
    vim.api.nvim_win_set_buf(state.outline, buf)
  end
  state.pane_buf[state.outline] = buf
  peek.show(state.outline, path)
end

-- M.peek_now — for the single click, which may not move the cursor at all.
function M.peek_now()
  peek_request = peek_request + 1
  peek_update()
end

-- peek_soon — for CursorMoved: only the last move in a burst asks.
local function peek_soon()
  peek_request = peek_request + 1
  local mine = peek_request
  vim.defer_fn(function()
    if mine == peek_request then peek_update() end
  end, PEEK_DELAY_MS)
end

-- The root picker is a folder browser, not a one-shot list. Choosing a row
-- walks into it and the list redraws in place; the root is only set when you
-- say so. Picking the destination from a flat list of ancestors and children
-- closed on the first Enter, so reaching anything two levels away took a
-- reopen per level.
--
-- Three kinds of row, told apart by their first characters. Plain Unicode on
-- purpose: the prompt has to read correctly on a terminal that has not had the
-- Nerd Font selected yet.
local ROW_USE  = '✓  '   -- set the root to the folder being browsed, and close
local ROW_UP   = '↑  '   -- browse the parent
local ROW_DOWN = '↓  '   -- browse this subfolder

-- browse_rows — what the picker shows while browsing `dir`.
--
-- The "use this folder" row comes first so it is where the cursor lands after
-- every step: arriving somewhere and pressing Enter again is how you say
-- "here". Subfolders are listed by name only, since the header already says
-- where you are and a full path per row buries the part that differs.
local function browse_rows(dir)
  local rows = { ROW_USE .. 'use this folder   ' .. vim.fn.fnamemodify(dir, ':~') }
  local parent = vim.fs.dirname(dir)
  if parent and parent ~= dir then
    rows[#rows + 1] = ROW_UP .. '..   ' .. vim.fn.fnamemodify(parent, ':~')
  end
  -- fs.dir rather than a glob, so a bracket or a space in a name cannot change
  -- what is listed.
  local names = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == 'directory' then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    rows[#rows + 1] = ROW_DOWN .. name .. '/'
  end
  return rows
end

-- browse_step — where a chosen row leads, given the folder being browsed.
--
-- Returns the next folder to browse, or `true` for "use this one". The path is
-- never read back out of the row text: an up row is the parent of `dir`, and a
-- down row is `dir` joined with the name, so a `~` in the display or a folder
-- literally named "..   x" cannot send the browser somewhere else.
local function browse_step(dir, row)
  if type(row) ~= 'string' then return nil end
  if row:sub(1, #ROW_USE) == ROW_USE then return true end
  if row:sub(1, #ROW_UP) == ROW_UP then
    local parent = vim.fs.dirname(dir)
    return (parent and parent ~= dir) and parent or nil
  end
  if row:sub(1, #ROW_DOWN) == ROW_DOWN then
    local name = row:sub(#ROW_DOWN + 1):gsub('/$', '')
    if name == '' then return nil end
    local target = dir .. '/' .. name
    return vim.fn.isdirectory(target) == 1 and target or nil
  end
  return nil
end
M._browse_rows, M._browse_step = browse_rows, browse_step

-- root_set — re-root the explorer pane.
--
-- The pane is neo-tree at position 'current', so :Neotree renders into
-- whichever window is focused. The picker is a floating window, so focus is
-- not the tree by the time a choice comes back — the window has to be made
-- current again first, or the editor pane becomes a second tree.
local function root_set(win, path)
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  vim.api.nvim_set_current_win(win)
  local ok, command = pcall(require, 'neo-tree.command')
  if not ok then
    vim.notify('[nanolander] neo-tree is not installed yet (:Lazy sync).',
      vim.log.levels.WARN)
    return
  end
  pcall(command.execute, { action = 'focus', source = 'filesystem', dir = path })
end

-- close_fzf — shut the picker from inside one of its own reload actions.
--
-- A reload action is exactly one that fzf does not close, so the "use this
-- folder" row has to close it itself. Deferred, because the action is still
-- running inside fzf's execute when this is called.
local function close_fzf()
  vim.schedule(function()
    local ok, win = pcall(require, 'fzf-lua.win')
    local self = ok and win.__SELF and win.__SELF()
    if self then pcall(self.close, self) end
  end)
end

-- M.root_pick — the floating folder browser, on the icon and on O in the tree.
--
-- fzf-lua when it is there: the list redraws in place through a reload action,
-- so walking five folders deep is five Enters in one window. vim.ui.select
-- otherwise, which cannot stay open, so it reopens after each step instead —
-- slower, and still never commits a root until "use this folder" is chosen.
-- Layer 3 has to stay useful on a box whose first start had no network.
function M.root_pick()
  local win = vim.api.nvim_get_current_win()
  local state_for_window = tree_state()
  local start = (state_for_window and state_for_window.path) or vim.uv.cwd()
  if not start then return end
  local browsing = start

  local has_fzf, fzf = pcall(require, 'fzf-lua')
  if has_fzf and fzf.fzf_exec then
    local function step(selected)
      local nxt = browse_step(browsing, selected and selected[1])
      if nxt == true then
        root_set(win, browsing)
        close_fzf()
      elseif nxt then
        browsing = nxt
      end
    end
    -- Enter and a double click both mean "go there"; a single click only moves
    -- the cursor, so it can never walk you somewhere by accident. The query is
    -- cleared and the cursor put back on "use this folder" after every step:
    -- a filter typed to find one subfolder would otherwise hide the rows of the
    -- next folder, and leave the cursor on some arbitrary row of it.
    local walk = { fn = step, reload = true, postfix = 'clear-query+first' }
    fzf.fzf_exec(function(cb)
      for _, row in ipairs(browse_rows(browsing)) do cb(row) end
      cb()
    end, {
      prompt = 'Tree root> ',
      winopts = { height = 0.6, width = 0.6, title = ' Choose the tree root ' },
      fzf_opts = {
        ['--no-sort'] = true,
        ['--header'] = 'Enter / double-click: open   ·   ✓ row or Ctrl-Y: use as root   ·   Esc: cancel',
        ['--header-first'] = true,
      },
      actions = {
        ['enter'] = walk,
        ['double-click'] = walk,
        ['ctrl-y'] = function() root_set(win, browsing) end,
      },
    })
    return
  end

  local function ask()
    vim.ui.select(browse_rows(browsing), {
      prompt = 'Tree root: ' .. vim.fn.fnamemodify(browsing, ':~'),
    }, function(choice)
      local nxt = browse_step(browsing, choice)
      if nxt == true then
        root_set(win, browsing)
      elseif nxt then
        browsing = nxt
        vim.schedule(ask)
      end
    end)
  end
  ask()
end

-- M.root_label — the explorer pane's first line: the root, neo-tree's sort
-- arrow, and the picker button, fitted to the pane.
--
-- The button used to be appended to whatever neo-tree produced, and neo-tree's
-- container truncates a line that does not fit from the right. The explorer
-- pane is a fifth of the screen, so a root a few folders deep —
-- ~/Coding/nanolander/share/nvim in a 34-column pane — lost the sort arrow and
-- the button off the end, and the button vanished after its first use. So the
-- path gives way instead, from the left: the end of a path is the part that
-- says where you are.
--
-- `text` is what neo-tree's own name component returned, `name` the root as
-- neo-tree names it. Anything neo-tree appended after the name — the arrow
-- today — is kept exactly as it was; only the name is shortened.
function M.root_label(text, name, win)
  local suffix = ''
  if type(name) == 'string' and text:sub(1, #name) == name then
    suffix = text:sub(#name + 1)
  else
    name = text
  end
  local button = '  ' .. M.ROOT_PICK_ICON
  local width = (win and vim.api.nvim_win_is_valid(win)) and vim.api.nvim_win_get_width(win) or 80
  -- Three cells for the indent and the folder icon neo-tree draws before the
  -- name, and one spare so the button never sits in the last column, where a
  -- terminal can wrap or clip it.
  local budget = width - 4 - vim.fn.strdisplaywidth(suffix) - vim.fn.strdisplaywidth(button)
  if budget < 4 then budget = 4 end
  if vim.fn.strdisplaywidth(name) > budget then
    local keep = name
    while vim.fn.strdisplaywidth('…' .. keep) > budget and vim.fn.strchars(keep) > 1 do
      keep = vim.fn.strcharpart(keep, 1)
    end
    -- Start at a separator when there is one to start at, so it reads …/share/nvim
    -- rather than …are/nvim.
    local slash = keep:find('/', 2, true)
    if slash and vim.fn.strdisplaywidth('…' .. keep:sub(slash)) <= budget then
      keep = keep:sub(slash)
    end
    name = '…' .. keep
  end
  return name .. suffix .. button
end

-- root_click — was this click on the picker button?
--
-- The button's column is not computed. The rendered first line is searched for
-- the icon and the click's byte column compared against where it actually
-- landed, because the text before it is neo-tree's: an indent, a folder icon,
-- the root name, and a sort arrow that is there only at position 'current'.
-- Anything that counted columns would be wrong the first time one of those
-- changed width.
local function root_click()
  local pos = vim.fn.getmousepos()
  if pos.line ~= 1 or pos.column < 1 then return false end
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  if not line then return false end
  local from, to = line:find(M.ROOT_PICK_ICON, 1, true)
  if not from then return false end
  -- One cell of slack on each side: the glyph is one column wide and a click
  -- at its edge is a click on it.
  if pos.column < from - 1 or pos.column > to + 1 then return false end
  M.root_pick()
  return true
end

local function tree_click()
  if root_click() then return end
  if media_path(tree_node()) then
    -- "Show me this one": the thumbnail in the pane above, and nothing else.
    -- The cursor stays in the tree, which is what keeps the second click of a
    -- double click on a buffer that maps <2-LeftMouse>. Asked for directly
    -- rather than left to CursorMoved, because a click on the row the cursor is
    -- already on moves nothing.
    M.peek_now()
    return
  end
  local m = vim.fn.maparg('<CR>', 'n', false, true)
  if m and m.callback then pcall(m.callback) end
end

-- outline_select — the same rule for the top-right pane: aerial jumps in the
-- editor window, never in whichever window it last saw the cursor in, which
-- with a terminal in the layout could be the terminal.
local function outline_select()
  local ok, aerial = pcall(require, 'aerial')
  if not ok then return end
  if alive(state.editor) then
    aerial.select({ winid = state.editor, quiet = true })
    vim.api.nvim_set_current_win(state.editor)
  else
    aerial.select({ quiet = true })
  end
end

-- settle_focus — leave the cursor in the editor pane, in normal mode, and keep
-- checking for a moment.
--
-- The panes fill themselves asynchronously: neo-tree scans the directory and
-- focuses its own window when the scan lands, which is after open() has already
-- returned, so a single vim.schedule runs too early and is then undone. This
-- re-checks a few times across a fifth of a second and stops as soon as it
-- finds what it wants.
--
-- A fresh Neovim has to come up in the editor pane in normal mode. Every
-- mapping in the panels is normal-mode, so insert mode there makes the whole
-- right column look like it does nothing.
--
-- Bounded on purpose: it gives up rather than fighting anyone who deliberately
-- clicks into a panel while the layout is still settling.
local function settle_focus()
  local tries = 0
  local function once()
    tries = tries + 1
    if not (alive(state.editor) and M.is_open()) then return end
    if vim.api.nvim_get_current_win() ~= state.editor then
      vim.api.nvim_set_current_win(state.editor)
    end
    if vim.fn.mode() ~= 'n' then vim.cmd('stopinsert') end
    local settled = vim.api.nvim_get_current_win() == state.editor
      and vim.fn.mode() == 'n'
    if not settled and tries < 4 then vim.defer_fn(once, 60) end
  end
  vim.schedule(once)
  vim.defer_fn(once, 60)
end

-- open — build the layout. Every other window is closed first: the point of
-- an IDE layout is that the four panes are always in the same place, which a
-- leftover split from earlier would break. Buffers are untouched, so nothing
-- is lost — :b brings any of them back into the editor pane.
function M.open()
  if M.is_open() then
    vim.api.nvim_set_current_win(state.editor)
    return
  end

  if #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.cmd('only') end
  state.editor = vim.api.nvim_get_current_win()

  -- The right column, full height, then split for the explorer underneath.
  vim.cmd('botright vsplit')
  state.outline = vim.api.nvim_get_current_win()
  vim.cmd('belowright split')
  state.explorer = vim.api.nvim_get_current_win()

  -- The terminal, below the editor and inside the left column only.
  vim.api.nvim_set_current_win(state.editor)
  vim.cmd('belowright split')
  state.term = vim.api.nvim_get_current_win()
  open_terminal(state.term)

  -- neo-tree in the bottom right: the whole project, expandable, following
  -- whichever file the editor pane is on.
  open_tree(state.explorer)

  -- aerial in the top right, pointed at the editor pane. open_in_win is
  -- aerial's own hook for custom layouts, so it fills a window we placed
  -- rather than opening one of its own.
  local ok_aerial, aerial = pcall(require, 'aerial')
  if ok_aerial then
    -- aerial only leaves a window's width alone once this is set on it.
    vim.w[state.outline].aerial_set_width = true
    aerial.open_in_win(state.outline, state.editor)
  else
    vim.notify('[nanolander] aerial.nvim is not installed yet (:Lazy sync).', vim.log.levels.WARN)
  end

  -- Fixed so that opening a split in the editor pane, or :resize inside one,
  -- cannot steal the columns back from the panels.
  for _, win in ipairs({ state.outline, state.explorer }) do
    if alive(win) then
      vim.wo[win].winfixwidth = true
      vim.wo[win].winfixheight = true
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
    end
  end

  for _, win in ipairs({ state.outline, state.explorer, state.term }) do
    if alive(win) then state.pane_buf[win] = vim.api.nvim_win_get_buf(win) end
  end

  M.resize()
  vim.api.nvim_set_current_win(state.editor)

  settle_focus()
end

function M.close()
  for _, win in ipairs(M.panels()) do
    pcall(vim.api.nvim_win_close, win, true)
  end
  state.outline, state.explorer, state.term = nil, nil, nil
  state.pane_buf = {}
  if alive(state.editor) then vim.api.nvim_set_current_win(state.editor) end
end

function M.toggle()
  if M.is_open() then M.close() else M.open() end
end

-- only_panels_left — true when the editor pane is gone and nothing but our
-- panels remains. Without this, :q on the last file leaves Neovim sitting
-- there showing an outline of nothing and a file explorer.
local function only_panels_left()
  local panels = M.panels()
  if #panels == 0 then return false end
  local open = vim.api.nvim_tabpage_list_wins(0)
  if #open ~= #panels then return false end
  for _, win in ipairs(open) do
    if not vim.tbl_contains(panels, win) then return false end
  end
  return true
end

-- editor_gone — :q closed the editor pane and only our panels are left. With
-- no window showing a file there is nothing to come back to, so quit, exactly
-- as :q would have if the layout were not here.
--
-- Two things stand in the way of a plain :quitall. Unsaved work is the one
-- that should: it is checked first, and instead of a stranded outline and a
-- terminal you get the layout back with that file in the editor pane. The
-- shell in the terminal pane is the one that should not — a running job makes
-- :quitall refuse with E948 — so it is closed once nothing of yours is at
-- stake.
function M.editor_gone()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == '' and vim.bo[buf].modified then
      local name = vim.api.nvim_buf_get_name(buf)
      vim.notify(('[nanolander] no write since last change for %s'):format(
        name ~= '' and vim.fn.fnamemodify(name, ':~:.') or ('buffer ' .. buf)),
        vim.log.levels.WARN)
      M.rebuild_around(buf)
      return
    end
  end

  for _, buf in ipairs(state.terms) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  state.terms, state.term_cur = {}, nil

  local ok, err = pcall(vim.cmd, 'quitall')
  if not ok then
    vim.notify(tostring(err), vim.log.levels.WARN)
    M.rebuild_around(nil)
  end
end

-- rebuild_around — put the layout back with `buf` in the editor pane. The
-- current window is one of the panels at this point, so it is that window
-- that becomes the editor and M.open's `only` clears the rest.
function M.rebuild_around(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = nil
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted and vim.bo[b].buftype == '' then
        buf = b
        break
      end
    end
  end
  if buf then
    vim.api.nvim_win_set_buf(0, buf)
  else
    vim.cmd('enew')
  end
  state.outline, state.explorer, state.term = nil, nil, nil
  state.pane_buf = {}
  M.open()
end

-- ---------------------------------------------------------------------------
-- Closing a tab
-- ---------------------------------------------------------------------------
--
-- The tabs along the top are buffers, so closing one means deleting the
-- buffer, not just the window that happens to show it. Both routes — the ✕ in
-- the tabline and :q — end up here.

-- next_listed — which buffer the editor pane falls back to. The alternate
-- file first, the way <C-^> would, then the next tab along.
local function next_listed(bufnr)
  local alt = vim.fn.bufnr('#')
  if alt > 0 and alt ~= bufnr and vim.api.nvim_buf_is_valid(alt) and vim.bo[alt].buflisted then
    return alt
  end
  local listed = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= bufnr and vim.bo[buf].buflisted then listed[#listed + 1] = buf end
  end
  for _, buf in ipairs(listed) do
    if buf > bufnr then return buf end
  end
  return listed[#listed]
end

---Close one tab: the buffer goes, the layout stays.
---@param bufnr integer|nil the buffer to close, current one when nil or 0
---@param force boolean|nil discard unsaved changes, what :q! means
function M.close_buffer(bufnr, force)
  if not bufnr or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  -- Not a tab at all — a panel, or the quickfix window. :q means what it
  -- always meant there: close this window.
  if not vim.bo[bufnr].buflisted then
    pcall(vim.cmd, force and 'quit!' or 'quit')
    return
  end

  if vim.bo[bufnr].modified and not force then
    local name = vim.api.nvim_buf_get_name(bufnr)
    vim.notify(('[nanolander] no write since last change for %s — :w first, or :q! to discard'):format(
      name ~= '' and vim.fn.fnamemodify(name, ':~:.') or ('buffer ' .. bufnr)),
      vim.log.levels.WARN)
    return
  end

  local fallback = next_listed(bufnr)
  if not fallback then
    -- The last tab. There is nothing left to edit, so this is a quit.
    M.editor_gone()
    return
  end

  -- Every window showing it moves on first, so deleting the buffer cannot
  -- take a window — or the layout — down with it.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_win_set_buf(win, fallback)
    end
  end
  pcall(vim.api.nvim_buf_delete, bufnr, { force = force == true })
end

-- quit_or_close_tab — what :q runs. In the editor pane it means "close this
-- tab", in the terminal pane "close this shell"; in the outline, the explorer,
-- a split or the quickfix window it still means "close this window", and with
-- the layout off it is left alone entirely.
function M.quit_or_close_tab(force)
  local win = vim.api.nvim_get_current_win()
  if alive(state.term) and win == state.term then
    M.term_close(nil, force)
  elseif M.is_open() and win == state.editor then
    M.close_buffer(nil, force)
  else
    pcall(vim.cmd, force and 'quit!' or 'quit')
  end
end

-- add_tabline_close_button — lualine wraps each tab in one click region that
-- switches to that buffer. Give the ✕ a region of its own, right after the
-- name, so a click there closes instead of switches. The buffer's own render
-- has already measured itself by the time this runs, hence the len fixup:
-- without it lualine truncates the tabline two columns early per tab.
-- close_tab — what the ✕ in the tabline does. Only ever a tab, which means only
-- ever a listed buffer.
--
-- :q in a panel legitimately closes that window, and close_buffer does that.
-- The ✕ must not: a click in the tabline is not a request to dismantle the
-- layout, and the tab it belongs to should not have been there at all.
function M.close_tab(bufnr)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then return end
  if not vim.bo[bufnr].buflisted then return end
  M.close_buffer(bufnr, false)
end

local function add_tabline_close_button()
  local ok, Buffer = pcall(require, 'lualine.components.buffers.buffer')
  if not ok or Buffer.hikovim_close_button then return end

  vim.cmd([[
    function! HikovimTablineClose(bufnr, clicks, button, modifiers) abort
      call v:lua.require'hikovim.ide'.close_tab(a:bufnr)
    endfunction
  ]])

  local original = Buffer.configure_mouse_click
  function Buffer:configure_mouse_click(name)
    local switch = original(self, name)
    self.len = self.len + vim.fn.strchars(CLOSE_ICON)
    return switch .. string.format('%%%d@HikovimTablineClose@%s%%T', self.bufnr, CLOSE_ICON)
  end

  -- Keep the panels out of the tabline.
  --
  -- lualine builds the strip from listed buffers, and then, if the *current*
  -- buffer was not among them, invents a tab for it so you can always see
  -- where you are. Focus a panel and that is what happens: the outline arrives
  -- as `[No Name]`, the tree as `neo-tree filesystem [1002]`, the terminal as
  -- `zsh` — each with a ✕ beside it. None of them is a file you are editing,
  -- and reaching for one of those ✕ is how you lose a pane.
  --
  -- Rather than deleting the invented tab afterwards, this stops it being
  -- invented: while the cursor is in a panel, the file in the editor pane
  -- answers "am I the current one?". lualine then finds a current buffer among
  -- the listed ones, adds nothing, and the tabline goes on highlighting the
  -- file you are editing — which is the truth worth showing while you are
  -- clicking around in the outline.
  local was_current = Buffer.is_current
  function Buffer:is_current()
    if was_current(self) then return true end
    if not pane_kind(vim.api.nvim_get_current_win()) then return false end
    local editor = M.editor_win()
    return editor ~= nil and self.bufnr == vim.api.nvim_win_get_buf(editor)
  end

  Buffer.hikovim_close_button = true
end

-- auto_start_allowed — the layout is for editing. These are the starts where
-- it would be in the way: a $EDITOR call from git, a diff, a piped stdin, or
-- a session that already restored its own windows.
local function auto_start_allowed()
  if vim.g.hikovim_ide_auto == 0 then return false end
  if vim.g.hikovim_stdin then return false end
  if vim.o.diff then return false end
  if #vim.api.nvim_tabpage_list_wins(0) > 1 then return false end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= '' then return false end
  local ft = vim.bo[buf].filetype
  if ft == 'gitcommit' or ft == 'gitrebase' then return false end
  local name = vim.api.nvim_buf_get_name(buf)
  return not name:match('COMMIT_EDITMSG$') and not name:match('MERGE_MSG$')
end

function M.setup()
  vim.api.nvim_create_user_command('IDE', M.open, { desc = 'VSCode-style layout' })
  vim.api.nvim_create_user_command('IDEClose', M.close, { desc = 'Drop the IDE panels' })

  vim.keymap.set({ 'n', 'x', 'o' }, '<F4>', M.toggle,
    { silent = true, desc = 'Toggle the IDE layout' })

  -- <C-w> from inside the terminal, without the <C-\><C-n> first. Terminal
  -- mode has no other use for it, and reaching for the editor pane is what
  -- you want it for nine times out of ten.
  vim.keymap.set('t', '<C-w>', [[<C-\><C-n><C-w>]], { silent = true, desc = 'Window commands' })

  vim.api.nvim_create_user_command('BufClose', function(cmd)
    M.quit_or_close_tab(cmd.bang)
  end, { bang = true, desc = 'Close this tab and its buffer' })

  -- :q closes the tab, buffer and all.
  --
  -- This is a <CR> mapping rather than the obvious :cnoreabbrev because an
  -- abbreviation cannot cover :q!. Vim only looks one character back when the
  -- character before the cursor is not a keyword character, so an abbreviation
  -- ending in ! never fires, and :q! would quietly stay vim's own quit — which
  -- in this layout means closing the editor pane and taking the session with
  -- it. Matching the whole command line here keeps :qa, :wq, :x, :q file and
  -- :1,2q exactly as they were.
  vim.keymap.set('c', '<CR>', function()
    if vim.fn.getcmdtype() == ':' then
      local line = vim.fn.getcmdline()
      if line == 'q' then return '<C-u>BufClose<CR>' end
      if line == 'q!' then return '<C-u>BufClose!<CR>' end
    end
    return '<CR>'
  end, { expr = true, desc = ':q closes the tab rather than the window' })

  add_tabline_close_button()
  apply_tab_highlights()

  vim.api.nvim_create_user_command('IDETerm', function(cmd)
    if cmd.bang then M.term_new() else M.term_focus() end
  end, { bang = true, desc = 'Terminal pane: focus it, or :IDETerm! for another shell' })

  vim.keymap.set({ 'n', 't' }, '<F6>', function() M.term_focus() end,
    { silent = true, desc = 'Terminal pane (again: next shell)' })
  vim.keymap.set({ 'n', 't' }, '<F7>', function() M.term_new() end,
    { silent = true, desc = 'Another shell in the terminal pane' })

  -- Clickable panes. See MOUSE at the top of this file.
  if MOUSE then vim.o.mouse = MOUSE end

  local group = vim.api.nvim_create_augroup('hikovim_ide', { clear = true })

  -- One click opens in the explorer pane. Buffer-local, so it applies to the
  -- tree and to nothing else.
  if CLICK_OPENS then
    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = 'neo-tree',
      callback = function(ev)
        vim.keymap.set('n', '<LeftRelease>', tree_click, {
          buffer = ev.buf, silent = true, nowait = true,
          desc = 'Open what was clicked — files go to the editor pane',
        })
      end,
    })
  end

  -- The thumbnail above the explorer. Not gated on CLICK_OPENS: it follows the
  -- cursor, and the keyboard moves the cursor as much as the mouse does. Both
  -- callbacks return nothing — a Lua autocmd callback that returns a truthy
  -- value is deleted.
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'neo-tree',
    callback = function(ev)
      vim.api.nvim_create_autocmd('CursorMoved', {
        group = group, buffer = ev.buf,
        callback = function() peek_soon() end,
      })
      vim.api.nvim_create_autocmd('WinLeave', {
        group = group, buffer = ev.buf,
        -- Scheduled, so the window being entered is current by the time the
        -- outline is reopened and focus is not pulled back.
        callback = function()
          peek_request = peek_request + 1
          vim.schedule(peek_hide)
        end,
      })
    end,
  })

  -- <CR> and double click in the outline obey the one-editor-window rule. The
  -- explorer pane needs no equivalent; see the note above outline_select.
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'aerial',
    callback = function(ev)
      local opts = { buffer = ev.buf, silent = true, nowait = true }
      vim.keymap.set('n', '<CR>', outline_select,
        vim.tbl_extend('force', opts, { desc = 'Jump to this symbol in the editor pane' }))
      vim.keymap.set('n', '<2-LeftMouse>', outline_select,
        vim.tbl_extend('force', opts, { desc = 'Jump to this symbol in the editor pane' }))
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'qf',
    callback = function(ev)
      vim.schedule(function() pcall(relocate_quickfix, ev.buf) end)
    end,
  })

  -- The catch-all: whatever displayed a buffer — fzf-lua, a quickfix jump, gf,
  -- :bnext — a pane that ends up holding a file hands it to the editor.
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
    group = group,
    callback = function() vim.schedule(function() pcall(M.enforce) end) end,
  })

  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function() pcall(M.resize) end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = apply_tab_highlights,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function()
      vim.schedule(function()
        if only_panels_left() then M.editor_gone() end
      end)
    end,
  })

  -- A shell that exits takes its own tab out of the strip, so `exit` and
  -- Ctrl-D do what the ✕ does. Not while Neovim itself is going down.
  -- Scheduled, so Neovim's own TermClose handler has finished tearing the
  -- buffer down before term_close decides what the pane should show next.
  vim.api.nvim_create_autocmd('TermClose', {
    group = group,
    callback = function(ev)
      if vim.v.exiting ~= vim.NIL then return end
      vim.schedule(function() pcall(M.term_close, ev.buf) end)
    end,
  })

  -- Terminal mode on entry, so the bottom-left pane behaves like the shell it
  -- is rather than a buffer you have to press i in.
  --
  -- Deferred, and then checked again, because startinsert does not take effect
  -- where it is called: it sets a flag, and insert mode begins when control
  -- returns to the main loop. Building the layout focuses the terminal pane to
  -- start its shell and then moves on to the editor pane, so the flag set here
  -- was being spent on the editor — a fresh Neovim came up in insert mode with
  -- the cursor in the file. That also made the explorer pane look dead: its
  -- click mapping is normal-mode, so nothing answered a click until Esc.
  vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
    group = group,
    pattern = 'term://*',
    callback = function()
      vim.schedule(function()
        if vim.bo[vim.api.nvim_get_current_buf()].buftype == 'terminal' then
          vim.cmd('startinsert')
        end
      end)
    end,
  })

  if not AUTO_START then return end

  vim.api.nvim_create_autocmd('StdinReadPre', {
    group = group,
    callback = function() vim.g.hikovim_stdin = true end,
  })

  vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    nested = true,
    callback = function()
      if auto_start_allowed() then pcall(M.open) end
    end,
  })
end

return M
