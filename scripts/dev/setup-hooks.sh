#!/bin/bash
# Usage: scripts/dev/setup-hooks.sh — enable the repository's git hooks (.githooks/) in this clone
# and install the pinned linters they use (install-lint-tools.sh) into <git common dir>/lint-tools,
# shared by every worktree of the clone and never tracked. Re-run it after a linter pin changes.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
tools=$(cd "$(git rev-parse --git-common-dir)" && pwd)/lint-tools
.github/scripts/install-lint-tools.sh "$tools"
git config core.hooksPath .githooks
echo "Hooks enabled (core.hooksPath=.githooks); linters in $tools"
