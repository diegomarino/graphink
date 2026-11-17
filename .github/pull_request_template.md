<!--
PR TITLE = the squashed commit on main, and for feat/fix/perf the release note, verbatim.
Use a Conventional Commit, lower case after the colon, written for users:
  feat: export PNG and JPEG at 72, 144, 150 or 300 DPI      -> Added
  fix: keep the default line width when you resize a line   -> Fixed
  perf: open large graphs faster                            -> Improved
  docs|test|ci|build|refactor|chore|style|revert: ...       -> not in the release notes
CI checks the title (PR title workflow). See docs/CONTRIBUTING-CI.md, "Release notes".
-->

## What and why

<!-- One or two sentences. Link the issue: Fixes #N / Refs #N. -->

## How it was verified

<!-- Commands run and their result. CI covers the windowless checks; native UI
     acceptance (launching Graphink and exercising the flow) is manual. -->

- [ ] CI green (fast checks, macOS Debug + Release, windowless product checks, PR title)
- [ ] Native acceptance done, or not applicable: <!-- what was exercised -->

## Checklist

- [ ] The PR title is a Conventional Commit; a feat/fix/perf title reads well as a user-facing release note
- [ ] For a release that needs hand-written notes: `release-notes/<version>.md` added or updated (and not left as a DRAFT)
- [ ] Branch is `feat/`, `fix/`, `docs/`, `ci/` or `chore/` plus a short slug (issue number if any)
- [ ] No original sample documents (Examples, test documents) overwritten
- [ ] OmniGroup pin and `Patches/OmniGroup` unchanged, or the change is explained and the bootstrap checks pass
- [ ] Deployment settings (macOS 12.0, arm64) unchanged unless this PR is about them
- [ ] No version committed: the app version comes from tags (`scripts/release/version.py`)
- [ ] No Debug build or development-entitled product attached or shared
