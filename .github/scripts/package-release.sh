#!/bin/bash
# Usage: package-release.sh BUILD_ROOT OUT_DIR EXPECTED_VERSION
# Packages BUILD_ROOT/Release/Products/Release/<App>.app as OUT_DIR/Graphink.dmg
# (the app plus an /Applications symlink) with Graphink.dmg.sha256 and
# BUILD-INFO.txt. This is the release artifact contract download links rely
# on (/releases/latest/download/Graphink.dmg). Refuses Debug products,
# development entitlements, unlaunchable ad-hoc + Hardened Runtime signatures
# and version mismatches, then re-checks everything inside the mounted image.
. "$(dirname "$0")/common.sh"
build_root=${1:?build root}
out=${2:?output dir}
expected_version=${3:?expected marketing version}

app="$build_root/Release/Products/Release/$APP_NAME.app"
test -d "$app" || { echo "::error::No Release app at $app" >&2; exit 1; }
case "$app" in */Debug/*) echo "::error::Refusing a Debug product" >&2; exit 1 ;; esac

# Checks applied to the built app and again to the copy inside the DMG.
check_app() {
  local candidate=$1 entitlements signature version build
  codesign --verify --deep --strict "$candidate"
  # Debug signs with the development entitlements and Xcode injects
  # get-task-allow into ad-hoc signatures unless
  # CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO; neither may ship.
  entitlements=$(codesign -d --entitlements - --xml "$candidate" 2>/dev/null || true)
  for forbidden in com.apple.security.cs.disable-library-validation com.apple.security.get-task-allow; do
    if grep -q "$forbidden" <<<"$entitlements"; then
      echo "::error::$candidate carries the development-only entitlement $forbidden and must not be distributed" >&2
      return 1
    fi
  done
  grep -q com.apple.security.app-sandbox <<<"$entitlements" || {
    echo "::error::$candidate lost the app-sandbox entitlement" >&2; return 1; }
  # An ad-hoc app with Hardened Runtime enforces library validation; dyld then
  # rejects its ad-hoc embedded frameworks ("different Team IDs") at launch.
  signature=$(codesign -dv "$candidate" 2>&1)
  if grep -q '^Signature=adhoc' <<<"$signature" && grep -q 'flags=.*runtime' <<<"$signature"; then
    echo "::error::$candidate is ad-hoc signed with Hardened Runtime and cannot launch; build with RELEASE_DISTRIBUTION_SETTINGS" >&2
    return 1
  fi
  if [[ "$SIGNING_MODE" == developer-id ]] && grep -q '^Signature=adhoc' <<<"$signature"; then
    echo "::error::SIGNING_MODE=developer-id but $candidate is ad-hoc signed" >&2; return 1
  fi
  version=$(plutil -extract CFBundleShortVersionString raw "$candidate/Contents/Info.plist")
  build=$(plutil -extract CFBundleVersion raw "$candidate/Contents/Info.plist")
  [[ "$version" == "$expected_version" ]] || {
    echo "::error::CFBundleShortVersionString is '$version', expected '$expected_version'" >&2; return 1; }
  [[ "$build" =~ ^[1-9][0-9]*$ ]] || {
    echo "::error::CFBundleVersion '$build' is not a positive integer" >&2; return 1; }
  [[ "$(lipo -archs "$candidate/Contents/MacOS/$APP_NAME")" == arm64 ]]
  echo "OK $candidate: $version ($build), $(grep -E '^CodeDirectory' <<<"$signature")"
}
case "$SIGNING_MODE" in
  adhoc) ;;
  developer-id) "$(dirname "$0")/sign-developer-id.sh" sign "$app" ;;
  *) echo "::error::Unknown SIGNING_MODE '$SIGNING_MODE'" >&2; exit 1 ;;
esac
check_app "$app"

# Content manifest that does not follow symlinks: file hashes, link targets, dirs.
manifest() {
  (cd "$1" && {
    find . -type f -exec shasum -a 256 {} +
    find . -type l -exec stat -f 'link %N -> %Y' {} +
    find . -type d
  } | LC_ALL=C sort)
}

mkdir -p "$out"
dmg="$out/$APP_NAME.dmg"
test ! -e "$dmg" || { echo "::error::$dmg already exists" >&2; exit 1; }
work=$(mktemp -d /private/tmp/graphink-dmg.XXXXXX)
staging="$work/$APP_NAME"
mkdir "$staging"
ditto "$app" "$staging/$APP_NAME.app"
ln -s /Applications "$staging/Applications"

# Reproducible-ish: fixed layout, and every staged timestamp set to the source
# commit time (timestamps are not part of the code signature). hdiutil itself
# still embeds volume dates and UUIDs, so the DMG bytes are not reproducible;
# the app inside is byte-identical to the built product.
stamp=$(TZ=UTC0 git log -1 --format=%cd --date=format-local:%Y%m%d%H%M.%S HEAD)
find "$staging" -exec touch -h -t "$stamp" {} +
codesign --verify --deep --strict "$staging/$APP_NAME.app"

hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$staging" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 "$dmg"
hdiutil verify -quiet "$dmg"
if [[ "$SIGNING_MODE" == developer-id ]]; then
  "$(dirname "$0")/sign-developer-id.sh" notarize "$dmg"
fi

# Mount read-only, without Finder, and check what a user would drag out.
mountpoint="$work/mount"
mkdir "$mountpoint"
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$mountpoint" "$dmg"
status=0
{
  [[ "$(readlink "$mountpoint/Applications")" == /Applications ]] &&
  [[ "$(find "$mountpoint" -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l | tr -d ' ')" == 2 ]] &&
  check_app "$mountpoint/$APP_NAME.app" &&
  diff <(manifest "$app") <(manifest "$mountpoint/$APP_NAME.app")
} || status=$?
hdiutil detach -quiet "$mountpoint"
[[ $status == 0 ]] || { echo "::error::Mounted DMG check failed" >&2; exit "$status"; }

(cd "$out" && shasum -a 256 "$APP_NAME.dmg" > "$APP_NAME.dmg.sha256")
{
  echo "Version: $expected_version (build $(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist"))"
  echo "Source SHA: $(cat "$build_root/source-sha.txt")"
  echo "Configuration: Release, arm64, macOS 12.0 or later"
  if [[ "$SIGNING_MODE" == developer-id ]]; then
    echo "Signing: Developer ID, Hardened Runtime, notarized and stapled"
  else
    echo "Signing: ad-hoc (no Team ID), Hardened Runtime off, not notarized"
  fi
  xcodebuild -version | tr '\n' ' '; echo
  codesign -dv "$app" 2>&1 | grep -E '^(Identifier|CodeDirectory|Signature|TeamIdentifier)'
  echo "SHA-256: $(cut -d ' ' -f 1 "$out/$APP_NAME.dmg.sha256")  $APP_NAME.dmg"
} > "$out/BUILD-INFO.txt"
cat "$out/BUILD-INFO.txt"
