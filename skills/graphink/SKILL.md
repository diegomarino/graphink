---
name: graphink
description: Make editable Graphink (.graphink) graph documents from a short JSON spec, and export them or existing .graphink/.ograph files to PNG or PDF, with the graphink command-line tool (macOS). Use when asked to make, draw or plot a graph, chart or diagram as a Graphink document (supply and demand, a function plot, a data series or scatter from CSV, a bar chart, an annotated economics or teaching graph), or to export a Graphink or GraphSketcher file.
license: MIT
compatibility: macOS 12 or later on Apple silicon, with the graphink tool (Graphink.app or the graphink-cli Homebrew cask). The scripts are POSIX sh.
---

# Graphink

Graphink documents are editable graphs: every line, point, fill and label stays a native object the
person can drag and restyle in the app. You never write the file format by hand. You write a small
JSON spec, `graphink create` builds the document with Graphink's own model and writer, `graphink
render` draws it the way the app's File > Export does, and you **look at the PNG** before you hand
anything over.

## Workflow

Paths are relative to this skill's folder.

1. **Find the tool:** `scripts/find-graphink.sh` prints its path (exit 0). Exit 3 means it is not
   installed: show the person the install steps it prints and wait; never run `sudo` or an installer
   yourself. Exit 4 means this is not a Mac: graphink cannot run here, so say so and stop.
2. **Plan** the model or data, the axis ranges and every label before writing JSON:
   [references/workflow.md](references/workflow.md).
3. **Write the spec:** [references/spec.md](references/spec.md). Start from the closest example in
   [assets/examples/](assets/examples/).
4. **Make it:** `scripts/make-graph.sh graph.json` writes `graph.graphink`, `graph.png` and
   `graph.pdf` and prints their paths. Add `--force` to replace them after a fix.
5. **Look** at `graph.png` with your image-viewing tool, check it (workflow.md, "Look"), fix the
   spec and repeat step 4 until it is right.
6. **Hand over** the `.graphink` (editable) and the PNG or PDF.

An error is one line that names the place in the spec, such as
`graphink create: objects[2].points[1] must be a point [x, y], not a number`; fix exactly that.
Messages and fixes: [references/troubleshooting.md](references/troubleshooting.md).

## Rules

- Never write or edit `.graphink` files directly (they are OPC packages); always go through
  `graphink create`.
- Solve the model before drawing (intersections, areas, extrema) and draw exactly those points.
  Never invent data: if the person gives none, use illustrative values and say so in the subtitle.
- Always render and look at a PNG before you say the graph is done: no cut-off text, no labels on
  lines, crossings where the model puts them.
- Never launch Graphink.app to check the work; rendering is the check.
- To export an existing document: `graphink render IN.graphink -o OUT.pdf` (or `.png`, with
  `--scale 2` or `--dpi 300` for sharper images). It never changes its input.
- For editable vector text, experimental `graphink render IN.graphink -o OUT.svg` uses the
  same renderer. Fonts are named, not embedded: the receiving machine needs the same fonts,
  including Kalam for Sketch/Chalkboard. SVG does not yet support document shadows. Always
  inspect the rendered result; SVG text shaping can differ from PDF. For an outline-based
  fallback, install Poppler separately (`brew install poppler`), export PDF, then run
  `pdftocairo -svg OUT.pdf OUT.svg` (not validated here; text becomes uneditable glyph outlines).

## Examples

| File | Shows |
| --- | --- |
| [supply-demand-tax.json](assets/examples/supply-demand-tax.json) | Supply and demand with a per-unit tax: shared intersection points, welfare fills, guides, point labels |
| [time-series-csv.json](assets/examples/time-series-csv.json) | A monthly series from CSV text with a header, a grid, a marked event |
| [function-plot.json](assets/examples/function-plot.json) | f(x) and f′(x) sampled from formulas, axes through the origin, extrema marked |
| [labelled-scatter.json](assets/examples/labelled-scatter.json) | A scatter with a name on every point, a dashed trend drawn by eye, the Studio style |
