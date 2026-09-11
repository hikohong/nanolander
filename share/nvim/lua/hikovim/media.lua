-- hikovim media — which file names are pictures, and which are videos.
--
-- Three places need the same answer and none of them can be the owner:
--
--   * video.lua's BufReadCmd, which replaces the binary read of a video with a
--     frame and the numbers
--   * image.nvim's hijack_file_patterns in plugins.lua, which does the same for
--     a picture
--   * ide.lua, where <CR> or a double click in the tree hands the file to the
--     system's own viewer instead of previewing it
--
-- A second copy of either list is how a container ends up with a preview and no
-- viewer, or a viewer and no preview. image.nvim keeps its options to itself —
-- there is no accessor on the module it returns — so asking the plugin what it
-- hijacks was not available either.
--
-- Containers and file formats, not codecs: this is about what the file is
-- called. The image list is exactly what image.nvim is told to hijack, so the
-- editor previews and the system opens the same set.

local M = {}

-- Autocmd globs, because that is the shape video.lua and image.nvim both want.
M.VIDEO = {
  '*.mp4', '*.m4v', '*.mkv', '*.mov', '*.avi', '*.webm',
  '*.flv', '*.wmv', '*.mpg', '*.mpeg', '*.ts', '*.m2ts',
}

M.IMAGE = {
  '*.png', '*.jpg', '*.jpeg', '*.gif', '*.webp', '*.avif', '*.bmp',
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

-- opens_externally — is this a file the editor previews but cannot really
-- show you?
--
-- Both answers are the same for the same reason. A preview is a still frame or
-- a picture painted on the terminal; watching a video and looking properly at
-- an image both belong to an application that does that, and the system already
-- knows which one it is.
function M.opens_externally(path)
  return M.is_video(path) or M.is_image(path)
end

return M
