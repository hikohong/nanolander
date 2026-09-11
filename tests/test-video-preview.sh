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
INIT="$REPO_ROOT/share/nvim/lua/hikovim/init.lua"

# --- shipped and wired -----------------------------------------------------
chk "video.lua ships"        "$(exists "$VIDEO")" "y"
chk "and is set up"          "$(grep -c "require('hikovim.video').setup()" "$INIT")" "1"

# BufReadCmd is the point: Neovim hands the whole read over, so the binary is
# never loaded and never guessed at.
chk "it replaces the read"   "$(grep -c "'BufReadCmd'" "$VIDEO")" "1"
chk "containers are matched" "$(grep -c "'\*.mkv'" "$VIDEO")" "1"

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
fi

finish
