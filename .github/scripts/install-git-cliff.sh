#!/bin/bash
# Usage: install-git-cliff.sh DIR — install the pinned, checksum-verified git-cliff release
# binary (GIT_CLIFF_VERSION in .github/ci.env) into DIR. In GitHub Actions it also adds DIR to
# PATH and exports GIT_CLIFF, which scripts/release/notes.py and the app's build phase use.
. "$(dirname "$0")/common.sh"
dir=${1:?install dir}

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) target=x86_64-unknown-linux-gnu; sha=$GIT_CLIFF_SHA256_LINUX_X86_64 ;;
  Darwin-arm64) target=aarch64-apple-darwin; sha=$GIT_CLIFF_SHA256_MACOS_ARM64 ;;
  *) echo "::error::No pinned git-cliff for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
archive="git-cliff-$GIT_CLIFF_VERSION-$target.tar.gz"
work=$(mktemp -d)
curl -fsSLo "$work/$archive" "https://github.com/orhun/git-cliff/releases/download/v$GIT_CLIFF_VERSION/$archive"
echo "$sha  $work/$archive" | shasum -a 256 -c -
tar -xzf "$work/$archive" -C "$work"
mkdir -p "$dir"
install -m 0755 "$work/git-cliff-$GIT_CLIFF_VERSION/git-cliff" "$dir/git-cliff"
"$dir/git-cliff" --version
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$dir" >> "$GITHUB_PATH"
  echo "GIT_CLIFF=$dir/git-cliff" >> "$GITHUB_ENV"
fi
