#!/usr/bin/env bash
# Assertions read variables the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either.
# shellcheck disable=SC1091,SC2034,SC2317
# find_payload picks the program, and command_works notices when it did not.
#
# Both of these exist because of one shipped bug. fastfetch's release tarball
# holds two files called fastfetch — usr/bin/fastfetch and a bash-completion
# script under usr/share — and `find` returns them in readdir order, so the
# completion script landed in ~/.local/bin/fastfetch on a real machine.
# command_works then ran it, got exit 0 and no output, and reported the tool
# verified. One bad pick plus one blind check is what let it through, so both
# halves are asserted here.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
NANOLANDER_LIB=1 . "$REPO_ROOT/bin/nanolander"

temp_home; W="$TEST_HOME"
trap 'rm -rf "$W"' EXIT

# --- find_payload ----------------------------------------------------------

# The fastfetch layout. The completion script is created first and lives in the
# alphabetically earlier directory, so a pass that only matches on name can
# reach it before the binary.
T="$W/tree"
mkdir -p "$T/usr/share/bash-completion/completions" "$T/usr/bin"
printf '#!/usr/bin/env bash\n_fastfetch() { :; }\n' \
  > "$T/usr/share/bash-completion/completions/fastfetch"
chmod 0644 "$T/usr/share/bash-completion/completions/fastfetch"
printf '#!/bin/sh\necho fastfetch 2.0\n' > "$T/usr/bin/fastfetch"
chmod 0755 "$T/usr/bin/fastfetch"
chk "picks the executable, not the completion" \
  "$(find_payload "$T" fastfetch)" "$T/usr/bin/fastfetch"

# A release that publishes a bare binary arrives as the file curl wrote, which
# is 0644. The executable-first pass must not be the only rule.
mkdir -p "$W/bare"
printf '#!/bin/sh\necho yq 4.0\n' > "$W/bare/yq"
chmod 0644 "$W/bare/yq"
chk "a non-executable exact match still wins" \
  "$(find_payload "$W/bare" yq)" "$W/bare/yq"

# The decorated-name pass prefers an executable too.
mkdir -p "$W/dec"
printf 'usage text\n' > "$W/dec/shfmt_v3.10.0_linux_amd64.txt"
printf '#!/bin/sh\necho shfmt 3.10\n' > "$W/dec/shfmt_v3.10.0_linux_amd64"
chmod 0755 "$W/dec/shfmt_v3.10.0_linux_amd64"
chk "prefix match finds the decorated binary" \
  "$(find_payload "$W/dec" shfmt)" "$W/dec/shfmt_v3.10.0_linux_amd64"

chk "nothing to find reports failure" "$(yn find_payload "$W/bare" absent)" "n"

# --- command_works ---------------------------------------------------------

BIN="$W/pathbin"
mkdir -p "$BIN"
PATH="$BIN:$PATH"

# The exact shape of the bug: on PATH, exits 0, prints nothing.
printf '#!/usr/bin/env bash\n_silent() { :; }\n' > "$BIN/silenttool"
chmod 0755 "$BIN/silenttool"
chk "silent exit 0 is not a working tool" "$(yn command_works silenttool)" "n"

printf '#!/bin/sh\necho realtool 1.2.3\n' > "$BIN/realtool"
chmod 0755 "$BIN/realtool"
chk "a version on stdout passes" "$(yn command_works realtool)" "y"

# poppler prints its version to stderr, so both streams have to count.
printf '#!/bin/sh\necho pdftoppm version 24.08 >&2\n' > "$BIN/pdftoppm"
chmod 0755 "$BIN/pdftoppm"
chk "a version on stderr passes" "$(yn command_works pdftoppm)" "y"

printf '#!/bin/sh\nexit 1\n' > "$BIN/brokentool"
chmod 0755 "$BIN/brokentool"
chk "a failing query is not a working tool" "$(yn command_works brokentool)" "n"

chk "absent from PATH is not a working tool" "$(yn command_works nosuchtool)" "n"

# entr and 7zz have no version flag, so PATH presence is the whole test and a
# silent exit 0 has to stay acceptable for exactly those two.
printf '#!/bin/sh\nexit 0\n' > "$BIN/entr"
chmod 0755 "$BIN/entr"
chk "entr is exempt from the output rule" "$(yn command_works entr)" "y"

# --- glibc_too_old_for -----------------------------------------------------
#
# A binary built against a newer glibc than the system has never reaches main:
# the loader refuses it. That is a platform gap, not a failed install, so the
# summary says SKIPPED (platform) and a complete run still exits 0. Amazon
# Linux 2023 is on glibc 2.34 while tree-sitter and resvg want 2.39 and 2.35,
# which made every full run on that platform exit 2.
cat > "$BIN/newglibctool" <<'STUB'
#!/bin/sh
echo "newglibctool: /lib64/libc.so.6: version \`GLIBC_2.39' not found" >&2
exit 1
STUB
chmod 0755 "$BIN/newglibctool"
chk "the loader's glibc error is recognised" "$(yn glibc_too_old_for newglibctool)" "y"
chk "and such a tool is not working"         "$(yn command_works newglibctool)" "n"

chk "an ordinary failure is not a glibc gap" "$(yn glibc_too_old_for brokentool)" "n"
chk "a working tool is not a glibc gap"      "$(yn glibc_too_old_for realtool)" "n"
chk "an absent tool is not a glibc gap"      "$(yn glibc_too_old_for nosuchtool)" "n"

finish
