#!/bin/bash
# Product checks against this run's own Debug build. Usage:
#   checks-products.sh BUILD_ROOT LOG_DIR
# Default: the windowless set (no NSWindow is created). With GUI_CHECKS=1 the
# offscreen-window checks also run; they need a logged-in Aqua session, which
# GitHub-hosted macOS runners have but a runner installed as a LaunchDaemon or
# reached only over SSH does not.
. "$(dirname "$0")/common.sh"
build_root=${1:?build root}
logs=${2:?log dir}
select_xcode

sha=$(git rev-parse HEAD)
test "$(cat "$build_root/source-sha.txt")" = "$sha"
products="$build_root/Debug/Products/Debug"
test -d "$products/$APP_NAME.app"
evidence="$build_root/checks"
mkdir "$evidence"

run_check documents "$logs" Checks/check-documents.sh --products "$products" --build-sha "$sha"
run_check format "$logs" python3 docs/format/check-format.py --products "$products" --source-sha "$sha"
run_check model-production "$logs" python3 Checks/Analyzer/model/check-production.py --products "$products" --output "$evidence/model-production"
run_check width-defaults "$logs" python3 Checks/check-width-defaults.py --products "$products" --output "$evidence/width-defaults"
run_check about-links "$logs" python3 Checks/check-about-links.py --products "$products" --output "$evidence/about-links"
run_check style-defaults "$logs" python3 UI/check-style-defaults.py --products "$products" --output "$evidence/style-defaults"
run_check style-presets "$logs" python3 UI/StylePresets/check-presets.py --products "$products" --output "$evidence/style-presets"
run_check creation-defaults "$logs" python3 UI/StylePresets/check-creation-defaults.py --products "$products" --output "$evidence/creation-defaults"
run_check package-documents "$logs" python3 UI/StylePresets/check-package-documents.py --products "$products" --output "$evidence/package-documents"
run_check document-types "$logs" python3 Checks/check-document-types.py --products "$products" --output "$evidence/document-types"
run_check new-from "$logs" python3 Checks/check-new-from.py --products "$products" --output "$evidence/new-from"
run_check legacy-roundtrips "$logs" python3 Checks/check-legacy-roundtrips.py --products "$products" --output "$evidence/legacy-roundtrips"
run_check cli "$logs" python3 tools/cli/check-cli.py --products "$products" --output "$evidence/cli"

if [[ "${GUI_CHECKS:-0}" == 1 ]]; then
  run_check sidebar "$logs" python3 Checks/check-sidebar.py --products "$products" --output "$evidence/sidebar"
  run_check viewport "$logs" python3 Checks/check-viewport.py --products "$products" \
    --objects "$build_root/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/$APP_NAME.LinkFileList" \
    --output "$evidence/viewport"
  run_check page-size "$logs" python3 Checks/check-page-size.py --products "$products" \
    --objects "$build_root/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/$APP_NAME.LinkFileList" \
    --output "$evidence/page-size"
  run_check zoom-accessibility "$logs" python3 Checks/check-zoom-accessibility.py --products "$products" \
    --objects "$build_root/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/$APP_NAME.LinkFileList" \
    --output "$evidence/zoom-accessibility"
  run_check assertion-policy "$logs" python3 Checks/check-assertion-policy.py --products "$products" \
    --objects "$build_root/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/$APP_NAME.LinkFileList" \
    --output "$evidence/assertion-policy"
  run_check key-loop "$logs" python3 Checks/check-key-loop.py --products "$products" \
    --objects "$build_root/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/$APP_NAME.LinkFileList" \
    --output "$evidence/key-loop"
  run_check snap-distance "$logs" python3 Checks/check-snap-distance.py --products "$products" \
    --objects "$build_root/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/$APP_NAME.LinkFileList" \
    --output "$evidence/snap-distance"
  run_check native-qualification "$logs" python3 Checks/check-native-qualification.py --products "$products" \
    --objects "$build_root/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/$APP_NAME.LinkFileList" \
    --output "$evidence/native-qualification"
  run_check find "$logs" python3 Checks/check-find.py --products "$products" \
    --objects "$build_root/Debug/Intermediates/GraphSketcher.build/Debug/GraphSketcher.build/Objects-normal/arm64/$APP_NAME.LinkFileList" \
    --output "$evidence/find"
else
  echo "Window-creating checks (sidebar, viewport, page-size, zoom-accessibility, assertion-policy, key-loop, snap-distance, native-qualification, find) skipped; set GUI_CHECKS=1 in a GUI session"
fi
# Last: every fixture the checks above wrote must not claim Graphink documents, and nothing but
# Graphink.app may sit in the products directory that is zipped and delivered.
run_check fixture-bundles "$logs" python3 Checks/check-fixture-bundles.py --products "$products" --evidence "$evidence"
echo "Product checks passed for $sha"
