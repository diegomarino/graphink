# Building Graphink

How to build Graphink and run its checks on a Mac. CI runs the same scripts; what only CI needs
is in [CONTRIBUTING-CI.md](CONTRIBUTING-CI.md). Why the 2014 code needed these steps is in
[architecture/reviving-graphsketcher.md](architecture/reviving-graphsketcher.md).

## Requirements

- An Apple silicon Mac with Xcode 27.2. The scripts check the version (`XCODE_VERSION` in
  `.github/ci.env`) and use `/Applications/Xcode_27.2.app` when it exists, without changing
  `xcode-select`.
- Python 3 and xmllint (both ship with macOS) for the checks.
- No signing certificate, keychain change or Apple developer account: builds are ad-hoc signed.

The project sets a macOS 12.0 deployment target. Graphink is only tested on current macOS
(27.2); the target is not a claim that older versions run it.

## 1. Fetch and patch OmniGroup

Graphink builds against OmniGroup's frameworks, pinned as a submodule at public revision
`2be207ce6f7b4f77498bb48dd5e27403fb689eb7` plus four local patches. From a clean checkout:

```bash
.github/scripts/bootstrap-omnigroup.sh
```

It fetches the pinned revision and runs the bootstrap block in
[Patches/OmniGroup/README.md](../Patches/OmniGroup/README.md), which applies the patches and
refuses any other change in `OmniGroup/`. Running it again is safe. After it, `git status`
shows `OmniGroup` as modified: that is the applied patches.

## 2. Build

```bash
root=$(mktemp -d /private/tmp/graphink-build.XXXXXX)
.github/scripts/build.sh Debug "$root"
.github/scripts/build.sh Release "$root"
```

Each configuration gets its own tree, so Debug and Release never share DerivedData:

| Path | What |
| --- | --- |
| `$root/<Configuration>/Products/<Configuration>/Graphink.app` | the app |
| `…/Graphink.app/Contents/Helpers/graphink` | the `graphink` command-line tool ([tools/cli](../tools/cli/README.md)), built by the `graphink` target the app depends on |
| `$root/<Configuration>/build.log` | the full `xcodebuild` log |
| `$root/<Configuration>/DerivedData`, `Intermediates` | build state |
| `$root/source-sha.txt` | the commit that was built |

The app version (`2026.11.0` style) comes from the latest `vYYYY.M.n` tag through
`scripts/release/version.py`; nothing in the tree records it. `build.sh` is one `xcodebuild`
call of scheme `ALL` in `GraphSketcher-Mac.xcworkspace` with ad-hoc signing
(`CODE_SIGN_IDENTITY=-`); read it for the exact settings.

To run the Debug app: `open "$root/Debug/Products/Debug/Graphink.app"`. To run its command-line
tool: `"$root/Debug/Products/Debug/Graphink.app/Contents/Helpers/graphink" --version` (Debug
builds print OmniBase's two-line assertions banner on stderr first).

To package the tool the way a release does, from the Release build:
`.github/scripts/package-cli.sh "$root/Release/Products/Release/Graphink.app" "$root/dist"`
writes `graphink-cli.zip` and its `.sha256`. For a quick rebuild of only the tool against a Debug
build there is `tools/cli/build.sh` (see its README).

## 3. Run the checks

```bash
logs=$(mktemp -d /private/tmp/graphink-logs.XXXXXX)
scripts/dev/setup-hooks.sh                         # once per clone: pinned linters, git hooks
.github/scripts/checks-fast.sh "$logs/fast"        # no Xcode needed
.github/scripts/checks-toolchain.sh "$logs/toolchain"
.github/scripts/checks-products.sh "$root" "$logs/products"
GUI_CHECKS=1 .github/scripts/checks-products.sh "$root" "$logs/gui"   # plus offscreen windows
```

The product checks run against the Debug build in `$root`. None of them launches Graphink.app;
some compile the app's own objects into small throwaway fixtures. `GUI_CHECKS=1` adds the checks
that create offscreen windows; they need a logged-in session (not SSH only). The table of
checks, and which need what, is in [CONTRIBUTING-CI.md](CONTRIBUTING-CI.md#which-checks-run-where).

Run the checks from a clean checkout: the bootstrap and `Checks/check-documents.sh` refuse
modified or untracked sources in the paths they guard.

### Checks run by hand

The path-algorithm check compiles OmniAppKit's patched `NSBezierPath-OAExtensions.m` directly,
with AddressSanitizer, against the Debug OmniBase and OmniFoundation frameworks, and compares
native quadratic segments with their exact cubic equivalents (patch 0002):

```bash
products="$root/Debug/Products/Debug"
out=$(mktemp -d /private/tmp/graphink-geometry.XXXXXX)
printf '%s\n' '#import <Cocoa/Cocoa.h>' '#import <Carbon/Carbon.h>' \
  '#import <OmniBase/OmniBase.h>' '#import <OmniFoundation/OmniFoundation.h>' \
  '#import <OmniAppKit/OAUtilities.h>' > "$out/prefix.h"
xcrun clang -arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -fblocks -g \
  -fsanitize=address -Wall -Werror -Wno-error=deprecated-declarations \
  '-Wno-#warnings' -DDEBUG -DOMNI_BUILDING_FOR_MAC=1 \
  -DOBJC_OLD_DISPATCH_PROTOTYPES=0 \
  '-DOMNI_BUNDLE_IDENTIFIER=@"com.omnigroup.OmniAppKit"' \
  -include "$out/prefix.h" -F"$products" \
  -framework AppKit -framework OmniBase -framework OmniFoundation \
  -Wl,-rpath,"$products" \
  OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSBezierPath-OAExtensions.m \
  Checks/AppKitChecks.m -o "$out/checks"
"$out/checks"
```

The fixture needs macOS 14 or later to build native quadratic segments. The asset pipeline
checks are listed in [CONTRIBUTING-CI.md](CONTRIBUTING-CI.md#checks-run-by-hand).

## Signing

Builds are ad-hoc signed with the App Sandbox on. Debug uses
`com.diegomarino.Graphink-Development.entitlements`, which adds only
[Disable Library Validation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation)
so the embedded ad-hoc frameworks (no Team ID) load. Release keeps the original entitlements.
Hardened Runtime is set in the project, but Xcode does not apply it to ad-hoc Debug signatures:
Debug's code signature flags are `0x2(adhoc)`, Release's `0x10002(adhoc,runtime)`. Check the
emitted signature (`codesign -dv`) rather than the build setting. Making a release DMG is in
[CONTRIBUTING-CI.md](CONTRIBUTING-CI.md#running-the-checks-locally).

The command-line tool in `Contents/Helpers/graphink` is signed as `com.diegomarino.Graphink.cli`
with no entitlements: it is never sandboxed, because it reads and writes the files named on its
command line. Like the app, an ad-hoc Release build with Hardened Runtime cannot load its ad-hoc
frameworks; build Release with `EXTRA_BUILD_SETTINGS` set to `RELEASE_DISTRIBUTION_SETTINGS` from
`.github/ci.env`, as `release.yml` does, to run it.

## Known limits

- `Checks/check-documents.sh` checks documents Graphink writes today (eight color samples, two
  XML and two ZIP save/reopen cycles each, schema validation) and that the 35 historical
  `.ograph` samples stay byte-identical. It is not a historical compatibility check:
  `--legacy-smoke` still reports seven failures among the 35 samples, the same as the 2014
  code (nonfinite snap parameters, first-load label visibility, an arrow-parent reference).
- The checks exercise production code offscreen. Using the real app (Release runtime, other
  Macs, VoiceOver, Finder and Quick Look) is checked by hand.
