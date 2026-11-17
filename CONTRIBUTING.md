# Contributing to Graphink

## Setup

- **Run `scripts/dev/setup-hooks.sh` once per clone.** It installs the pinned ruff,
  shellcheck and actionlint into `<git common dir>/lint-tools` (`.git/lint-tools` in a
  plain clone, shared by its worktrees, never tracked) and enables
  [`.githooks/pre-commit`](.githooks/pre-commit), which lints the staged version of each
  Python file, shell script and workflow you commit. `git commit --no-verify` skips it
  once. `.github/scripts/checks-fast.sh` uses the same linters, and requires them.

## Commit messages

- **Pull requests target `main` and are squash-merged.** The PR title becomes the commit
  on `main`.
- **PR titles are [Conventional Commits](https://www.conventionalcommits.org/)**, checked in
  CI: `type(optional scope): subject`, lower case after the colon.
- **`feat`, `fix` and `perf` are for the product only**: a change people using Graphink can
  notice. Project tooling (CI, build, release and check scripts, linters, hooks) is `chore`,
  with a scope when it helps, even when it fixes a bug in that tooling:
  `chore(ci): pick the signing identity without a SIGPIPE under pipefail`, not `fix(ci): …`.
- **`feat`, `fix` and `perf` titles are the release notes, verbatim** (under Added, Fixed and
  Improved). Write them for users: what changed for them, not how it was done.
  `feat: export PNG and JPEG at 300 DPI`, not `feat: add RSExportAccessory`.
  `docs`, `test`, `ci`, `build`, `refactor`, `chore`, `style` and `revert` are not shown.
- **Never commit a version number.** The app version comes from release tags
  (`vYYYY.M.n`), created by the "Release" workflow or `scripts/release.sh`.
  Hand-written notes for a release go in `release-notes/<version>.md`.

Builds, checks, CI, versioning and releases: [docs/CONTRIBUTING-CI.md](docs/CONTRIBUTING-CI.md).
The current Mac build procedure: [docs/BUILDING.md](docs/BUILDING.md).
