-- hikovim zoom — zooming the picture in the editor pane.
--
-- Three ways in, all ending in M.zoom:
--
--   the toolbar under the description    [ - ]  100%  [ + ]  [ fit ]
--   middle button held, scroll wheel     in or out, about the point under the mouse
--   ctrl + scroll wheel                  the same, and on a trackpad that is ctrl
--                                        and two fingers
--
-- A trackpad pinch cannot be one of them. iTerm2 keeps the pinch for itself and
-- changes the font size with it — its advanced setting
-- pinchToChangeFontSizeDisabled switches that off, it does not pass the gesture
-- on — and no terminal mouse protocol has a way to carry one. What does reach a
-- program is a scroll event with its modifiers, so ctrl and two fingers is the
-- closest gesture there is. macOS's own scroll-to-zoom uses ctrl too when it is
-- switched on in Accessibility, and takes the gesture before iTerm2 sees it.
--
-- How a zoom is drawn. The picture in the editor pane is picture.lua's
-- normalised copy, fitted to the window by image.nvim. Zoomed in, the part of
-- that copy in view is cropped out; zoomed out, the copy is shrunk onto a canvas
-- in the editor's background. image.nvim still places the result, so a resize,
-- a scroll and a window moving over it are handled exactly as they are for the
-- unzoomed picture.
--
-- Each view is made at exactly the size the picture is already drawn at, in
-- pixels. That is not tidiness, it is most of the speed and all of the zooming:
-- image.nvim never draws a picture larger than it is, so a crop left at its own
-- size came out smaller the further in it went — 381% drew in 52 columns
-- instead of 132 — and image.nvim re-scales anything whose width is not the
-- width it will draw, which was another ImageMagick run of about 200 ms on
-- every step. Measured on a 1600-pixel photo: the view went from 241 ms to 103
-- ms zooming in and from 402 ms to 98 ms zooming out, and image.nvim's rescale
-- stopped happening.
--
-- Each view is written once per session under Neovim's temporary directory,
-- named by what is in it, so going back to a zoom already visited costs no
-- ImageMagick at all.
--
-- A burst of wheel events is one zoom. A trackpad sends dozens a second, and
-- each drawn view costs image.nvim a sixel encode, so the level and the
-- percentage update on every event while the picture is drawn once the burst
-- has paused.

local M = {}

local picture = require('hikovim.picture')

M.STEP = 1.25
M.MIN_STEP, M.MAX_STEP = -6, 10   -- about 26% to 931%
M.FILETYPE = 'hikovim_picture'

-- How long the wheel has to pause before the view is drawn.
local COALESCE_MS = 60

-- How long a middle button press counts as held without a sign of it. A
-- release that happens outside the terminal never arrives, and without a limit
-- every later scroll over the picture would zoom.
local HELD_MS = 3000

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function M.level(step) return M.STEP ^ step end

-- M.view — the rectangle of the picture in view at `step`, centred on (cx, cy),
-- in fractions of the picture's own width and height. Zoomed in it stays inside
-- the picture; zoomed out it is larger than the picture and always centred.
function M.view(step, cx, cy)
  local w = 1 / M.level(step)
  if w >= 1 then return { x = (1 - w) / 2, y = (1 - w) / 2, w = w, h = w } end
  return { x = clamp(cx - w / 2, 0, 1 - w), y = clamp(cy - w / 2, 0, 1 - w), w = w, h = w }
end

-- M.view_argv — the ImageMagick command that makes that view of a W×H copy,
-- `bw`×`bh` pixels when the drawn size is known. A temporary file, so it is
-- written with the fastest PNG compression: the default spent more time
-- compressing than cropping.
function M.view_argv(src, out, rect, W, H, bg, bw, bh)
  local fast = { '-define', 'png:compression-level=1', 'png:' .. out }
  if rect.w < 1 then
    local argv = { 'magick', src, '-crop', ('%dx%d+%d+%d'):format(
      math.max(1, math.floor(rect.w * W + 0.5)), math.max(1, math.floor(rect.h * H + 0.5)),
      math.floor(rect.x * W + 0.5), math.floor(rect.y * H + 0.5)), '+repage' }
    if bw then vim.list_extend(argv, { '-resize', ('%dx%d!'):format(bw, bh) }) end
    return vim.list_extend(argv, fast)
  end
  if bw then
    local level = 1 / rect.w
    return vim.list_extend({ 'magick', src,
      '-resize', ('%dx%d!'):format(math.max(1, math.floor(bw * level)), math.max(1, math.floor(bh * level))),
      '-background', bg, '-gravity', 'center', '-extent', ('%dx%d'):format(bw, bh) }, fast)
  end
  return vim.list_extend({ 'magick', src, '-background', bg, '-gravity', 'center',
    '-extent', ('%dx%d'):format(math.floor(rect.w * W + 0.5), math.floor(rect.h * H + 0.5)) }, fast)
end

-- M.anchored — the centre after zooming from `step` to `to` about a point at
-- fractions (fx, fy) of what is on screen: that point of the picture stays
-- under the mouse.
function M.anchored(step, cx, cy, to, fx, fy)
  local old = M.view(step, cx, cy)
  local px, py = old.x + fx * old.w, old.y + fy * old.h
  local w = 1 / M.level(to)
  local new = M.view(to, px - fx * w + w / 2, py - fy * w + w / 2)
  if new.w >= 1 then return 0.5, 0.5 end
  return new.x + new.w / 2, new.y + new.h / 2
end

-- ---------------------------------------------------------------------------
-- The toolbar
-- ---------------------------------------------------------------------------

-- M.toolbar — the line of buttons, and where each one is: display columns in
-- the line, 1-based. The percentage is between the two buttons it changes, so
-- the ones after it move as it grows; the ranges are always worked out for the
-- line as it is drawn.
function M.toolbar(step)
  local text, ranges = '  ', {}
  local function add(label, action)
    local from = vim.fn.strdisplaywidth(text) + 1
    text = text .. label
    if action then
      ranges[#ranges + 1] = { from = from, to = from + vim.fn.strdisplaywidth(label) - 1, action = action }
    end
    text = text .. '  '
  end
  add('[ - ]', -1)
  add(('%d%%'):format(math.floor(M.level(step) * 100 + 0.5)))
  add('[ + ]', 1)
  add('[ fit ]', 'fit')
  text = text .. '· middle button or ctrl + scroll zooms at the mouse'
  return text, ranges
end

local function set_toolbar(buf)
  local line = vim.b[buf].hikovim_zoom_line
  if not line or line > vim.api.nvim_buf_line_count(buf) then return end
  local text = M.toolbar(vim.b[buf].hikovim_zoom_step or 0)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, line - 1, line, false, { text })
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

-- ---------------------------------------------------------------------------
-- Drawing a view
-- ---------------------------------------------------------------------------

local view_dir
local function view_path(png, rect, bg, bw, bh)
  if not view_dir then
    view_dir = vim.fn.tempname() .. '-zoom'
    vim.fn.mkdir(view_dir, 'p')
  end
  local key = vim.fn.sha256(table.concat({
    png, ('%.4f'):format(rect.x), ('%.4f'):format(rect.y), ('%.4f'):format(rect.w), bg,
    bw or 0, bh or 0,
  }, '|'))
  return view_dir .. '/' .. key .. '.png'
end

-- drawn_box — the size in pixels the picture in `buf` is drawn at: its cells
-- from image.nvim, times the cell size. A view made at exactly that size is one
-- image.nvim draws as it is; one pixel either way, and it rescales or crops it
-- first. Remembered per buffer, since the image being replaced may not have
-- finished drawing when the next zoom asks, and forgotten when the window
-- changes size. nil until a picture has drawn.
local function drawn_box(buf)
  local ok, image = pcall(require, 'image')
  local okt, utils = pcall(require, 'image/utils')
  if ok and okt and utils.term and utils.term.get_size then
    local got, size = pcall(utils.term.get_size)
    local have, images = pcall(image.get_images, { buffer = buf })
    local g = have and images[1] and images[1].rendered_geometry
    if got and size and (size.cell_width or 0) > 0 and (size.cell_height or 0) > 0
      and g and (g.width or 0) > 0 and (g.height or 0) > 0 then
      vim.b[buf].hikovim_zoom_px_w = math.floor(g.width * size.cell_width + 0.5)
      vim.b[buf].hikovim_zoom_px_h = math.floor(g.height * size.cell_height + 0.5)
    end
  end
  return vim.b[buf].hikovim_zoom_px_w, vim.b[buf].hikovim_zoom_px_h
end

local generation = {}

-- M.render — draw the view `buf` is at. Only the newest request for a buffer
-- draws; one that finishes after a later zoom was asked for is dropped.
function M.render(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local png = vim.b[buf].hikovim_picture_png
  if not png then return end
  generation[buf] = (generation[buf] or 0) + 1
  local mine = generation[buf]
  local step = vim.b[buf].hikovim_zoom_step or 0
  local y = vim.b[buf].hikovim_picture_y or 3
  local function current() return generation[buf] == mine and vim.api.nvim_buf_is_valid(buf) end

  if step == 0 then
    vim.b[buf].hikovim_picture_view = nil
    return picture.draw(buf, png, y)
  end
  drawn_box(buf)

  picture.identify(png, function(info)
    if not (current() and info and info.width and info.height) then return end
    local rect = M.view(step, vim.b[buf].hikovim_zoom_cx or 0.5, vim.b[buf].hikovim_zoom_cy or 0.5)
    local bg = picture.background()
    local bw, bh = drawn_box(buf)
    local out = view_path(png, rect, bg, bw, bh)
    local function show()
      if not current() then return end
      vim.b[buf].hikovim_picture_view = out
      picture.draw(buf, out, y)
    end
    if vim.uv.fs_stat(out) then return show() end
    vim.system(M.view_argv(png, out, rect, info.width, info.height, bg, bw, bh), {},
      vim.schedule_wrap(function(res)
        if res.code == 0 and vim.uv.fs_stat(out) then show() end
      end))
  end)
end

local timers = {}
local function render_soon(buf)
  local timer = timers[buf] or vim.uv.new_timer()
  timers[buf] = timer
  timer:stop()
  timer:start(COALESCE_MS, 0, vim.schedule_wrap(function() M.render(buf) end))
end

---Zoom the picture in `buf`.
---@param buf integer
---@param delta integer|'fit' steps in (positive) or out, or back to the fitted picture
---@param anchor table|nil { fx, fy }: the point to zoom about, as fractions of what is on screen
---@param now boolean|nil draw straight away rather than after a pause: a click, not a wheel
function M.zoom(buf, delta, anchor, now)
  if not (vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == M.FILETYPE
    and vim.b[buf].hikovim_picture_png) then return end
  local step = vim.b[buf].hikovim_zoom_step or 0
  local cx, cy = vim.b[buf].hikovim_zoom_cx or 0.5, vim.b[buf].hikovim_zoom_cy or 0.5
  local to
  if delta == 'fit' then
    to, cx, cy = 0, 0.5, 0.5
  else
    to = clamp(step + delta, M.MIN_STEP, M.MAX_STEP)
    if to == step then return end
    local fx, fy = 0.5, 0.5
    if anchor then fx, fy = anchor.fx, anchor.fy end
    cx, cy = M.anchored(step, cx, cy, to, fx, fy)
  end
  vim.b[buf].hikovim_zoom_step = to
  vim.b[buf].hikovim_zoom_cx = cx
  vim.b[buf].hikovim_zoom_cy = cy
  set_toolbar(buf)
  if now then
    if timers[buf] then timers[buf]:stop() end
    M.render(buf)
  else
    render_soon(buf)
  end
end

-- ---------------------------------------------------------------------------
-- The mouse
-- ---------------------------------------------------------------------------

-- picture_under_mouse — the picture buffer in the window under the mouse. A
-- wheel event scrolls the window it is over without focusing it, and a
-- buffer-local mapping belongs to the focused buffer, so the wheel mappings are
-- global and ask where the mouse is.
local function picture_under_mouse()
  local pos = vim.fn.getmousepos()
  if not (pos.winid ~= 0 and vim.api.nvim_win_is_valid(pos.winid)) then return nil end
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  if vim.bo[buf].filetype ~= M.FILETYPE or not vim.b[buf].hikovim_picture_png then return nil end
  return buf, pos
end

-- anchor_of — where the mouse is on the drawn picture, as fractions, or nil
-- when it is not over the picture itself (the description, the margin).
local function anchor_of(buf, pos)
  local ok, image = pcall(require, 'image')
  if not ok then return nil end
  local got, images = pcall(image.get_images, { buffer = buf })
  local g = got and images[1] and images[1].rendered_geometry
  if not (g and (g.width or 0) > 0 and (g.height or 0) > 0) then return nil end
  local fx = (pos.screencol - 1 - g.x + 0.5) / g.width
  local fy = (pos.screenrow - 1 - g.y + 0.5) / g.height
  if fx < 0 or fx > 1 or fy < 0 or fy > 1 then return nil end
  return { fx = fx, fy = fy }
end

local middle_at   -- when the middle button went down over a picture, or nil

local function middle_held()
  return middle_at ~= nil and (vim.uv.now() - middle_at) < HELD_MS
end

-- wheel — a mapping for one wheel direction. Over a picture, and with the
-- middle button held when `needs_middle`, it zooms; anywhere else it is the
-- key it was, so scrolling everywhere else is untouched. Expression mappings
-- may not change buffers, so the zoom itself runs a moment later.
local function wheel(key, delta, needs_middle)
  return function()
    local buf, pos = picture_under_mouse()
    if buf and (not needs_middle or middle_held()) then
      if needs_middle then middle_at = vim.uv.now() end
      local anchor = anchor_of(buf, pos)
      vim.schedule(function() M.zoom(buf, delta, anchor) end)
      return ''
    end
    return key
  end
end

-- click — the toolbar. `key` is what the click is when it is not on a button.
local function click(buf, key)
  return function()
    local pos = vim.fn.getmousepos()
    local line = vim.b[buf].hikovim_zoom_line
    if line and pos.winid ~= 0 and vim.api.nvim_win_is_valid(pos.winid)
      and vim.api.nvim_win_get_buf(pos.winid) == buf and pos.line == line then
      local info = vim.fn.getwininfo(pos.winid)[1]
      local col = pos.wincol - (info and info.textoff or 0)
      local _, ranges = M.toolbar(vim.b[buf].hikovim_zoom_step or 0)
      for _, r in ipairs(ranges) do
        if col >= r.from and col <= r.to then
          vim.schedule(function() M.zoom(buf, r.action, nil, true) end)
          return ''
        end
      end
    end
    return key
  end
end

---Called by picture.lua once a picture buffer has its description: the toolbar
---goes on `line`, and the buttons on it answer clicks.
---@param buf integer
---@param line integer 1-based line of the toolbar
function M.attach(buf, line)
  vim.b[buf].hikovim_zoom_line = line
  vim.b[buf].hikovim_zoom_step = vim.b[buf].hikovim_zoom_step or 0
  set_toolbar(buf)
  -- A single click acts on release, when <LeftMouse> has already put the
  -- cursor in this window. A quick second click arrives as <2-LeftMouse>, which
  -- would otherwise select a word instead of pressing the button again.
  local opts = { buffer = buf, expr = true, silent = true, desc = 'Zoom toolbar' }
  vim.keymap.set('n', '<LeftRelease>', click(buf, '<LeftRelease>'), opts)
  vim.keymap.set('n', '<2-LeftMouse>', click(buf, '<2-LeftMouse>'), opts)
  vim.keymap.set('n', '<3-LeftMouse>', click(buf, '<3-LeftMouse>'), opts)
  vim.keymap.set('n', '<4-LeftMouse>', click(buf, '<4-LeftMouse>'), opts)
end

function M.setup()
  local opts = { expr = true, silent = true }
  vim.keymap.set('n', '<ScrollWheelUp>', wheel('<ScrollWheelUp>', 1, true),
    vim.tbl_extend('force', opts, { desc = 'Scroll; with the middle button held over a picture, zoom in' }))
  vim.keymap.set('n', '<ScrollWheelDown>', wheel('<ScrollWheelDown>', -1, true),
    vim.tbl_extend('force', opts, { desc = 'Scroll; with the middle button held over a picture, zoom out' }))
  vim.keymap.set('n', '<C-ScrollWheelUp>', wheel('<C-ScrollWheelUp>', 1, false),
    vim.tbl_extend('force', opts, { desc = 'Over a picture, zoom in at the mouse' }))
  vim.keymap.set('n', '<C-ScrollWheelDown>', wheel('<C-ScrollWheelDown>', -1, false),
    vim.tbl_extend('force', opts, { desc = 'Over a picture, zoom out at the mouse' }))
  -- Middle click pastes, which in a picture is an error about 'modifiable'. Over
  -- a picture it only says the button is down.
  vim.keymap.set('n', '<MiddleMouse>', function()
    if picture_under_mouse() then
      middle_at = vim.uv.now()
      return ''
    end
    middle_at = nil
    return '<MiddleMouse>'
  end, vim.tbl_extend('force', opts, { desc = 'Paste; over a picture, hold to zoom with the wheel' }))
  vim.keymap.set('n', '<MiddleRelease>', function()
    middle_at = nil
    return '<MiddleRelease>'
  end, vim.tbl_extend('force', opts, { desc = 'Middle button released' }))
  vim.api.nvim_create_autocmd('FocusLost', {
    group = vim.api.nvim_create_augroup('hikovim_zoom', { clear = true }),
    callback = function() middle_at = nil end,
  })
end

return M
