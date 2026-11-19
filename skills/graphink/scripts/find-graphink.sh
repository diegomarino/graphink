#!/bin/sh
# Print the path of a working `graphink` command-line tool, or say how to install it.
#
# Looks, in order, for `graphink` on PATH, then for the tool inside Graphink.app in /Applications
# and ~/Applications (GRAPHINK_APP_DIRS, colon-separated, replaces that list). A candidate counts
# only if `graphink --version` runs.
#
# Exit status:
#   0  found: its path is the only line on stdout
#   3  not installed: how to install it is on stderr
#   4  not a Mac: graphink needs macOS, on stderr
#   2  invalid arguments
# Usage: find-graphink.sh [--version]   (--version also prints the tool's version on stderr)

show_version=no
case "${1:-}" in
  "") ;;
  --version) show_version=yes ;;
  -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "find-graphink.sh: unexpected argument $1" >&2; exit 2 ;;
esac

if [ "$(uname -s)" != Darwin ]; then
  cat >&2 <<'EOF'
graphink needs a Mac: it draws with macOS's own graphics and text frameworks, so it runs only on
macOS 12 or later on Apple silicon. It cannot be installed on this system. Support for other
platforms is tracked at https://github.com/diegomarino/graphink/issues/8.
Tell the person the graph has to be made on a Mac; do not try to write .graphink files by hand.
EOF
  exit 4
fi

works() {
  [ -x "$1" ] && "$1" --version > /dev/null 2>&1
}

found=
if candidate=$(command -v graphink 2> /dev/null) && works "$candidate"; then
  found=$candidate
else
  dirs=${GRAPHINK_APP_DIRS-/Applications:$HOME/Applications}
  old_ifs=$IFS
  IFS=:
  for dir in $dirs; do
    if [ -n "$dir" ] && works "$dir/Graphink.app/Contents/Helpers/graphink"; then
      found="$dir/Graphink.app/Contents/Helpers/graphink"
      break
    fi
  done
  IFS=$old_ifs
fi

if [ -z "$found" ]; then
  cat >&2 <<'EOF'
graphink is not installed. Ask the person to install it in one of these ways (each needs their
approval; do not run sudo or an installer on your own), then run this script again:

  1. Homebrew, the tool only (no app needed):
       brew install --cask diegomarino/tap/graphink-cli
  2. The app: download Graphink.dmg from https://github.com/diegomarino/graphink/releases/latest
     and drag Graphink to Applications. This script then finds the tool inside it. To also put
     graphink on PATH, choose Graphink > Install Command-Line Tool... and run the command it shows.
  3. Or download graphink-cli.zip from the same page, unzip it and add
     graphink-cli/Contents/Helpers to PATH.

The first run of a build that is not notarized is blocked by macOS: allow it in
System Settings > Privacy & Security > Open Anyway.
EOF
  exit 3
fi

if [ "$show_version" = yes ]; then
  "$found" --version 2> /dev/null | sed -n '$p' >&2
fi
echo "$found"
