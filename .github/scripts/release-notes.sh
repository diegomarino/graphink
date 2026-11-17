#!/bin/bash
# Usage: release-notes.sh VERSION BUILD_INFO OUT — writes the GitHub Release body.
# The "What's new" part is the same notes the app bundles: release-notes/<VERSION>.md when it
# exists, otherwise git-cliff's feat/fix/perf entries for the tag (scripts/release/notes.py).
. "$(dirname "$0")/common.sh"
version=${1:?version}
build_info=${2:?BUILD-INFO.txt}
out=${3:?output file}
whats_new=$(python3 scripts/release/notes.py version-notes --version "$version")

{
  echo "Graphink $version for Mac (Apple silicon, macOS 12 or later)."
  echo
  echo "## What's new"
  echo
  echo "$whats_new"
  echo
  echo "**Download:** \`$APP_NAME.dmg\` below. Open it and drag $APP_NAME to Applications."
  echo "Check the download with \`shasum -a 256 -c $APP_NAME.dmg.sha256\` in the folder holding both files."
  echo
  if [[ "$SIGNING_MODE" == developer-id ]]; then
    echo "This build is signed with a Developer ID and notarized by Apple."
  else
    cat <<EOF
### This build is not notarized

$APP_NAME is not yet signed with an Apple Developer ID, so macOS blocks the
first launch with a message that it "cannot verify" the app. To open it:

1. Drag $APP_NAME from the disk image to **Applications** and open it once;
   choose **Done** (not Move to Trash) when macOS blocks it.
2. Open **System Settings > Privacy & Security**.
3. Scroll to **Security**, where "$APP_NAME was blocked to protect your Mac"
   is shown, and click **Open Anyway**.
4. Confirm with **Open Anyway** again and your password. Later launches open
   normally.
EOF
  fi
  echo
  echo "The app version ($version) is independent of the .graphink document format"
  echo "(OPC profile opc-v1, document version 1)."
  echo
  echo '```'
  cat "$build_info"
  echo '```'
} > "$out"
