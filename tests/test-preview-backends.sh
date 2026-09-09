#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either, so the
# never-invoked (SC2329) and unused (SC2034) reports on those are wrong, and so
# is SC2317. SC2016 is off because a stub's body must reach the file with a
# literal $1 in it. SC2030/SC2031 are off because a PATH set inside $( ) is
# exactly the scope wanted: the stub must be visible to the one call under test
# and to nothing after it.
# shellcheck disable=SC1091,SC2016,SC2030,SC2031,SC2034,SC2317,SC2329
# yazi and the preview backends.
#
# The reason this file exists is that keyword matching picks the wrong asset for
# both projects that need an override: it takes FFmpeg's -gpl-shared build,
# whose ffmpeg cannot run once the archive is gone, and yazi's gnu build, which
# wants a newer glibc than Amazon Linux 2 has. Both traps are asserted here, so
# a later refactor of select_asset cannot quietly reopen them.
#
# The github_install cases come last: they override two of the script's own
# functions, and leaving that until the end means nothing has to put them back.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
NANOLANDER_LIB=1 . "$REPO_ROOT/bin/nanolander"

temp_home; W="$TEST_HOME"
trap 'rm -rf "$W"' EXIT
LOCAL_BIN="$W/bin"
LOCAL_OPT="$W/opt"
STATE_DIR="$W/state"
MANIFEST="$STATE_DIR/installed"

# --- the catalog ------------------------------------------------------------
in_catalog() { printf '%s\n' "$TOOL_CATALOG" | grep -c "^$1|"; }
chk "yazi is in the catalog"    "$(in_catalog yazi)" "1"
chk "file is in the catalog"    "$(in_catalog file)" "1"
chk "ffmpeg is in the catalog"  "$(in_catalog ffmpeg)" "1"
chk "poppler is in the catalog" "$(in_catalog pdftoppm)" "1"
chk "7-Zip is in the catalog"   "$(in_catalog 7zz)" "1"
chk "magick is in the catalog"  "$(in_catalog magick)" "1"
chk "resvg is in the catalog"   "$(in_catalog resvg)" "1"

# print_tool_catalog prints a heading when the category changes, so every entry
# of one category has to sit together or the heading appears twice.
chk "preview backends stay contiguous" \
  "$(printf '%s\n' "$TOOL_CATALOG" | awk -F'|' '{print $3}' | uniq \
     | grep -c 'File preview backends')" "1"

chk "yazi has a release repo"     "$(github_repo yazi)" "sxyazi/yazi"
chk "poppler is repository-only"  "$(github_repo pdftoppm)" ""
chk "magick is repository-only"   "$(github_repo magick)" ""

# The same tool is packaged under different names, and the older name is the one
# still shipping on the platforms that matter here.
chk "7zip candidates cover p7zip"    "$(pkg_candidates 7zz | grep -c 'p7zip-full')" "1"
chk "ffmpeg candidates cover AL2023" "$(pkg_candidates ffmpeg | grep -c 'ffmpeg-free')" "1"

# --- the two asset traps ----------------------------------------------------
OS_KIND="ubuntu"
ARCH="x86_64"
OS_KEYWORDS="linux"
ARCH_KEYWORDS="x86_64-unknown-linux-gnu x86_64-unknown-linux-musl linux_amd64 linux-amd64 x86_64 amd64 x64 64bit"

# GitHub returns assets in name order, which puts -gpl-shared before -gpl.
FF="https://x/ffmpeg-master-latest-linux64-gpl-shared.tar.xz
https://x/ffmpeg-master-latest-linux64-gpl.tar.xz	"
select_asset "$FF"
chk "keyword matching takes the shared build" \
  "$PICKED_URL" "https://x/ffmpeg-master-latest-linux64-gpl-shared.tar.xz"
chk "so ffmpeg names the static one" \
  "$(github_asset_name ffmpeg)" "ffmpeg-master-latest-linux64-gpl.tar.xz"
chk "and the arm64 one is named too" \
  "$(ARCH=arm64; github_asset_name ffmpeg)" "ffmpeg-master-latest-linuxarm64-gpl.tar.xz"

Y="https://x/yazi-x86_64-unknown-linux-gnu.zip
https://x/yazi-x86_64-unknown-linux-musl.zip	"
select_asset "$Y"
chk "keyword matching takes yazi's gnu build" \
  "$PICKED_URL" "https://x/yazi-x86_64-unknown-linux-gnu.zip"
chk "so yazi names the musl one" \
  "$(github_asset_name yazi)" "yazi-x86_64-unknown-linux-musl.zip"
chk "musl on arm64 as well" \
  "$(ARCH=arm64; github_asset_name yazi)" "yazi-aarch64-unknown-linux-musl.zip"
chk "and the named asset does win" \
  "$(select_named_asset "$Y" "$(github_asset_name yazi)" && printf '%s' "$PICKED_URL")" \
  "https://x/yazi-x86_64-unknown-linux-musl.zip"

# macOS takes everything from Homebrew, so there is no name to pin there.
chk "no override on macOS"        "$(OS_KIND=macos; github_asset_name yazi)" ""
chk "no override for other tools" "$(github_asset_name rg)" ""

chk "yazi brings ya"           "$(github_extras yazi)" "ya"
chk "ffmpeg brings ffprobe"    "$(github_extras ffmpeg)" "ffprobe"
chk "most tools bring nothing" "$(github_extras rg)" ""

# --- where there is nothing to install --------------------------------------
unsupported() { OS_KIND="$1"; ARCH="$2"; yn tool_unsupported_here "$3"; }
chk "yazi skipped on armv7"           "$(unsupported ubuntu armv7 yazi)" "y"
chk "yazi skipped on armv6"           "$(unsupported ubuntu armv6 yazi)" "y"
chk "yazi installed on arm64"         "$(unsupported ubuntu arm64 yazi)" "n"
chk "yazi installed on x86_64"        "$(unsupported amazon x86_64 yazi)" "n"
chk "resvg skipped on Linux arm64"    "$(unsupported ubuntu arm64 resvg)" "y"
chk "resvg installed on macOS arm64"  "$(unsupported macos arm64 resvg)" "n"
chk "resvg installed on Linux x86_64" "$(unsupported ubuntu x86_64 resvg)" "n"
chk "Neovide unchanged"               "$(unsupported ubuntu arm64 neovide)" "y"
chk "eza has no exception"            "$(unsupported ubuntu armv6 eza)" "n"

# --- verification and compat links ------------------------------------------
STUB="$W/stub"; mkdir -p "$STUB"
# 7-Zip has no version flag, so being on PATH is the whole test. A stub that
# fails every argument proves command_works is not calling one.
printf '#!/bin/sh\nexit 3\n' > "$STUB/7zz"
printf '#!/bin/sh\ncase "$1" in -v) echo "pdftoppm 24.02";; *) exit 1;; esac\n' > "$STUB/pdftoppm"
printf '#!/bin/sh\ncase "$1" in -version) echo "ffmpeg 7.1";; *) exit 1;; esac\n' > "$STUB/ffmpeg"
chmod +x "$STUB/7zz" "$STUB/pdftoppm" "$STUB/ffmpeg"
chk "7zz is verified by presence"   "$(PATH="$STUB:$PATH"; yn command_works 7zz)" "y"
chk "pdftoppm is verified with -v"  "$(PATH="$STUB:$PATH"; yn command_works pdftoppm)" "y"
chk "ffmpeg is verified with -version" "$(PATH="$STUB:$PATH"; yn command_works ffmpeg)" "y"

# Older p7zip calls it 7z, and ImageMagick 6 has convert but no magick. The
# link is only made when the modern name is missing, so the host's own 7zz and
# magick have to be off PATH or there is nothing for this to assert.
LINKS="$W/links"; mkdir -p "$LINKS"
printf '#!/bin/sh\necho 7z 16.02\n' > "$LINKS/7z"
printf '#!/bin/sh\necho convert IM6\n' > "$LINKS/convert"
chmod +x "$LINKS/7z" "$LINKS/convert"
( PATH="$LINKS:$(path_without 7zz magick)"; make_compat_links >/dev/null 2>&1 )
chk "7z is linked to 7zz"         "$("$LOCAL_BIN/7zz" 2>/dev/null)" "7z 16.02"
chk "convert is linked to magick" "$("$LOCAL_BIN/magick" 2>/dev/null)" "convert IM6"

# --- the preview note -------------------------------------------------------
RESULTS="yazi|SUCCESS|GitHub release|/usr/local/bin/yazi
eza|FAILED|-|-
"
chk "a success is seen"     "$(yn tool_succeeded yazi)" "y"
chk "a failure is not"      "$(yn tool_succeeded eza)" "n"
chk "an absent tool is not" "$(yn tool_succeeded ffmpeg)" "n"
out=$(report_preview_notes 2>&1)
chk "the note says SSH works" "$(printf '%s' "$out" | grep -c 'travel over SSH')" "1"
chk "the note names ueberzug" "$(printf '%s' "$out" | grep -c 'Ueberzug')" "1"
RESULTS="eza|SUCCESS|package manager|/usr/bin/eza
"
chk "no yazi, no note" "$(report_preview_notes 2>&1 | wc -c | tr -d ' ')" "0"

# --- github_install honours both, offline -----------------------------------
# A .zip fixture would need the zip command and a .tar.xz would need xz; neither
# is guaranteed on a runner. The wiring is what matters here, and the real yazi
# and FFmpeg names are asserted above.
OS_KIND="ubuntu"
ARCH="x86_64"

mk_tarball() {
  local variant="$1"
  mkdir -p "$W/src/f-$variant"
  printf '#!/bin/sh\necho faketool %s\n' "$variant" > "$W/src/f-$variant/faketool"
  printf '#!/bin/sh\necho helper %s\n' "$variant" > "$W/src/f-$variant/helper"
  chmod +x "$W/src/f-$variant/faketool" "$W/src/f-$variant/helper"
  tar -czf "$W/f-$variant.tar.gz" -C "$W/src" "f-$variant"
}
mk_tarball x86_64-unknown-linux-gnu
mk_tarball x86_64-unknown-linux-musl

github_api() {
  cat <<J
{"tag_name":"v1.0","assets":[
{"name":"f-x86_64-unknown-linux-gnu.tar.gz","browser_download_url":"file://$W/f-x86_64-unknown-linux-gnu.tar.gz"},
{"name":"f-x86_64-unknown-linux-musl.tar.gz","browser_download_url":"file://$W/f-x86_64-unknown-linux-musl.tar.gz"}]}
J
}
github_asset_name() { printf 'f-x86_64-unknown-linux-musl.tar.gz'; }
github_extras() { printf 'helper'; }

github_install faketool fake/repo >/dev/null 2>&1
chk "the named asset is the one installed" \
  "$("$LOCAL_BIN/faketool" 2>/dev/null)" "faketool x86_64-unknown-linux-musl"
chk "the extra binary lands too" \
  "$("$LOCAL_BIN/helper" 2>/dev/null)" "helper x86_64-unknown-linux-musl"
chk "the extra is recorded for --uninstall" \
  "$(grep -c "^$LOCAL_BIN/helper$" "$MANIFEST")" "1"

# An upstream rename must degrade to keyword matching, not fail the tool.
github_asset_name() { printf 'f-x86_64-unknown-linux-gone.tar.gz'; }
rm -f "$LOCAL_BIN/faketool"
out=$(github_install faketool fake/repo 2>&1)
chk "a renamed asset still installs"  "$?" "0"
chk "the fallback says what happened" "$(printf '%s' "$out" | grep -c 'falling back to keyword matching')" "1"
chk "and keyword matching took the gnu build" \
  "$("$LOCAL_BIN/faketool" 2>/dev/null)" "faketool x86_64-unknown-linux-gnu"

# A missing extra is a warning: the catalog command is there and works.
github_asset_name() { printf ''; }
github_extras() { printf 'absent'; }
out=$(github_install faketool fake/repo 2>&1)
chk "a missing extra does not fail the tool" "$?" "0"
chk "and it is reported" "$(printf '%s' "$out" | grep -c 'No absent alongside faketool')" "1"

finish
