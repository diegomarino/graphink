# Third-party source and notice provenance

This records where Graphink's third-party code, notices and fonts come from. It is a
packaging investigation (first made on 2026-11-09 for the executable code and resources),
not a legal certification. The app shows these notices from About Graphink (see
[Notices in the app](#notices-in-the-app)).

## Retained origin and modifications

GraphSketcher retains its original Robin Stewart and Omni credits and source
copyright headers. The root [Omni Source License 2007](../OmniSourceLicense.html)
is retained unchanged and copied into the Mac app. Its SHA-256 is
`b811c202aef202a2b495279424ddc647f46a0faf2e1d2cf2e766a28a67bafc1a`.
Use this supplied license, not a pre-2007 archived Omni license.

OmniGroup comes from public revision
`2be207ce6f7b4f77498bb48dd5e27403fb689eb7`; the exact original license is
[available at that revision](https://github.com/omnigroup/OmniGroup/blob/2be207ce6f7b4f77498bb48dd5e27403fb689eb7/OmniSourceLicense.html).
The four local changes are retained as
[parent-owned patches](../Patches/OmniGroup/README.md), distinct from upstream
authorship. Git history records the migration modifications; no new private
dependency revision replaces that public origin.

The app includes [ThirdPartyNotices.html](../GraphSketcher/App/English.lproj/ThirdPartyNotices.html)
with the original Omni permission/condition/disclaimer, 217 distinct original
Omni copyright lines and the original notice blocks identified below. Credits
links to this local document, which links to the unchanged original license.

## Inspected notice families

All OmniGroup paths below are relative to the pinned dependency.

| Family | Original source of notice | Reason retained |
| --- | --- | --- |
| Omni | Root/framework `OmniSourceLicense.html` and original source headers | Six Omni frameworks, model/OmniStyle and app sources |
| Nisus LinkBack | Parent `LinkBack/Source/LinkBack.h` | LinkBack remains embedded despite deferred interoperability testing |
| SFMT | `Frameworks/OmniFoundation/SFMT/SFMT-LICENSE.txt` | Included through OFRandom.m |
| minizip | `Frameworks/OmniUnzip/unzip/zip.h` and `unzip.h` | Vendored zip/unzip/ioapi implementation; retain its 2005-era notices |
| Apple NetReachability | `Frameworks/OmniFoundation/OFNetReachability.m` | Compiled implementation with its original Apple permission text |
| mpack 1.5 | Original codes.c, identified by `NSData-OFEncoding.m` | Active adapted Base64 implementation; both CMU and Bellcore notice blocks |

The original mpack source was retrieved from
[Debian's preserved mpack 1.5 source](https://sources.debian.org/data/main/m/mpack/1.5-5/codes.c).
Source SHA-256:
`6ebf28c671a29f6c8028c7a542dc902e3710c4270469ec2b89cea484d7c48e47`.
The two original notice blocks together hash to
`4594fff0e053c96fff027d678ea1f4bf79272afa96e819104820e97fb1714a2b`.
The notice texts in `ThirdPartyNotices.html` are byte-exact extracts of these sources
(git blob of the source at the pin, then SHA-256 of the extracted notice):

| Notice | Source | Source blob | Notice SHA-256 |
| --- | --- | --- | --- |
| Omni Source License 2007 | `OmniSourceLicense.html` (whole file) | `3e5916a72b78f5f43d1f8fe47b9239a889fd88aa` | `b811c202aef202a2b495279424ddc647f46a0faf2e1d2cf2e766a28a67bafc1a` |
| SFMT | `Frameworks/OmniFoundation/SFMT/SFMT-LICENSE.txt` (whole file) | `decb299153989ac0fcf3253a430ae5e25ad268ad` | `34a32f97ac258a2d8f9f7c9155504c2e3fb97f1ae4b577e18e08ea07eee1f4ed` |
| Nisus LinkBack | `LinkBack/Source/LinkBack.h` (comment block) | `cc74cba4ed9bd9e4f26a2585750c99deece8695e` | `7ec2b9c3a16fbd15dc886bf99f1b590c91fe3c60ce73acdb4382018cade1012f` |
| minizip unzip | `Frameworks/OmniUnzip/unzip/unzip.h` (comment block) | `1af7c2529706f954bf1a6c16544a802ac8011f64` | `c1a7307a11767da168ddf926e3dc76a68309ff62f69e09a10b1acfabdacbd225` |
| minizip zip | `Frameworks/OmniUnzip/unzip/zip.h` (comment block) | `b63862831e57096436935b253831f712d23a779e` | `13147502873dc3cdbb135b860f67050f435452b666e5a988066bb6cdf8f42c66` |
| Apple NetReachability | `Frameworks/OmniFoundation/OFNetReachability.m` (comment block) | `2522f844fb1a8d8d9f1f8ebe1555e84a356c8709` | `096d38dc2e930d93cd37218f7f43b98d90a9be33fa1be25791b6ef5683b66d2c` |
| mpack 1.5 (CMU, Bellcore) | Debian's `codes.c` above (prefix before the first `#include`) | — | `4594fff0e053c96fff027d678ea1f4bf79272afa96e819104820e97fb1714a2b` |

mpack's adapted Base64 code is active in `NSData-OFEncoding.m` (blob
`fbfb0c0fb38190e8a7243bc4573d46e970cf46cd`), which names mpack-1.5;
`WRAP_FOUNDATION_BASE64_API` is 0, selecting that implementation.

## Scope and exclusions

The actual Debug build supplied 611 direct source inputs (568 C-family and 43
Swift); one was the build-only FixStringsFile tool, leaving 610 shipped-target
inputs. Object/link mappings and 1,229 source/dependency paths were inspected.
This scope is tied to the recorded build, not every file in OmniGroup.

ASCII85 reference files encode85.c/decode85.c exist at the same public pin,
carry Omni authorship and explicitly refer to the supplied 2007 license.
They are referenced by the active NSData implementation, not separately
compiled programs or an unresolved Adobe license.

The unzip source retains an Info-ZIP reference. Both NOCRYPT and NOUNCRYPT are
defined by the actual prefix; dependency records exclude crypt.h. The referenced
encryption implementation is excluded from this build. Do not substitute a
later Info-ZIP license and claim it is the exact historical text for disabled
code. Preserve the original reference comments.

OS-provided libraries are distinct from vendored minizip. A header's RSA MD5
origin sentence alone does not establish a copied RSA implementation: the
inspected digest code uses CommonCrypto. This was not a complete artwork/font,
historical-derivation or Release-symbol audit. Future dependency or target
changes require reassessing which code and notices are shipped.

## Bundled font

Style presets use Kalam Regular (weight 400, PostScript name `Kalam-Regular`), unmodified, from
[google/fonts](https://github.com/google/fonts) revision `3e5667764ccfea32ce0c3d58a3a4756de890adc1`
(`ofl/kalam/Kalam-Regular.ttf`, SHA-256
`57cecb63d4608019371954274ae1d8c397764debd5b19d4a33c1efa4dc923c0b`). Copyright (c) 2014 Indian
Type Foundry, SIL Open Font License 1.1. The complete licence and the file URLs and hashes are
in `GraphSketcher/App/Resources/StyleFonts/{OFL.txt,PROVENANCE.json}`, and the licence is the
eighth notice block of `ThirdPartyNotices.html`. The app registers the font for its own process
with CoreText at startup; nothing is installed. PDF exports embed it; documents reopened
elsewhere follow that consumer's font fallback.

## Notices in the app

About Graphink's Credits link to the bundled `ThirdPartyNotices.html`, which starts with a link
to the original Omni licence and a section index past the 217 copyright lines. AppKit's About
text view resolves the relative link but, for a file URL, only reveals it in Finder. The
app-local `RSAboutPanelController` (named by `OAAboutPanelControllerClass` in `Info.plist`)
intercepts exactly that bundled notices URL: it asks for the default HTTPS application without
opening any URL, opens the bundled file in it and handles the click. A missing browser or a
failed open is logged and consumed, so Finder is never shown. Other links keep the upstream
behavior. No dependency patch, absolute path or entitlement is involved, and the page works
offline.

`Checks/check-about-links.py` checks the packaged bytes, that the first seven notice blocks
and the Omni licence equal the pre-2026 notices (a pinned copy, `Checks/reference/`), the
section anchors, the emitted controller class, and the native link dispatch from an initial and
a relocated fixture (a path with spaces and Unicode). Opening a real browser from the sandboxed
app stays a manual check.
