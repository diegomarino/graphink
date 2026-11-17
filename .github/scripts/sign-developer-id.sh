#!/bin/bash
# Developer ID signing and notarization, used only when SIGNING_MODE=developer-id
# in .github/ci.env. NOT YET EXERCISED: no certificate or API key exists for this
# project. Written to the documented Apple flow so switching is a settings
# change plus secrets; run it once on a test tag before relying on it.
#
#   sign-developer-id.sh sign APP        re-sign frameworks and app (Hardened Runtime)
#   sign-developer-id.sh notarize DMG    sign the DMG, notarize, staple, assess
#
# Required environment (repository or `release` environment secrets):
#   DEVELOPER_ID_P12_BASE64     base64 of the Developer ID Application .p12
#   DEVELOPER_ID_P12_PASSWORD   its password
#   NOTARY_KEY_P8_BASE64        base64 of the App Store Connect API key (.p8)
#   NOTARY_KEY_ID, NOTARY_ISSUER_ID
. "$(dirname "$0")/common.sh"

: "${RUNNER_TEMP:=$(mktemp -d)}"
keychain="$RUNNER_TEMP/graphink-signing.keychain-db"

setup_keychain() {
  [[ -f "$keychain" ]] && return 0
  : "${DEVELOPER_ID_P12_BASE64:?}" "${DEVELOPER_ID_P12_PASSWORD:?}"
  local password p12="$RUNNER_TEMP/developer-id.p12"
  password=$(uuidgen)
  security create-keychain -p "$password" "$keychain"
  security set-keychain-settings -lut 3600 "$keychain"
  security unlock-keychain -p "$password" "$keychain"
  base64 --decode <<<"$DEVELOPER_ID_P12_BASE64" > "$p12"
  security import "$p12" -k "$keychain" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
  rm -f "$p12"
  security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" > /dev/null
  # Word splitting is intended: keep the existing search list after ours.
  # shellcheck disable=SC2046
  security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
}

identity() {
  local ids
  # Read every match, then keep the first: `| head -n 1` can close the pipe early, and under
  # pipefail sed's SIGPIPE (exit 141) fails the signing step (same race as common.sh select_xcode).
  ids=$(security find-identity -v -p codesigning "$keychain" |
    sed -nE 's/^ *[0-9]+\) ([0-9A-F]{40}) "Developer ID Application: .*"$/\1/p')
  printf '%s\n' "${ids%%$'\n'*}"
}

sign_app() {
  local app=$1 id entitlements
  setup_keychain
  id=$(identity)
  [[ -n "$id" ]] || { echo "::error::No Developer ID Application identity in the imported .p12" >&2; exit 1; }
  # Keep the app's own Release entitlements, minus anything development-only.
  entitlements="$RUNNER_TEMP/release.entitlements"
  codesign -d --entitlements - --xml "$app" > "$entitlements"
  for key in com.apple.security.get-task-allow com.apple.security.cs.disable-library-validation; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$entitlements" 2>/dev/null || true
  done
  # Inside out: nested code first, the app last.
  find "$app/Contents" -depth \( -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' \
    -o -name '*.xpc' -o -name '*.mdimporter' -o -name '*.qlgenerator' -o -name '*.app' \) -print0 |
    while IFS= read -r -d '' nested; do
      codesign --force --timestamp --options runtime --sign "$id" "$nested"
    done
  codesign --force --timestamp --options runtime --entitlements "$entitlements" --sign "$id" "$app"
  codesign --verify --deep --strict "$app"
}

notarize_dmg() {
  local dmg=$1 id key="$RUNNER_TEMP/notary-key.p8"
  : "${NOTARY_KEY_P8_BASE64:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER_ID:?}"
  setup_keychain
  id=$(identity)
  codesign --force --timestamp --sign "$id" "$dmg"
  base64 --decode <<<"$NOTARY_KEY_P8_BASE64" > "$key"
  xcrun notarytool submit "$dmg" --key "$key" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" --wait --timeout 30m
  rm -f "$key"
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  spctl --assess --type open --context context:primary-signature -vv "$dmg"
}

case "${1:-}" in
  sign) sign_app "${2:?app}" ;;
  notarize) notarize_dmg "${2:?dmg}" ;;
  *) echo "usage: sign-developer-id.sh sign APP | notarize DMG" >&2; exit 2 ;;
esac
