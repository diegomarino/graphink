# Graphink control glyphs (original vector family)

The toolbar and inspector images of the Mac app: 54 original SVG masters and the PDFs the app
loads. `GraphSketcher/App/RSModernImages.m` registers them before `NSApplicationMain` under
their original names, so nibs and code keep requesting the legacy names.

## Production deliverables

- [54 original editable SVG masters](Production) and
  [machine-readable meanings/provenance index](Production/meanings.json).
- [Loader manifest](../../GraphSketcher/App/Images/Modern/manifest.json) and
  all 54 referenced `gs-<legacyName>.pdf` files in that same Modern directory.
- [Per-file original hashes and dimensions](asset-inventory.json) and
  [provenance](PROVENANCE.md).

Coverage: all 18 toolbar names; all 35 used inspector images/sections; the used
12×51pt error-bar sheet diagram. No fancy-checkbox files, cursors, experimental
badge, branding, app/document icons or dependency assets. All originals and
licenses remain in place. Generated shape/dash menu artwork is Objective-C,
outside these exported resource names.

Toolbar masters use the authorized 24pt grid, 1.5pt rounded strokes and graph
nodes. Inspector point sizes/aspect ratios match the originals: 32pt axis
controls, 24pt section tabs, 19×12/24×12pt line samples, 12pt point/shadow
samples, 14×18pt canvas indicators and 84×12pt arrow illustrations. Tiny
illustrations use a calibrated 1.25pt stroke. All masters contain geometry,
not fonts, embedded legacy art or raster images.

## Loader contract

`Modern/manifest.json` has exactly one `images` array. Every entry contains
exactly `name`, `file`, `width`, `height`, `template`. Names are legacy basenames;
files are unique `gs-<legacyName>.pdf` leaves in Modern; sizes are positive
point dimensions. All 54 entries currently use `template: true`. Reduced alpha
is intentional for contextual axes, transparent-window and disabled previews.

Control meanings and source names live separately in Production/meanings.json,
so the loader schema stays exact. Modern contains only the 54 PDFs and its
manifest: no same-basename PNG/TIFF alternatives. PDFs have their own correct
point-sized page boxes as well as manifest sizing.

The app side (the folder reference, loading before `NSApplicationMain`, the
setSize/setTemplate/setName aliases, visible failures for missing or invalid
resources) is `RSModernImages.m`. Native section labels, tooltips, localization and
accessibility come from the app, not the artwork: the sidebar's sections are labelled
Style, Axes, Canvas and Data. Keep the early registration: existing nib, configuration
and dynamic callers request the original names.

## Reproduce and verify

Use existing Python 3/Pillow, librsvg and Poppler; no new packages were added.
Export reads SVG masters; it does not recreate their geometry from legacy art.
Default export regenerates only the named Modern PDFs and manifest, writing
the manifest after every conversion succeeds. Export failure is nonzero and
partial outputs are retained; do not hand off a failed regeneration.

```sh
python3 UI/Design/export-production-icons.py --help
python3 UI/Design/export-production-icons.py
python3 UI/Design/check-production-icons.py
python3 UI/Design/check-production-rendering.py
```

Use `--output` with a new directory to export a review copy instead. Checks
pin all 54 names and original inspector sizes, the exact loader schema,
source geometry-only elements, one-page PDF boxes, zero raster PDF images,
original hashes, unclipped/nonempty rendered alpha and SVG/PDF alpha agreement.
The rendering check renders every exported PDF in light and dark, using
transient raster intermediates. PDF creation timestamps may vary; the SVG
masters are the reproducible geometric authority. Product builds need none
of these export tools because the PDFs are pre-generated and committed.

## Studies

- [Representative seven-glyph sheet](representative-icons.svg), exported with
  `export-icons.py`.
- [Sidebar study](sidebar-mockup-light-dark.png), with its [editable SVG](sidebar-mockup.svg)
  and [builder](build-sidebar-mockup.py): a 520 × 440 pt canvas beside a 280 pt sidebar with
  the four-section icon and label selector, as later implemented. Its menu presentation and
  sample values were design proposals; the native controls are the app's.

File and render checks establish resource completeness and geometry, not AppKit alias lookup,
custom-cell tinting, Retina optical quality or VoiceOver behavior, which are native checks.
