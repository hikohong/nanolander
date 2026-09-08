#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either. SC2016 is
# off because the rc line under test must contain a literal $HOME, not this
# process's expansion of it — that is the thing being asserted.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
# The Nerd Font installer, offline.
#
# github_api is overridden and the archive is a local fixture, so family
# selection, the digest check, the monospaced-only rule and the manifest all
# run for real without the network.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
NANOLANDER_LIB=1 . "$REPO_ROOT/bin/nanolander"

W=$(mktemp -d); export HOME="$W"
LOCAL_BIN="$W/.local/bin"; LOCAL_OPT="$W/.local/opt"
STATE_DIR="$W/.local/share/nanolander"; MANIFEST="$STATE_DIR/installed"
OS_KIND="ubuntu"

# An archive shaped like the upstream one: monospaced faces, proportional
# faces, and documentation that must not be installed as a font.
python3 - "$W" <<'PY'
import zipfile,sys
w=sys.argv[1]
names=["JetBrainsMonoNerdFontMono-Regular.ttf","JetBrainsMonoNerdFontMono-Bold.ttf",
       "JetBrainsMonoNerdFontMono-Italic.ttf",
       "JetBrainsMonoNerdFont-Regular.ttf","JetBrainsMonoNerdFontPropo-Regular.ttf",
       "README.md","LICENSE"]
with zipfile.ZipFile(f"{w}/JetBrainsMono.zip","w") as z:
    for n in names: z.writestr(n, b"fake-font-data-"+n.encode())
PY
SUM=$(sha256sum "$W/JetBrainsMono.zip" | awk '{print $1}')

github_api(){ cat <<J
{"tag_name":"v3.2.1","assets":[
{"name":"Hack.zip","digest":"sha256:dead","browser_download_url":"file://$W/Hack.zip"},
{"name":"JetBrainsMono.zip","digest":"sha256:$SUM","browser_download_url":"file://$W/JetBrainsMono.zip"}]}
J
}

chk "no font before install" "$(nerd_font_installed && echo y || echo n)" "n"
out=$(install_nerd_font 2>&1); rc=$?
chk "install rc" "$rc" "0"
chk "digest verified" "$(printf '%s' "$out" | grep -c 'SHA-256 verified')" "1"
FD="$W/.local/share/fonts"
chk "picked the right family, not Hack" "$(count_files "$FD"/JetBrainsMono*)" "3"
chk "only Mono faces installed" "$(count_files "$FD"/*NerdFontMono-*)" "3"
chk "proportional faces skipped" "$(count_files "$FD"/*NerdFontPropo* "$FD"/*NerdFont-Regular*)" "0"
chk "docs not installed as fonts" "$(count_files "$FD"/README* "$FD"/LICENSE*)" "0"
chk "detected after install" "$(nerd_font_installed && echo y || echo n)" "y"
chk "manifest lists each face" "$(grep -c 'NerdFontMono' "$MANIFEST")" "3"

# An existing Nerd Font is left alone.
rm -f "$MANIFEST"
ensure_nerd_font nerd-font "Nerd Font" >/dev/null 2>&1
chk "already-present is not reinstalled" "$([ -f "$MANIFEST" ] && echo reinstalled || echo skipped)" "skipped"
chk "recorded as existing" "$(printf '%s' "$RESULTS" | grep -c 'nerd-font|SUCCESS|existing')" "1"

# and still counts as a success in the summary.
chk "counted as success" "$COUNT_SUCCESS" "1"

# A wrong digest must refuse, and write nothing.
rm -rf "$FD"; RESULTS=""; COUNT_SUCCESS=0
github_api(){ printf '%s\n' "{\"assets\":[{\"name\":\"JetBrainsMono.zip\",\"digest\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"browser_download_url\":\"file://$W/JetBrainsMono.zip\"}]}"; }
out=$(install_nerd_font 2>&1); chk "bad digest rc" "$?" "1"
chk "bad digest refuses" "$(printf '%s' "$out" | grep -c 'SHA-256 mismatch')" "1"
chk "nothing written on mismatch" "$(count_files "$FD"/*)" "0"

# A family that is not in the release fails with a usable pointer.
NERD_FONT_FAMILY="NoSuchFamily"
github_api(){ printf '%s\n' '{"assets":[{"name":"Hack.zip","browser_download_url":"file:///nope/Hack.zip"}]}'; }
out=$(install_nerd_font 2>&1); chk "missing family rc" "$?" "1"
chk "suggests NANOLANDER_NERD_FONT" "$(printf '%s' "$out" | grep -c 'NANOLANDER_NERD_FONT')" "1"
NERD_FONT_FAMILY="JetBrainsMono"

# The filter reaches it by either name.
ONLY_LIST="nerd-font"; wants_tool nerd-font "Nerd Font" && r=y || r=n; chk "--only nerd-font" "$r" "y"
ONLY_LIST="nerdfont";  wants_tool nerd-font "Nerd Font" && r=y || r=n; chk "--only nerdfont (display name)" "$r" "y"
ONLY_LIST=""; SKIP_LIST="nerd-font"; wants_tool nerd-font "Nerd Font" && r=y || r=n; chk "--skip nerd-font" "$r" "n"
SKIP_LIST=""

# Never from a package manager: that is what keeps the platforms identical.
chk "no package candidates" "$(pkg_candidates nerd-font)" ""

# Only the destination differs between platforms.
OS_KIND="macos"; chk "macOS font dir" "$(font_dir)" "$W/Library/Fonts"
OS_KIND="ubuntu"; chk "linux font dir" "$(font_dir)" "$W/.local/share/fonts"

rm -rf "$W"
finish
