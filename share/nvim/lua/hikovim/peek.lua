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

-- clear — take whatever image is on the terminal for this buffer off it. A sixel
-- is painted, not owned, so a buffer that stops showing does not take its
-- picture with it.
function M.clear()
  local ok, image = pcall(require, 'image')
  if not (ok and peek_buf and vim.api.nvim_buf_is_valid(peek_buf)) then return end
  pcall(function()
    for _, img in ipairs(image.get_images({ buffer = peek_buf })) do img:clear() end
  end)
end

local function draw(win, png, y)
  local ok, image = pcall(require, 'image')
  if not ok or not vim.api.nvim_win_is_valid(win) then return end
  if vim.api.nvim_win_get_buf(win) ~= peek_buf then return end
  M.clear()
  local made, img = pcall(image.from_file, png, { window = win, buffer = peek_buf, x = 0, y = y })
  if made and img then pcall(function() img:render() end) end
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
  M.clear()
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
      draw(win, png, #lines + 1)
    end)
  end)
end

-- M.cancel — make every request still in flight stale. For when the pane gives
-- the outline back.
function M.cancel()
  generation = generation + 1
  M.clear()
end

M._generation = function() return generation end

return M
