#!/bin/bash
# Usage: .github/scripts/build.sh Debug|Release BUILD_ROOT
# The docs/BUILDING.md command for one configuration, into its own
# BUILD_ROOT/<configuration> tree (DerivedData is never shared between
# configurations). The full log is kept at BUILD_ROOT/<configuration>/build.log.
# EXTRA_BUILD_SETTINGS (comma-separated KEY=value, no spaces) is appended for the release
# packaging build only; PR builds use the README command unchanged.
# BUILD_NUMBER, when set, becomes CURRENT_PROJECT_VERSION (CFBundleVersion).
# MARKETING_VERSION (CFBundleShortVersionString) is always injected: the caller's value (release
# builds pass the tag's version), else `scripts/release/version.py current` (latest vYYYY.M.n tag
# reachable from HEAD, or this month's .0 without tags). It is never read from a committed file.
. "$(dirname "$0")/common.sh"

configuration=${1:?configuration}
build_root=${2:?build root}
case "$configuration" in Debug|Release) ;; *) echo "Unknown configuration $configuration" >&2; exit 2 ;; esac

select_xcode
configuration_root="$build_root/$configuration"
mkdir -p "$build_root"
mkdir "$configuration_root"
git rev-parse HEAD > "$build_root/source-sha.txt"

extra=()
if [[ -n "${EXTRA_BUILD_SETTINGS:-}" ]]; then
  IFS=, read -r -a extra <<<"$EXTRA_BUILD_SETTINGS"
  echo "Extra build settings: ${extra[*]}"
fi
marketing_version=${MARKETING_VERSION:-$(python3 scripts/release/version.py current)}
[[ "$marketing_version" =~ ^20[0-9]{2}\.([1-9]|1[0-2])\.(0|[1-9][0-9]*)$ ]] || {
  echo "::error::MARKETING_VERSION '$marketing_version' is not calendar YYYY.M.n" >&2; exit 2; }
extra+=("MARKETING_VERSION=$marketing_version")
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  [[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "::error::BUILD_NUMBER '$BUILD_NUMBER' is not a positive integer" >&2; exit 2; }
  extra+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi

status=0
xcodebuild -workspace GraphSketcher-Mac.xcworkspace -scheme ALL \
  -configuration "$configuration" \
  -derivedDataPath "$configuration_root/DerivedData" \
  -sdk macosx -destination 'platform=macOS,arch=arm64' \
  MACOSX_DEPLOYMENT_TARGET=12.0 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  SYMROOT="$configuration_root/Products" \
  OBJROOT="$configuration_root/Intermediates" ${extra[@]+"${extra[@]}"} build \
  > "$configuration_root/build.log" 2>&1 || status=$?

grep -E '(error|warning): ' "$configuration_root/build.log" | sort -u | tail -n 50 || true
tail -n 15 "$configuration_root/build.log"
if [[ $status != 0 ]]; then
  echo "::error::$configuration build failed with exit $status" >&2
  exit "$status"
fi

app="$configuration_root/Products/$configuration/$APP_NAME.app"
test -d "$app"
codesign --verify --deep --strict "$app"
codesign -dv "$app" 2>&1 | grep -E '^(Identifier|Format|CodeDirectory|Signature|TeamIdentifier)'
lipo -archs "$app/Contents/MacOS/$APP_NAME"
printf 'Version %s (build %s)\n' \
  "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" \
  "$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")"
echo "Built $app"
