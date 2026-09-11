#!/usr/bin/env bash
# Assertions read variables that the sourced script owns, and override its
# functions with fixtures. ShellCheck cannot see through either.
# shellcheck disable=SC1091,SC2034,SC2317
# bin/vlc-default: the content-type table, the LaunchServices parser, and the
# rule that a write counts only when the preference file agrees.
#
# duti, PlistBuddy and LaunchServices exist only on macOS, so what is testable
# here is the data and the parser — fed a recorded PlistBuddy dump rather than
# a real one.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
VLC_DEFAULT_LIB=1 . "$REPO_ROOT/bin/vlc-default"

# --- the table -------------------------------------------------------------
chk "video type count" "$(printf '%s\n' "$VIDEO_TYPES" | grep -c '|')" "24"

# every record must have exactly 4 fields
bad=0
while IFS= read -r l; do
  [ -n "$l" ] || continue
  n=$(printf '%s' "$l" | tr -cd '|' | wc -c)
  [ "$n" -eq 3 ] || bad=$((bad + 1))
done <<X
$VIDEO_TYPES
X
chk "all records 4-field" "$bad" "0"

# Only ever the macOS build's bundle identifier. A record naming anything else
# is the bug this script exists to avoid: a Parallels-published Windows VLC
# owning .mp4 boots a virtual machine on a double click.
chk "every handler is the Mac VLC" \
  "$(printf '%s\n' "$VIDEO_TYPES" | awk -F'|' '$3 != "org.videolan.vlc"' | wc -l | tr -d ' ')" "0"
chk "no parallels handler" "$(printf '%s\n' "$VIDEO_TYPES" | grep -c 'parallels')" "0"
chk "every role is all" \
  "$(printf '%s\n' "$VIDEO_TYPES" | awk -F'|' '$2 != "all"' | wc -l | tr -d ' ')" "0"

# No duplicate content type: duti would write the later one over the earlier,
# and the report would show the same row twice.
chk "no duplicate content types" \
  "$(printf '%s\n' "$VIDEO_TYPES" | cut -d'|' -f1 | sort | uniq -d | wc -l | tr -d ' ')" "0"

# The types the request was actually about, plus the two generic ones that
# catch a container none of the specific rows name.
for uti in public.mpeg-4 org.matroska.mkv public.avi com.apple.quicktime-movie \
           com.microsoft.windows-media-wmv org.webmproject.webm \
           public.mpeg-2-transport-stream public.movie public.video; do
  chk "table covers $uti" \
    "$(printf '%s\n' "$VIDEO_TYPES" | awk -F'|' -v u="$uti" '$1 == u' | wc -l | tr -d ' ')" "1"
done

# Audio and images are VLC's business too, and deliberately not ours: taking
# .mp3 or .jpg away from Music and Preview was never asked for.
for uti in public.mp3 public.jpeg org.xiph.flac public.m3u-playlist \
           com.apple.m4a-audio public.png; do
  chk "table leaves $uti alone" \
    "$(printf '%s\n' "$VIDEO_TYPES" | awk -F'|' -v u="$uti" '$1 == u' | wc -l | tr -d ' ')" "0"
done

# Every extension named in --help has to appear in some record's label,
# otherwise the help promises a type the table does not set. The brackets
# become spaces so that a whole-word match works wherever in the label the
# extension sits: matching "$ext)" only ever finds the last one of a group, and
# an unanchored match makes .ts indistinguishable from .m2ts.
labels=$(printf '%s\n' "$VIDEO_TYPES" | cut -d'|' -f4 | tr '()' '  ')
for ext in .mp4 .m4v .mkv .avi .mov .qt .wmv .flv .f4v .webm .mpg .mpeg .m2v \
           .ts .m2ts .mts .vob .3gp .3g2 .asf .rm .rmvb .divx .ogv .ogm .mxf .dv; do
  chk "label mentions $ext" "$(printf '%s\n' "$labels" | grep -cF " $ext ")" "1"
done

# --- the parser ------------------------------------------------------------
# A recorded PlistBuddy dump. The nested LSHandlerPreferredVersions dictionary
# is the whole reason this is parsed by brace depth: it carries an
# LSHandlerRoleAll key of its own, always "-", and reading fields at any depth
# would hand back "-" as the handler for every type.
DUMP='Array {
    Dict {
        LSHandlerContentType = public.mpeg-4
        LSHandlerPreferredVersions = Dict {
            LSHandlerRoleAll = -
        }
        LSHandlerRoleAll = org.videolan.vlc
    }
    Dict {
        LSHandlerContentType = public.avi
        LSHandlerRoleAll = com.apple.QuickTimePlayerX
    }
    Dict {
        LSHandlerContentTag = txt
        LSHandlerContentTagClass = public.filename-extension
        LSHandlerRoleAll = com.apple.TextEdit
    }
    Dict {
        LSHandlerContentType = public.html
        LSHandlerRoleViewer = com.apple.Safari
    }
    Dict {
        LSHandlerContentType = org.matroska.mkv
        LSHandlerPreferredVersions = Dict {
            LSHandlerRoleAll = -
        }
        LSHandlerRoleAll = org.videolan.vlc
    }
}'

parsed=$(printf '%s\n' "$DUMP" | parse_handler_dump)
chk "parser finds every role-all type" "$(printf '%s\n' "$parsed" | grep -c '|')" "3"
chk "parser reads the outer handler, not the nested dash" \
  "$(printf '%s\n' "$parsed" | awk -F'|' '$1 == "public.mpeg-4" { print $2 }')" "org.videolan.vlc"
chk "parser never yields a dash handler" "$(printf '%s\n' "$parsed" | grep -c '|-$')" "0"
chk "parser keeps a foreign handler as it is" \
  "$(printf '%s\n' "$parsed" | awk -F'|' '$1 == "public.avi" { print $2 }')" "com.apple.QuickTimePlayerX"
# An extension-tag record has no content type, and a viewer-only record has no
# LSHandlerRoleAll. Neither is a default-for-everything binding, so neither is
# something this script may report on or overwrite.
chk "parser skips an extension-tag record" "$(printf '%s\n' "$parsed" | grep -c 'txt')" "0"
chk "parser skips a viewer-only record" "$(printf '%s\n' "$parsed" | grep -c 'public.html')" "0"
chk "parser handles an empty dump" "$(printf '' | parse_handler_dump | wc -c | tr -d ' ')" "0"

# --- handler_for and pending_count -----------------------------------------
HANDLERS="$parsed"
chk "handler_for known type" "$(handler_for public.mpeg-4)" "org.videolan.vlc"
chk "handler_for foreign type" "$(handler_for public.avi)" "com.apple.QuickTimePlayerX"
chk "handler_for unrecorded type" "$(handler_for public.mpeg)" ""
# Partial state: two of the twenty-four types point at VLC, so twenty-two are
# still pending. A run that reported 0 here would tell the user there was
# nothing to do on a machine where QuickTime still owns .avi.
chk "pending_count counts what is left" "$(pending_count)" "22"

HANDLERS=""
chk "pending_count on a bare machine" "$(pending_count)" "24"

HANDLERS=$(printf '%s\n' "$VIDEO_TYPES" | awk -F'|' '{ print $1 "|" $3 }')
chk "pending_count when everything is set" "$(pending_count)" "0"

# --- show_value ------------------------------------------------------------
chk "show_value marks a match" \
  "$(show_value org.videolan.vlc org.videolan.vlc 'x' | grep -c '\[ok\]')" "1"
chk "show_value marks a difference" \
  "$(show_value com.apple.QuickTimePlayerX org.videolan.vlc 'x' | grep -c '\[->\]')" "1"
chk "show_value names an unset type" \
  "$(show_value '' org.videolan.vlc 'x' | grep -c '(system default)')" "1"

# --- argument handling -----------------------------------------------------
chk "bad option exits 64" \
  "$(bash "$REPO_ROOT/bin/vlc-default" --nonsense >/dev/null 2>&1; printf '%s' "$?")" "64"
chk "--help exits 0" \
  "$(bash "$REPO_ROOT/bin/vlc-default" --help >/dev/null 2>&1; printf '%s' "$?")" "0"
chk "--help names --apply" \
  "$(bash "$REPO_ROOT/bin/vlc-default" --help 2>/dev/null | grep -q -- '--apply'; yn test $? -eq 0)" "y"
chk "--version prints the version" \
  "$(bash "$REPO_ROOT/bin/vlc-default" --version 2>/dev/null)" "vlc-default $VLC_DEFAULT_VERSION"

# Report is the default: no argument may write anything. Asserted on the
# argument parser rather than by running it, since a run needs macOS.
chk "no argument means report" \
  "$(awk '/local action="report"/ { print "y"; exit }' "$REPO_ROOT/bin/vlc-default")" "y"

finish
