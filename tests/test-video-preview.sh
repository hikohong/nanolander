#!/usr/bin/env bash
# Assertions read variables the sourced script owns and grep the shipped Lua.
# ShellCheck sees through neither.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
# What opening a video shows.
#
# The formatting is exercised through a real Neovim against a fixture of
# ffprobe's output, so no video file and no ffmpeg is needed to check it — which
# matters because neither is on a CI runner. Everything that needs a terminal to
# draw into is out of reach here and is listed in tests/README.md instead.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

VIDEO="$REPO_ROOT/share/nvim/lua/hikovim/video.lua"
MEDIA="$REPO_ROOT/share/nvim/lua/hikovim/media.lua"
PLUGINS_LUA="$REPO_ROOT/share/nvim/lua/hikovim/plugins.lua"
INIT="$REPO_ROOT/share/nvim/lua/hikovim/init.lua"

# --- shipped and wired -----------------------------------------------------
chk "video.lua ships"        "$(exists "$VIDEO")" "y"
chk "and is set up"          "$(grep -c "require('hikovim.video').setup()" "$INIT")" "1"

# BufReadCmd is the point: Neovim hands the whole read over, so the binary is
# never loaded and never guessed at.
chk "it replaces the read"   "$(grep -c "'BufReadCmd'" "$VIDEO")" "1"

# The container list lives in media.lua, because three readers need the same
# answer: video.lua's BufReadCmd, picture.lua's, and ide.lua's decision about
# what <CR> and a double click hand to the system. A second copy is how a
# format ends up with a preview and no viewer, or the reverse.
chk "media.lua ships"          "$(exists "$MEDIA")" "y"
chk "containers are matched"   "$(grep -c "'\*.mkv'" "$MEDIA")" "1"
chk "video.lua reads them"     "$(grep -c 'pattern = media.VIDEO' "$VIDEO")" "1"
chk "and keeps no copy"        "$(grep -c "'\*.mkv'" "$VIDEO")" "0"
chk "pictures are matched"     "$(grep -c "'\*.png'" "$MEDIA")" "1"
chk "picture.lua reads them"   "$(grep -c 'pattern = media.IMAGE' "$REPO_ROOT/share/nvim/lua/hikovim/picture.lua")" "2"
chk "and plugins.lua keeps no copy" "$(grep -c "'\*.png'" "$PLUGINS_LUA")" "0"

# A preview that kept buftype '' would let :w write this text over the video.
chk "the buffer cannot be written" "$(grep -c "buftype = 'nowrite'" "$VIDEO")" "1"
# ...but it is still an ordinary tab that :q closes.
chk "and is still a tab"     "$(grep -c 'buflisted = true' "$VIDEO")" "1"

# Both tools come from the FFmpeg catalog entry; neither is a new dependency.
# Named twice: once to check it exists, once to run it.
chk "numbers come from ffprobe" "$(grep -c "'ffprobe'" "$VIDEO")" "2"
chk "the frame from ffmpeg"      "$(grep -c "'ffmpeg', '-v', 'error'" "$VIDEO")" "1"
# Synchronous calls would stall the editor on a large file.
chk "both run asynchronously"    "$(grep -c 'vim.system' "$VIDEO")" "2"
# Most files open on a black frame.
chk "the frame is seeked into"   "$(grep -c 'duration \* 0.1' "$VIDEO")" "1"

# The boundary this feature is built on: preview, never playback. Anything that
# starts a player belongs to an opener, not to a buffer.
chk "nothing here plays"     "$(grep -cE "'(mpv|ffplay|vlc)'" "$VIDEO")" "0"

# --- the formatting, against a fixture of ffprobe's output ------------------
# Needs a real Neovim. Skipped where there is none, the way the zsh check is.
if command -v nvim >/dev/null 2>&1; then
  temp_home; H="$TEST_HOME"
  trap 'rm -rf "$H"' EXIT

  cat > "$H/probe.lua" <<'LUA'
local v = require('hikovim.video')
-- exactly the shape ffprobe -of default=noprint_wrappers=1 emits
local fixture = table.concat({
  'codec_name=h264',
  'width=1920',
  'height=1080',
  'r_frame_rate=30000/1001',
  'duration=134.600000',
  'size=13000000',
  'bit_rate=1800000',
}, '\n')
local lines, duration = v.describe('/tmp/photo-shoot.mp4', fixture)
local out = io.open(vim.env.OUT, 'w')
for _, l in ipairs(lines) do out:write(l .. '\n') end
out:write('duration=' .. tostring(duration) .. '\n')

-- A file ffprobe knew almost nothing about must not produce empty or nil lines.
local sparse = v.describe('/tmp/odd.mkv', 'codec_name=theora')
out:write('sparse_lines=' .. #sparse .. '\n')
for i, l in ipairs(sparse) do out:write('sparse' .. i .. '=' .. l .. '\n') end

-- media.lua answers what each preview claims and what the tree hands to the
-- system. One table, so a format cannot get a preview and no viewer.
local media = require('hikovim.media')
for _, case in ipairs({
  { 'lower', 'a.mp4' }, { 'upper', 'A.MP4' }, { 'mkv', 'x.MKV' },
  { 'text', 'n.txt' }, { 'image', 'p.png' },
  { 'bare', '.mp4' }, { 'noext', 'plain' },
  { 'indir', '/tmp/dir.mkv/file.txt' },
  { 'nil', nil }, { 'empty', '' },
}) do
  out:write('isvideo_' .. case[1] .. '=' .. tostring(media.is_video(case[2])) .. '\n')
end
for _, case in ipairs({
  { 'png', 'a.png' }, { 'jpgup', 'B.JPG' }, { 'jpeg', 'c.jpeg' },
  { 'gif', 'd.gif' }, { 'webp', 'e.webp' }, { 'avif', 'f.avif' },
  { 'bmp', 'g.bmp' }, { 'video', 'h.mp4' }, { 'text', 'i.txt' },
  { 'bare', '.png' }, { 'nil', nil },
}) do
  out:write('isimage_' .. case[1] .. '=' .. tostring(media.is_image(case[2])) .. '\n')
end
for _, case in ipairs({
  { 'video', 'a.mp4' }, { 'image', 'b.png' }, { 'text', 'c.txt' },
}) do
  out:write('external_' .. case[1] .. '=' ..
    tostring(media.opens_externally(case[2])) .. '\n')
end
out:close()
LUA

  OUT="$H/out" nvim --headless -u NONE \
    --cmd "set rtp+=$REPO_ROOT/share/nvim" \
    -c "luafile $H/probe.lua" -c 'qa!' >/dev/null 2>&1

  got() { grep -m1 "^$1" "$H/out" 2>/dev/null; }
  chk "the name is the first line" "$(sed -n 1p "$H/out" 2>/dev/null)" "  photo-shoot.mp4"
  # 30000/1001 is 29.97, not 30 — a fraction ffprobe uses for anything NTSC.
  chk "resolution, codec, fps"     "$(sed -n 2p "$H/out" 2>/dev/null)" "  1920×1080 · h264 · 29.97 fps"
  # 134.6s is 00:02:14; 13000000 bytes is 12.4 MB, not 13 MB.
  chk "duration, size, bitrate"    "$(sed -n 3p "$H/out" 2>/dev/null)" "  00:02:14 · 12.4 MB · 1.8 Mbps"
  chk "duration is returned too"   "$(got duration=)" "duration=134.6"

  # join() drops the parts ffprobe did not supply rather than printing gaps,
  # and the line vanishes entirely when nothing on it came back.
  chk "a sparse file still formats" "$(got sparse_lines=)" "sparse_lines=2"
  chk "and prints only what it has" "$(got sparse2=)" "sparse2=  theora"

  # media.is_video is where the BufReadCmd pattern list comes from, and what the
  # tree asks before handing a file over — one table, or a container gets a
  # preview and no viewer, or the reverse.
  chk "a video is one"              "$(got isvideo_lower=)" "isvideo_lower=true"
  # A file off a camera or a screen recorder is often shouted.
  chk "case does not matter"        "$(got isvideo_upper=)" "isvideo_upper=true"
  chk "so is .MKV"                  "$(got isvideo_mkv=)"   "isvideo_mkv=true"
  chk "a text file is not"          "$(got isvideo_text=)"  "isvideo_text=false"
  # Images have their own path — image.nvim draws them in the editor pane.
  chk "nor is an image"             "$(got isvideo_image=)" "isvideo_image=false"
  # A name that is nothing but the extension is a dotfile, not a video.
  chk "nor a bare extension"        "$(got isvideo_bare=)"  "isvideo_bare=false"
  chk "nor a name without one"      "$(got isvideo_noext=)" "isvideo_noext=false"
  # Matching the whole path would hand a text file to the player because a
  # directory above it happens to be called something.mkv.
  chk "only the name is read"       "$(got isvideo_indir=)" "isvideo_indir=false"
  # The tree can hand over a node with no path at all.
  chk "nil is not a video"          "$(got isvideo_nil=)"   "isvideo_nil=false"
  chk "nor is an empty name"        "$(got isvideo_empty=)" "isvideo_empty=false"

  # The picture half of the same table, and exactly what image.nvim is told to
  # hijack — so the editor previews and the system opens the same set.
  chk "a png is an image"           "$(got isimage_png=)"   "isimage_png=true"
  chk "shouted names count too"     "$(got isimage_jpgup=)" "isimage_jpgup=true"
  chk "jpeg is one"                 "$(got isimage_jpeg=)"  "isimage_jpeg=true"
  chk "gif is one"                  "$(got isimage_gif=)"   "isimage_gif=true"
  chk "webp is one"                 "$(got isimage_webp=)"  "isimage_webp=true"
  chk "avif is one"                 "$(got isimage_avif=)"  "isimage_avif=true"
  chk "bmp is one"                  "$(got isimage_bmp=)"   "isimage_bmp=true"
  chk "a video is not an image"     "$(got isimage_video=)" "isimage_video=false"
  chk "nor is a text file"          "$(got isimage_text=)"  "isimage_text=false"
  chk "nor a bare extension either" "$(got isimage_bare=)"  "isimage_bare=false"
  chk "nor nil"                     "$(got isimage_nil=)"   "isimage_nil=false"

  # Both kinds leave for the same reason: a preview is a still frame or a
  # thumbnail painted on the terminal, and looking at either properly belongs to
  # an application the system already knows about.
  chk "a video opens externally"    "$(got external_video=)" "external_video=true"
  chk "so does a picture"           "$(got external_image=)" "external_image=true"
  chk "a text file does not"        "$(got external_text=)"  "external_text=false"
fi

finish
