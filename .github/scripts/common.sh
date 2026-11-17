# shellcheck shell=bash
# Sourced by the other CI scripts; Bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

ci_repo_root=$(git rev-parse --show-toplevel)
cd "$ci_repo_root"
# shellcheck source=../ci.env
. "$ci_repo_root/.github/ci.env"

# Select the recorded Xcode without changing the machine's global xcode-select.
# Hosted xcode-27 images install it at $XCODE_APP; a self-hosted Mac may have it
# at the default path. Either way the version must match exactly.
select_xcode() {
  if [[ -z "${DEVELOPER_DIR:-}" && -d "$XCODE_APP" ]]; then
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
  fi
  local version
  # Read all output, then keep the first line: `| head -n 1` can close the pipe early, and under
  # pipefail xcodebuild's SIGPIPE (exit 141) fails the build.
  version=$(xcodebuild -version)
  version=${version%%$'\n'*}
  if [[ "$version" != "Xcode $XCODE_VERSION" ]]; then
    echo "::error::Expected Xcode $XCODE_VERSION, found '$version' (DEVELOPER_DIR=${DEVELOPER_DIR:-unset})" >&2
    exit 1
  fi
  echo "Using $version at $(xcode-select -p 2>/dev/null || true) DEVELOPER_DIR=${DEVELOPER_DIR:-unset}"
  xcrun --sdk macosx --show-sdk-version
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}" >> "$GITHUB_ENV"
  fi
}

# Run one named check, keep its log, and fail loudly with the log tail.
run_check() {
  local name=$1 log_dir=$2
  shift 2
  mkdir -p "$log_dir"
  echo "::group::$name"
  local status=0
  "$@" > "$log_dir/$name.log" 2>&1 || status=$?
  tail -n 40 "$log_dir/$name.log"
  echo "::endgroup::"
  if [[ $status != 0 ]]; then
    echo "::error::$name failed with exit $status (log: $log_dir/$name.log)" >&2
    return "$status"
  fi
}
