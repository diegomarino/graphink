#!/bin/bash
# Graphink calendar version helper (YYYY.M.n). The version comes from git tags, never from a
# committed file; scripts/release/version.py holds the rules.
#   version.sh show            the version a build of HEAD gets (latest vYYYY.M.n tag reachable
#                              from HEAD, or YYYY.M.0 for this month in Europe/Madrid)
#   version.sh check           that value is a valid YYYY.M.n, and the xcconfig only has the fallback
#   version.sh check-tag TAG   TAG is a release tag vYYYY.M.n; prints its version
# Runs on Linux and macOS; needs bash, git and python3.
. "$(dirname "$0")/common.sh"

valid_version() {
  [[ "$1" =~ ^(20[0-9]{2})\.([1-9]|1[0-2])\.(0|[1-9][0-9]*)$ ]]
}

case "${1:-}" in
  show) python3 scripts/release/version.py current ;;
  check)
    version=$(python3 scripts/release/version.py current)
    valid_version "$version" || { echo "::error::Computed version '$version' is not calendar YYYY.M.n" >&2; exit 1; }
    [[ $(grep -cE '^MARKETING_VERSION[[:space:]]*=[[:space:]]*0\.0\.0[[:space:]]*$' "$VERSION_XCCONFIG") == 1 &&
       $(grep -cE '^MARKETING_VERSION[[:space:]]*=' "$VERSION_XCCONFIG") == 1 ]] || {
      echo "::error::$VERSION_XCCONFIG must keep only the MARKETING_VERSION = 0.0.0 fallback; versions come from tags" >&2; exit 1; }
    echo "Build version $version (from tags); xcconfig holds only the fallback" ;;
  check-tag)
    python3 scripts/release/version.py from-tag "${2:?tag}" || {
      echo "::error::'$2' is not a release tag vYYYY.M.n (no zero padding)" >&2; exit 1; } ;;
  *) echo "usage: version.sh show|check|check-tag TAG" >&2; exit 2 ;;
esac
