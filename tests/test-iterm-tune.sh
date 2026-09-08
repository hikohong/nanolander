#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either. SC2016 is
# off because the rc line under test must contain a literal $HOME, not this
# process's expansion of it — that is the thing being asserted.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
# bin/iterm-tune: the settings tables it writes and the font-name check.
#
# PlistBuddy and iTerm2 exist only on macOS, so what is testable here is the
# data — that every record is well formed, that the advisory keys are not in
# the write tables, and that a Nerd Font is recognised by its face name.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
ITERM_TUNE_LIB=1 . "$REPO_ROOT/bin/iterm-tune"
chk "global settings count" "$(printf '%s\n' "$GLOBAL_SETTINGS" | grep -c '|')" "3"
chk "profile settings count" "$(printf '%s\n' "$PROFILE_SETTINGS" | grep -c '|')" "6"
# every record must have exactly 4 fields
bad=0
while IFS= read -r l; do [ -n "$l" ] || continue; n=$(printf '%s' "$l" | tr -cd '|' | wc -c); [ "$n" -eq 3 ] || bad=$((bad+1)); done <<X
$GLOBAL_SETTINGS
$PROFILE_SETTINGS
X
chk "all records 4-field" "$bad" "0"
chk "battery GPU target" "$(printf '%s\n' "$GLOBAL_SETTINGS" | awk -F'|' '/DisableMetalWhenUnplugged/{print $3}')" "false"
chk "throughput target" "$(printf '%s\n' "$GLOBAL_SETTINGS" | awk -F'|' '/MetalMaximizeThroughput/{print $3}')" "true"
chk "transparency off" "$(printf '%s\n' "$PROFILE_SETTINGS" | awk -F'|' '/^Transparency/{print $3}')" "0"
chk "scrollback bounded" "$(printf '%s\n' "$PROFILE_SETTINGS" | awk -F'|' '/Unlimited Scrollback/{print $3}')" "false"
chk "scrollback limit set" "$(printf '%s\n' "$PROFILE_SETTINGS" | awk -F'|' '/Scrollback Lines/{print $3}')" "10000"
chk "ligature keys" "$(printf '%s\n' "$PROFILE_SETTINGS" | grep -c 'Ligatures')" "2"
chk "triggers not in write table" "$(printf '%s\n%s\n' "$GLOBAL_SETTINGS" "$PROFILE_SETTINGS" | grep -c 'Triggers')" "0"
chk "bg image not in write table" "$(printf '%s\n%s\n' "$GLOBAL_SETTINGS" "$PROFILE_SETTINGS" | grep -c 'Background Image')" "0"
chk "show_value marks match" "$(show_value false false 'x')" "  [ok] x                                  current: false      target: false"
chk "show_value marks diff" "$(show_value true false 'x' | grep -c '\[->\]')" "1"
chk "show_value handles unset" "$(show_value '' false 'x' | grep -c '(unset)')" "1"

# is_nerd_font — patched faces advertise themselves in the face name, either
# spelled out or abbreviated.
for f in "JetBrainsMonoNFM-Regular" "HackNF-Regular" "MesloLGSNF-Regular" \
         "FiraCode Nerd Font Mono" "JetBrainsMonoNerdFontMono-Regular"; do
  chk "recognised as a Nerd Font: $f" "$(yn is_nerd_font "$f")" "y"
done
for f in "Monaco" "Menlo-Regular" "SFMono-Regular" "Courier New"; do
  chk "not a Nerd Font: $f" "$(yn is_nerd_font "$f")" "n"
done

finish
