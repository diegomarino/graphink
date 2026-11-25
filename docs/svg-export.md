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
