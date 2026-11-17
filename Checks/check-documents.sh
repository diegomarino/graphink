#!/bin/bash
# T47 preparation. Run only after the coordinator reviews the dependency handoff and
# builds this exact integrated HEAD in this worktree. Never borrow worker products.
set -euo pipefail
usage() {
    cat <<'HELP'
Usage: Checks/check-documents.sh --products ABSOLUTE_PATH --build-sha FULL_SHA
       Checks/check-documents.sh --products ABSOLUTE_PATH --build-sha FULL_SHA --legacy-smoke
       Checks/check-documents.sh --self-check

Compile and run eight NEW native-color documents through production RSGraph IO,
XML/ZIP save/reopen, color undo/redo and bitmap drawing/selection checks.
Products must come from a reviewed build of this exact HEAD.
The own OmniGroup checkout must contain exactly the reviewed full patch series
recorded in unmodified Patches/OmniGroup files at HEAD.
The supplied SHA is an operator attestation of product provenance; framework
hashes and source/toolchain identity are recorded, not proof of how products built.

Example (after the reviewed build):
  Checks/check-documents.sh --products /private/tmp/gs-own-build/Build/Products/Debug --build-sha "$(git rev-parse HEAD)"

Requires Xcode command-line tools and model/Omni frameworks with public headers. No build, download, dependency change or install
is performed. All 35 originals are hash-protected. --legacy-smoke separately
runs the historical corpus, including its four known schema defects, as diagnostic
evidence. Legacy color equality/old-app compatibility is not a new-document gate.
New generated XML must validate against the explicit current schema.
Exit 0: checks and original hashes passed; 1: checks/build/preservation failed;
2: invalid arguments or missing prerequisites. Evidence stays in the printed
new temporary directory. No UI, importer, sandbox or visual acceptance implied.
HELP
}
# Exit status alone cannot establish completion (including assertions at atexit).
completion_ok() {
    local log=$1 count=$2 baseline=$3 index format
    [[ $(grep -c '^COMPLETE ' <<< "$log") == 1 ]] || return 1
    [[ $(grep -Fxc "COMPLETE samples=$count failed=0 roundtrips=$((count * 2)) baseline=$baseline selfchecks=1" <<< "$log") == 1 ]] || return 1
    [[ $(grep -c '^PASS sample=' <<< "$log") == "$count" ]] || return 1
    [[ $(grep -Ec '^PASS roundtrip-(xml|zip) sample=' <<< "$log") == "$((count * 2))" ]] || return 1
    [[ $(grep -c '^BASELINE sha256=' <<< "$log") == "$baseline" ]] || return 1
    if grep -Eq 'FATAL ASSERTION|Assertion Failed:|^(Error: )?(ASSERT[^ ]*|PRECONDITION|POSTCONDITION|INVARIANT|NOTREACHED|OBASSERT[^ ]*) failed|^FAIL ' <<< "$log"; then return 1; fi
    for ((index=1; index<=count; index++)); do
        [[ $(grep -Fxc "PASS sample=$index" <<< "$log") == 1 ]] || return 1
        for format in xml zip; do
            [[ $(grep -Fxc "PASS roundtrip-$format sample=$index" <<< "$log") == 1 ]] || return 1
        done
    done
}
run_ok() {
    [[ $1 == 0 ]] && completion_ok "$2" "$3" "$4"
}
sources_match_head() {
    local pin=2be207ce6f7b4f77498bb48dd5e27403fb689eb7 actual expected
    git diff --quiet HEAD -- GraphSketcher Checks/DocumentChecks.m Checks/check-documents.sh Patches/OmniGroup || return 1
    git diff --cached --quiet HEAD -- GraphSketcher Checks/DocumentChecks.m Checks/check-documents.sh Patches/OmniGroup OmniGroup || return 1
    [[ -z $(git ls-files --others --exclude-standard -- Patches/OmniGroup) ]] || return 1
    [[ $(git rev-parse HEAD:OmniGroup) == "$pin" && $(git -C OmniGroup rev-parse HEAD) == "$pin" ]] || return 1
    git -C OmniGroup diff --cached --quiet || return 1
    [[ -z $(git -C OmniGroup ls-files --others --exclude-standard) ]] || return 1
    actual=$(git -C OmniGroup diff --no-ext-diff --no-color --binary --no-renames --abbrev=8) || return 1
    expected=$(python3 -c 'import pathlib, sys
blocks = []
for path in sys.argv[1:]:
    blocks.extend("diff --git " + part for part in pathlib.Path(path).read_text().split("diff --git ")[1:])
print("".join(sorted(blocks)), end="")' Patches/OmniGroup/000[1234]-*.patch) || return 1
    # Hunk-header function context depends on Git's diff driver version; compare without it.
    actual=$(sed -E 's/^(@@ -[0-9,]+ \+[0-9,]+ @@).*$/\1/' <<< "$actual") || return 1
    expected=$(sed -E 's/^(@@ -[0-9,]+ \+[0-9,]+ @@).*$/\1/' <<< "$expected") || return 1
    [[ -n "$expected" && "$actual" == "$expected" ]]
}
# shellcheck disable=SC2329 # invoked as an EXIT trap
preserve() {
    local status=$? preserved=1
    trap - EXIT
    if ! shasum -a 256 -- "${samples[@]}" > "$run/originals.after.sha256"; then preserved=0; fi
    if ! cmp -s "$run/originals.before.sha256" "$run/originals.after.sha256"; then
        echo 'FAIL: original corpus hashes changed; inspect evidence. No automatic restore attempted.' >&2
        preserved=0
    else
        echo 'PASS: original corpus hashes unchanged'
    fi
    if [[ ! -f "$run/verification.exit" ]]; then
        echo 'FAIL: runner exited before verification completed' >&2
        preserved=0
    fi
    if ((status == 0 && !preserved)); then status=1; fi
    exit "$status"
}
runner_shell_self_check() {
    local fixture mode status expected
    fixture=$(mktemp -d /private/tmp/GraphSketcher-runner-shell.XXXXXX) || return 1
    for mode in empty nonzero unexpected; do
        mkdir "$fixture/$mode" || return 1
        printf 'disposable original\n' > "$fixture/$mode/source" || return 1
        shasum -a 256 -- "$fixture/$mode/source" > "$fixture/$mode/originals.before.sha256" || return 1
        set +e
        (
            set -euo pipefail
            run="$fixture/$mode"
            samples=("$run/source")
            trap preserve EXIT
            # shellcheck disable=SC2154 # 'unexpected' reads an unset variable: set -u must fail the subshell
            case "$mode" in
                empty)
                    inputs=()
                    set -- executable output ${inputs[@]+"${inputs[@]}"}
                    [[ $# == 2 && $1 == executable && $2 == output ]] || exit 1
                    printf '%q ' "$@" > "$run/checks.command"
                    xml_outputs=()
                    for saved in ${xml_outputs[@]+"${xml_outputs[@]}"}; do exit 1; done
                    inputs=('name with spaces' '*')
                    set -- output ${inputs[@]+"${inputs[@]}"}
                    [[ $# == 3 && $2 == 'name with spaces' && $3 == '*' ]] || exit 1
                    printf '0\n' > "$run/verification.exit"
                    exit 0 ;;
                nonzero) exit 7 ;;
                unexpected) unset missing; : "$missing" ;;
            esac
        ) > "$fixture/$mode/log" 2>&1
        status=$?
        set -e
        case "$mode" in empty) expected=0 ;; nonzero) expected=7 ;; unexpected) expected=1 ;; esac
        if [[ $status != "$expected" ]]; then cat "$fixture/$mode/log" >&2; return 1; fi
    done
    printf 'PASS: shell %s preserves empty arguments and failure exits (evidence: %s)\n' "$BASH_VERSION" "$fixture"
}
runner_self_check() {
    local valid invalid
    valid=$'BASELINE sha256=fixture\nPASS sample=1\nPASS roundtrip-xml sample=1\nPASS roundtrip-zip sample=1\nCOMPLETE samples=1 failed=0 roundtrips=2 baseline=1 selfchecks=1'
    run_ok 0 "$valid" 1 1 || return 1
    if run_ok 1 "$valid" 1 1 || run_ok 139 "$valid" 1 1; then return 1; fi
    for invalid in "" "${valid%$'\n'COMPLETE*}" "${valid/PASS sample=1/}" "${valid/PASS roundtrip-xml sample=1/}" \
        "${valid/failed=0/failed=1}" "${valid/samples=1/samples=2}" \
        "$valid"$'\nError: ASSERT failed. Requires fixture' "$valid"$'\nError: PRECONDITION failed at exit' \
        "$valid"$'\nASSERT failed at exit' "$valid"$'\nAssertion Failed:' \
        "$valid"$'\nPASS sample=1' "$valid"$'\nCOMPLETE incomplete'; do
        if run_ok 0 "$invalid" 1 1; then echo 'FAIL: completion refusal self-check' >&2; return 1; fi
    done
    echo 'PASS: runner rejects nonzero exits, incomplete counts, duplicates and assertion/failure logs'
    runner_shell_self_check
}
products='' build_sha=''
legacy_smoke=0
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --self-check) [[ $# == 1 ]] || { usage >&2; exit 2; }; runner_self_check; exit $? ;;
        --legacy-smoke) legacy_smoke=1; shift ;;
        --products|--build-sha)
            (($# >= 2)) || { usage >&2; exit 2; }
            case "$1" in --products) products=$2 ;; --build-sha) build_sha=$2 ;; esac
            shift 2 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done
[[ -n "$products" && "$products" = /* && "$build_sha" =~ ^[0-9a-f]{40}$ ]] || { usage >&2; exit 2; }
root=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$root"
[[ "$(git rev-parse HEAD)" = "$build_sha" ]] || { echo 'Build SHA must equal this worktree HEAD; integrate the reviewed handoff first.' >&2; exit 2; }
sources_match_head || { echo 'Source, harness or dependency differs from HEAD plus the exact reviewed patch series; prepare the reviewed checkout first.' >&2; exit 2; }
for item in GraphSketcherModel.framework OmniFoundation.framework OmniBase.framework OmniUnzip.framework OmniQuartz.framework OmniAppKit.framework; do
    [[ -e "$products/$item" ]] || { printf 'Missing reviewed product: %s/%s\n' "$products" "$item" >&2; exit 2; }
done
products=$(cd "$products" && pwd -P)
run=$(mktemp -d /private/tmp/GraphSketcher-document-checks.XXXXXX)
printf 'Evidence: %s\n' "$run"
# Preserve evidence on failure; only this newly allocated directory receives writes.
samples=()
while IFS= read -r -d '' path; do samples+=("$path"); done < <(git ls-files -z -- '*.ograph')
((${#samples[@]} == 35)) || { echo 'Corpus differs from 35-file baseline; review inventory before running.' >&2; exit 2; }
shasum -a 256 -- "${samples[@]}" > "$run/originals.before.sha256"
inputs=()
sample_count=8
baseline_count=0
if ((legacy_smoke)); then inputs=("${samples[@]}"); sample_count=35; baseline_count=4; fi
trap preserve EXIT
{
    printf 'source_sha=%s\nproducts=%s\n' "$build_sha" "$products"
    git submodule status OmniGroup
    /usr/bin/sw_vers
    /usr/bin/uname -m
    xcodebuild -version
    xcrun --show-sdk-path
    shasum -a 256 "$products/GraphSketcherModel.framework/GraphSketcherModel" Checks/DocumentChecks.m Checks/check-documents.sh
} > "$run/provenance.txt" 2>&1
bundle="$run/DocumentChecks.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources" "$run/outputs"
# Keep production defaults/registrations, but use an isolated bundle identity and
# a fatal CheckController instead of the app controller. Do not load app nibs.
cp "$root/GraphSketcher/App/Info.plist" "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 12.0' "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :NSHumanReadableCopyright Copyright 2026 The Omni Group' "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1' "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.0' "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable DocumentChecks' "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.graphsketcher.migration.documentchecks' "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :NSPrincipalClass NSApplication' "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :OFControllerClass CheckController' "$bundle/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :NSMainNibFile' "$bundle/Info.plist"
# Fixtures never declare document types, UTIs, URL schemes or services: running one registers it
# with Launch Services, where it would claim .graphink/.ograph (Checks/check-fixture-bundles.py).
for key in CFBundleDocumentTypes UTExportedTypeDeclarations UTImportedTypeDeclarations CFBundleURLTypes NSServices; do
  /usr/libexec/PlistBuddy -c "Delete :$key" "$bundle/Info.plist" 2>/dev/null || true
done
# Use only headers and frameworks from the explicit, reviewed build products.
# No project files, source compilation flags or dependency pins are changed.
# shellcheck disable=SC2054 # -Wl,-rpath,DIR is one linker argument; the commas are its syntax
compile=(xcrun clang -fno-objc-arc -DOMNI_BUILDING_FOR_MAC=1 -F "$products"
    -framework Cocoa -framework QuartzCore -framework GraphSketcherModel
    -framework OmniBase -framework OmniFoundation -framework OmniUnzip
    -framework OmniQuartz -framework OmniAppKit
    -Wl,-rpath,"$products" -o "$bundle/MacOS/DocumentChecks" "$root/Checks/DocumentChecks.m")
printf '%q ' "${compile[@]}" > "$run/compile.command"
printf '\n' >> "$run/compile.command"
if ! "${compile[@]}" > "$run/compile.log" 2>&1; then
    echo "Harness compilation failed; see $run/compile.log" >&2; exit 1
fi
# Framework install names may use @executable_path/../Frameworks.
ln -s "$products" "$bundle/Frameworks"
/usr/bin/otool -L "$bundle/MacOS/DocumentChecks" > "$run/linked-frameworks.txt"
# Bash 3.2 treats an empty array as unset under nounset.
printf '%q ' "$bundle/MacOS/DocumentChecks" "$run/outputs" ${inputs[@]+"${inputs[@]}"} > "$run/checks.command"
printf '\n' >> "$run/checks.command"
set +e
"$bundle/MacOS/DocumentChecks" "$run/outputs" ${inputs[@]+"${inputs[@]}"} > "$run/checks.log" 2>&1
result=$?
set -e
printf '%s\n' "$result" > "$run/checks.exit"
cat "$run/checks.log"
if ! run_ok "$result" "$(cat "$run/checks.log")" "$sample_count" "$baseline_count"; then
    echo "FAIL: native exit, completion/counts or assertion-free termination check; see $run/checks.log" >&2
    result=1
fi
if (( !legacy_smoke )); then
    xml_outputs=("$run/outputs/"*-xml-*.ograph)
    if ((${#xml_outputs[@]} != sample_count * 2)); then
        echo 'FAIL: missing current XML outputs for schema verification' >&2; result=1
    fi
    for saved in ${xml_outputs[@]+"${xml_outputs[@]}"}; do
        if ! xmllint --nonet --noout --relaxng "$root/GraphSketcher/Model/XML/GraphSketcher.rng" "$saved" >> "$run/schema.log" 2>&1; then result=1; fi
    done
fi
printf '%s\n' "$result" > "$run/verification.exit"
exit "$result"
