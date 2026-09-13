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

local peek_buf
local generation = 0

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

local function set_lines(lines)
  local buf = M.buffer()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
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
    local w, h = bytes:match('"%d+;%d+;(%d+);(%d+)')
    M.erase()
    send('\27[s' .. ('\27[%d;%dH'):format(row + 1, col + 1) .. bytes .. '\27[u')
    painted = {
      row = row, col = col,
      rows = math.min(rows, math.ceil((tonumber(h) or rows * ch) / ch)),
      cols = math.min(cols, math.ceil((tonumber(w) or cols * cw) / cw)),
    }
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
      if last then vim.defer_fn(M.repaint, 250) end
    end,
  })
  -- Only the calls that end in a flush. render always does; clear does unless
  -- it is shallow (clear(id, true)), which only forgets the image. Repainting
  -- after a shallow clear sent the same thumbnail twice for nothing.
  local render, clear = backend.render, backend.clear
  backend.render = function(...)
    if last then vim.defer_fn(M.repaint, 250) end
    return render(...)
  end
  backend.clear = function(id, shallow, ...)
    if last and not shallow then vim.defer_fn(M.repaint, 250) end
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
  vim.system(picture.identify_argv(path), { text = true }, vim.schedule_wrap(function(res)
    local info = res.code == 0 and picture.parse_identify(res.stdout) or nil
    if info and info.format == 'PNG' and (info.frames or 1) <= 1 then
      info.frames = picture.apng_frames(path) or info.frames
    end
    done(picture.describe(name, info, st and st.size))
  end))
end

-- M.show — describe `path` and draw its thumbnail in `win`, which must already
-- be showing M.buffer(). Only the newest request is allowed to draw.
function M.show(win, path)
  generation = generation + 1
  local mine = generation
  local function current()
    return mine == generation and vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_buf(win) == peek_buf
  end
  watch_image_nvim()
  last = nil
  M.erase()
  set_lines({ '  ' .. vim.fn.fnamemodify(path, ':t'), '  …' })
  describe(path, function(lines)
    if not current() then return end
    local body = vim.deepcopy(lines)
    body[#body + 1] = ''
    for _ = 1, 40 do body[#body + 1] = '' end
    set_lines(body)
    thumbnail(path, function(png)
      if not current() then return end
      if not png then
        set_lines(vim.list_extend(vim.deepcopy(lines), { '', '  no preview for this file' }))
        return
      end
      last = { win = win, y = #lines + 1, png = png }
      local wanted = last
      paint(win, #lines + 1, png, function() return current() and last == wanted end)
    end)
  end)
end

-- M.cancel — make every request still in flight stale. For when the pane gives
-- the outline back.
function M.cancel()
  generation = generation + 1
  last = nil
  M.erase()
end

M._generation = function() return generation end

return M
