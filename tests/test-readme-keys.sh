#!/usr/bin/env bash
# The grep patterns here are literal markdown — backticks and pipes as they
# appear on the page — so single quotes are deliberate and nothing in them is
# meant to expand.
# shellcheck disable=SC1091,SC2016
# README.md is the specification, and its keys reference is the one place a
# reader is told what every mapping does. This suite is what keeps the two from
# drifting: every lhs and every user command the configuration defines has to be
# written down there. Nothing here needs Neovim, a plugin or a platform — it
# reads the lua source as text.
#
# Only what *this* configuration defines is checked. The plugin defaults the
# reference also lists — neo-tree's <BS>, oil's `-`, aerial's `{` — live
# upstream and are pinned by share/nvim/lazy-lock.json, so asserting those would
# need the plugins installed; tests/README.md says so.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

README="$REPO_ROOT/README.md"
KEYS="$REPO_ROOT/share/nvim/lua/hikovim/keys.lua"
IDE="$REPO_ROOT/share/nvim/lua/hikovim/ide.lua"
PLUGINS="$REPO_ROOT/share/nvim/lua/hikovim/plugins.lua"

# The reference itself, and its sub-headings. A refactor that drops a pane's
# table takes every key in it with it, and each assertion below would still
# pass by finding the key somewhere else in the file.
chk "the reference exists" "$(grep -c '^### Keys and commands$' "$README")" "1"
for h in 'Rebound, because the vim plugin is gone' \
         'Added, only on keys' \
         'The layout and its panes' \
         'In the file tree' \
         'In the directory editor' \
         'Completion and predictive text' \
         'Editing, from the coding plugins' \
         'In the outline' \
         'From a language server' \
         'Unchanged from'; do
  chk "reference section: $h" "$(grep -c "^#### .*$h" "$README")" "1"
done

# Every lhs the configuration maps, as README spells it: <leader> is `,` there,
# and lua's '<C-\\>s' is a single backslash on the page.
lhs_list() {
  {
    grep -ohE "map(_nxo)?\('[^']+'" "$KEYS"
    grep -ohE "keymap\.set\((\{[^}]*\}|'[a-z]'), '[^']+'" "$IDE"
    # plugins.lua defines mappings three more ways, and every one of them was
    # missed the first time this suite was written — dial's <C-a> passed
    # undocumented because only the two modules above were read.
    #
    #   keys = { { '<C-a>', … } }          a lazy lazy-load trigger
    #   mappings = { ['<CR>'] = … }        a plugin's own keymap table
    #   keymap = { accept = '<C-l>', … }   named fields, as copilot spells it
    #
    # The first pattern also catches a dependency line, 'owner/repo', which
    # the slash filter below drops.
    grep -ohE "^[[:space:]]*\{ '[^']+'," "$PLUGINS"
    grep -ohE "\['[^']+'\][[:space:]]*=" "$PLUGINS"
    grep -ohE "=[[:space:]]*'<[^']+>'" "$PLUGINS"
  } | sed -E "s/.*'([^']+)'.*/\1/" \
    | sed -e 's/<leader>/,/' -e 's/\\\\/\\/' \
    | grep -E '^(<|,|\]|\[)|^.$' \
    | sort -u
}

# The two mouse mappings are documented in words, because "single click" is
# what a reader does and <LeftRelease> is only what the config calls it. They
# are checked against that wording instead of the key name.
readme_spelling() {
  case "$1" in
    '<LeftRelease>')  printf 'single click' ;;
    '<2-LeftMouse>')  printf 'double click' ;;
    *)                printf '`%s`' "$1" ;;
  esac
}

# The reference section alone, not the whole file. A key mentioned in passing
# somewhere else is not documented: <C-a> passed this suite on a sentence in
# the layer-3 table while its own row had been deleted, and neo-tree's
# clear_filter row carried <C-x> for dial.
reference=$(sed -n '/^### Keys and commands$/,/^### [^K]/p' "$README")
chk "the reference was found" \
  "$([ "$(printf '%s\n' "$reference" | wc -l | tr -d ' ')" -gt 80 ] && echo yes || echo no)" "yes"

count=0
missing=""
while IFS= read -r key; do
  [ -n "$key" ] || continue
  count=$((count + 1))
  printf '%s\n' "$reference" | grep -Fq -- "$(readme_spelling "$key")" \
    || missing="$missing $key"
done <<KEYS_IN
$(lhs_list)
KEYS_IN

# Both mouse spellings have to be in the tree section, not merely somewhere in
# the file: <2-LeftMouse> passed this suite once on a sentence in a paragraph
# about why the double click used to do nothing.
tree_section=$(sed -n '/^#### In the file tree/,/^#### /p' "$README")
chk "single click is in the tree section" \
  "$(printf '%s\n' "$tree_section" | grep -q 'single click' && echo yes || echo no)" "yes"
chk "double click is in the tree section" \
  "$(printf '%s\n' "$tree_section" | grep -q 'double click' && echo yes || echo no)" "yes"

# A count too, so a regex that silently stops matching cannot pass by finding
# nothing to check.
chk "every mapped key is documented" "$missing" ""
chk "mappings found to check" "$([ "$count" -ge 34 ] && echo enough || echo "$count")" "enough"

# The user commands, the same way.
cmd_missing=""
cmd_count=0
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  cmd_count=$((cmd_count + 1))
  grep -Fq -- "\`:$cmd\`" "$README" || cmd_missing="$cmd_missing :$cmd"
done <<CMDS
$(grep -ohE "create_user_command\('[A-Za-z]+'" "$IDE" | sed -E "s/.*'([^']+)'\$/\1/" | sort -u)
CMDS
chk "every user command is documented" "$cmd_missing" ""
chk "commands found to check" "$cmd_count" "4"

# The <C-\> family is eight letters in ~/.vimrc and has to stay eight here: a
# letter quietly dropped from the config is a key that answers nothing, and one
# dropped from README is a reader who never learns it exists.
chk "cscope letters mapped" "$(grep -cE "map\('<C-\\\\\\\\>" "$KEYS")" "8"
chk "cscope letters documented" \
  "$(grep -oE '`<C-\\>[a-z]`' "$README" | sort -u | wc -l | tr -d ' ')" "8"

# The reference is the only copy of the :q rule and of the layout's commands.
# Two copies is how the one nobody edits goes stale.
chk "one :q explanation" "$(grep -c 'closes the tab rather than the window' "$README")" "1"
chk "one layout command table" "$(grep -c '| `:IDE` / `:IDEClose` |' "$README")" "1"

# What the file tree section has to keep saying, because it is the part a reader
# comes to it for and the part that is easy to get wrong: the root is not pinned
# to the project, and :Neotree renders into the focused window.
chk "navigate_up documented" "$(grep -c '| `<BS>` | root up one level' "$README")" "1"
chk "Neotree dir= documented" "$(grep -c 'Neotree dir=' "$README")" "2"
chk "the focused-window trap is stated" "$(grep -c "position = 'current'" "$README")" "1"

# Completion is the one documented decision this configuration reversed, so
# README must not still be telling a reader that it is on demand only. The
# sentence that said so outlived the change once already.
chk "no stale on-demand-only claim" \
  "$(grep -c 'Completion is on demand' "$README")" "0"
chk "the reversal is explained" \
  "$(grep -c 'Completion is automatic now' "$README")" "1"

# What a reader needs to know about Copilot before it disappoints them: that it
# is the one entry that cannot simply land.
copilot_section=$(sed -n '/^#### Completion and predictive text/,/^#### /p' "$README")
for phrase in 'Node' 'subscription' 'Copilot auth'; do
  chk "copilot caveat names $phrase" \
    "$(printf '%s\n' "$copilot_section" | grep -qF "$phrase" && echo yes || echo no)" "yes"
done

# mini.bracketed's disabled targets are a deliberate list, and the reason each
# one is off is the part that gets lost. Four letters, four rows.
bracket_table=$(sed -n '/^| Letter | Left to |/,/^$/p' "$README")
chk "the disabled bracket letters are a table of four" \
  "$(printf '%s\n' "$bracket_table" | grep -cE '^\| `')" "4"

finish
