#!/bin/bash
# Checks that need neither Xcode nor the OmniGroup submodule. Runs on Linux
# (needs python3, xmllint, ruff, shellcheck and actionlint) and on macOS. Usage: checks-fast.sh LOG_DIR
. "$(dirname "$0")/common.sh"
logs=${1:?log dir}

run_check opc-fixture "$logs" python3 docs/format/check-opc.py \
  docs/format/fixtures/opc-v1/minimal.graphink --expect-payload docs/format/minimal.graphink
run_check opc-self-check "$logs" python3 docs/format/check-opc.py --self-check
run_check app-version "$logs" .github/scripts/version.sh check
run_check release-scripts "$logs" env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/release/tests -v
# The agent skill's find-graphink.sh and make-graph.sh, with a simulated uname and a stand-in tool.
run_check skill-scripts "$logs" env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/skills -v

# The Examples catalog checker lands with the example-models work; check its
# manifest whenever the tool is present (default mode only verifies).
if [[ -f Examples/Tools/manifest.py ]]; then
  run_check examples-manifest "$logs" python3 Examples/Tools/manifest.py
  # File > New From bundles byte copies of the catalog; default mode only verifies.
  run_check new-from-sync "$logs" python3 Examples/Tools/sync-new-from.py
else
  echo "Examples/Tools/manifest.py not present on this revision; skipped"
fi

# Lint our Python tooling (rules and excludes in pyproject.toml), shell scripts and workflows with
# the pinned linters from install-lint-tools.sh. RUFF, SHELLCHECK and ACTIONLINT override them;
# otherwise the ones scripts/dev/setup-hooks.sh installs in <git common dir>/lint-tools, if there,
# else the ones on PATH.
tools=$(cd "$(git rev-parse --git-common-dir)" && pwd)/lint-tools
[[ -x "$tools/ruff" && -x "$tools/shellcheck" && -x "$tools/actionlint" ]] || tools=
ruff=${RUFF:-${tools:+$tools/}ruff} shellcheck=${SHELLCHECK:-${tools:+$tools/}shellcheck}
actionlint=${ACTIONLINT:-${tools:+$tools/}actionlint}
for tool in "$ruff" "$shellcheck" "$actionlint"; do
  command -v "$tool" > /dev/null || { echo "::error::$tool not found; run .github/scripts/install-lint-tools.sh DIR and set RUFF/SHELLCHECK/ACTIONLINT" >&2; exit 1; }
done
# --force-exclude applies pyproject.toml's excludes to the files named here.
git ls-files -z '*.py' > "$logs/ruff-files"
run_check ruff "$logs" xargs -0 "$ruff" check --force-exclude --no-cache < "$logs/ruff-files"
git ls-files -z '.github/scripts/*.sh' 'scripts/*.sh' 'Checks/*.sh' 'tools/*.sh' 'skills/*.sh' '.githooks/*' > "$logs/shellcheck-files"
# SCRIPTDIR resolves the scripts' `. "$(dirname "$0")/common.sh"` sources.
run_check shellcheck "$logs" xargs -0 "$shellcheck" -x -P SCRIPTDIR < "$logs/shellcheck-files"
# actionlint checks every .github/workflows file, and their run: blocks with the same shellcheck.
# -pyflakes= : no workflow runs inline Python, and pyflakes is not pinned.
run_check actionlint "$logs" "$actionlint" -shellcheck "$(command -v "$shellcheck")" -pyflakes=

# Every tracked Python file must at least compile; every tracked shell script
# must parse. Byte-code goes to a throwaway prefix so the tree stays clean.
pycache=$(mktemp -d)
git ls-files -z '*.py' | PYTHONPYCACHEPREFIX="$pycache" xargs -0 python3 -m py_compile
git ls-files -z '*.sh' | xargs -0 -n 1 bash -n
echo "Python compile and shell parse checks passed"
