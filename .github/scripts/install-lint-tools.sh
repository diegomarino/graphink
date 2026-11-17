#!/bin/bash
# Usage: install-lint-tools.sh DIR — install the pinned, checksum-verified ruff, shellcheck and
# actionlint release binaries (RUFF_VERSION, SHELLCHECK_VERSION, ACTIONLINT_VERSION in
# .github/ci.env) into DIR. In GitHub Actions it also adds DIR to PATH and exports RUFF,
# SHELLCHECK and ACTIONLINT, which checks-fast.sh uses.
. "$(dirname "$0")/common.sh"
dir=${1:?install dir}

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    ruff_target=x86_64-unknown-linux-gnu; ruff_sha=$RUFF_SHA256_LINUX_X86_64
    shellcheck_target=linux.x86_64; shellcheck_sha=$SHELLCHECK_SHA256_LINUX_X86_64
    actionlint_target=linux_amd64; actionlint_sha=$ACTIONLINT_SHA256_LINUX_X86_64 ;;
  Darwin-arm64)
    ruff_target=aarch64-apple-darwin; ruff_sha=$RUFF_SHA256_MACOS_ARM64
    shellcheck_target=darwin.aarch64; shellcheck_sha=$SHELLCHECK_SHA256_MACOS_ARM64
    actionlint_target=darwin_arm64; actionlint_sha=$ACTIONLINT_SHA256_MACOS_ARM64 ;;
  *) echo "::error::No pinned ruff/shellcheck/actionlint for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
work=$(mktemp -d)
# fetch URL SHA256: download into $work and verify the checksum.
fetch() {
  local archive=${1##*/}
  curl -fsSLo "$work/$archive" "$1"
  echo "$2  $work/$archive" | shasum -a 256 -c -
  tar -xf "$work/$archive" -C "$work"
}
fetch "https://github.com/astral-sh/ruff/releases/download/$RUFF_VERSION/ruff-$ruff_target.tar.gz" "$ruff_sha"
fetch "https://github.com/koalaman/shellcheck/releases/download/v$SHELLCHECK_VERSION/shellcheck-v$SHELLCHECK_VERSION.$shellcheck_target.tar.xz" "$shellcheck_sha"
fetch "https://github.com/rhysd/actionlint/releases/download/v$ACTIONLINT_VERSION/actionlint_${ACTIONLINT_VERSION}_$actionlint_target.tar.gz" "$actionlint_sha"
mkdir -p "$dir"
install -m 0755 "$work/ruff-$ruff_target/ruff" "$dir/ruff"
install -m 0755 "$work/shellcheck-v$SHELLCHECK_VERSION/shellcheck" "$dir/shellcheck"
install -m 0755 "$work/actionlint" "$dir/actionlint"
"$dir/ruff" --version
"$dir/shellcheck" --version
"$dir/actionlint" -version
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$dir" >> "$GITHUB_PATH"
  { echo "RUFF=$dir/ruff"; echo "SHELLCHECK=$dir/shellcheck"; echo "ACTIONLINT=$dir/actionlint"; } >> "$GITHUB_ENV"
fi
