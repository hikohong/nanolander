-- hikovim picture preview — what a picture shows when you open one.
--
-- image.nvim used to take pictures over by itself, through its
-- hijack_file_patterns, and handed each file straight to ImageMagick and on to
-- sixel. Driving its own pipeline over a corpus of real files showed what that
-- missed, which is most of what "some pictures show nothing" meant:
--
--   a PNG with transparency   sixel has no alpha; 949 bytes, nearly blank
--   an animated PNG (.png)    535 bytes, nearly blank
--   a 7000×5000 PNG           1.2 s to encode, on every redraw
--   an animated WebP          dimensions read as 8960×0, so nothing is drawn
--   a multi-page TIFF         format read as "tifftifftiff"
--   an animated GIF           every frame encoded and stacked into one sixel
--   HEIC, TIFF, SVG, ICO …    not in the list at all, so the raw bytes
--
-- So pictures come through here instead, the way videos come through
-- video.lua: the read is replaced with the numbers, and the picture is drawn
-- from one normalised copy —
--
--   first frame only        [0]: animated and multi-page files draw one image
--   the right way up        -auto-orient: phone photos carry EXIF rotation
--   no transparency         -alpha remove, onto the editor's own background
--   no bigger than needed   -resize 1600x1600>: shrink only, never enlarge
--
-- — cached by path, modification time and size, so the second look is
-- immediate and a changed file is converted again.
--
-- It animates nothing, for the same reason video.lua plays nothing: a sixel is
-- painted on the terminal rather than owned by a buffer, so every frame would
-- tear. An animated file says how many frames it has, and gx hands it to the
-- system's viewer, which plays it.
--
-- Decoding goes ImageMagick, then sips on macOS, then ffmpeg, each one only when
-- the one before could not read the file. All three are already here: magick
-- and ffmpeg from the catalog, sips from the system.

local M = {}

local media = require('hikovim.media')

-- The largest a normalised copy is ever made. image.nvim still fits it to the
-- window; this only keeps a 7000×5000 original from being encoded at full size.
M.DISPLAY_BOX = '1600x1600'

-- Room for the picture under the text; see the same constant in video.lua.
local FILLER_LINES = 60

local function have(cmd)
  return vim.fn.executable(cmd) == 1
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

-- background — the colour transparency is blended onto: the editor's own, so a
-- transparent icon looks the way it would on the page it came from. The cache
-- key includes it, so changing colourscheme converts again.
function M.background()
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = 'Normal', link = false })
  if ok and hl and hl.bg then return ('#%06x'):format(hl.bg) end
  return '#1c1c1c'
end

-- cache_path — where the normalised copy of `path` at `box` lives.
function M.cache_path(path, box, bg)
  local st = vim.uv.fs_stat(path)
  if not st then return nil end
  local key = vim.fn.sha256(table.concat({
    path, st.mtime.sec, st.mtime.nsec or 0, st.size, box, bg or '',
  }, '|'))
  return vim.fn.stdpath('cache') .. '/nanolander/pictures/' .. key .. '.png'
end

-- convert_argv — the one ImageMagick command every picture goes through.
--
-- A module function so the suite can assert each flag without ImageMagick on
-- the machine running it. -density comes before the input because it only
-- means something while a vector format is being rasterised; for a bitmap it
-- is ignored.
function M.convert_argv(src, out, box, bg)
  return {
    'magick', '-density', '144', src .. '[0]',
    '-auto-orient',
    '-background', bg, '-alpha', 'remove', '-alpha', 'off',
    '-resize', box .. '>',
    '-strip',
    'png:' .. out,
  }
end

-- identify_argv — format, size and frame count, read from the file itself.
-- One line per frame comes back for a sequence; the first is the one used.
function M.identify_argv(src)
  return { 'magick', 'identify', '-format', '%m|%w|%h|%n\n', src }
end

-- describe — the lines above the picture.
function M.describe(name, info, bytes)
  local lines = { '  ' .. name }
  local parts = {}
  if info and info.format then parts[#parts + 1] = info.format end
  if info and info.width and info.height then
    parts[#parts + 1] = info.width .. '×' .. info.height
  end
  parts[#parts + 1] = human_bytes(bytes)
  lines[#lines + 1] = '  ' .. table.concat(parts, ' · ')
  local frames = info and tonumber(info.frames) or 1
  if frames > 1 then
    local animated = { GIF = true, WEBP = true, PNG = true, APNG = true, AVIF = true }
    if animated[info.format or ''] then
      lines[#lines + 1] = ('  animated · %d frames — showing the first; gx plays it in the system viewer')
        :format(frames)
    else
      lines[#lines + 1] = ('  %d pages — showing the first'):format(frames)
    end
  end
  return lines
end

-- apng_frames — the frame count of an animated PNG, or nil for a still one.
--
-- ImageMagick identifies an APNG saved with a .png name as one PNG frame, so
-- its own count cannot say it is animated. The APNG format can: an acTL chunk
-- sits before the image data, and its first four bytes after the tag are the
-- frame count, big-endian. Reading the head of the file is enough, and needs
-- nothing installed.
function M.apng_frames(path)
  local fd = vim.uv.fs_open(path, 'r', 438)
  if not fd then return nil end
  local head = vim.uv.fs_read(fd, 4096, 0) or ''
  vim.uv.fs_close(fd)
  if head:sub(2, 4) ~= 'PNG' then return nil end
  local at = head:find('acTL', 1, true)
  if not at then return nil end
  local b1, b2, b3, b4 = head:byte(at + 4, at + 7)
  if not b4 then return nil end
  local n = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
  return n > 1 and n or nil
end

-- parse_identify — "PNG|320|200|3\n..." into a table. nil when it is not that.
function M.parse_identify(out)
  local first = (out or ''):match('^[^\n]+')
  if not first then return nil end
  local format, w, h, n = first:match('^([^|]*)|(%d+)|(%d+)|(%d+)')
  if not format then return nil end
  return { format = format, width = tonumber(w), height = tonumber(h), frames = tonumber(n) }
end

local function set_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local body = vim.list_extend(vim.deepcopy(lines), { '' })
  for _ = 1, FILLER_LINES do body[#body + 1] = '' end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, body)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

-- run — vim.system as a chain of fallbacks. Calls done(true) on the first
-- command in `steps` that exits 0 and leaves `out` behind, done(false) if none do.
--
-- Every continuation is schedule_wrap'd. vim.system's on_exit runs in a fast
-- event context, where vim.fn and most of vim.api are refused, and the chain
-- goes straight back into executable(), sha256() and nvim_get_hl(). Headless
-- tests that called normalise from the main loop passed; the real path, which
-- calls it from inside identify's on_exit, died on sha256 and left the buffer
-- saying "reading…" for good.
local function run(steps, out, done)
  local i = 0
  local function nxt()
    i = i + 1
    local step = steps[i]
    if not step then return done(false) end
    if not have(step[1]) then return nxt() end
    vim.system(step, { text = true }, vim.schedule_wrap(function(res)
      if res.code == 0 and vim.uv.fs_stat(out) then
        done(true)
      else
        nxt()
      end
    end))
  end
  nxt()
end

-- M.normalise — make (or reuse) the display copy of `path`, then call done(png)
-- or done(nil). Shared with the explorer pane's preview, which asks for a much
-- smaller box.
function M.normalise(path, box, done)
  local bg = M.background()
  local out = M.cache_path(path, box, bg)
  if not out then return done(nil) end
  if vim.uv.fs_stat(out) then return done(out) end
  vim.fn.mkdir(vim.fn.fnamemodify(out, ':h'), 'p')

  -- ImageMagick first. When it cannot read the file, a platform decoder turns
  -- it into a plain PNG, and ImageMagick normalises that — a PNG it can always
  -- read — so every picture ends up with the same four properties.
  local raw = out .. '.decoded.png'
  run({ M.convert_argv(path, out, box, bg) }, out, function(ok)
    if ok then return done(out) end
    local fallbacks = {}
    if vim.fn.has('mac') == 1 then
      fallbacks[#fallbacks + 1] = { 'sips', '-s', 'format', 'png', path, '--out', raw }
    end
    fallbacks[#fallbacks + 1] = { 'ffmpeg', '-v', 'error', '-y', '-i', path, '-frames:v', '1', raw }
    run(fallbacks, raw, function(decoded)
      if not decoded then return done(nil) end
      run({ M.convert_argv(raw, out, box, bg) }, out, function(ok2)
        os.remove(raw)
        done(ok2 and out or nil)
      end)
    end)
  end)
end

-- draw — put `png` under the text in whichever window shows `buf`.
local function draw(buf, png, y)
  local ok, image = pcall(require, 'image')
  if not ok then return end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then return end
  -- One image per buffer: a redraw replaces it rather than stacking a second
  -- one on the terminal.
  local previous = vim.b[buf].hikovim_picture_image_id
  if previous then
    pcall(function()
      for _, img in ipairs(image.get_images({ buffer = buf })) do img:clear() end
    end)
  end
  local made, img = pcall(image.from_file, png, { window = win, buffer = buf, x = 0, y = y })
  if made and img then
    vim.b[buf].hikovim_picture_image_id = img.id
    pcall(function() img:render() end)
  end
end

-- M.preview — fill the buffer, then go and find out what is in the file.
function M.preview(buf, path)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  -- A view of the file, not the file: nowrite so :w can never put this text
  -- where the picture was. Same as video.lua.
  vim.bo[buf].buftype = 'nowrite'
  vim.bo[buf].buflisted = true
  vim.bo[buf].filetype = 'hikovim_picture'
  vim.bo[buf].swapfile = false

  -- gx opens the file itself in the system's viewer. Neovim's own gx opens
  -- whatever is under the cursor, which here is a line of description; the
  -- description promises gx for an animated file, so it has to mean this file.
  vim.keymap.set('n', 'gx', function() vim.ui.open(path) end, {
    buffer = buf, silent = true, desc = 'Open this picture in the system viewer',
  })

  local name = vim.fn.fnamemodify(path, ':t')
  local st = vim.uv.fs_stat(path)
  local bytes = st and st.size
  set_lines(buf, { '  ' .. name, '  reading…' })

  if not have('magick') then
    set_lines(buf, {
      '  ' .. name,
      '  ImageMagick is not on PATH, so there is nothing to read the picture with.',
      '  It comes with the catalog: ./bin/nanolander --only magick',
    })
    return
  end

  -- schedule_wrap for the same reason as in run(): normalise uses vim.fn.
  vim.system(M.identify_argv(path), { text = true }, vim.schedule_wrap(function(res)
    local info = res.code == 0 and M.parse_identify(res.stdout) or nil
    if info and info.format == 'PNG' and (info.frames or 1) <= 1 then
      info.frames = M.apng_frames(path) or info.frames
    end
    M.normalise(path, M.DISPLAY_BOX, function(png)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local lines = M.describe(name, info, bytes)
        if not png then
          lines[#lines + 1] = '  Nothing on this machine could decode this file —'
          lines[#lines + 1] = '  not ImageMagick' .. (vim.fn.has('mac') == 1 and ', not sips' or '')
            .. ', not ffmpeg. gx hands it to the system viewer.'
          set_lines(buf, lines)
          return
        end
        set_lines(buf, lines)
        vim.b[buf].hikovim_picture_png = png
        vim.b[buf].hikovim_picture_y = #lines + 1
        draw(buf, png, #lines + 1)
      end)
    end)
  end))
end

function M.setup()
  local group = vim.api.nvim_create_augroup('hikovim_picture', { clear = true })
  vim.api.nvim_create_autocmd('BufReadCmd', {
    group = group,
    pattern = media.IMAGE,
    -- Returns nothing: a truthy return deletes the autocmd, which is how the
    -- second picture of each extension used to open as binary. See the same
    -- note in video.lua, which had the bug first.
    callback = function(ev)
      if vim.fn.filereadable(ev.file) ~= 1 then return end
      M.preview(ev.buf, vim.fn.fnamemodify(ev.file, ':p'))
    end,
  })
  -- A picture drawn once is drawn into one window. Coming back to its tab, or
  -- showing it in another window, draws it again — from the cached copy, so
  -- that costs an encode and no conversion.
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    pattern = media.IMAGE,
    callback = function(ev)
      local png = vim.b[ev.buf].hikovim_picture_png
      if png and vim.uv.fs_stat(png) then
        vim.schedule(function() draw(ev.buf, png, vim.b[ev.buf].hikovim_picture_y or 3) end)
      end
    end,
  })
end

return M
