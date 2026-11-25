# The `graphink` command-line tool

`graphink` creates and exports Graphink documents without opening the app, on the app's own model
framework (`GraphSketcherModel`):

```
graphink render IN -o OUT.{pdf,svg,png,jpg,tiff} [--dpi N | --scale N] [--force] [--info]
graphink create SPEC.json -o OUT.graphink [--force]
graphink --version | help [render|create]
```

- **`render`** draws a `.graphink` (OPC, and the older XML and ZIP containers) or a GraphSketcher
  `.ograph` the way File ▸ Export does. It never writes to its input.
- **`create`** builds a document from a JSON spec (the agent skill's
  [spec](../../skills/graphink/references/spec.md)), saves it with the production OPC writer (with
  its PDF preview) and reopens it with the production reader before it reports success.

Exit status: 0 success, 1 read, spec, render or write failure (one line on stderr), 2 invalid
arguments. An existing output is refused unless `--force`.

## SVG (experimental)

`graphink render in.graphink -o out.svg` records the shared renderer's paths and editable
text. SVG uses the canvas size in points; `--dpi` and `--scale` only affect raster output.
The app's Export menu does not offer SVG yet. SVG currently refuses documents with nonzero
shadows. Text uses the saved font family, size, bold/italic traits and TextKit line positions.
Fonts are named, not embedded: install Kalam (in the app's `Contents/Resources/StyleFonts`,
licensed under the included OFL) to view Sketch/Chalkboard exports faithfully. An editor's
font substitution or text shaping can change the result. See [the experiment](../../docs/svg-export.md).

For a PDF-based alternative, install Poppler separately (`brew install poppler`) and run:

```bash
graphink render in.graphink -o out.pdf
pdftocairo -svg out.pdf out.svg
```

This converts text to glyph outlines, so it loses text editing. Poppler is GPL and is not
bundled with Graphink. This conversion command has not been validated by this experiment.

## Where it comes from

The Xcode target `graphink` in `GraphSketcher/App/GraphSketcher.xcodeproj` builds it from
`GraphSketcher/App/CLI` plus the app files it shares (`RSGraphExport`, `RSStylePresets`,
`RSPageGeometry`). The app target depends on it and copies it, signed, to
`Graphink.app/Contents/Helpers/graphink`. Its `Info.plist` is made from the app's by
`CLI/make-info-plist.py` (only OmniFoundation's registrations, identifier
`com.diegomarino.Graphink.cli`, no document types) and embedded in the binary
(`__TEXT,__info_plist`). The rpath `@executable_path/../Frameworks` finds the app's frameworks, and
the tool registers the style fonts of the bundle that contains it (`Helpers/../..`, after resolving
symbolic links), so the same binary works in the app, from `graphink-cli.zip` (the same layout,
made by `.github/scripts/package-cli.sh`) and through a link on `PATH`. It is not sandboxed: it
reads and writes the files you name.

## One export, two callers

File ▸ Export and `graphink render` both call `RSGraphExport` (`RSGraphPDFData`,
`RSGraphRasterData`), and `RSGraphView -drawRect:` uses its `RSDrawGraphForExport` whenever it is
not drawing to the screen (saved previews, copies, EPS, printing). The tool holds the graph in an
`RSGraphEditor`, as `GraphDocument` does, sets its bounds to the canvas and runs the editor's
layout pass (`prepareForDisplay`), as the graph view does before it draws. Raster size is
`round(points × dpi / 72)` per side, and the image records its DPI.

The stored geometry is drawn as saved: snapped points are not recomputed (the app does that after
selection changes). That changes nothing for the examples and up to a few hundred pixels in seven of
the historical samples.

## Development build

The checks and releases use the Xcode target. To try a change to the tool without rebuilding the
app, compile it against a Debug build (docs/BUILDING.md):

```bash
tools/cli/build.sh "$root/Debug/Products/Debug" /private/tmp/graphink-cli
export PATH="/private/tmp/graphink-cli/bin:$PATH"
graphink render Examples/Microeconomics/06-monopoly.graphink -o monopoly.png --scale 2
```

Built against Debug products, the tool prints OmniBase's two-line assertions banner on stderr.

## Checks

- `tools/cli/check-cli.py --products "$root/Debug/Products/Debug" --output NEW_DIR` (products tier)
  checks the helper in the built app and the same tool from `graphink-cli.zip` (packaged and
  unpacked by the check): signature, identifier, no sandbox, only the bundled frameworks in
  `otool -L`, an embedded `Info.plist` without document types. It renders every example and the 35
  historical samples to PNG and PDF read-only; each example's PDF, rasterized the way the previews
  were made, must equal its `Previews/*.png` pixel for pixel. It creates the example specs
  (the agent skill's `skills/graphink/assets/examples`), runs `docs/format/check-opc.py` and the
  RELAX NG schema on them, runs the skill's `make-graph.sh` on one with the helper on `PATH`, and
  checks that bad specs and arguments are refused without writing anything.
  The zip's copy must render byte-identical PNGs and create identical documents.
- `Checks/check-cli-app.py` (`GUI_CHECKS=1`) opens every example in production app objects, draws
  it in an offscreen window and takes File ▸ Export's data: `graphink render` must produce the
  same PNG bytes at 72 and 144 DPI and the same PDF pixels. It also checks the Install Command-Line
  Tool… menu item and window: the command names the running bundle's helper, survives a path with
  shell-special characters (read back by sh, and by interactive zsh and bash, so `!` is covered),
  and Copy puts exactly it on the pasteboard.
- `Checks/check-export-paths.py` (`GUI_CHECKS=1`) covers the drawing paths that go through
  `RSGraphView -drawRect:`: with everything selected, the view's PNG export must equal
  `graphink render`'s, and the view's PDF, Copy as Image's PDF and the saved preview must equal its PDF
  pixel for pixel (Copy's PNG and TIFF need an on-screen window, so offscreen their absence is
  recorded). With `--base-root`, `--base-products` and `--base-objects` from a build of another
  revision it also compares every one of these outputs with that revision's: against main before
  `RSGraphExport` (401fa55), all 170 outputs of the 34 examples were identical.
