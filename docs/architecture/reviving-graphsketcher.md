# Reviving GraphSketcher

GraphSketcher was open-sourced in 2014 for Xcode 5.1, OS X 10.8 and iOS 7, built against a 2014
OmniGroup checkout. Twelve years later none of that toolchain exists. This note records what had
to change so the same Objective-C code builds and runs on current macOS (Xcode 27.2, macOS 27.2,
Apple silicon), and what was left alone on purpose. The first 26 commits of this repository are
the untouched 2014 history; everything after them is the revival.

The guiding choice was to keep the app what it was: Objective-C and AppKit, manual reference
counting, Omni's frameworks, the original document model. No rewrite, no ARC conversion, no
Swift. Changes are as small as current macOS allows, so `git blame` still leads to the original
authors for most lines.

## OmniGroup: a newer public pin and four patches

The 2014 submodule (`40fbf9d1`, over `git://`, which GitHub no longer serves) does not build with
current Xcode. The submodule now points over HTTPS at public OmniGroup revision `2be207ce` (2022),
unmodified upstream, and four patches in `Patches/OmniGroup/` are applied on top by a bootstrap
that refuses any other change. There is no private fork.

| Patch | Why it exists |
| --- | --- |
| `0001-sign-fixstringsfile-before-tests` | The build compiles a small tool, `FixStringsFile`, and runs its tests before Xcode signs it. arm64 code must be signed to run, so the patch ad-hoc signs the tool first. Tests and app signing are unchanged. |
| `0002-modern-mac-compiler-compatibility` | Current clang rejects or warns about code the 2014-2022 compilers accepted: missing `(void)` prototypes, implicit enum conversions, missing declarations and imports. It also handles a new AppKit behaviour: since macOS 14 `NSBezierPath` can contain quadratic curve elements, which Omni's path algorithms (hit testing, lengths, intersections, plist serialization) did not know. Each quadratic is presented to them as its exact cubic equivalent; stored paths keep the cubic schema. Two K&R prototype warnings in the vendored minizip stay visible. |
| `0003-defer-mail-validation` | When OmniAppKit loaded, a Debug-only check asserted that a sandboxed app has the Apple Events and Mail scripting entitlements, which Graphink does not request, so every sandboxed Debug launch failed it. The check now runs only when the AppleScript mail path is used. No entitlement is added and no check is removed. |
| `0004-analyzer-contracts-and-lifetimes` | Fixes the Clang static analyzer found in the pinned frameworks: object lifetimes and missing-input handling (XML signatures, inspector constraints, table dragging, XML namespace prefixes, AppleScript setup) and nullability contracts, including the nullable inspector-tab lookup the sidebar relies on. Nil behaviour is unchanged. |

## The build

- One workspace, `GraphSketcher-Mac.xcworkspace`, scheme `ALL`: the app plus the Omni frameworks
  it embeds and LinkBack. Project-level settings come from small `Graphink-Project-*.xcconfig`
  files that include Omni's global configurations.
- arm64 only, deployment target macOS 12.0 passed on the command line. Nibs no longer carry
  their own obsolete deployment target and inherit the build's.
- `ENABLE_DEBUG_DYLIB=NO` keeps a Debug app's code in its main executable, as in Release,
  instead of the separate debug dylib recent Xcode creates.
- Ad-hoc signing with no Team ID, so Debug adds only the Disable Library Validation entitlement
  to load its embedded ad-hoc frameworks. The App Sandbox, user-selected file access and
  printing entitlements are the original ones. Hardened Runtime is set but not effective in
  ad-hoc Debug signatures. Release DMGs are ad-hoc too until Developer ID signing exists.
- The app version is injected at build time from git tags (calendar `YYYY.M.n`); no file in
  the tree carries it.

## The code

- **Colors.** The model used OmniQuartz's `OQColor`. It now stores native `NSColor` throughout
  (sRGB, gray, Display P3, CMYK, named, pattern and extended colors), with checks that every
  kind survives XML and ZIP save and reopen.
- **Removed APIs.** OmniFoundation's `OFNaN` sentinel is gone; `NSDecimalNumber notANumber`
  replaces it in OmniStyle. An `NSInputContext` crash workaround copied from OmniOutliner,
  which swizzled a private class, was removed. `NSApp` calls in Mac code became
  `[NSApplication sharedApplication]`.
- **Saving.** Saving renders the live graph view into a PDF preview, which AppKit requires on
  the main thread, so documents no longer write asynchronously.
- **Assertions.** OmniFoundation turns every `NSAssert` into a crash, AppKit's own included.
  Current AppKit asserts internally in situations an accessibility client can trigger; see
  `AppController.m` for the policy that lets those through without hiding Graphink's own.
- **Lifecycle fixes** found on the way: controller and declaration repairs, label edits flushed
  before the field editor goes away, tracking rectangles kept valid during view setup, initial
  window setup and preview updates kept out of the undo history.

## Identity and documents

The app became Graphink, `com.diegomarino.Graphink`, with its own document type: `.graphink`,
exported UTI `com.diegomarino.graphink.document`. `.ograph` keeps GraphSketcher's
`com.graphsketcher.graphdocument`, now imported, so Graphink never outranks an installed copy of
the original. See [identity-and-naming.md](identity-and-naming.md).

New documents are written as OPC packages ([../format/opc-v1.md](../format/opc-v1.md)): a
versioned envelope with a required-feature list around the original native XML payload. The
2014 format had no version, aborted on an unknown namespace and silently dropped unknown
fields. Old `.ograph` files (XML or ZIP) open through the same reader and keep their format on a
normal Save.

## Qualification

The revival added offscreen checks that
compile production sources or the app's own objects into throwaway fixtures, without launching
the app: document round trips for every color kind, the 35 historical `.ograph` samples kept
byte-identical, the sidebar, viewport, paper sizes, New From, Find, keyboard loop, snap
distances, the assertion policy, and a native qualification set (crash recovery with AppKit's
real autosave timer, adopting legacy styles, the shared font and color panels with two
documents, the full-screen frame). The app itself was checked by hand on a separate Mac in
several rounds; those found real defects the offscreen checks could not (a crash under an
accessibility client, Tab never reaching the sidebar), each then covered by a check. The full
list is in [../CONTRIBUTING-CI.md](../CONTRIBUTING-CI.md#which-checks-run-where).

## Left as is, on purpose

- **About 180 deprecation warnings in the 2014 code.** About 100 are renamed constants with a
  drop-in replacement (`NSOnState`, `NS*KeyMask`, event types, calendar units), to be replaced
  later in one mechanical commit listed in `.git-blame-ignore-revs`. The rest (pasteboard types,
  `lockFocus`, `colorUsingColorSpaceName:`, sheets and alerts) need real rewrites. A few 2026
  lines keep deprecated calls whose replacement is not equivalent; see
  [../CONTRIBUTING-CI.md](../CONTRIBUTING-CI.md#known-compiler-warnings).
- **Internal names.** Classes, paths, project and framework names and the XML namespace stay
  GraphSketcher.
- **Not built or not tested.** The Quick Look generator and Spotlight importer sources are kept
  but no longer built into the app, so they were not revived. The iPad
  sources are kept as history. LinkBack is embedded but its interoperability is untested.
- **Historical documents.** The 35 original samples are never modified. Seven of them still fail
  the legacy smoke test exactly as they did in 2014; the revival guarantees what Graphink
  writes today, not every quirk of old files.
