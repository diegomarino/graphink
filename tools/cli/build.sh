#!/bin/bash
# Development build of graphink against the frameworks of a docs/BUILDING.md Debug build, without
# rebuilding the app. Releases and the checks use the Xcode target (Graphink.app/Contents/Helpers).
usage() {
    cat <<'HELP'
Usage: tools/cli/build.sh PRODUCTS OUTPUT

PRODUCTS  <build root>/Debug/Products/Debug from .github/scripts/build.sh
OUTPUT    a new directory (an existing path is refused)

Compiles the graphink target's sources (GraphSketcher/App/CLI plus the app files it shares) with
clang into the layout the app and graphink-cli.zip use:
  OUTPUT/graphink-cli/Contents/Helpers/graphink   the tool, Info.plist embedded (put OUTPUT/bin on PATH)
  OUTPUT/graphink-cli/Contents/Frameworks         a symbolic link to PRODUCTS: keep that build
  OUTPUT/graphink-cli/Contents/Resources          the style fonts
  OUTPUT/bin/graphink                             a symbolic link to the tool
  OUTPUT/build.log                                the compiler output
Exit 0: built; 1: compile or setup failure; 2: invalid arguments.
HELP
}
set -euo pipefail
cli_dir=$(cd "$(dirname "$0")" && pwd)
. "$cli_dir/../../.github/scripts/common.sh"

if [[ $# -ne 2 || $1 == -h || $1 == --help ]]; then usage; [[ $# -eq 1 && ($1 == -h || $1 == --help) ]] && exit 0; exit 2; fi
products=$(cd "$1" 2>/dev/null && pwd) || { echo "No such directory: $1" >&2; exit 2; }
output=$2
[[ -d "$products/GraphSketcherModel.framework" ]] || { echo "No GraphSketcherModel.framework in $products" >&2; exit 2; }
[[ -e "$output" ]] && { echo "$output already exists; choose a new directory" >&2; exit 2; }
select_xcode > /dev/null

app=GraphSketcher/App
mkdir -p "$output/bin"
output=$(cd "$output" && pwd)
contents="$output/graphink-cli/Contents"
mkdir -p "$contents/Helpers" "$contents/Resources"
ln -s "$products" "$contents/Frameworks"
cp -R "$app/Resources/StyleFonts" "$contents/Resources/StyleFonts"

# The target's Info.plist, with the settings Xcode would expand.
plist="$output/Info.plist"
python3 "$app/CLI/make-info-plist.py" "$app/Info.plist" "$plist.in"
python3 - "$plist.in" "$plist" "$(python3 scripts/release/version.py current)" <<'PY'
import sys
text = open(sys.argv[1]).read()
for name, value in (("PRODUCT_BUNDLE_IDENTIFIER", "com.diegomarino.Graphink.cli"), ("EXECUTABLE_NAME", "graphink"),
                    ("MARKETING_VERSION", sys.argv[3]), ("CURRENT_PROJECT_VERSION", "1"), ("MACOSX_DEPLOYMENT_TARGET", "12.0")):
    text = text.replace("$(" + name + ")", value)
open(sys.argv[2], "w").write(text)
PY

# shellcheck disable=SC2054 # -Wl,-rpath,DIR and -Wl,-sectcreate,... are single linker arguments
compile=(xcrun clang -arch arm64 -mmacosx-version-min=12.0 -fno-objc-arc -fblocks -Wall -Werror
    -Wno-deprecated-declarations -DOMNI_BUILDING_FOR_MAC=1
    -include "$app/GraphSketcher_Prefix.h" -I "$app" -F "$products"
    -framework Cocoa -framework QuartzCore -framework CoreText -framework ImageIO
    -framework GraphSketcherModel -framework OmniBase -framework OmniFoundation -framework OmniAppKit
    -framework OmniQuartz -framework OmniUnzip
    -Wl,-rpath,@executable_path/../Frameworks -Wl,-sectcreate,__TEXT,__info_plist,"$plist")
sources=("$app"/CLI/*.m "$app/RSGraphExport.m" "$app/RSStylePresets.m" "$app/RSPageGeometry.m")
echo "+ ${compile[*]} ${sources[*]} -o $contents/Helpers/graphink" > "$output/build.log"
if ! "${compile[@]}" "${sources[@]}" -o "$contents/Helpers/graphink" >> "$output/build.log" 2>&1; then
    tail -n 30 "$output/build.log" >&2
    echo "Compile failed; see $output/build.log" >&2
    exit 1
fi
codesign --force --sign - --identifier com.diegomarino.Graphink.cli "$contents/Helpers/graphink" >> "$output/build.log" 2>&1
ln -s "$contents/Helpers/graphink" "$output/bin/graphink"
echo "Built $output/bin/graphink"
