#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either. SC2016 is
# off because the rc line under test must contain a literal $HOME, not this
# process's expansion of it — that is the thing being asserted.
# shellcheck disable=SC1091,SC2016,SC2034,SC2317
# Shell config: backup, --restore-shell and --uninstall, against a throwaway HOME.
#
# The same-second cases are here because a collision once overwrote the only
# copy of the original rc file and then restored from it.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
temp_home; H="$TEST_HOME"

# Which rc file gets written is decided by the runner's login shell, so it is
# not a constant: this suite used to infer it from uname, which was already
# wrong for a Linux box whose login shell is zsh. --shell pins it instead, so
# every assertion below is about backup/restore/uninstall and nothing else.
# Picking the target is test-shell-target.sh's job.
RCNAME=".bashrc"
RC="$H/$RCNAME"
NL="$REPO_ROOT/bin/nanolander"
# No package manager work: these assertions are about the rc file.
stub_tools "$H/stub" apt-get brew dnf yum sudo

# A realistic pre-existing rc file the user cares about.
cat > "$RC" <<'USERRC'
# my own config
export EDITOR=vim
alias gs='git status'
PS1='\u@\h:\w\$ '
USERRC
ORIG=$(cat "$RC")

# ---- install ------------------------------------------------------------
"$NL" --shell bash --only git --with-aliases >/dev/null 2>&1
chk "install exit" "$?" "0"
chk "backup dir created" "$([ -d "$H/.nanolander-backups" ] && echo y || echo n)" "y"
chk "one backup of the rc file" "$(count_files "$H/.nanolander-backups"/"$RCNAME".*)" "1"
chk "backup matches the original" "$(cat "$H/.nanolander-backups"/"$RCNAME".* )" "$ORIG"
chk "PATH line added" "$(grep -Fxc 'export PATH="$HOME/.local/bin:$PATH"' "$RC")" "1"
chk "alias block added" "$(grep -c '>>> nanolander aliases >>>' "$RC")" "1"
chk "user content intact" "$(grep -c "alias gs='git status'" "$RC")" "1"

# ---- restore ------------------------------------------------------------
out=$("$NL" --restore-shell 2>&1); chk "restore exit" "$?" "0"
chk "rc restored byte-for-byte" "$(cat "$RC")" "$ORIG"
chk "install backup untouched" "$(count_files "$H/.nanolander-backups"/"$RCNAME".*)" "1"
chk "pre-restore snapshot kept" "$(count_files "$H/.nanolander-backups/pre-restore"/"$RCNAME".*)" "1"
# restoring twice must land on the same content, not toggle
"$NL" --restore-shell >/dev/null 2>&1
chk "restore is idempotent" "$(cat "$RC")" "$ORIG"
# same-second runs must not clobber each other's backups
for _ in 1 2 3; do "$NL" --shell bash --only git >/dev/null 2>&1; "$NL" --restore-shell >/dev/null 2>&1; done
chk "no backup was overwritten" "$(cat "$RC")" "$ORIG"

# ---- install again, then uninstall --------------------------------------
"$NL" --shell bash --only git --with-aliases >/dev/null 2>&1
echo 'export MY_LATER_VAR=1' >> "$RC"          # user edits after install
mkdir -p "$H/.local/share/nanolander" "$H/.local/bin" "$H/.local/opt"
printf 'fake\n' > "$H/.local/bin/faketool"; chmod +x "$H/.local/bin/faketool"
mkdir -p "$H/.local/opt/nvim-github/bin"
printf '%s\n%s\n' "$H/.local/bin/faketool" "$H/.local/opt/nvim-github" >> "$H/.local/share/nanolander/installed"
# a hostile manifest entry that must be refused
OUTSIDE="$H/precious.txt"; echo keep > "$OUTSIDE"
printf '%s\n' "$OUTSIDE" >> "$H/.local/share/nanolander/installed"

out=$("$NL" --uninstall 2>&1); chk "uninstall exit" "$?" "0"
chk "PATH line gone"      "$(grep -Fxc 'export PATH="$HOME/.local/bin:$PATH"' "$RC")" "0"
chk "alias block gone"    "$(grep -c 'nanolander aliases' "$RC")" "0"
chk "user config kept"    "$(grep -c "alias gs='git status'" "$RC")" "1"
chk "later user edit kept" "$(grep -c 'MY_LATER_VAR' "$RC")" "1"
chk "PS1 untouched"       "$(grep -c 'PS1=' "$RC")" "1"
chk "manifest tool removed" "$([ -e "$H/.local/bin/faketool" ] && echo y || echo n)" "n"
chk "nvim tree removed"     "$([ -e "$H/.local/opt/nvim-github" ] && echo y || echo n)" "n"
chk "outside path REFUSED"  "$([ -e "$OUTSIDE" ] && echo y || echo n)" "y"
chk "refusal reported"      "$(printf '%s' "$out" | grep -c 'Refusing to remove a path outside')" "1"
chk "manifest cleared"      "$([ -e "$H/.local/share/nanolander/installed" ] && echo y || echo n)" "n"

# ---- uninstall is safe to repeat ---------------------------------------
before=$(cat "$RC")
"$NL" --uninstall >/dev/null 2>&1
chk "second uninstall is a no-op" "$(cat "$RC")" "$before"

# ---- restore with no backups at all ------------------------------------
H2=$(mktemp -d)
HOME="$H2" XDG_DATA_HOME="$H2/.local/share" "$NL" --restore-shell >/dev/null 2>&1
chk "restore with no backups fails" "$?" "1"

rm -rf "$H" "$H2"
finish
