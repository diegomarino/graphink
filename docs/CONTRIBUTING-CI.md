# Contributing: CI, pull requests and builds

How Graphink is checked, built and released on GitHub. The build itself is
defined in [docs/BUILDING.md](BUILDING.md) and the dependency
bootstrap in [Patches/OmniGroup/README.md](../Patches/OmniGroup/README.md);
CI runs those exact procedures, it does not redefine them.

Repository- and toolchain-specific values (repo slug, Pages URL, Xcode version
and path, OmniGroup pin) live in one file: [`.github/ci.env`](../.github/ci.env).

## Workflows

| Workflow | Trigger | Runs on | What it does |
|---|---|---|---|
| [`ci.yml`](../.github/workflows/ci.yml) | every PR, push to `main`, manual | Ubuntu + hosted macOS | lint, fast checks, release-notes preview, then Debug and Release builds with checks; on `main` also a `Graphink.dmg` workflow artifact |
| [`pr-title.yml`](../.github/workflows/pr-title.yml) | PR opened, edited, updated | Ubuntu | commitlint on the PR title (Conventional Commits) |
| [`release-tag.yml`](../.github/workflows/release-tag.yml) "Release" | manual on `main`, no inputs | Ubuntu | computes the next version, checks there is something to release, tags `main` and starts the tag pipeline |
| [`release.yml`](../.github/workflows/release.yml) "Release build" | tag `vYYYY.M.n`, or manual on a tag ref | hosted macOS + Ubuntu | builds and checks the tag, packages `Graphink.dmg`, then publishes the GitHub Release after approval |

All actions are pinned by commit SHA, with the version in a comment.
Dependabot ([`dependabot.yml`](../.github/dependabot.yml)) proposes weekly
grouped bumps for actions only; the OmniGroup pin is never bumped automatically.
Workflows default to `contents: read`; only the release publish job (`contents:
write`), the Release tagging job (`contents: write` to push the tag, `actions: write` to
start the tag pipeline) get more.

### CI jobs

1. **lint** (Ubuntu): installs the pinned linters with
   [`install-lint-tools.sh`](../.github/scripts/install-lint-tools.sh), then runs
   actionlint on `.github/workflows` (with the pinned shellcheck on every `run:`
   block) and shellcheck on `.github/scripts` and `scripts/release.sh`.
2. **fast** (Ubuntu, no Xcode): [`checks-fast.sh`](../.github/scripts/checks-fast.sh)
   runs `docs/format/check-opc.py` on the OPC v1 fixture and in `--self-check`,
   the version check, the release scripts' unit tests (`scripts/release/tests`),
   `Examples/Tools/manifest.py` and `sync-new-from.py`, ruff, shellcheck and actionlint (see
   [Linters](#linters)), a compile check of every tracked Python file and a parse
   check of every tracked shell script.
3. **notes** (Ubuntu): installs the pinned git-cliff and writes the unreleased release
   notes (what the next release would say) to the job summary.
4. **macOS Debug / Release** (hosted `xcode-27`, a matrix, separate DerivedData
   per configuration; full history with tags, because the version and the bundled
   release notes come from them):
   - [`bootstrap-omnigroup.sh`](../.github/scripts/bootstrap-omnigroup.sh) does a
     shallow fetch of the pinned gitlink, then runs the README bootstrap
     block verbatim (pin and exact patch-series checks included).
   - Debug only, [`checks-toolchain.sh`](../.github/scripts/checks-toolchain.sh):
     checks that need clang and the patched sources but no products.
   - [`build.sh`](../.github/scripts/build.sh): the docs/BUILDING.md
     `xcodebuild` command for that configuration (ad-hoc, arm64, macOS 12.0),
     then signature and architecture checks.
   - Debug only, [`checks-products.sh`](../.github/scripts/checks-products.sh):
     windowless checks against this run's own Debug products.
   - On pushes to `main`, Release is built with the distribution settings and
     packaged with `package-release.sh`; `Graphink.dmg` is uploaded as a workflow
     artifact kept for 5 days. That is never a tag or a GitHub Release.
   - Otherwise only logs are uploaded. PR builds never upload an app.

### Linters

`checks-fast.sh` runs three linters, pinned with their SHA-256 in `.github/ci.env`
(`RUFF_VERSION`, `SHELLCHECK_VERSION`, `ACTIONLINT_VERSION`) and installed as release
binaries by [`install-lint-tools.sh`](../.github/scripts/install-lint-tools.sh) (Linux
x86-64 and macOS arm64). They are required, locally too: `checks-fast.sh` stops if it
cannot find them. It takes `RUFF`, `SHELLCHECK` and `ACTIONLINT` if set, otherwise the
ones `scripts/dev/setup-hooks.sh` installed in `<git common dir>/lint-tools`, otherwise
the ones on `PATH`.

- **ruff** on every tracked Python file outside `Examples/` and `OmniGroup/`
  ([`pyproject.toml`](../pyproject.toml)). Only rules that find bugs: pyflakes
  (`F`: unused imports and variables, undefined names), pycodestyle errors and
  warnings (`E`, `W`: bare `except`, invalid escapes) and bugbear (`B`: mutable
  defaults, loop-variable closures) and `EXE` (a shebang needs the executable bit,
  and an executable needs a shebang). The compact style the scripts use on purpose
  is not linted: no line length (`E501`), one-line `if x: y` and `a; b`, named
  lambdas, imports after the `sys.path` setup; nor `zip(strict=)` (`B905`) and
  `raise SystemExit` without `from` (`B904`). Do not run `ruff format`.
- **shellcheck** (`-x -P SCRIPTDIR`, default severity) on `.github/scripts/*.sh`,
  `scripts/**/*.sh`, `Checks/*.sh` and `.githooks/*`. Disable a rule only inline, on the
  command it applies to, with the reason after it:
  `# shellcheck disable=SC2054 # -Wl,-rpath,DIR is one linker argument`.

- **actionlint** on every file in `.github/workflows`, with the pinned shellcheck on
  their `run:` blocks (`-shellcheck`) and pyflakes off (no workflow runs inline Python).

The **lint** job runs actionlint and shellcheck with the same pinned binaries.

**Pre-commit hook.** [`.githooks/pre-commit`](../.githooks/pre-commit) runs the same
three linters, with the same options, on what is being committed only: the staged
version of each added or changed Python file, covered shell script and workflow. It
lints a copy of the index, so unstaged edits neither hide nor cause findings, and
takes well under a second. [`scripts/dev/setup-hooks.sh`](../scripts/dev/setup-hooks.sh)
installs the linters into `<git common dir>/lint-tools` (no system-wide install) and
sets `git config core.hooksPath .githooks`; re-run it when a pin in `ci.env`
changes. `git commit --no-verify` skips the hook once; CI still runs everything.

### Which checks run where

| Check | Needs | CI tier |
|---|---|---|
| ruff (`pyproject.toml`), shellcheck, actionlint | pinned binaries (`install-lint-tools.sh`) | fast (and pre-commit, staged files) |
| `docs/format/check-opc.py` (fixture, `--self-check`) | Python, xmllint | fast |
| `Examples/Tools/manifest.py` (check mode, once present) | Python | fast |
| `Examples/Tools/sync-new-from.py` (check mode: bundled New From copies equal the catalog) | Python | fast |
| `Checks/check-documents.sh --self-check` | Bash | toolchain |
| `Checks/Analyzer/dependencies/check-packaging.py` | git, OmniGroup clone, `/private/tmp` | toolchain |
| `Checks/Analyzer/dependencies/check-regressions.py` | clang, patched OmniGroup | toolchain |
| `Checks/Analyzer/model/check-model.py` | clang | toolchain |
| `Checks/Analyzer/app/checks.py`, `menu-checks.py` | clang (menus build offscreen, no window) | toolchain |
| `Checks/check-graphink-extensions.py` | clang | toolchain |
| `Checks/check-documents.sh --products` | Debug products | products |
| `docs/format/check-format.py` | Debug products | products |
| `Checks/Analyzer/model/check-production.py` | Debug products | products |
| `Checks/check-width-defaults.py`, `check-about-links.py` | Debug products | products |
| `UI/check-style-defaults.py`, `UI/StylePresets/check-presets.py`, `check-creation-defaults.py`, `check-package-documents.py` | Debug products | products |
| `Checks/check-document-types.py`, `check-new-from.py`, `check-legacy-roundtrips.py` | Debug products | products |
| `Checks/check-fixture-bundles.py` (no check fixture app can claim Graphink documents or ship with the products) | Debug products, the checks' evidence, read-only Launch Services database | products |
| `Checks/check-sidebar.py`, `Checks/check-viewport.py`, `Checks/check-page-size.py`, `Checks/check-zoom-accessibility.py`, `Checks/check-assertion-policy.py`, `Checks/check-key-loop.py`, `Checks/check-snap-distance.py`, `Checks/check-native-qualification.py`, `Checks/check-find.py` | Debug products plus an Aqua session (offscreen `NSWindow`s; `check-assertion-policy.py` also runs an `NSApplication` event loop and accessibility requests; `check-native-qualification.py` emulates the key window and never shows the shared font and color panels; `check-find.py` uses the shared find pasteboard and restores it) | opt-in: `GUI_CHECKS=1` |
| `UI/Graphink/Cursors/check-cursors.py`, `UI/Design/*`, `UI/LogoStudy/*` | Pillow, poppler (asset pipelines) | not in CI |
| `UI/StylePresets/check-archives.py` | a separately compiled fixture and a native package | not in CI |
| `Examples/Microeconomics/validate.py` | rendered PDFs from a generate run | not in CI |

"Windowless" means no `NSWindow` is created. Several of those checks still
call `+[NSApplication sharedApplication]`. Hosted macOS runners provide a
logged-in session, so everything above passes there. No check launches
Graphink.app, and none of them proves native UI acceptance, which stays manual.

### Checks run by hand

The asset pipelines are not in CI. From the repository root:

```bash
out=$(mktemp -d /private/tmp/graphink-checks.XXXXXX)
python3 UI/Design/check-production-icons.py      # the 54 control glyphs: names, sizes, loader schema, PDFs
python3 UI/Design/check-production-rendering.py  # renders every PDF; regenerates the light/dark proof
python3 UI/Graphink/Cursors/check-cursors.py --app "$root/Debug/Products/Debug/Graphink.app" --output "$out/cursors"
xcrun clang -fno-objc-arc -Wall -Wextra -Werror -Wno-unused-parameter -I GraphSketcher/App \
  -framework AppKit GraphSketcher/App/RSModernImages.m Checks/ModernImagesChecks.m -o "$out/modern-images"
"$out/modern-images" "$root/Debug/Products/Debug/Graphink.app"   # loads the 54 images from the built app
```

The image check fixes the 54 names from the original inventory and checks the exported PDF
bytes, aliases, template flags, logical sizes and the rejection of missing or invalid
resources. The style preset checks (`UI/StylePresets/check-presets.py --products ... --output
NEW_DIR`) run in the products tier and need host access for offscreen AppKit rendering; they
compile the app-local preset code into an isolated fixture bundle and never load the app's nib.

### Known compiler warnings

Deprecation warnings left as they are, on purpose:

- 2026 code: `GraphDocument.m` `setAllowedFileTypes:` (its `allowedContentTypes` replacement
  resolves through the registered UTI, which the explicit tags exist to avoid) and its override
  of the synchronous `saveToURL:ofType:forSaveOperation:error:` (synchronous callers still use
  it); `RSGraphView.m` `beginSheet:modalForWindow:modalDelegate:…` (a completion block changes
  the context ownership); `RSNumber.m` `NSRunAlertPanel`.
- 2014 code: about 90 warnings (`GraphSketcher/` and `LinkBack/`), left so blame stays meaningful.
  None is a drop-in rename: pasteboard types, `lockFocus`, `colorUsingColorSpaceName:`, sheets and
  alerts, `commitEditing`, `NSConnection` and similar need real rewrites. The renamed constants
  (`NSOnState`, `NS*KeyMask`, event types, calendar units) were replaced in one mechanical commit
  listed in [`.git-blame-ignore-revs`](../.git-blame-ignore-revs); run
  `git config blame.ignoreRevsFile .git-blame-ignore-revs` once per clone so `git blame` skips it
  (GitHub's blame view reads the file by itself).
- Checks: `ZoomAccessibilityChecks.m` uses the attribute-based accessibility API on purpose (it
  drives the path that crashed); `ViewportChecks.m` calls the synchronous save the app
  overrides; `XMLChecks.m` passes nil on purpose to test a nil contract.

## Runners

**Decision: GitHub-hosted only.** Graphink needs Xcode 27.2 and the macOS 27.2 SDK
(docs/BUILDING.md). GitHub's `xcode-27` image (Apple silicon, macOS 27) became
generally available on 2026-10-15 and ships Xcode 27.0, 27.1 (default) and
**27.2** (`/Applications/Xcode_27.2.app`, SDK `macosx27.2`). `macos-latest` and
`macos-26` do not have it. GitHub now names macOS images after their major Xcode
version, so there is no `macos-27` label. Because 27.2 is not the image default,
`build.sh` selects it through `DEVELOPER_DIR` and fails fast if
`xcodebuild -version` is not exactly `Xcode 27.2`, rather than quietly building
with another Xcode.

The runner label is a single switch: the repository variable `MACOS_RUNNER`
(default `xcode-27`). Set it to a hosted label such as `xcode-27-xlarge`
(larger M2 Pro runner, faster, always billed) or to a future `xcode-28`.

**Cost.** Standard hosted runners are free for public repositories. While the
repository is private, macOS minutes cost $0.062/min (3/4-core) and draw on the
plan's included Actions credit (a monetary allowance: $12/month on Free, $18 on
Pro/Team). Linux costs $0.006/min. Larger runners (`-xlarge`, $0.102/min) are
billed even on public repos. Measured on a 12-core Mac mini: bootstrap 4 s, toolchain checks
about 2 s, Debug build 200 s, Release build 218 s, product checks 21 s. A hosted 3-core runner
is slower; the estimate is 10–15 min per matrix leg, about 25–30 macOS minutes per PR run.

**Rejected: self-hosted runners.** A fork PR on a public repo can edit the
workflow and choose any runner, so a self-hosted runner there means running
untrusted code on owned hardware.

## Versioning

- **App version** (`CFBundleShortVersionString`) is calendar `YYYY.M.n`: no
  zero padding, `M` is the month of publication, `n` counts releases within
  that month from 0 (`2026.11.0`, `2026.11.1`, `2026.12.0`). It comes from
  **git tags**, never from a committed file. One script holds the rules,
  [`scripts/release/version.py`](../scripts/release/version.py):
  - `next`: the next release, from the latest valid `vYYYY.M.n` tag and today's
    date in Europe/Madrid (same month: `n + 1`; otherwise `YYYY.M.0`; no tags:
    this month's `.0`). Malformed tags are ignored.
  - `current`: the version of a build of `HEAD`, which is the latest valid tag reachable from
    `HEAD` (what `git describe --tags --match 'v[0-9]*'` finds), or this month's
    `.0` when there is none. Development builds therefore carry the last
    release's number and differ from it only by `CFBundleVersion`. The version
    stays purely numeric.
- **Every scripted build injects it** as `MARKETING_VERSION=` on the `xcodebuild`
  command line: [`build.sh`](../.github/scripts/build.sh) (CI and local) and the
  [docs/BUILDING.md](BUILDING.md) command use `version.py current`,
  and release builds use the tag's version.
  [`Graphink-Version.xcconfig`](../GraphSketcher/App/Configurations/Graphink-Version.xcconfig)
  keeps only documentation and a `0.0.0` fallback for builds that bypass the
  scripts (for example plain Xcode). `version.sh check` (fast CI) fails if a real
  version is committed there again.
- **Build number** (`CFBundleVersion`) is a monotonically increasing integer:
  release builds use the release workflow's run number plus `BUILD_NUMBER_BASE`
  (`.github/ci.env`; raise the base if the workflow is ever renamed). Local
  and PR builds use the placeholder `1` from the xcconfig.
- **Tags** are annotated `vYYYY.M.n` tags on `main`, created only by the Release
  workflow or `scripts/release.sh` (see Releases).
- **Document format is versioned separately.** The `.graphink` format (OPC
  profile `opc-v1`, document `version="1"`; see [docs/format](format/)) does
  not change with app releases, and an app release does not imply a format change.
- The Spotlight/QuickLook plugin and iPad plists still use the historical Omni
  macros. They are not the app version.

## Release notes

Release notes are written for users and come from PR titles. PRs are
**squash-merged**, so the PR title becomes the commit subject on `main`, and
[git-cliff](https://git-cliff.org) ([`cliff.toml`](../cliff.toml), pinned
`GIT_CLIFF_VERSION` in `.github/ci.env`) turns subjects into notes:

| PR title type | Release notes |
|---|---|
| `feat:` | **Added** |
| `fix:` | **Fixed** |
| `perf:` | **Improved** |
| `docs`, `test`, `ci`, `build`, `refactor`, `chore`, `style`, `revert` | hidden, unless the commit body has a `Release-Note: notable` line (then **Improved**) |

**A `feat`, `fix` or `perf` title appears in the release notes verbatim**, with
only its first letter capitalized, so write it for users: say what changed for
them, not how. Good: `feat: export PNG and JPEG at 72, 144, 150 or 300 DPI`,
`fix: keep the default line width when you resize a selected line`. Not:
`fix: guard RSUnknown in setWidth`. They are for product changes only: a fix to
CI, scripts or checks is `chore(ci): ...` (see [CONTRIBUTING.md](../CONTRIBUTING.md)). Scopes are optional
(`feat(export): ...`) and are not shown. Start the subject in lower case, as commitlint requires.
Commits that are not Conventional Commits (the inherited GraphSketcher history)
are skipped.

A version's notes are `release-notes/<version>.md` when that file exists
(hand-written; it replaces the generated notes), otherwise git-cliff's entries
for the commits since the previous tag. The file uses the same `### Added`,
`### Fixed` and `### Improved` groups, may start with a short paragraph, and
blocks a release while it contains the word `DRAFT`. The same notes are used
for the GitHub release body and inside the app: the build phase
"Generate Release Notes" runs
[`scripts/release/notes.py html`](../scripts/release/notes.py) and bundles the
notes of every **published** version reachable from `HEAD` (tags only, never
unreleased commits or unpublished files) as `MessageOfTheDay.html`. Graphink shows
that page once after an update whose notes changed, never on first launch, and
from Help > Release Notes. There is no committed changelog file.

## Releases

**Artifact contract** (download links rely on it): every release attaches
a Release-configuration **`Graphink.dmg`** plus `Graphink.dmg.sha256` and
`BUILD-INFO.txt`. Releases are normal (not draft, not prerelease) and marked
latest, so `https://github.com/<REPO_SLUG>/releases/latest/download/Graphink.dmg`
always resolves to the newest one. Debug is never packaged.

**To release, run the "Release" workflow** (Actions > Release > Run workflow, on
`main`). It has no inputs; the version is never typed. Locally,
[`scripts/release.sh`](../scripts/release.sh) does the same: without arguments it
prints the next version and its notes; `scripts/release.sh --tag` creates the
annotated tag on a clean `main` that matches `origin/main` and prints the
`git push origin vX` command.

1. [`release-tag.yml`](../.github/workflows/release-tag.yml) computes the next
   version (`version.py next`). It refuses when the tag exists, when there are no
   `feat`/`fix`/`perf` commits since the last tag and no
   `release-notes/<version>.md`, or when that file is still a DRAFT. It writes the
   notes to the run summary, pushes the annotated tag on `main`'s HEAD, and
   dispatches `release.yml` on the tag (a tag pushed with the workflow token does
   not start push workflows by itself). A tag pushed by a person starts
   `release.yml` directly.
2. `release.yml` (job **build**, environment `release-build`) checks out the tag
   with full history, takes the version from the tag and injects it into both
   builds, installs git-cliff, bootstraps, runs the toolchain checks, builds
   Debug only to run the product checks, then builds Release with the
   distribution settings and the release build number, and runs
   [`package-release.sh`](../.github/scripts/package-release.sh):
   - refuses anything but `Release/Products/Release/Graphink.app`, the
     development entitlements (`disable-library-validation`, `get-task-allow`),
     a lost sandbox entitlement, an ad-hoc + Hardened Runtime signature (it
     cannot launch), a version mismatch, or a non-integer build number;
   - stages `Graphink.app` (ditto) and an `Applications -> /Applications`
     symlink, sets all staged timestamps to the commit time, and runs
     `hdiutil create -format UDZO -fs HFS+`. The app inside is byte-identical
     to the build. The DMG itself is not bit-reproducible, because hdiutil
     embeds dates and UUIDs;
   - verifies the image, mounts it read-only without Finder, re-runs every app
     check on the mounted copy, `diff`s it against the build and checks the
     symlink, then writes `Graphink.dmg.sha256` and `BUILD-INFO.txt`.
   The release body comes from [`release-notes.sh`](../.github/scripts/release-notes.sh):
   the version's notes ("What's new"), the download and install notes, and
   `BUILD-INFO.txt`. The app inside the DMG bundles the same notes.
3. Job **publish** waits for approval on the `release` environment (required
   reviewers). That approval is the manual gate. It then verifies the checksum
   and runs `gh release create --latest`, which publishes the release.

A manual run of `release.yml` on an existing tag ref
(`gh workflow run release.yml --ref v2026.11.0`) rebuilds it. It publishes only
when `publish` is ticked, still behind the same approval, and refuses if the
release already exists. It has no version input.

### Signing modes (`SIGNING_MODE` in `.github/ci.env`)

**`adhoc` (current).** The Release packaging build adds
`RELEASE_DISTRIBUTION_SETTINGS` =
`ENABLE_HARDENED_RUNTIME=NO,CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`, passed as
command-line overrides. The project's settings are unchanged. Why: an ad-hoc
app with Hardened Runtime aborts at launch, because library validation rejects
its ad-hoc embedded frameworks ("different Team IDs"), and Xcode injects
`get-task-allow` into ad-hoc signatures. The result keeps exactly the
original Release entitlements (sandbox, user-selected files, print). It is
**not notarized**: the release notes walk users through
System Settings > Privacy & Security > Open Anyway. PR builds keep the README
command unchanged.

**`developer-id` (later, ready but never exercised).**
[`sign-developer-id.sh`](../.github/scripts/sign-developer-id.sh) re-signs every
nested framework/bundle and then the app with the Developer ID identity,
`--options runtime` (Hardened Runtime back on) and `--timestamp`. It keeps the
app's own Release entitlements and strips the development ones. It then signs
the DMG, notarizes it with `notarytool --wait`, staples it, and checks it with
`spctl`. `RELEASE_DISTRIBUTION_SETTINGS` is not applied in this mode. To switch:
1. Join the Apple Developer Program; create a *Developer ID Application*
   certificate and an App Store Connect API key (Developer role).
2. Add secrets to the `release-build` environment (restrict it to `v*` tags):
   `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`,
   `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`.
3. Set `SIGNING_MODE=developer-id`, then push a test tag (and delete the
   resulting release) before the first real one. The script runs in a
   throwaway keychain, so PRs and forks never see the secrets.

## Pull requests

- **Default branch: `main`** (the `graphink` repository). PRs target `main`;
  CI and the branch protection below assume it.
- **Branches:** `<type>/<slug>`, where type is `feat`, `fix`, `docs`, `ci`,
  `chore` or `site`, and the slug starts with the issue number when there is one
  (for example `feat/issue-10-example-models`, `fix/check-documents-hunk-context`).
- **PR titles are Conventional Commits** (`type(scope): subject`, scope optional;
  types `feat`, `fix`, `perf`, `docs`, `test`, `ci`, `build`, `refactor`, `chore`,
  `style`, `revert`). PRs are squash-merged, so the title becomes the commit on
  `main`; `pr-title.yml` checks it with commitlint
  ([`.commitlintrc.json`](../.commitlintrc.json), pinned version, CI only: no Node
  in the build). `feat`, `fix` and `perf` titles become release notes verbatim (see
  Release notes), so write them for users. Commits inside a PR branch are not
  linted; they disappear in the squash.
- The PR template ([`.github/pull_request_template.md`](../.github/pull_request_template.md))
  asks for verification evidence and native-acceptance status.
- [`CODEOWNERS`](../.github/CODEOWNERS) assigns everything to `@diegomarino`.

### Branch protection and repository settings

Applied on `diegomarino/graphink`. Ruleset **main** (the default branch):
- a pull request before merging, with 1 approval, Code Owner review and stale
  approvals dismissed on new commits; admins may bypass it only through a pull
  request (a sole maintainer merges their own PRs, never pushes to `main`);
- required status checks, with branches up to date:
  `Lint workflows and scripts`, `Fast checks (no Xcode)`, `macOS Debug`,
  `macOS Release`, `PR title (Conventional Commits)`;
- conversations resolved; **squash merging only** (the PR title is the commit
  subject the release notes are built from);
- no force pushes, no deletion.

Ruleset **release tags** (`v*`): a published tag cannot be moved or deleted
(admins may bypass). Tag *creation* is not restricted: a personal repository
cannot list GitHub Actions as a ruleset bypass, and `release-tag.yml` creates the
tag with the workflow token. Only accounts with write access can create tags.

Repository settings:
- squash merging only, with the PR title and body; branches deleted on merge;
- Actions: workflows from fork PRs need approval for all external contributors;
  the default `GITHUB_TOKEN` permission is read-only and cannot approve PRs;
- environment `release` with a required reviewer (the publish gate) and
  `release-build` without reviewers (signing secrets later), both limited to
  `v*` tags;
- secret scanning and push protection on.

## Pages

The project site is not in this repository yet: it is added, with its Pages
workflow, after review. `PAGES_URL` in `.github/ci.env` and the About box's
"Graphink documentation" link already name its address,
`https://diegomarino.github.io/graphink/`.

## Running the checks locally

```bash
scripts/dev/setup-hooks.sh   # once per clone: pinned linters in <git common dir>/lint-tools, hooks on
.github/scripts/checks-fast.sh /private/tmp/graphink-logs/fast
.github/scripts/bootstrap-omnigroup.sh
.github/scripts/checks-toolchain.sh /private/tmp/graphink-logs/toolchain
root=$(mktemp -d /private/tmp/GraphSketcher-build.XXXXXX)
.github/scripts/build.sh Debug "$root"
.github/scripts/checks-products.sh "$root" /private/tmp/graphink-logs/products
.github/scripts/build.sh Release "$root"
python3 -m unittest discover -s scripts/release/tests   # set GIT_CLIFF=... to include the git-cliff case
scripts/release.sh                                      # next version and its notes (needs git-cliff)

# A local Graphink.dmg the way release.yml makes it (separate root, Release only):
. .github/ci.env
dmg_root=$(mktemp -d /private/tmp/GraphSketcher-build.XXXXXX)
EXTRA_BUILD_SETTINGS=$RELEASE_DISTRIBUTION_SETTINGS BUILD_NUMBER=1 \
  .github/scripts/build.sh Release "$dmg_root"
.github/scripts/package-release.sh "$dmg_root" "$dmg_root/dist" "$(.github/scripts/version.sh show)"
```

Run these from a clean checkout. The bootstrap and `check-documents.sh` refuse
modified or untracked sources in the guarded paths.
