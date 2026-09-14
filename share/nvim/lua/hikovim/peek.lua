-- hikovim peek — a thumbnail in the top-right pane while you move through the
-- explorer.
--
-- Walking the tree with j and k, or one click at a time, and landing on a
-- picture or a video shows it in the pane above — the outline's pane — without
-- touching the editor pane. <CR> or a double click is what opens the file up
-- there. Looking is cheap and choosing is deliberate, the same split as a
-- single click and a double click everywhere else in the tree.
--
-- Built for moving fast, which is the whole point of it:
--
--   * a thumbnail, not the picture: picture.lua's normalise at PEEK_BOX, a
--     fraction of the editor's copy, so a sixel small enough to draw at once
--   * cached by path, modification time and size, so a second pass over the
--     same folder costs an encode and no decode
--   * every request carries a generation number, and a result that comes back
--     after the cursor has moved on is dropped rather than drawn — holding j
--     through a folder of photos must end on the last photo, not on whichever
--     conversion happened to finish last
--
-- It paints its own sixel rather than going through image.nvim, and that is
-- the one thing here not to undo. image.nvim's sixel backend answers any change
-- to any image by clearing the whole screen with :mode and repainting every
-- image on it. With the thumbnail inside image.nvim, every move in the tree
-- cleared the screen and repainted the picture open in the editor pane —
-- measured from the bytes a terminal receives, one to two full clears and a
-- repaint of that picture per move, even onto a text file. Painted here, a move
-- sends one small sixel and nothing else, and the editor pane is left alone.
--
-- Two facts make that safe without :mode:
--
--   * the thumbnail sits over the buffer's blank filler lines, which are blank
--     before and after, so Neovim never writes into those cells and cannot
--     paint over it
--   * Neovim will not rewrite cells whose content did not change — not even for
--     nvim__redraw with valid = false, measured the same way — so taking the
--     thumbnail off is done here too, by writing spaces in the editor's
--     background over exactly the rectangle it covered, which is what Neovim
--     already believes is there
--
-- When image.nvim does clear the screen for its own reasons — a resize, focus
-- coming back to the terminal — the thumbnail goes with everything else, so it
-- is painted again once that flush is done.
--
-- Three more things keep "blank before and after" true, each found by counting
-- what landed on the thumbnail's cells after it was sent:
--
--   * the window's display options: ~/.vimrc's `set list` draws ↵ on every
--     empty line, so the "blank" filler was never blank (media.quiet_window)
--   * the buffer's shape: a fixed header and a fixed body, so moving from one
--     file to the next rewrites the header rows and never a row under the
--     thumbnail. Shrinking to two lines while loading meant every one of those
--     rows was redrawn on every move
--   * the order: Neovim's screen goes out through the TUI, a separate process,
--     and a sixel goes straight to the terminal. With the conversion cached the
--     sixel was sent in the same tick as the redraw and the TUI's text landed
--     0-1 ms after it — which is why the thumbnail worked for the first pass
--     over a folder and never again. The redraw is flushed first, and the sixel
--     waits a moment behind it
--
-- And one thing keeps it cheap: a burst of image.nvim renders — hundreds in a
-- quarter of a second when focus comes back — asks for one repaint, not one each.
--
-- This module owns the buffer and what is drawn in it. Which window it goes in,
-- and when it gives way to the outline again, is ide.lua's business — it is a
-- pane rule, and the pane rules live there.

local M = {}

local media = require('hikovim.media')
local picture = require('hikovim.picture')

-- The largest a thumbnail is made. The pane is a fifth of the screen wide and
-- half the screen tall, so this is already more than it can show at most sizes.
M.PEEK_BOX = '480x480'

-- The filetype ide.lua's pane rule recognises as allowed in the outline pane.
M.FILETYPE = 'hikovim_peek'

-- The buffer's shape, which never changes between files: HEADER_LINES of
-- description and a blank line, then BODY_LINES of filler for the thumbnail to
-- sit on. Descriptions are at most three lines — picture.describe and
-- video.describe both — and a fourth would be cut rather than move the
-- thumbnail down.
M.HEADER_LINES = 4
local BODY_LINES = 200

-- How long a sixel waits behind the redraw it follows. The TUI writes what it
-- was flushed within a few milliseconds; this is comfortably past that and well
-- under what a person can see.
local SETTLE_MS = 24

-- How long the previous thumbnail may stand in for the next one. A cached
-- thumbnail arrives well inside it, so moving between pictures does not blink.
local STALE_MS = 150

local peek_buf
local generation = 0
local showing          -- what the newest request is for: window, path, mtime, size

-- M.buffer — the one scratch buffer every thumbnail is shown in. Unlisted and
-- nofile: it is a view, never a file, and never a tab.
function M.buffer()
  if peek_buf and vim.api.nvim_buf_is_valid(peek_buf) then return peek_buf end
  peek_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[peek_buf].buftype = 'nofile'
  vim.bo[peek_buf].bufhidden = 'hide'
  vim.bo[peek_buf].swapfile = false
  vim.bo[peek_buf].filetype = M.FILETYPE
  vim.api.nvim_buf_set_name(peek_buf, 'peek://')
  return peek_buf
end

function M.is_peek(buf)
  return buf ~= nil and buf == peek_buf and vim.api.nvim_buf_is_valid(buf)
end

-- set_lines — the header rows, over a body that stays exactly as it was. Only
-- the header is written once the body exists, so Neovim has nothing to redraw
-- under the thumbnail.
local function set_lines(header, note)
  local buf = M.buffer()
  local top = {}
  for i = 1, M.HEADER_LINES - 1 do top[i] = header[i] or '' end
  top[M.HEADER_LINES] = ''
  vim.bo[buf].modifiable = true
  if vim.api.nvim_buf_line_count(buf) < M.HEADER_LINES + BODY_LINES then
    local body = {}
    for _ = 1, BODY_LINES do body[#body + 1] = '' end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_extend(top, body))
  else
    vim.api.nvim_buf_set_lines(buf, 0, M.HEADER_LINES, false, top)
  end
  -- A note where the thumbnail would be, only ever when there is none — and the
  -- row is left alone unless it actually changes, since it is under the picture.
  local want = note or ''
  if (vim.api.nvim_buf_get_lines(buf, M.HEADER_LINES, M.HEADER_LINES + 1, false)[1] or '') ~= want then
    vim.api.nvim_buf_set_lines(buf, M.HEADER_LINES, M.HEADER_LINES + 1, false, { want })
  end
  vim.bo[buf].modifiable = false
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

-- What is on the terminal right now, so it can be taken off again exactly:
-- { row, col, rows, cols } in 0-based screen cells, plus what to repaint.
local painted
local last = nil          -- { win, y, png } — the thumbnail that should be showing

-- Encoded sixel per thumbnail and box. A second pass over a folder re-sends
-- bytes instead of running ImageMagick again.
local sixel_cache, sixel_order, SIXEL_CACHE_MAX = {}, {}, 64

local function remember(key, value)
  if not sixel_cache[key] then
    sixel_order[#sixel_order + 1] = key
    if #sixel_order > SIXEL_CACHE_MAX then
      sixel_cache[table.remove(sixel_order, 1)] = nil
    end
  end
  sixel_cache[key] = value
end

local function send(bytes)
  pcall(vim.fn.chansend, vim.v.stderr, bytes)
end

-- cell_size — the terminal's cell in pixels, from image.nvim's own probe, so the
-- two agree on geometry. nil when there is no terminal that answers.
local function cell_size()
  local ok, utils = pcall(require, 'image/utils')
  if not (ok and utils.term and utils.term.get_size) then return nil end
  local got, size = pcall(utils.term.get_size)
  if got and size and (size.cell_width or 0) > 0 and (size.cell_height or 0) > 0 then
    return size.cell_width, size.cell_height
  end
end

-- background_sgr — the escape that sets the editor's background, for the
-- spaces that take a thumbnail off.
local function background_sgr()
  if not vim.o.termguicolors then return '\27[49m' end
  local hex = picture.background()
  return ('\27[48;2;%d;%d;%dm'):format(
    tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16))
end

-- M.erase — spaces over the rectangle the last thumbnail covered.
function M.erase()
  if not painted then return end
  local blank = string.rep(' ', painted.cols)
  local seq = { '\27[s', background_sgr() }
  for i = 0, painted.rows - 1 do
    seq[#seq + 1] = ('\27[%d;%dH'):format(painted.row + i + 1, painted.col + 1) .. blank
  end
  seq[#seq + 1] = '\27[0m\27[u'
  send(table.concat(seq))
  painted = nil
end

-- where — the screen rectangle a thumbnail may use in `win`, below `y` lines of
-- text: 0-based row and column of its top-left cell, and how many cells it has.
local function where(win, y)
  local info = vim.fn.getwininfo(win)[1]
  if not info then return nil end
  local row = info.winrow - 1 + y
  local col = info.wincol - 1 + (info.textoff or 0)
  local rows = info.height - y - 1
  local cols = info.width - (info.textoff or 0) - 1
  if rows < 2 or cols < 4 then return nil end
  return row, col, rows, cols
end

-- paint — put `png` on the terminal in `win`, `y` lines down.
local function paint(win, y, png, still_wanted)
  local cw, ch = cell_size()
  if not cw then return end
  local row, col, rows, cols = where(win, y)
  if not row then return end
  local key = ('%s|%dx%d'):format(png, cols * cw, rows * ch)

  local function place(bytes)
    if not still_wanted() then return end
    -- Whatever this tick changed on screen goes to the TUI now, and the sixel
    -- follows once it has been written. See the header: the other order is the
    -- thumbnail that vanished as soon as its conversion was cached.
    pcall(vim.api.nvim__redraw, { flush = true })
    vim.defer_fn(function()
      if not still_wanted() then return end
      local w, h = bytes:match('"%d+;%d+;(%d+);(%d+)')
      local rect = {
        row = row, col = col, w = w, h = h,
        rows = math.min(rows, math.ceil((tonumber(h) or rows * ch) / ch)),
        cols = math.min(cols, math.ceil((tonumber(w) or cols * cw) / cw)),
      }
      -- The same size in the same place covers the old picture pixel for pixel,
      -- so erasing it first would only be a blink.
      local same = painted and painted.row == rect.row and painted.col == rect.col
        and painted.w == rect.w and painted.h == rect.h
      if not same then M.erase() end
      send('\27[s' .. ('\27[%d;%dH'):format(row + 1, col + 1) .. bytes .. '\27[u')
      painted = rect
    end, SETTLE_MS)
  end

  if sixel_cache[key] then return place(sixel_cache[key]) end
  vim.system({ 'magick', png, '-resize', ('%dx%d>'):format(cols * cw, rows * ch), 'sixel:-' }, {},
    vim.schedule_wrap(function(res)
      if res.code ~= 0 or not res.stdout or res.stdout == '' then return end
      remember(key, res.stdout)
      place(res.stdout)
    end))
end

-- M.repaint — draw the wanted thumbnail again, after something cleared the
-- screen. Nothing when no thumbnail is wanted or its window has gone.
function M.repaint()
  if not last then return end
  if not (vim.api.nvim_win_is_valid(last.win) and vim.api.nvim_win_get_buf(last.win) == peek_buf) then
    last = nil
    return
  end
  painted = nil  -- the screen was cleared; there is nothing of ours left to erase
  local wanted = last
  paint(wanted.win, wanted.y, wanted.png, function() return last == wanted end)
end

-- repaint_after — one repaint, `ms` after the last thing that asked for one.
--
-- Every render image.nvim's sixel backend receives ends in a flush, so each one
-- used to schedule a repaint of its own. When focus comes back to the terminal
-- image.nvim renders hundreds of times in a quarter of a second, and each of
-- those became a thumbnail sent to the terminal: 365 of them, tens of megabytes,
-- in a second and a half — enough to stall the terminal and to cut the editor
-- pane's picture in half on the way. A timer that restarts on every call sends
-- the thumbnail once, after the burst.
local repaint_timer
local function repaint_after(ms)
  repaint_timer = repaint_timer or vim.uv.new_timer()
  repaint_timer:stop()
  repaint_timer:start(ms, 0, vim.schedule_wrap(M.repaint))
end

-- watch_image_nvim — repaint after image.nvim clears the screen. Every render
-- and clear its sixel backend receives ends in a :mode flush 50 ms later, so
-- the thumbnail is put back once that has passed. Installed once, on the
-- module image.nvim itself loads (the slash spelling is a different cache entry
-- from the dotted one, and wrapping that would wrap nothing).
local watching = false
local function watch_image_nvim()
  if watching then return end
  local ok, backend = pcall(require, 'image/backends/sixel')
  if not ok or type(backend) ~= 'table' then return end
  watching = true
  -- A resize moves the pane and redraws the screen, so the thumbnail is placed
  -- again for the new geometry. The callback returns nothing: a truthy return
  -- would delete the autocmd.
  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, {
    group = vim.api.nvim_create_augroup('hikovim_peek', { clear = true }),
    callback = function()
      if last then repaint_after(250) end
    end,
  })
  -- Only the calls that end in a flush. render always does; clear does unless
  -- it is shallow (clear(id, true)), which only forgets the image. Repainting
  -- after a shallow clear sent the same thumbnail twice for nothing.
  local render, clear = backend.render, backend.clear
  backend.render = function(...)
    if last then repaint_after(250) end
    return render(...)
  end
  backend.clear = function(id, shallow, ...)
    if last and not shallow then repaint_after(250) end
    return clear(id, shallow, ...)
  end
end

-- thumbnail — the small copy of a picture, or of a video's frame, then done(png).
local function thumbnail(path, done)
  if media.is_image(path) then
    return picture.normalise(path, M.PEEK_BOX, done)
  end
  -- A video: take the same frame video.lua shows, keep it in the picture cache
  -- under its own key, then shrink it like any picture.
  local video = require('hikovim.video')
  local frame = picture.cache_path(path, 'frame', '')
  if not frame then return done(nil) end
  if vim.uv.fs_stat(frame) then return picture.normalise(frame, M.PEEK_BOX, done) end
  if vim.fn.executable('ffprobe') == 0 or vim.fn.executable('ffmpeg') == 0 then return done(nil) end
  vim.fn.mkdir(vim.fn.fnamemodify(frame, ':h'), 'p')
  vim.system(video.probe_argv(path), { text = true }, vim.schedule_wrap(function(probe)
    local _, duration = video.describe(path, probe.stdout or '')
    vim.system(video.frame_argv(path, video.frame_at(duration), frame), { text = true },
      vim.schedule_wrap(function(res)
        if res.code ~= 0 or not vim.uv.fs_stat(frame) then return done(nil) end
        picture.normalise(frame, M.PEEK_BOX, done)
      end))
  end))
end

-- describe — the lines above the thumbnail, from the same readers the editor
-- pane uses, then done(lines).
local function describe(path, done)
  local name = vim.fn.fnamemodify(path, ':t')
  if media.is_video(path) then
    if vim.fn.executable('ffprobe') == 0 then return done({ '  ' .. name }) end
    local video = require('hikovim.video')
    return vim.system(video.probe_argv(path), { text = true }, vim.schedule_wrap(function(res)
      done(res.code == 0 and (video.describe(path, res.stdout or '')) or { '  ' .. name })
    end))
  end
  local st = vim.uv.fs_stat(path)
  if vim.fn.executable('magick') == 0 then return done({ '  ' .. name }) end
  picture.identify(path, function(info)
    done(picture.describe(name, info, st and st.size))
  end)
end

-- M.show — describe `path` and draw its thumbnail in `win`, which must already
-- be showing M.buffer(). Only the newest request is allowed to draw.
--
-- The same file in the same window again is not a new request. CursorMoved
-- fires twice for one landing when the pane swap makes the tree redraw, and
-- starting over erased a thumbnail that had just arrived and drew it again 300
-- ms later — a blink on exactly the move that should look settled. It puts the
-- thumbnail back in place instead, which also mends one that something else
-- painted over.
function M.show(win, path)
  local st = vim.uv.fs_stat(path)
  local wanted_sig = table.concat({ win, path, st and st.mtime.sec or 0, st and st.size or 0 }, '|')
  if showing == wanted_sig then
    if last then M.repaint() end
    return
  end
  showing = wanted_sig

  generation = generation + 1
  local mine = generation
  local function current()
    return mine == generation and vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_buf(win) == peek_buf
  end
  watch_image_nvim()
  media.quiet_window(win)
  -- The previous thumbnail stays until this one is ready to take its place;
  -- place() erases it then, and only if the two differ. But not for long: a
  -- conversion that is not cached yet takes a moment, and the last file's
  -- picture under this file's name is worse than a gap.
  last = nil
  vim.defer_fn(function()
    if current() and last == nil then M.erase() end
  end, STALE_MS)
  local name = vim.fn.fnamemodify(path, ':t')
  set_lines({ '  ' .. name, '  …' })
  describe(path, function(lines)
    if not current() then return end
    set_lines(lines)
    thumbnail(path, function(png)
      if not current() then return end
      if not png then
        M.erase()
        set_lines(lines, '  no preview for this file')
        return
      end
      last = { win = win, y = M.HEADER_LINES, png = png }
      local wanted = last
      paint(win, M.HEADER_LINES, png, function() return current() and last == wanted end)
    end)
  end)
end

-- M.cancel — make every request still in flight stale. For when the pane gives
-- the outline back.
function M.cancel()
  generation = generation + 1
  showing = nil
  last = nil
  if repaint_timer then repaint_timer:stop() end
  M.erase()
end

M._generation = function() return generation end

return M
