#!/bin/bash
# Usage: package-cli.sh APP OUT_DIR
# Packages the graphink command-line tool of APP (a built Graphink.app) as OUT_DIR/graphink-cli.zip
# with graphink-cli.zip.sha256. The zip holds one folder, graphink-cli/, in the app's own layout, so
# the same signed binary runs from it: Contents/Helpers/graphink, the frameworks it links
# (Contents/Frameworks, found through its @executable_path/../Frameworks rpath), the style fonts and
# the license notices (Contents/Resources). The Homebrew cask graphink-cli links
# graphink-cli/Contents/Helpers/graphink onto PATH. Every file is copied from APP unchanged, so the
# signatures are the app's; release.yml runs this on the checked Release app after
# package-release.sh. tools/cli/check-cli.py runs it on Debug products, never uploaded.
. "$(dirname "$0")/common.sh"
app=${1:?app}
out=${2:?output dir}
tool="$app/Contents/Helpers/graphink"
test -x "$tool" || { echo "::error::No command-line tool at $tool" >&2; exit 1; }
codesign --verify --strict "$tool"

mkdir -p "$out"
out=$(cd "$out" && pwd)
zip="$out/graphink-cli.zip"
test ! -e "$zip" || { echo "::error::$zip already exists" >&2; exit 1; }
work=$(mktemp -d /private/tmp/graphink-cli-zip.XXXXXX)
# The staged copy holds every framework; never leave it behind, also when a step fails.
trap 'rm -rf "$work"' EXIT
contents="$work/graphink-cli/Contents"
mkdir -p "$contents/Helpers" "$contents/Frameworks" "$contents/Resources/English.lproj"
ditto "$tool" "$contents/Helpers/graphink"

# The frameworks the tool loads: its @rpath dependencies and theirs, from the app.
pending=("$tool") copied=" "
while [[ ${#pending[@]} -gt 0 ]]; do
  binary=${pending[0]}
  pending=("${pending[@]:1}")
  for name in $(otool -L "$binary" | sed -nE 's|^[[:space:]]*@rpath/([^/]+)\.framework/.*|\1|p'); do
    [[ "$copied" == *" $name "* ]] && continue
    framework="$app/Contents/Frameworks/$name.framework"
    test -d "$framework" || { echo "::error::graphink needs $name.framework, which $app does not embed" >&2; exit 1; }
    ditto "$framework" "$contents/Frameworks/$name.framework"
    copied="$copied$name "
    pending+=("$framework/$name")
  done
done
ditto "$app/Contents/Resources/StyleFonts" "$contents/Resources/StyleFonts"
ditto "$app/Contents/Resources/OmniSourceLicense.html" "$contents/Resources/OmniSourceLicense.html"
ditto "$app/Contents/Resources/English.lproj/ThirdPartyNotices.html" "$contents/Resources/English.lproj/ThirdPartyNotices.html"

# The same commit-time stamps as the DMG; then a smoke run from the staged copy.
stamp=$(TZ=UTC0 git log -1 --format=%cd --date=format-local:%Y%m%d%H%M.%S HEAD)
find "$work/graphink-cli" -exec touch -h -t "$stamp" {} +
codesign --verify --strict "$contents/Helpers/graphink"
for framework in "$contents"/Frameworks/*.framework; do codesign --verify --strict "$framework"; done
"$contents/Helpers/graphink" --version

(cd "$work" && ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent graphink-cli "$zip")
(cd "$out" && shasum -a 256 graphink-cli.zip > graphink-cli.zip.sha256)
echo "Packaged $zip with$copied"
cat "$out/graphink-cli.zip.sha256"
