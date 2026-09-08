#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either. SC2016 is
# off because the rc line under test must contain a literal $HOME, not this
# process's expansion of it — that is the thing being asserted.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
# --uninstall removes what the manifest records and nothing else.
#
# Both font directories are covered because the macOS one lives outside
# ~/.local, and a path outside either must be refused even when the manifest
# asks for it.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
H=$(mktemp -d); export HOME="$H"; NL="$REPO_ROOT/bin/nanolander"
printf 'export EDITOR=vim\n' > "$H/.bashrc"
mkdir -p "$H/.local/share/nanolander" "$H/.local/share/fonts" "$H/Library/Fonts" "$H/.local/bin"

# A font in each platform's directory, plus user fonts that must survive.
touch "$H/.local/share/fonts/JetBrainsMonoNerdFontMono-Regular.ttf"
touch "$H/Library/Fonts/JetBrainsMonoNerdFontMono-Bold.ttf"
touch "$H/.local/share/fonts/MyOwnFont.ttf"
touch "$H/Library/Fonts/MyPurchasedFont.otf"
printf '%s\n%s\n' "$H/.local/share/fonts/JetBrainsMonoNerdFontMono-Regular.ttf" \
                  "$H/Library/Fonts/JetBrainsMonoNerdFontMono-Bold.ttf" > "$H/.local/share/nanolander/installed"
# A path outside the install directories must be refused even when the
# manifest asks for it.
printf '%s\n' "/etc/passwd" >> "$H/.local/share/nanolander/installed"

out=$("$NL" --uninstall 2>&1); chk "uninstall exit" "$?" "0"
chk "linux font removed"  "$([ -e "$H/.local/share/fonts/JetBrainsMonoNerdFontMono-Regular.ttf" ] && echo y || echo n)" "n"
chk "macOS font removed"  "$([ -e "$H/Library/Fonts/JetBrainsMonoNerdFontMono-Bold.ttf" ] && echo y || echo n)" "n"
chk "user font kept (linux)" "$([ -e "$H/.local/share/fonts/MyOwnFont.ttf" ] && echo y || echo n)" "y"
chk "user font kept (macOS)" "$([ -e "$H/Library/Fonts/MyPurchasedFont.otf" ] && echo y || echo n)" "y"
chk "system path refused"  "$([ -e /etc/passwd ] && echo y || echo n)" "y"
chk "refusal reported"     "$(printf '%s' "$out" | grep -c 'Refusing to remove a path outside')" "1"
rm -rf "$H"
finish
