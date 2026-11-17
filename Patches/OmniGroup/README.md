# OmniGroup Mac build patch

The parent gitlink stays at public revision
`2be207ce6f7b4f77498bb48dd5e27403fb689eb7`. Apply these patches after
initializing that revision; no private submodule commit is required.

From a fresh parent checkout:

```bash
bash <<'BOOTSTRAP'
(
  set -eu
  git diff --quiet HEAD -- GraphSketcher Checks Patches/OmniGroup
  git diff --cached --quiet HEAD -- GraphSketcher Checks Patches/OmniGroup OmniGroup
  test -z "$(git ls-files --others --exclude-standard -- Patches/OmniGroup)"
  test "$(git rev-parse HEAD:OmniGroup)" = 2be207ce6f7b4f77498bb48dd5e27403fb689eb7
  if test -e OmniGroup/.git; then
    test "$(git -C OmniGroup rev-parse HEAD)" = 2be207ce6f7b4f77498bb48dd5e27403fb689eb7
  fi
  git submodule update --init OmniGroup
  test "$(git -C OmniGroup rev-parse HEAD)" = 2be207ce6f7b4f77498bb48dd5e27403fb689eb7
  git -C OmniGroup diff --cached --quiet
  test -z "$(git -C OmniGroup ls-files --others --exclude-standard)"
  patch1=Patches/OmniGroup/0001-sign-fixstringsfile-before-tests.patch
  patch2=Patches/OmniGroup/0002-modern-mac-compiler-compatibility.patch
  patch3=Patches/OmniGroup/0003-defer-mail-validation.patch
  patch4=Patches/OmniGroup/0004-analyzer-contracts-and-lifetimes.patch
  patches=("$patch1" "$patch2" "$patch3" "$patch4")
  # The patch files touch disjoint paths; compare in Git's path order.
  patch_diff() {
    python3 -c 'import pathlib, sys
blocks = []
for path in sys.argv[1:]:
    blocks.extend("diff --git " + part for part in pathlib.Path(path).read_text().split("diff --git ")[1:])
print("".join(sorted(blocks)), end="")' "$@"
  }
  # Hunk-header function context depends on Git's diff driver version; compare without it.
  strip_hunk_context() { sed -E 's/^(@@ -[0-9,]+ \+[0-9,]+ @@).*$/\1/'; }
  actual="$(git -C OmniGroup diff --no-ext-diff --no-color --binary --no-renames --abbrev=8)"
  actual="$(printf '%s\n' "$actual" | strip_hunk_context)"
  reviewed=0
  for count in 0 1 2 3 4; do
    expected="$(patch_diff "${patches[@]:0:count}")"
    expected="$(printf '%s\n' "$expected" | strip_hunk_context)"
    if test "$actual" = "$expected"; then reviewed=1; break; fi
  done
  if test "$reviewed" != 1; then
    echo "Refusing unrelated or incompatible OmniGroup changes." >&2
    exit 1
  fi
  for patch in "${patches[@]}"; do
    if git -C OmniGroup apply --check "../$patch"; then
      git -C OmniGroup apply "../$patch"
    elif git -C OmniGroup apply --reverse --check "../$patch"; then
      echo "Already applied: $patch"
    else
      echo "Incompatible patch: $patch" >&2
      exit 1
    fi
  done
)
BOOTSTRAP
```

The first patch signs only the generated `FixStringsFile` executable with a local
ad-hoc identity before its existing test phase executes it. Xcode's normal
signing happens later. All five original tests and strict shell failure
handling remain unchanged. This does not change application signing, sandbox
settings, identifiers, or test expectations.

The second patch contains declaration/import/compiler compatibility fixes and
quadratic-to-cubic normalization for the existing Mac path algorithms.
The two K&R prototype diagnostics remain visible as warnings for the three
vendored minizip C files in the Mac target; other warnings-as-errors remain
unchanged. Quadratic normalization preserves input paths and the existing cubic
plist schema; focused production-source ASan checks are documented in
[docs/BUILDING.md](../../docs/BUILDING.md).

The third patch defers the unchanged Debug-only mail entitlement validation from
framework load to the central AppleScript executor used by AppleMail and
Mailsmith. The browser/mailto URL path is unaffected. No mail capabilities are
added and no assertion/validation is disabled. No mail is launched by bootstrap
or qualification.

The fourth patch fixes analyzer-confirmed lifetime and missing-input handling in
XML signatures, inspector constraints, table dragging, XML namespace prefixes,
and AppleScript initialization. It also corrects nullable lookup, URL rewrite,
and configuration-migration contracts without changing their nil behavior.
It includes the nullable inspector-tab lookup contract used by the app sidebar.

The block accepts a clean dependency or an exact prefix of the four-patch series.
It rejects staged/untracked files and every other tracked change, including extra
edits inside patched files. Repeating the block preserves an already applied
series. Existing three-patch checkouts upgrade by applying only patch 0004.
It does not reset, stash, or overwrite incompatible work. Parent tracked source,
staged and untracked patch changes are also rejected.
`Checks/check-documents.sh` requires the exact complete four-patch series;
its `sources_match_head` guard rejects incomplete prefixes and unrelated edits.
The three original patches and the public pin are unchanged.

The bootstrap block uses Bash arrays (run it in Bash). Focused recipe/guard
fixtures: `python3 Checks/Analyzer/dependencies/check-packaging.py`.


Mac-only Debug diagnostic command (run from the parent checkout):

```sh
xcodebuild -workspace GraphSketcher-Mac.xcworkspace -scheme ALL \
  -configuration Debug \
  -derivedDataPath /private/tmp/GraphSketcher-build/T53/pass2/DerivedData \
  -sdk macosx -destination 'platform=macOS,arch=arm64' \
  MACOSX_DEPLOYMENT_TARGET=12.0 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  SYMROOT=/private/tmp/GraphSketcher-build/T53/pass2/Products \
  OBJROOT=/private/tmp/GraphSketcher-build/T53/pass2/Intermediates build
```

These command-line settings are explicit development overrides, not migrated
project defaults. Passing the tool tests does not establish a passing workspace
build or native application acceptance.
