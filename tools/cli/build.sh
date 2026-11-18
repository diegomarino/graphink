#!/bin/bash
# Build graphink-render and graphink-create against the frameworks of a docs/BUILDING.md build.
usage() {
    cat <<'HELP'
Usage: tools/cli/build.sh PRODUCTS OUTPUT

PRODUCTS  <build root>/<Config>/Products/<Config> from .github/scripts/build.sh
OUTPUT    a new directory (an existing path is refused)

Writes:
  OUTPUT/bin/graphink-render, OUTPUT/bin/graphink-create   the commands (put OUTPUT/bin on PATH)
  OUTPUT/GraphinkCLI.bundle                                the tool bundle they run
  OUTPUT/build.log                                         the compiler output

The bundle's Info.plist is the app's, so the tools register the same preference defaults as
Graphink.app, under their own identifier (com.diegomarino.Graphink.cli): they never read or write
the app's preferences. It declares no document types, so it can never claim .graphink files.
Frameworks/ is a symbolic link to PRODUCTS: keep that build while you use the tools.
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

mkdir -p "$output/bin"
output=$(cd "$output" && pwd)
bundle="$output/GraphinkCLI.bundle/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources"
ln -s "$products" "$bundle/Frameworks"
cp -R GraphSketcher/App/Resources/StyleFonts "$bundle/Resources/StyleFonts"

plist="$bundle/Info.plist"
cp GraphSketcher/App/Info.plist "$plist"
for setting in 'CFBundleIdentifier com.diegomarino.Graphink.cli' 'CFBundleName graphink-cli' \
    'CFBundleExecutable graphink-render' 'CFBundlePackageType BNDL' 'CFBundleVersion 1' \
    "CFBundleShortVersionString $(python3 scripts/release/version.py current)" \
    'NSPrincipalClass NSApplication' 'OFControllerClass GICController' 'LSMinimumSystemVersion 12.0' \
    'NSHumanReadableCopyright Copyright 2026 Graphink contributors'; do
    /usr/libexec/PlistBuddy -c "Set :${setting%% *} ${setting#* }" "$plist"
done
# Never declare document types, UTIs or services (Checks/check-fixture-bundles.py lists these keys).
for key in NSMainNibFile CFBundleDocumentTypes UTExportedTypeDeclarations UTImportedTypeDeclarations \
    CFBundleURLTypes NSServices CFBundleGetInfoString CFBundleHelpBookFolder CFBundleHelpBookName CFBundleIconFile \
    LinkBackApplicationURL LinkBackServer OAAboutPanelControllerClass; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" 2>/dev/null || true
done

# shellcheck disable=SC2054 # -Wl,-rpath,DIR is one linker argument
compile=(xcrun clang -arch arm64 -mmacosx-version-min=12.0 -fno-objc-arc -fblocks -Wall -Werror
    -Wno-deprecated-declarations -DOMNI_BUILDING_FOR_MAC=1
    -include GraphSketcher/App/GraphSketcher_Prefix.h -I GraphSketcher/App -I "$cli_dir" -F "$products"
    -framework Cocoa -framework QuartzCore -framework CoreText -framework ImageIO
    -framework GraphSketcherModel -framework OmniBase -framework OmniFoundation -framework OmniAppKit
    -framework OmniQuartz -framework OmniUnzip
    -Wl,-rpath,@executable_path/../Frameworks)
shared=("$cli_dir/GraphinkCLI.m" GraphSketcher/App/RSStylePresets.m)
for tool in graphink-render graphink-create; do
    echo "+ ${compile[*]} ${shared[*]} $cli_dir/$tool.m -o $bundle/MacOS/$tool" >> "$output/build.log"
    if ! "${compile[@]}" "${shared[@]}" "$cli_dir/$tool.m" -o "$bundle/MacOS/$tool" >> "$output/build.log" 2>&1; then
        tail -n 30 "$output/build.log" >&2
        echo "Compile failed; see $output/build.log" >&2
        exit 1
    fi
    # The tool must run from inside the bundle so NSBundle.mainBundle finds Info.plist and the fonts.
    printf '#!/bin/sh\nexec "%s/MacOS/%s" "$@"\n' "$bundle" "$tool" > "$output/bin/$tool"
    chmod 755 "$output/bin/$tool"
done
echo "Built $output/bin/graphink-render and $output/bin/graphink-create"
