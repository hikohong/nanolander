#!/usr/bin/env bash
# Assertions grep the shipped Lua and run it against fixtures; ShellCheck sees
# through neither. The Lua is quoted and must not expand here.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
# What opening a picture shows.
#
# image.nvim used to take pictures by itself, straight from the original file.
# Driving its own pipeline over real files found what that missed: a PNG with
# transparency drawn as a near-blank, an animated PNG likewise, every frame of a
# GIF stacked into one sixel, an animated WebP read as 8960×0, a multi-page TIFF
# read as "tifftifftiff", a 7000×5000 PNG re-encoded for a second per redraw, and
# HEIC, TIFF, SVG and ICO not taken at all. picture.lua normalises every picture
# into one cached copy instead. Drawing needs a terminal and is out of reach
# here; tests/README.md says so.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

PIC="$REPO_ROOT/share/nvim/lua/hikovim/picture.lua"
VIDEO="$REPO_ROOT/share/nvim/lua/hikovim/video.lua"
MEDIA="$REPO_ROOT/share/nvim/lua/hikovim/media.lua"
PLUGINS_LUA="$REPO_ROOT/share/nvim/lua/hikovim/plugins.lua"
INIT="$REPO_ROOT/share/nvim/lua/hikovim/init.lua"

# --- shipped and wired -----------------------------------------------------
chk "picture.lua ships"            "$(exists "$PIC")" "y"
chk "init.lua sets it up"          "$(grep -c "require('hikovim.picture').setup()" "$INIT")" "1"
chk "it replaces the read"         "$(grep -c "'BufReadCmd'" "$PIC")" "1"
chk "for the pictures media.lua names" "$(grep -c 'pattern = media.IMAGE' "$PIC")" "2"
# image.nvim hijacking too would mean two readers racing for one buffer.
chk "image.nvim no longer hijacks" "$(grep -c 'hijack_file_patterns = {},' "$PLUGINS_LUA")" "1"
chk "the buffer cannot be written" "$(grep -c "buftype = 'nowrite'" "$PIC")" "1"

# --- the formats -----------------------------------------------------------
for ext in png jpg heic heif tif tiff svg ico icns psd apng webp avif gif qoi jxl dng cr2 cr3 nef arw raf; do
  chk "media.lua names *.$ext" "$(grep -c "'\*\.$ext'" "$MEDIA")" "1"
done

# --- the one conversion, flag by flag ----------------------------------------
# Each flag answers one of the failures above. Asserted on the argv so no
# ImageMagick is needed to check it.
chk "first frame only"             "$(grep -c "src .. '\[0\]'" "$PIC")" "1"
chk "the right way up"             "$(grep -c "'-auto-orient'" "$PIC")" "1"
chk "transparency is blended away" "$(grep -c "'-alpha', 'remove'" "$PIC")" "1"
chk "only ever shrunk"             "$(grep -c "box .. '>'" "$PIC")" "1"
chk "vector density before input"  "$(grep -c "'magick', '-density', '144', src" "$PIC")" "1"
chk "cached, keyed on mtime and size" "$(grep -c 'st.mtime.sec, st.mtime.nsec or 0, st.size' "$PIC")" "1"
# When ImageMagick cannot read a file, a platform decoder turns it into a PNG
# that ImageMagick can.
chk "sips is a fallback on macOS"  "$(grep -c "'sips', '-s', 'format', 'png'" "$PIC")" "1"
chk "ffmpeg is the last resort"    "$(grep -c "'ffmpeg', '-v', 'error', '-y', '-i', path, '-frames:v', '1'" "$PIC")" "1"

# The boundary this is built on, same as video.lua: preview, never animate.
chk "nothing here animates"        "$(grep -cE "'(mpv|ffplay|vlc|gifsicle)'" "$PIC")" "0"

# --- two bugs this found, kept out ------------------------------------------
# A Lua autocmd callback that returns a truthy value is deleted. Both BufReadCmd
# callbacks ended in `return true`, so the second file of each extension in a
# session opened as binary — video.lua since it shipped. One file per headless
# Neovim never showed it.
for f in "$PIC" "$VIDEO"; do
  chk "$(basename "$f") BufReadCmd never returns true" \
    "$(awk "/nvim_create_autocmd\('BufReadCmd'/,/^  \}\)/" "$f" | grep -cE '^\s*return true')" "0"
done
# vim.system's on_exit runs in a fast event context, where vim.fn is refused;
# normalise calls sha256() and nvim_get_hl() straight away. Called from the main
# loop it worked, called from identify's callback it died and left "reading…".
chk "every system callback is scheduled" \
  "$(grep -c 'vim.system(.*vim.schedule_wrap(function(res)' "$PIC")" "2"

# --- behaviour, against fixtures, in a real Neovim ---------------------------
if command -v nvim >/dev/null 2>&1; then
  temp_home; H="$TEST_HOME"
  trap 'rm -rf "$H"' EXIT

  # A real APNG header — signature, IHDR, acTL with num_frames 3 — and a plain one.
  printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\xa0\x00\x00\x00\x64\x08\x06\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08acTL\x00\x00\x00\x03\x00\x00\x00\x00' > "$H/anim.png"
  printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\xa0\x00\x00\x00\x64\x08\x06\x00\x00\x00\x00' > "$H/still.png"
  printf 'not really a picture' > "$H/a.png"
  cp "$H/a.png" "$H/b.png"; cp "$H/a.png" "$H/c.png"
  printf 'not really a video' > "$H/a.mp4"; cp "$H/a.mp4" "$H/b.mp4"

  cat > "$H/probe.lua" <<'LUA'
local p = require('hikovim.picture')
local out = io.open(vim.env.OUT, 'w')
local function w(k, v) out:write(k .. '=' .. tostring(v) .. '\n') end

-- identify prints one line per frame; the first is the one that counts.
local info = p.parse_identify('GIF|160|100|3\nGIF|160|100|3\nGIF|160|100|3\n')
w('fmt', info.format); w('wh', info.width .. 'x' .. info.height); w('n', info.frames)
w('junk', p.parse_identify('tifftifftiff'))

local d = p.describe('anim.gif', { format = 'GIF', width = 160, height = 100, frames = 3 }, 573)
w('d1', d[1]); w('d2', d[2]); w('d3', d[3])
local t = p.describe('scan.tiff', { format = 'TIFF', width = 320, height = 200, frames = 3 }, 1152812)
w('t3', t[3])
w('still_lines', #p.describe('p.png', { format = 'PNG', width = 1, height = 1, frames = 1 }, 10))

w('apng', p.apng_frames(vim.env.H .. '/anim.png'))
w('still', p.apng_frames(vim.env.H .. '/still.png'))

local argv = table.concat(p.convert_argv('/x/in.heic', '/c/out.png', '1600x1600', '#000000'), ' ')
w('argv', argv)
out:close()
LUA
  export H
  OUT="$H/out" nvim --headless -u NONE --cmd "set rtp+=$REPO_ROOT/share/nvim" \
    -c "luafile $H/probe.lua" -c 'qa!' >/dev/null 2>&1
  got() { grep -m1 "^$1=" "$H/out" 2>/dev/null | cut -d= -f2-; }
  chk "format from the first frame"   "$(got fmt)" "GIF"
  chk "size from the first frame"     "$(got wh)"  "160x100"
  chk "frame count read"              "$(got n)"   "3"
  chk "concatenated junk is refused"  "$(got junk)" "nil"
  chk "the name is the first line"    "$(got d1)"  "  anim.gif"
  chk "format, size, bytes"           "$(got d2)"  "  GIF · 160×100 · 573.0 B"
  chk "animated says so, and how"     "$(got d3)"  "  animated · 3 frames — showing the first; gx plays it in the system viewer"
  chk "pages are not animation"       "$(got t3)"  "  3 pages — showing the first"
  chk "a still has no third line"     "$(got still_lines)" "2"
  # ImageMagick calls an APNG named .png one frame; its acTL chunk does not.
  chk "an APNG is counted from acTL"  "$(got apng)"  "3"
  chk "a still PNG is not"            "$(got still)" "nil"
  chk "the argv is exactly this" "$(got argv)" \
    "magick -density 144 /x/in.heic[0] -auto-orient -background #000000 -alpha remove -alpha off -resize 1600x1600> -strip png:/c/out.png"

  # The regression itself: several files of one extension in one session. With
  # `return true` the autocmd deleted itself after the first and the rest were
  # read raw.
  cat > "$H/many.lua" <<'LUA'
local out = io.open(vim.env.OUT2, 'w')
for _, pat in ipairs({ '*.png', '*.mp4' }) do
  local grp = pat == '*.png' and 'hikovim_picture' or 'hikovim_video'
  out:write(pat .. '_left=' .. #vim.api.nvim_get_autocmds({ event = 'BufReadCmd', group = grp, pattern = pat }) .. '\n')
end
local raw = 0
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  local name = vim.api.nvim_buf_get_name(b)
  if name:match('%.png$') or name:match('%.mp4$') then
    local first = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ''
    if first:find('not really') then raw = raw + 1 end
  end
end
out:write('raw=' .. raw .. '\n')
out:close()
LUA
  (cd "$H" && OUT2="$H/out2" nvim --headless -u NONE --cmd "set rtp+=$REPO_ROOT/share/nvim" \
    -c "lua require('hikovim.picture').setup(); require('hikovim.video').setup()" \
    -c 'e a.png' -c 'e b.png' -c 'e c.png' -c 'e a.mp4' -c 'e b.mp4' \
    -c "luafile $H/many.lua" -c 'qa!' >/dev/null 2>&1)
  got2() { grep -m1 "^$1=" "$H/out2" 2>/dev/null | cut -d= -f2-; }
  chk "the picture autocmd survives three PNGs" "$(got2 '\*.png_left')" "1"
  chk "the video autocmd survives two MP4s"     "$(got2 '\*.mp4_left')" "1"
  chk "none of the five was read raw"           "$(got2 raw)" "0"
fi

finish
