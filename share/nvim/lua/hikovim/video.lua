-- hikovim video preview — what a video file shows when you open one.
--
-- Opening an .mp4 in a text editor is normally a mistake: Neovim reads a few
-- megabytes of binary, guesses at an encoding and fills the window with
-- rubbish. This replaces that with what yazi shows for the same file — a frame
-- out of the middle, and the numbers worth knowing.
--
--     photo-shoot.mp4
--     1920×1080 · h264 · 29.97 fps
--     00:02:14 · 12.4 MB · 1.8 Mbps
--
--     ┌───────────────────────────┐
--     │  a frame, drawn by        │
--     │  image.nvim               │
--     └───────────────────────────┘
--
-- It plays nothing. Playback in a buffer is not a missing feature, it is the
-- wrong place for it: one 960×540 frame is 625 KB of sixel, so 24 fps means
-- 14 MB/s of escape sequences for the terminal to parse, and a sixel image is
-- painted on the terminal rather than owned by a buffer — every statusline tick
-- would tear through it. To watch the file, hand it to something that watches
-- files.
--
-- ffmpeg and ffprobe both come from the FFmpeg entry in nanolander's catalog,
-- and the drawing is image.nvim, which is already here for images. So this
-- costs no new dependency. Where any of the three is missing the preview loses
-- that part and says so, rather than failing.

local M = {}

-- The extensions worth intercepting live in media.lua, because ide.lua needs
-- the same list to decide what a double click hands to the system viewer, and
-- image.nvim needs the picture half of it. Two copies is how a container gets
-- a preview and no viewer.
local media = require('hikovim.media')

-- Room for the picture underneath the text. A terminal-painted image is not
-- made of buffer lines, so without these the window is mostly `~` and
-- scrolling behaves oddly.
local FILLER_LINES = 60

local function have(cmd)
  return vim.fn.executable(cmd) == 1
end

-- hms — 134.6 seconds as 00:02:14.
local function hms(seconds)
  local n = math.floor(tonumber(seconds) or 0)
  return ('%02d:%02d:%02d'):format(n / 3600, (n % 3600) / 60, n % 60)
end

local function human_bytes(bytes)
  local b = tonumber(bytes)
  if not b then return nil end
  local units = { 'B', 'KB', 'MB', 'GB' }
  local i = 1
  while b >= 1024 and i < #units do
    b = b / 1024
    i = i + 1
  end
  return ('%.1f %s'):format(b, units[i])
end

-- fps — ffprobe reports the frame rate as a fraction, "30000/1001".
local function fps(rate)
  if not rate then return nil end
  local num, den = rate:match('^(%d+)/(%d+)$')
  if not num then return nil end
  den = tonumber(den)
  if den == 0 then return nil end
  return ('%.4g fps'):format(tonumber(num) / den)
end

-- join — the parts of one line that actually came back, separated by a dot.
--
-- Varargs, and counted with select('#'), because ffprobe leaves gaps: a file
-- with a codec but no resolution gives (nil, 'theora', nil). Passing that as a
-- table and walking it with ipairs stops at the first nil, so the line came out
-- empty and a sparsely described file lost it entirely.
local function join(...)
  local kept = {}
  for i = 1, select('#', ...) do
    local p = select(i, ...)
    if p and p ~= '' then kept[#kept + 1] = p end
  end
  if #kept == 0 then return nil end
  return '  ' .. table.concat(kept, ' · ')
end

-- describe — ffprobe's key=value output as the lines above the frame. A module
-- function rather than a local so the suite can assert the formatting without
-- needing ffmpeg on the machine running it.
function M.describe(path, out)
  local f = {}
  for key, value in out:gmatch('([%w_]+)=([^\n]*)') do
    -- Streams come before format, and format's duration is the authoritative
    -- one, so later keys are allowed to win.
    if value ~= 'N/A' and value ~= '' then f[key] = value end
  end

  local lines = { '  ' .. vim.fn.fnamemodify(path, ':t') }
  local size = (f.width and f.height) and (f.width .. '×' .. f.height) or nil
  lines[#lines + 1] = join(size, f.codec_name, fps(f.r_frame_rate))
  lines[#lines + 1] = join(
    f.duration and hms(f.duration) or nil,
    human_bytes(f.size),
    f.bit_rate and ('%.3g Mbps'):format(tonumber(f.bit_rate) / 1e6) or nil
  )
  return lines, tonumber(f.duration)
end

local function set_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local body = vim.list_extend(vim.deepcopy(lines), { '' })
  for _ = 1, FILLER_LINES do
    body[#body + 1] = ''
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, body)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

-- show_frame — draw the extracted still under the text.
local function show_frame(buf, thumb, y)
  local ok, image = pcall(require, 'image')
  -- No image.nvim means no UI to draw into: the numbers are the whole preview,
  -- which is also what happens under `nvim --headless`.
  if not ok then return end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then return end
  local made, img = pcall(image.from_file, thumb, {
    window = win, buffer = buf, x = 0, y = y,
  })
  if made and img then pcall(function() img:render() end) end
end

-- M.frame_at — where the frame is taken: a tenth of the way in, so it is not
-- the black frame most files open on.
function M.frame_at(duration)
  if duration and duration > 4 then return duration * 0.1 end
  return 0
end

-- M.frame_argv — the one ffmpeg command that takes that frame. Exported so the
-- explorer pane's preview (peek.lua) takes the same frame rather than a copy of
-- the command drifting away from this one.
function M.frame_argv(path, at, out)
  return {
    'ffmpeg', '-v', 'error', '-y',
    '-ss', tostring(at), '-i', path,
    '-frames:v', '1', out,
  }
end

-- M.probe_argv — the ffprobe query describe() reads. Exported for the same
-- reason as frame_argv.
function M.probe_argv(path)
  return {
    'ffprobe', '-v', 'error',
    '-select_streams', 'v:0',
    '-show_entries', 'stream=codec_name,width,height,r_frame_rate',
    '-show_entries', 'format=duration,size,bit_rate',
    '-of', 'default=noprint_wrappers=1',
    path,
  }
end

-- extract — one frame, into the preview under the text.
local function extract(buf, path, duration, y)
  if not have('ffmpeg') then return end
  local thumb = vim.fn.tempname() .. '.png'
  vim.system(M.frame_argv(path, M.frame_at(duration), thumb), { text = true }, function(res)
    if res.code ~= 0 then return end
    vim.schedule(function()
      if vim.fn.filereadable(thumb) == 1 then show_frame(buf, thumb, y) end
    end)
  end)
end

-- preview — fill the buffer, then go and find out what is in the file.
function M.preview(buf, path)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  -- A view of the file, not the file: nowrite so that :w can never put this
  -- text where the video was, and listed so it is an ordinary tab that :q
  -- closes.
  vim.bo[buf].buftype = 'nowrite'
  vim.bo[buf].buflisted = true
  vim.bo[buf].filetype = 'hikovim_video'
  vim.bo[buf].swapfile = false

  local name = vim.fn.fnamemodify(path, ':t')
  if not have('ffprobe') then
    set_lines(buf, {
      '  ' .. name,
      '  ffprobe is not on PATH, so there is nothing to read the file with.',
      '  It comes with FFmpeg: ./bin/nanolander --only ffmpeg',
    })
    return
  end

  set_lines(buf, { '  ' .. name, '  reading…' })

  vim.system(M.probe_argv(path), { text = true }, function(res)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if res.code ~= 0 then
        set_lines(buf, { '  ' .. name, '  ffprobe could not read this file.' })
        return
      end
      local lines, duration = M.describe(path, res.stdout or '')
      set_lines(buf, lines)
      -- The frame goes below the text, so where it starts depends on how many
      -- of those lines ffprobe actually gave us.
      extract(buf, path, duration, #lines + 1)
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd('BufReadCmd', {
    group = vim.api.nvim_create_augroup('hikovim_video', { clear = true }),
    pattern = media.VIDEO,
    -- Returns nothing, deliberately. A Lua autocmd callback that returns a
    -- truthy value is deleted (:h nvim_create_autocmd), and this one used to
    -- end in `return true` in the belief that it meant "handled". So the first
    -- video of each extension got its preview and removed the autocmd for that
    -- extension, and the second .mp4 of a session opened as binary. Every
    -- headless check opened one file per Neovim, which is why none saw it.
    --
    -- A file that cannot be read is left alone: there is nothing to preview,
    -- and an empty buffer is what Neovim would have given it anyway.
    callback = function(ev)
      if vim.fn.filereadable(ev.file) ~= 1 then return end
      M.preview(ev.buf, vim.fn.fnamemodify(ev.file, ':p'))
    end,
  })
end

return M
