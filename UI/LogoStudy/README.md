# GraphSketcher logo study - B1 selected

The user selected **B1 / Slightly smaller** on 2026-11-12: the Bezier G with
seven blue nodes of radius 1.7 and a 1.75-unit stroke. Geometry, anchor
positions and GraphSketcher wordmark remain unchanged.

Selected editable masters:

| Appearance | Symbol | Wordmark lockup |
| --- | --- | --- |
| Light | [SVG](Masters/bezier-g-nodes-medium-symbol-light.svg) | [SVG](Masters/bezier-g-nodes-medium-lockup-light.svg) |
| Dark | [SVG](Masters/bezier-g-nodes-medium-symbol-dark.svg) | [SVG](Masters/bezier-g-nodes-medium-lockup-dark.svg) |

Matching PDFs and 1x/2x PNGs use the same basenames in `Exports/`.
This selection supersedes the historical "pending human choice" labels in
the unchanged review artifacts. All alternatives remain retained for reference.
The Mac app's `GraphSketcher/App/GSAppIcon.icns` and `GSDocIcon.icns` are byte copies of the
delivery package below; the GraphSketcher-era icons are kept in `UI/LegacyMacIcons`.

The selected B1 macOS/iPad delivery package is in `Delivery/`
([delivery sheet](Delivery/preview-delivery.png),
[Apple appearance renders](Delivery/preview-apple-appearances.png)):

| Path | Purpose |
| --- | --- |
| `Delivery/GraphSketcher.icon/` | Editable Icon Composer document shared by Mac and iPad: two SVG layers (curve and nodes), default/dark fills, system clear/tinted renderings. No bundled typefaces. |
| `Delivery/macOS/Assets.xcassets/` | Ten-slot Mac AppIcon catalog: 16, 32, 128, 256, 512 points, each 1x/2x. |
| `Delivery/macOS/GSAppIcon.icns`, `GSDocIcon.icns` | Native ICNS for the app and for documents (with a newly drawn folded-page carrier); the app's `Info.plist` names these leaves. |
| `Delivery/macOS/*.iconset/` | Both editable PNG iconsets, ten slots each, through 1024 pixels. |
| `Delivery/iPad/` | Modern single-size AppIcon catalog, opaque legacy PNG fallbacks and the `Document-ograph-*` / `DocumentIconGraph-*` document icons the historical iPad plist and code name. |
| `Delivery/Branding/` | The four selected B1 symbol/wordmark masters, their PDFs and transparent 1x/2x PNGs. |
| `Delivery/Sources/` | Editable SVGs of the app background, document carrier, dark/tinted forms and the separated B1 layers. |
| `Delivery/checks.json`, `apple-validation.json` | Artifact and source hashes, PNG bounds, native ICNS readback, asset-only compilation and twelve native appearance renders. |

All artwork derives from the four selected `Masters/bezier-g-nodes-medium-*` SVGs with a
uniform transform (`translate(102.4 102.4) scale(25.6)` on a 1024 canvas); the path, seven
anchors, 1.75-unit stroke and 1.7-unit node radius are unchanged, and nothing copies Omni
artwork, SF Symbols or system templates. App icons are symbol-only; only the Mac ICNS fallback
has a pre-drawn tile and margin. `Delivery/build-assets.py` and `verify-apple-assets.py`
rebuild and check the package. The Mac app uses the ICNS route; the historical iPad project
was not migrated.

The latest comparison is [the B refinement](preview-g-b-refinement.png),
with [editable sheet](preview-g-b-refinement.svg) and [PDF](Exports/preview-g-b-refinement.pdf).
B1 reduces the blue node radius from 2 to 1.7 (15% smaller). B2 retains radius 2
and changes nodes to pure black on light, with a white-node dark equivalent.
The path, stroke and all seven anchors remain identical to B. Existing B and
all previous artwork/exports are preserved.

The earlier comparison is [the minimal G node variations](preview-g-variants.png),
with [editable sheet](preview-g-variants.svg) and [PDF](Exports/preview-g-variants.pdf).
A retains the current G; B enlarges nodes from radius 1.4 to 2; C changes only
their fill to warm terracotta (`#bf603e` light, `#ffb27a` dark); D combines both.
The Bezier path, line width, seven anchor coordinates and wordmark layout are
identical in all four. The current G and all previous studies remain unchanged.

The previous refinement is [the G with actual Bezier anchors](preview-g-nodes.png),
with [editable construction sheet](preview-g-nodes.svg) and
[PDF](Exports/preview-g-nodes.pdf). It marks every segment endpoint and join.

Earlier explorations are in [the second-round comparison](preview-round-02.png), also available
as [editable SVG](preview-round-02.svg) and [PDF](Exports/preview-round-02.pdf).
The first two directions remain in [the original comparison sheet](preview-sheet.png), also editable as
[SVG](preview-sheet.svg) and exported as [PDF](Exports/preview-sheet.pdf).

- **01 / Curve + nodes:** an asymmetric arch with three solid points. The
  broader stroke and open ends suggest drawing a curve by hand.
- **02 / Graph + axes:** an open coordinate frame and a three-point rising
  line. Quieter and more literal, with one accent endpoint.

- **03 / Simplified heritage:** the original app icon's crossing graphs and
  warm filled area, reduced to fresh geometry on open axes. Paper, grid,
  perspective and pen are omitted.
- **04 / Bezier G:** an open G drawn as cubic Bezier segments, with graph
  nodes on its ends and lower curve. The symbol is drawn geometry, not type.
- **04b / GS variation:** separately drawn G and S curves in one square.
  A secondary exploration; denser than the G at 16 points.

- **04 refinement / G with actual anchors:** four cubic segments and two
  straight segments, with all seven on-curve anchors marked at radius 1.4.
  Cubic joins have aligned tangent handles. The construction sheet shows
  off-curve controls as hollow squares, with a thinner curve for clarity;
  handles are excluded from symbol and lockup exports. The prior G is retained.

All directions echo the existing UI family's round caps, round joins and
solid graph nodes. The light accent is `#27769a`; dark uses `#80c8e8`.
Colors are study choices. The dark versions require a dark surface; transparent
exports do not contain their own backdrop.

## Files and editing

`Masters/` contains forty-four editable SVGs: eleven marks, each with symbol-only
and exact-name GraphSketcher lockup, each in light and dark appearances. Symbol
canvases are 32 x 32; lockups are 340 x 64. Dimensions are design points.
The SVG coordinate canvas maps to one pixel per point for the 1x PNG exports.
The lockup symbol is positioned at (8, 8) and enlarged 1.5x; text begins at x=72.

`Exports/` contains forty-four transparent PDF assets with point-sized page boxes,
forty-four transparent 1x PNGs, forty-four transparent 2x PNGs, and five comparison PDFs.
The sheets show the symbols at 16, 24 and 32 points as well as enlarged forms.
There is no app-icon container, document icon, alternate name or branding system.

SVGs are the editing authority. Edit their path coordinates, circles or live
text directly. Keep the two appearance geometries in sync. Each sheet is a
standalone composition; update its corresponding inline geometry if a master
changes. Re-export and verify using the installed tools:

```sh
python3 UI/LogoStudy/export-and-check.py
```

This command writes only this directory's named exports, preview PNGs and
`checks.json`; it also leaves a PDF-rendered proof in
`/private/tmp/gs-logo-preview-sheet-pdf-proof.png` and
`/private/tmp/gs-logo-preview-round-02-pdf-proof.png` and
`/private/tmp/gs-logo-preview-g-nodes-pdf-proof.png` and
`/private/tmp/gs-logo-preview-g-variants-pdf-proof.png` and
`/private/tmp/gs-logo-preview-g-b-refinement-pdf-proof.png` for inspection. It does not generate
or overwrite SVG masters. No new dependencies were installed. It uses existing
Python/Pillow, librsvg and Poppler. PDF creation timestamps can vary.

## Provenance and typography

Created 2026-11-12 by the GraphSketcher logo-study designer agent, in the
permanent `ui-logo` worktree on `ui/logo-study`, based on
`8bf9896ba0abedd1dd73a38e20c9bd53bc722154`.

The first-round symbols are original hand-authored vector coordinates: an explicitly
constructed cubic Bezier arch and circles; a separately constructed axes
polyline, plotted polyline and circles. No Omni art was traced, imported or
transformed. No SF Symbols, stock logo, raster generation, downloaded artwork
or external visual reference was used for that first round. The existing files read for stylistic
context were `UI/Design/representative-icons.svg`, the Production draw,
interpolate and axes inspector masters, and the Design README/provenance and
export scripts. Those sources were preserved.

Round 02 follows the user's request to simplify the original icon and explore
G / GS. `GraphSketcher/App/GSAppIcon.icns` was read as a visual reference through
a temporary PNG conversion; the source was not modified or included in these
exports. The heritage mark is a conceptual reinterpretation of its crossing
plots and warm filled area, **not claimed as an independently invented motif**.
All of its vector coordinates are newly hand-authored, without image tracing,
path extraction or embedded source art. The G and GS symbols are newly drawn
Bezier paths, not font outlines. The original eight masters, their exports
and the first comparison sheet remain byte-identical to the first commit.
The G anchor refinement adds new hand-authored geometry and does not modify
previous artwork or exports.
The warm area uses `#d36651` in light and `#f0947d` in dark at 20% opacity.

The wordmark is the exact text **GraphSketcher**, set in the existing system
**Helvetica Neue Regular**. This typeface and lettering are **not original
artwork**. Fontconfig resolved the installed `HelveticaNeue.ttc`; no fonts were
downloaded and no standalone font files are bundled. SVG text remains live and
requires that system typeface for identical rendering. Cairo embeds a font
subset inside lockup/sheet PDFs for portable appearance; these are document
resources, not supplied font files. Symbol-only masters/PDFs contain no text.
No licenses or notices were added, removed or changed by this study, and this
note does not certify trademark availability or assign a new license.

## Verification boundary

`checks.json` records artifact hashes, renderer identity and per-master 1x/2x
pixel dimensions and ink bounds. The checker verifies forty-four SVG viewBoxes,
exact lockup naming, symbol control hull/circle bounds, nonempty alpha with
clear canvas margins, padded-viewBox renders to detect hidden clipping, and
all forty-nine PDF page counts and boxes. For the refined G it also
compares the ordered circle centers with every path endpoint and join, and
checks alignment and direction of consecutive cubic tangent handles. G variants
also require the same path data and stroke width as the accepted geometry. Poppler independently renders each asset
PDF at 1x and 2x and checks its nonempty ink bounds with clear margins.
The curve stays inside the convex hull of its control points; round stroke
expansion also stays inside the canvas. Lockup text bounds are verified from
renders rather than a claimed font-independent measurement.

All SVG and independently rendered PDF comparison sheets were visually
inspected for text, spacing, small-size symbols and light/dark appearance.
This establishes bounded artifact checks, not human preference, legal
clearance, Retina-device acceptance or native app behavior. No native app was
launched, no build was run, and no production source or resource was changed.
