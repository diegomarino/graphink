# Graphink command-line tools

Two commands built on the app's own model framework (`GraphSketcherModel`), with no window and without
launching Graphink.app:

- **`graphink-render INPUT -o OUTPUT`** draws a document to PDF, PNG, JPEG or TIFF the way File ▸ Export
  does. It reads `.graphink` (OPC, and the older XML and ZIP containers) and GraphSketcher `.ograph`, and
  never writes to its input.
- **`graphink-create SPEC.json -o OUTPUT.graphink`** builds a document from a small JSON spec
  ([spec.md](../skills/graphink-documents/spec.md)), saves it with the production OPC writer (with its
  PDF preview), and reopens it with the production reader before it reports success.

The Claude Code skill that teaches an agent to use them is in
[tools/skills/graphink-documents](../skills/graphink-documents/SKILL.md).

## Build

From a clean checkout, after the Debug build in [docs/BUILDING.md](../../docs/BUILDING.md):

```bash
tools/cli/build.sh "$root/Debug/Products/Debug" /private/tmp/graphink-cli
export PATH="/private/tmp/graphink-cli/bin:$PATH"
```

`build.sh` compiles the two tools with clang against the products' frameworks (the way the checks build
their fixtures) into `GraphinkCLI.bundle`, and writes `bin/graphink-render` and `bin/graphink-create`,
which run the tools inside the bundle. The bundle's `Info.plist` is the app's, so the tools register the
same preference defaults, under their own identifier; it declares no document types. Its `Frameworks`
is a link to the products directory, and `Resources/StyleFonts` holds Kalam for Sketch and Chalkboard
documents. Built against Debug products, the tools print OmniBase's two-line assertions banner on stderr.

## Use

```bash
graphink-render Examples/Microeconomics/06-monopoly.graphink -o monopoly.pdf
graphink-render Examples/Microeconomics/06-monopoly.graphink -o monopoly.png --scale 2   # or --dpi 144
graphink-render --info old.ograph                     # page size and pixel size only
graphink-create tools/skills/graphink-documents/examples/function-plot.json -o plot.graphink
```

Raster size is `round(points × dpi / 72)` per side, as in the export panel; the image records its DPI.
An existing output is refused unless `--force`. Exit status: 0 success, 1 read, spec, render or write
failure (one line on stderr), 2 invalid arguments.

## How the render matches Export

`graphink-render` holds the graph in an `RSGraphEditor`, as `GraphDocument` does, sets its bounds to the
canvas, runs the editor's layout pass (`prepareForDisplay`: whitespace, axis labels, owned labels) and
then draws exactly what `RSGraphView -drawRect:` draws when not drawing to screen: the background and
`drawAllGraphElementsExcept:nil`. The PDF is one page the size of the canvas. Raster images use the
export's bitmap (8-bit RGBA, `NSCalibratedRGBColorSpace`, ImageIO with the DPI recorded).

One deliberate difference: `RSGraphView -bitmapImageRepWithResolution:` scales the context by
pixels/points after `+graphicsContextWithBitmapImageRep:` has already done so, which draws only the
lower-left part of the page above 72 DPI. `graphink-render` scales once.

The stored geometry is drawn as saved: snapped points are not recomputed (the app does that after
selection changes). That changes nothing for the examples and up to a few hundred pixels in seven of the
historical samples.

## Checks

```bash
python3 tools/cli/check-cli.py --products "$root/Debug/Products/Debug" --output NEW_DIR
```

It builds the tools, renders every `.graphink` under `Examples/` and the 35 historical samples to PNG and
PDF, and checks that none of them changed. Each example's PDF, rasterized the way the previews were made,
must equal its `Previews/*.png` pixel for pixel (all 31 previews); the direct PNG (Generic RGB, like the app's export) may
differ only by antialiasing and color rounding. It creates the skill's example specs, runs
`docs/format/check-opc.py` and the RELAX NG schema on them, renders them, and checks that bad specs and
arguments are refused without writing anything. `.github/scripts/checks-products.sh` runs it.
