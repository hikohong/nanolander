#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
# Which shell config file a run targets, and why.
#
# This suite exists because of a shipped bug: the file was chosen from the
# distribution alone, so an Amazon Linux cloud desktop had its configuration
# written into ~/.zshrc while the login shell was /usr/bin/logbash. Nothing in
# it was ever read, and sourcing it by hand printed a zsh syntax error per line.
# The logbash row below is that machine.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

NANOLANDER_LIB=1 . "$REPO_ROOT/bin/nanolander"

# ---- shell_kind_of: a wrapper counts, an unrelated shell does not -------
chk "bash"          "$(shell_kind_of /bin/bash)"            "bash"
chk "logbash"       "$(shell_kind_of /usr/bin/logbash)"     "bash"
chk "zsh"           "$(shell_kind_of /bin/zsh)"             "zsh"
chk "brew zsh"      "$(shell_kind_of /usr/local/bin/zsh)"   "zsh"
chk "fish is neither"  "$(shell_kind_of /usr/bin/fish)"     ""
chk "tcsh is neither"  "$(shell_kind_of /bin/tcsh)"         ""
chk "sh is neither"    "$(shell_kind_of /bin/sh)"           ""
chk "empty is neither" "$(shell_kind_of '')"                ""

# ---- resolve_shell_rc: precedence --------------------------------------
# A fixture login shell, so the outcome does not depend on the runner's own.
login_as() { LOGIN_SHELL_FIXTURE="$1"; }
current_login_shell() { printf '%s' "$LOGIN_SHELL_FIXTURE"; }

resolve_with() {
  OPT_SHELL="$1"
  OPT_SET_DEFAULT_SHELL="$2"
  OS_KIND="$3"
  SHELL_KIND="$4"          # the platform default resolve_shell_rc may fall back to
  OS_LABEL="fixture"
  resolve_shell_rc
}

# The bug: platform default says zsh, login shell says bash. bash wins.
login_as /usr/bin/logbash
resolve_with "" 0 amazon zsh
chk "logbash beats the amazon default" "$SHELL_RC" "$HOME/.bashrc"
chk "logbash sets the kind"            "$SHELL_KIND" "bash"
chk "the reason names the login shell" \
  "$(printf '%s' "$SHELL_RC_REASON" | grep -c 'login shell is /usr/bin/logbash')" "1"

# The mirror image: an Ubuntu box whose owner logs into zsh.
login_as /bin/zsh
resolve_with "" 0 ubuntu bash
chk "zsh login beats the ubuntu default" "$SHELL_RC" "$HOME/.zshrc"
chk "zsh login sets the kind"            "$SHELL_KIND" "zsh"

# An unrecognised login shell keeps the platform default rather than guessing.
login_as /usr/bin/fish
resolve_with "" 0 amazon zsh
chk "fish falls back to the default" "$SHELL_RC" "$HOME/.zshrc"
chk "the fallback is explained" \
  "$(printf '%s' "$SHELL_RC_REASON" | grep -c 'neither bash nor zsh')" "1"

# No readable passwd entry is a fallback too, with its own wording.
login_as ""
resolve_with "" 0 ubuntu bash
chk "unreadable login shell falls back" "$SHELL_RC" "$HOME/.bashrc"
chk "the unreadable case is explained" \
  "$(printf '%s' "$SHELL_RC_REASON" | grep -c 'could not read')" "1"

# --shell outranks the login shell.
login_as /bin/bash
resolve_with zsh 0 ubuntu bash
chk "--shell zsh wins"        "$SHELL_RC" "$HOME/.zshrc"
chk "--shell is the reason"   "$(printf '%s' "$SHELL_RC_REASON" | grep -c -- '--shell')" "1"
login_as /bin/zsh
resolve_with bash 0 macos zsh
chk "--shell bash wins on macOS too" "$SHELL_RC" "$HOME/.bashrc"

# --set-default-shell is a request for zsh, so target zsh even from bash.
login_as /usr/bin/logbash
resolve_with "" 1 amazon zsh
chk "--set-default-shell targets zsh" "$SHELL_RC" "$HOME/.zshrc"
# ...except on Ubuntu, where the option is documented as having no effect.
login_as /bin/bash
resolve_with "" 1 ubuntu bash
chk "--set-default-shell is inert on ubuntu" "$SHELL_RC" "$HOME/.bashrc"
# --shell still outranks it.
login_as /bin/bash
resolve_with zsh 1 amazon zsh
chk "--shell outranks --set-default-shell" "$SHELL_RC" "$HOME/.zshrc"

temp_home; H="$TEST_HOME"

# ---- ensure_zsh_present is gated on the target, not the platform -------
# A bash target must not install zsh for a file nothing will read.
#
# PATH is emptied for the duration, because ensure_zsh_present returns early
# when zsh is already on PATH. Without that, this assertion passed on any host
# that happens to have zsh — including the one this was written on — whatever
# the gate said. Nothing in the function needs an external command once the
# package helpers are overridden, so an empty PATH is safe.
mkdir -p "$H/empty"
reached_pkg=""
package_available() { reached_pkg="yes"; return 1; }
install_package()   { reached_pkg="yes"; return 1; }
OS_KIND="amazon"; SHELL_RC="$H/.bashrc"
OLD_PATH="$PATH"
# Narrowing PATH is the point of this block, not an accident, and it is put back
# five lines down.
# shellcheck disable=SC2123
PATH="$H/empty"
SHELL_KIND="bash"; ensure_zsh_present >/dev/null 2>&1
rc_bash=$?; reached_bash="$reached_pkg"
reached_pkg=""
SHELL_KIND="zsh"; ensure_zsh_present >/dev/null 2>&1
reached_zsh="$reached_pkg"
PATH="$OLD_PATH"
chk "bash target never installs zsh"     "$reached_bash" ""
chk "bash target returns cleanly"        "$rc_bash"      "0"
chk "zsh target does reach the packager" "$reached_zsh"  "yes"

# ---- report_foreign_rc -------------------------------------------------
SHELL_KIND="bash"
printf '# just mine\nexport EDITOR=vim\n' > "$H/.zshrc"
out=$(report_foreign_rc 2>&1)
chk "a clean foreign file is not mentioned" "$(printf '%s' "$out" | grep -c 'also carries')" "0"
{
  shell_line zoxide zsh; printf '\n'
  shell_line starship zsh; printf '\n'
} >> "$H/.zshrc"
out=$(report_foreign_rc 2>&1)
chk "managed lines in the foreign file are reported" \
  "$(printf '%s' "$out" | grep -c 'also carries 2 managed line')" "1"
chk "the report names the file" "$(printf '%s' "$out" | grep -c "$H/.zshrc")" "1"
chk "nothing was deleted" "$(grep -c 'export EDITOR=vim' "$H/.zshrc")" "1"
# A missing foreign file is silence, not an error.
rm -f "$H/.zshrc"
out=$(report_foreign_rc 2>&1); chk "missing foreign file exits 0" "$?" "0"
chk "missing foreign file says nothing" "$(printf '%s' "$out" | wc -c | tr -d ' ')" "0"

# ---- --shell argument validation ---------------------------------------
NL="$REPO_ROOT/bin/nanolander"
"$NL" --shell fish >/dev/null 2>&1
chk "--shell fish is a usage error" "$?" "64"
"$NL" --shell >/dev/null 2>&1
chk "--shell with no value is a usage error" "$?" "64"
"$NL" --shell bash --set-default-shell >/dev/null 2>&1
chk "--shell bash with --set-default-shell is refused" "$?" "64"
out=$("$NL" --shell=ZSH --list-tools 2>&1)
chk "--shell=ZSH is accepted, case-insensitively" "$?" "0"
chk "--shell is documented in --help" "$("$NL" --help | grep -c -- '--shell bash|zsh')" "1"

rm -rf "$H"
finish
