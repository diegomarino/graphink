# Native SVG export experiment (#16)

This experiment follows option (a): let the existing renderer produce the geometry,
and record its drawing operations. PDF conversion remains a useful fallback; generating
SVG from the document model would duplicate layout and is out of scope.

## Drawing map

`RSDrawGraphForExport` resets the mapper's curve cache, draws the background/grid,
then calls `drawAllGraphElementsExcept:nil`. Its drawing leaves are:

| Renderer operation | Drawing leaf |
| --- | --- |
| Background | `drawBackgroundWithColor:` → rectangle fill |
| Grid | `drawGrid` → two stroked paths |
| Bars, points, hollow markers, short lines | `RSVertex(Rendering) drawUsingMapper:` → path fills, including the hollow marker's background |
| Fills (including degenerate fills) | `drawFill:inProgress:` → filled or stroked paths |
| Axes, ticks, arrowheads | `drawAxis:` → stroked axis/tick path, filled arrowheads |
| Lines, dashes, endpoint caps, arrow/railroad decorations | `drawLine:` → stroke and fills |
| Axis labels and user labels | `drawLabel:` → `RSText drawAtPoint:baselineRotatedByDegrees:` → attributed string drawing |

All shape construction, rotation of path coordinates, dash selection, label positioning,
axis formatting and whitespace calculation stay with the renderer/mapper. Other stroke,
fill and color calls in these files draw selection/tool feedback and are outside export.
There are no image or gradient drawing leaves on this path. Debug-only text bounds are
disabled. Path helpers construct geometry but do not paint it.

Two existing behaviors need care: `drawLine:` culls against the union of screen bounds,
and `drawAllGraphElementsExcept:` invokes the shadow methods. The experiment must not
change either for existing outputs. Nonzero shadows need a separate fidelity decision.

## Seam and implementation sequence

1. Introduce `RSDrawing`: stroke/fill a fully styled path with an explicit color,
   fill a rectangle, draw an attributed string at a point and rotation. With no backend,
   execute the same AppKit operations as today. Scope a backend to the current thread,
   restore it even after exceptions, and allow nested scopes. Route every export leaf
   above through it; leave screen feedback alone. Commit as a refactor.
2. Implement an SVG backend in `RSGraphExport.m`, preserving draw order, fill rule,
   alpha, stroke width, dashes/phase, caps, joins and miter limit. Flip the graph's
   y-up coordinates once; counter-flip text. Use AppKit's layout manager for text
   line fragments and attribute runs, referencing fonts by family/weight/style.
3. Add `.svg` to `graphink render`, using the shared export entry point after normal
   layout. Keep the app's Export menu unchanged. Commit the feature with focused checks.
4. Render every example, rasterize SVG offscreen using WebKit, compare against PDF
   at the same resolution, and report actual differences. Run the existing fast,
   toolchain and GUI-enabled product checks; compare existing exports with the base.
5. Preserve a small report and worst-case images, remove owned builds/temporary data,
   and write the requested handoff with remaining work and a recommendation.

## Verification focus

The focused checks should catch lost geometry/style, wrong y direction or rotated text,
flattened/noneditable text, multiline baseline errors, XML metacharacters, fonts with
bold/italic traits, output overwrite/input protection, and a backend leaking into later
PDF/PNG draws. Existing comparators, historical samples and baselines remain untouched.

## Current experiment

`graphink render INPUT -o OUTPUT.svg` now records native geometry and text. The default
seam was compared against a build of main (8d59f38): all 170 exports of the 34 examples
matched exactly (PNG pixels and rasterized PDF pixels). The recorder references fonts;
it does not embed them. It rejects nonzero document shadows with a PDF fallback message.

Run the additional check separately from the existing product checks:

```bash
python3 Checks/check-svg-export.py --products "$root/Debug/Products/Debug" --output NEW_DIR
```

The check renders all 34 examples plus disposable Kalam and Medium-weight text fixtures,
rasterizes SVG using an unshown WebKit view at 2×, and reports every pixel comparison in
`report.json` with PDF/SVG/difference PNGs. It supplies Kalam to WebKit using checker-only
CSS, modeling an environment with that font available. The exported files contain no
font data. No tolerance or allowlist hides discrepancies. `--structure-only` skips the
rasterizer, and `--tool` can select a development helper.

The remaining fidelity work is concentrated in text. AppKit string drawing and TextKit
can choose different baselines when a line contains font fallback characters (for example
the welcome document's ⌘ symbols), and browser shaping can differ. Rich-text decorations,
explicit kerning, bidirectional text, ligatures across attribute boundaries and unusual
paragraph alignment need further qualification. Scientific notation's reduced font and
baseline offsets pass through the same layout manager, but are not a general promise of
rich-text equivalence. SVG retains real text nodes; Illustrator/Figma import and editing
have not been tested. Zero-width hairline strokes are another unqualified edge case.

For portable Kalam output, an opt-in embedded `@font-face` subset would avoid installation
requirements; the bundled font's OFL permits redistribution under its terms. Browser
support is straightforward, but an SVG editor's support for embedded fonts must be tested.
Naming the font remains the most interoperable editing option when it is installed.

Adding the app Export menu item would require registering the SVG export type, teaching
the export panel and save path to call `RSGraphSVGData`, localizing its label, and adding
offscreen menu/export checks. It does not require document-format changes or new layout.
