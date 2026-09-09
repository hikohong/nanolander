#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either. SC2016 is
# off because the rc line under test must contain a literal $HOME, not this
# process's expansion of it — that is the thing being asserted.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
# Release-asset selection and the --only/--skip filter.
#
# The suffix-before-substring rule is the reason this file exists: a machine
# reporting arm64 must never be handed a linux_arm build.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
NANOLANDER_LIB=1 . "$REPO_ROOT/bin/nanolander"

OS_KEYWORDS="linux"
ARCH_KEYWORDS="aarch64-unknown-linux-gnu aarch64-unknown-linux-musl linux_arm64 linux-arm64 aarch64 arm64"
A="https://x/yq_linux_arm	d1
https://x/yq_linux_arm64	d2
https://x/yq_linux_amd64	d3"
select_asset "$A"
chk "arm64 must not pick linux_arm" "$PICKED_URL" "https://x/yq_linux_arm64"
chk "digest stays paired with its own asset" "$PICKED_DIGEST" "d2"

ARCH_KEYWORDS="armv7-unknown-linux-gnueabihf arm-unknown-linux-gnueabihf linux_armv7 linux-armv7 armv7l armv7 armhf"
select_asset "https://x/dive_linux_arm64.tar.gz	
https://x/dive_linux_armv7.tar.gz	"
chk "armv7 picks armv7, not arm64" "$PICKED_URL" "https://x/dive_linux_armv7.tar.gz"

ARCH_KEYWORDS="x86_64-unknown-linux-gnu x86_64 amd64"
select_asset "https://x/t-x86_64-unknown-linux-gnu.tar.gz.sha256	
https://x/t_amd64.deb	
https://x/t-x86_64-unknown-linux-gnu.tar.gz	"
chk "checksums and .deb are skipped" "$PICKED_URL" "https://x/t-x86_64-unknown-linux-gnu.tar.gz"

select_asset "https://x/glow_2.0.0_Linux_x86_64.tar.gz	"
chk "OS match is case-insensitive" "$PICKED_URL" "https://x/glow_2.0.0_Linux_x86_64.tar.gz"

OS_KEYWORDS="apple-darwin darwin macos osx"
ARCH_KEYWORDS="aarch64-apple-darwin arm64-apple-darwin darwin_arm64 arm64 aarch64"
chk "darwin never takes a linux asset" \
  "$(yn select_asset "https://x/t-aarch64-unknown-linux-gnu.tar.gz	")" "n"

chk "strip .tar.gz"        "$(strip_archive_ext a-b.tar.gz)" "a-b"
chk "strip .tbz"           "$(strip_archive_ext btop-x86_64-linux-musl.tbz)" "btop-x86_64-linux-musl"
chk "bare binary untouched" "$(strip_archive_ext yq_linux_amd64)" "yq_linux_amd64"

# Neovide publishes an uncompressed .tar. Missing from is_archive, the tarball
# itself was installed as the binary and died with an exec format error.
chk "strip .tar"           "$(strip_archive_ext neovide-linux-x86_64.tar)" "neovide-linux-x86_64"
chk ".tar is an archive"   "$(yn is_archive neovide-linux-x86_64.tar)" "y"
chk ".tar.gz is an archive" "$(yn is_archive t.tar.gz)" "y"
chk "a bare binary is not" "$(yn is_archive direnv.linux-amd64)" "n"

# gping's gnu build wants a glibc newer than Amazon Linux 2023 carries, so the
# static musl build is pinned by name for every Linux architecture.
OS_KIND="ubuntu"
chk "gping is pinned to musl on x86_64" \
  "$(ARCH=x86_64; github_asset_name gping)" "gping-Linux-musl-x86_64.tar.gz"
chk "gping is pinned to musl on arm64" \
  "$(ARCH=arm64; github_asset_name gping)" "gping-Linux-musl-arm64.tar.gz"
chk "gping is pinned to musl on armv7" \
  "$(ARCH=armv7; github_asset_name gping)" "gping-Linux-musleabihf-armv7.tar.gz"
chk "no gping override on macOS" "$(OS_KIND=macos; github_asset_name gping)" ""

# The last asset of a release used to be dropped: tr leaves no trailing
# newline on the final chunk and read discards it.
J='{"assets":[{"name":"a","digest":"sha256:aaa","browser_download_url":"https://x/a.tar.gz"},{"name":"b","browser_download_url":"https://x/b.tar.gz","digest":"sha256:bbb"}]}'
chk "parse_assets keeps the last asset" \
  "$(printf '%s' "$J" | parse_assets | tr '\t' '=' | tr '\n' ' ')" \
  "https://x/a.tar.gz=aaa https://x/b.tar.gz=bbb "

ONLY_LIST=""; SKIP_LIST=""
chk "no filter installs everything" "$(yn wants_tool rg ripgrep)" "y"
ONLY_LIST="rg,nvim"
chk "--only by command name"        "$(yn wants_tool rg ripgrep)" "y"
chk "--only excludes the rest"      "$(yn wants_tool bat bat)" "n"
ONLY_LIST=" RIPGREP , Neovim "
chk "--only ignores case and space" "$(yn wants_tool rg ripgrep)" "y"
chk "--only matches display name"   "$(yn wants_tool nvim Neovim)" "y"
ONLY_LIST=""; SKIP_LIST="lazydocker,dive"
chk "--skip excludes"               "$(yn wants_tool dive dive)" "n"
chk "--skip keeps the rest"         "$(yn wants_tool rg ripgrep)" "y"

finish
