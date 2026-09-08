#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either. SC2016 is
# off because the rc line under test must contain a literal $HOME, not this
# process's expansion of it — that is the thing being asserted.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
# github_install end to end, offline.
#
# github_api is overridden to emit a fixture and the assets are file:// URLs,
# so download, SHA-256 verification, extraction and install all run for real
# without touching the network.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
NANOLANDER_LIB=1 . "$REPO_ROOT/bin/nanolander"

temp_home; W="$TEST_HOME"
trap 'rm -rf "$W"' EXIT
LOCAL_BIN="$W/bin"
LOCAL_OPT="$W/opt"
STATE_DIR="$W/state"
MANIFEST="$STATE_DIR/installed"
OS_KEYWORDS="linux"
ARCH_KEYWORDS="x86_64-unknown-linux-gnu linux_amd64 x86_64 amd64"

# A tarball with the binary one directory down, as delta and dust ship.
mkdir -p "$W/src/faketool-1.0-x86_64-unknown-linux-gnu"
printf '#!/bin/sh\necho faketool 1.0\n' > "$W/src/faketool-1.0-x86_64-unknown-linux-gnu/faketool"
chmod +x "$W/src/faketool-1.0-x86_64-unknown-linux-gnu/faketool"
tar -czf "$W/f-x86_64-unknown-linux-gnu.tar.gz" -C "$W/src" faketool-1.0-x86_64-unknown-linux-gnu
SUM=$(sha256sum "$W/f-x86_64-unknown-linux-gnu.tar.gz" | awk '{print $1}')

github_api() {
  cat <<J
{"tag_name":"v1.0","assets":[
{"name":"checksums.txt","browser_download_url":"file://$W/checksums.txt"},
{"name":"f-x86_64-unknown-linux-gnu.tar.gz","digest":"sha256:$SUM","browser_download_url":"file://$W/f-x86_64-unknown-linux-gnu.tar.gz"}]}
J
}
out=$(github_install faketool fake/repo 2>&1)
chk "tarball install succeeds"   "$?" "0"
chk "digest is verified"         "$(printf '%s' "$out" | grep -c 'SHA-256 verified')" "1"
chk "binary is installed"        "$("$LOCAL_BIN/faketool" 2>/dev/null)" "faketool 1.0"
INSTALL_SOURCE=""
github_install faketool fake/repo >/dev/null 2>&1
chk "source recorded"            "$INSTALL_SOURCE" "GitHub release"

# A bare binary under a decorated name, as yq, shfmt and direnv ship.
printf '#!/bin/sh\necho yq 4.0\n' > "$W/yq_linux_amd64"
chmod +x "$W/yq_linux_amd64"
github_api() { printf '%s\n' "{\"assets\":[{\"name\":\"yq_linux_amd64\",\"browser_download_url\":\"file://$W/yq_linux_amd64\"}]}"; }
github_install yq fake/yq >/dev/null 2>&1
chk "bare binary installs"        "$?" "0"
chk "installed under plain name"  "$("$LOCAL_BIN/yq" 2>/dev/null)" "yq 4.0"

# A wrong digest must refuse, and leave nothing behind.
github_api() { printf '%s\n' "{\"assets\":[{\"name\":\"f.tar.gz\",\"digest\":\"sha256:$(printf '0%.0s' $(seq 64))\",\"browser_download_url\":\"file://$W/f-x86_64-unknown-linux-gnu.tar.gz\"}]}"; }
rm -f "$LOCAL_BIN/evil"
out=$(github_install evil fake/evil 2>&1)
chk "digest mismatch fails"       "$?" "1"
chk "mismatch is reported"        "$(printf '%s' "$out" | grep -c 'SHA-256 mismatch')" "1"
chk "nothing written on mismatch" "$(exists "$LOCAL_BIN/evil")" "n"

github_api() { printf '%s\n' '{"assets":[{"name":"t-windows-amd64.zip","browser_download_url":"file:///nope.zip"}]}'; }
github_install nope fake/nope >/dev/null 2>&1
chk "no asset for this platform fails" "$?" "1"

# Neovim keeps its runtime tree and is reached through a symlink.
mkdir -p "$W/src/nvim-linux-x86_64/bin" "$W/src/nvim-linux-x86_64/share/nvim/runtime"
printf '#!/bin/sh\necho NVIM v0.11\n' > "$W/src/nvim-linux-x86_64/bin/nvim"
chmod +x "$W/src/nvim-linux-x86_64/bin/nvim"
tar -czf "$W/nvim-linux-x86_64.tar.gz" -C "$W/src" nvim-linux-x86_64
github_api() { printf '%s\n' "{\"assets\":[{\"name\":\"nvim-linux-x86_64.tar.gz\",\"browser_download_url\":\"file://$W/nvim-linux-x86_64.tar.gz\"}]}"; }
github_install nvim neovim/neovim >/dev/null 2>&1
chk "neovim installs"             "$?" "0"
chk "runs through the symlink"    "$("$LOCAL_BIN/nvim" 2>/dev/null)" "NVIM v0.11"
chk "runtime tree preserved"      "$(exists "$LOCAL_OPT/nvim-github/share/nvim/runtime")" "y"
chk "nvim is a symlink"           "$(yn test -L "$LOCAL_BIN/nvim")" "y"

# Shell config is written once and compared whole-line.
RC="$W/rc"; : > "$RC"
add_line_once "$RC" 'export PATH="$HOME/.local/bin:$PATH"' >/dev/null
add_line_once "$RC" 'export PATH="$HOME/.local/bin:$PATH"' >/dev/null
chk "no duplicate rc line"        "$(grep -c 'local/bin' "$RC")" "1"
add_line_once "$RC" 'export PATH="$HOME/.local/bin:$PATH" # other' >/dev/null
chk "a different line still lands" "$(wc -l < "$RC" | tr -d ' ')" "2"

OPT_WITH_ALIASES=1
RC2="$W/rc2"; : > "$RC2"
add_alias_block "$RC2" >/dev/null
add_alias_block "$RC2" >/dev/null
chk "alias block written once"    "$(grep -c '>>> nanolander aliases >>>' "$RC2")" "1"
chk "every alias is guarded"      "$(grep -c 'alias ' "$RC2")" "$(grep -c 'command -v' "$RC2")"
chk "alias block is closed"       "$(grep -c '<<< nanolander aliases <<<' "$RC2")" "1"

finish
