#!/bin/bash
# macOS checks that need Xcode's clang and the bootstrapped OmniGroup sources,
# but no build products and no windows. Usage: checks-toolchain.sh LOG_DIR
. "$(dirname "$0")/common.sh"
logs=${1:?log dir}
select_xcode
evidence=$(mktemp -d /private/tmp/graphink-ci-toolchain.XXXXXX)

run_check documents-runner-self-check "$logs" Checks/check-documents.sh --self-check
run_check dependency-packaging "$logs" python3 Checks/Analyzer/dependencies/check-packaging.py
run_check dependency-regressions "$logs" python3 Checks/Analyzer/dependencies/check-regressions.py
run_check model-analyzer "$logs" python3 Checks/Analyzer/model/check-model.py
run_check app-analyzer "$logs" python3 Checks/Analyzer/app/checks.py --output "$evidence/app"
run_check app-menus "$logs" python3 Checks/Analyzer/app/menu-checks.py --output "$evidence/menus"
run_check graphink-extensions "$logs" python3 Checks/check-graphink-extensions.py --output "$evidence/extensions"
echo "Toolchain checks passed; evidence in $evidence"
