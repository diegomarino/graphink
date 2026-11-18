---
name: graphink-documents
description: Create Graphink (.graphink) graph documents from a JSON spec and render them to PNG or PDF with the graphink-create and graphink-render command-line tools. Use when asked to make, draw or plot a graph, chart or diagram as a Graphink document (supply and demand, a function plot, a data series or scatter from CSV, a bar chart, an annotated economics or teaching graph), or to export an existing .graphink or .ograph file to PNG or PDF.
---

# Graphink documents

Graphink documents are editable graphs: every line, point, fill and label stays a native object the
person can drag and restyle in the app. You never write the file format by hand. Write a small JSON spec,
let `graphink-create` build the document with Graphink's own model and writer, render it with
`graphink-render`, then **look at the PNG** before you hand anything over.

## 1. Find the tools

```bash
command -v graphink-create graphink-render
```

If they are not on `PATH`, look for a build (`*/bin/graphink-create` under the directory the person
named, or `/private/tmp/graphink-cli*`). To build them you need the Graphink repository, Xcode and a
Debug build; from the repository root:

```bash
.github/scripts/bootstrap-omnigroup.sh
root=$(mktemp -d /private/tmp/graphink-build.XXXXXX)
.github/scripts/build.sh Debug "$root"                 # about 4 minutes
tools/cli/build.sh "$root/Debug/Products/Debug" /private/tmp/graphink-cli
export PATH="/private/tmp/graphink-cli/bin:$PATH"
```

Never launch Graphink.app to check your work: render instead. Built against a Debug build, the tools
start with a two-line `*** Assertions are ON ***` banner on stderr; ignore it.

## 2. Plan the graph

Before writing JSON, decide and write down (in `$comment`) what the graph must show:

- **The model or data.** For economics, solve it first: equations, intersections, areas. Every point you
  draw must be consistent with them (an equilibrium is where the two lines really cross). For data, keep
  the source and say so in a label if it will be shared.
- **Axis ranges and steps.** Ranges a little beyond the content (about 10%), round steps giving 5–12 ticks.
  Use a range that starts above 0 (years) or a log axis only when the data needs it.
- **What each label says and where it goes.** Labels are placed in data coordinates; put them in empty
  space next to what they name, not on top of lines.

## 3. Write the spec

The full reference is [spec.md](spec.md). The shape:

```json
{
  "graphink": 1,
  "$comment": "Demand P = 14 - Q, supply P = 2 + Q/2; equilibrium (8, 6).",
  "title": "Market Equilibrium",
  "x": {"title": "Quantity Q (units per week)", "min": 0, "max": 14, "step": 2},
  "y": {"title": "Price P (dollars per unit)", "min": 0, "max": 16, "step": 2},
  "objects": [
    {"type": "line", "points": [[0, 14], [8, 6], [14, 0]], "color": "blue", "label": "D"},
    {"type": "line", "points": [[0, 2], [8, 6], [14, 9]], "color": "teal", "label": "S"},
    {"type": "point", "at": [8, 6], "label": "E"}
  ]
}
```

Object types: `line` (polyline or `"curve": "curved"`), `function` (`"f": "x^2/4 - 1"`, sampled),
`series` (data points, from `points` or `csv` text), `point`, `fill` (shaded polygon), `bars`, `label`
(free text, at data coordinates or `page` points). Colors: `ink blue teal orange purple red green gray`
or `#RRGGBB`.

Rules that keep graphs correct and editable:

- Use **straight lines through computed points** for exact relationships: `function` for formulas,
  `line` with the solved intersections for economics curves (include the intersections as vertices, so
  the shared point moves both curves in the app). Use `"curve": "curved"` only for a hand-drawn shape
  where overshoot does not matter (an indifference curve sketch).
- Fill corners go **in order around the region**, using the same coordinates as the lines that bound it.
- Guides (dotted lines to the axes) use `"color": "guide", "width": 1, "dash": "dotted"`.
- Label each curve once. Short names (`D`, `S`, `MC`, `f(x)`) as the line's `label`; longer notes as
  `label` objects in empty space.
- Never invent data. If the person gives none, make illustrative values and say so in the subtitle.

## 4. Create, render, look

```bash
graphink-create graph.json -o graph.graphink
graphink-render graph.graphink -o graph.png            # 72 DPI: one pixel per point
```

Then read `graph.png` (with your image-viewing tool) and check, in this order:

1. Nothing is cut off at the page edges, and nothing important sits outside the plot area by accident.
2. No label overlaps a line, a point or another label; every label is next to what it names.
3. Lines cross where the model says; fills cover the intended regions; the axes read correctly.
4. The title and axis titles say what is plotted, with units.

Fix the spec and run both commands again with `--force` until the PNG is right. For the final files:
`graphink-render graph.graphink -o graph.pdf` (vector) and `--scale 2` or `--dpi 300` for sharp PNGs.
`graphink-render --info file.graphink` prints the page and pixel size.

## Errors

`graphink-create` refuses a bad spec with one line naming the place, for example
`graphink-create: objects[2].points[1] must be a point [x, y], not a number` or
`objects[0]: unknown key "colour"`. Fix exactly that and rerun. Exit status 1 is a spec or file
problem, 2 is a command-line mistake. Existing outputs are never replaced without `--force`, and
`graphink-render` never writes over its input.

## Examples

Worked specs in [examples/](examples/), each created and checked by `tools/cli/check-cli.py`:

| File | Shows |
| --- | --- |
| [supply-demand-tax.json](examples/supply-demand-tax.json) | Supply and demand with a per-unit tax: shared intersection points, welfare fills (CS, revenue, PS, DWL), guides, point labels |
| [time-series-csv.json](examples/time-series-csv.json) | A monthly series from CSV text with a header, grid, a marked event |
| [function-plot.json](examples/function-plot.json) | f(x) and f′(x) sampled from formulas, axes crossing at the origin, extrema marked |
| [labelled-scatter.json](examples/labelled-scatter.json) | A scatter with a name on every point, a dashed trend drawn by eye, the Studio style |
