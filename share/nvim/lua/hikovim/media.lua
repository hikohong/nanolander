-- hikovim media — which file names are pictures, and which are videos.
--
-- Three places need the same answer and none of them can be the owner:
--
--   * video.lua's BufReadCmd, which replaces the binary read of a video with a
--     frame and the numbers
--   * picture.lua's BufReadCmd, which does the same for a picture
--   * ide.lua, where <CR> or a double click in the tree hands the file to the
--     system's own viewer instead of previewing it
--
-- A second copy of either list is how a container ends up with a preview and no
-- viewer, or a viewer and no preview.
--
-- Containers and file formats, not codecs: this is about what the file is
-- called. Pictures used to be exactly what image.nvim was told to hijack, and
-- that list was seven names long; picture.lua decodes through ImageMagick, sips
-- and ffmpeg, so the list is what one of those reads.

local M = {}

-- Autocmd globs, because that is the shape video.lua and image.nvim both want.
M.VIDEO = {
  '*.mp4', '*.m4v', '*.mkv', '*.mov', '*.avi', '*.webm',
  '*.flv', '*.wmv', '*.mpg', '*.mpeg', '*.ts', '*.m2ts',
}

M.IMAGE = {
  -- the everyday ones
  '*.png', '*.jpg', '*.jpeg', '*.jpe', '*.jfif', '*.gif', '*.webp', '*.avif',
  '*.bmp', '*.apng',
  -- what a phone takes
  '*.heic', '*.heif',
  -- design and graphics
  '*.tif', '*.tiff', '*.svg', '*.ico', '*.icns', '*.psd', '*.tga', '*.qoi',
  '*.dds', '*.hdr', '*.pcx', '*.xpm', '*.pbm', '*.pgm', '*.ppm', '*.pnm',
  '*.jxl',
  -- camera raw
  '*.dng', '*.cr2', '*.cr3', '*.nef', '*.arw', '*.raf', '*.orf', '*.rw2',
  '*.pef', '*.srw',
}

-- matches — does this name end in one of these globs?
--
-- The file name only. Matching the whole path hands a text file to the viewer
-- because a directory above it happens to be called something.mkv.
--
-- `#name > #ext` is what keeps a dotfile out: `.mp4` is a name, not a video.
local function matches(path, patterns)
  if type(path) ~= 'string' or path == '' then return false end
  local name = vim.fn.fnamemodify(path, ':t'):lower()
  for _, pattern in ipairs(patterns) do
    local ext = pattern:match('^%*(%.%w+)$')
    if ext and #name > #ext and name:sub(-#ext) == ext then return true end
  end
  return false
end

function M.is_video(path)
  return matches(path, M.VIDEO)
end

function M.is_image(path)
  return matches(path, M.IMAGE)
end

-- is_media — a picture or a video: what the explorer pane previews in the pane
-- above as the cursor lands on it.
function M.is_media(path)
  return M.is_video(path) or M.is_image(path)
end

-- opens_externally — is <CR> on this file a hand-off to the system?
--
-- A video, yes: the editor pane can show one frame of it, and watching it
-- belongs to a player. A picture, no longer: the pane above already shows a
-- thumbnail as the cursor moves, so choosing a picture means looking at it
-- properly, and the editor pane draws the full normalised copy. gx still hands
-- either one to the system.
function M.opens_externally(path)
  return M.is_video(path)
end

return M
