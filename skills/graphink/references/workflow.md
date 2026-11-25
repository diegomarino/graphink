# Workflow: plan, spec, create, render, look, fix

## Plan

Before writing JSON, decide and write down (in the spec's `$comment`) what the graph must show:

- **The model or data.** For economics, solve it first: equations, intersections, areas. Every point
  you draw must agree with them (an equilibrium is where the two lines really cross). For data, keep
  the source, and say it in a label when the graph will be shared. Never invent data: if the person
  gives none, use illustrative values and say so in the subtitle.
- **Axis ranges and steps.** Ranges a little beyond the content (about 10%), round steps that give
  5–12 ticks. Use a range that starts above 0 (years) or a log axis only when the data needs it.
- **What each label says and where it goes.** Labels are placed in data coordinates; put them in
  empty space next to what they name, not on top of lines.

## Spec

The full reference is [spec.md](spec.md); copy the closest file in
[../assets/examples/](../assets/examples/) and change it. The shape:

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

Rules that keep graphs correct and editable:

- Use **straight lines through computed points** for exact relationships: `function` for formulas,
  `line` with the solved intersections for economics curves. Include the intersections as vertices,
  so that the shared point moves both curves in the app. Use `"curve": "curved"` only for a
  hand-drawn shape where overshoot does not matter (an indifference curve sketch).
- Fill corners go **in order around the region**, with the same coordinates as the lines that bound
  it.
- A trend or regression line through data is a `fit` on the series (give the series an `id`), never a
  `line` placed by eye: Graphink computes the least-squares line, labels it with its equation and R²,
  and keeps it right when a point moves in the app.
- Guides (dotted lines to the axes) use `"color": "guide", "width": 1, "dash": "dotted"`.
- Label each curve once. Short names (`D`, `S`, `MC`, `f(x)`) as the line's `label`; longer notes as
  `label` objects in empty space.

## Create and render

```bash
scripts/make-graph.sh graph.json            # graph.graphink, graph.png (72 DPI), graph.pdf
scripts/make-graph.sh graph.json --force    # again, after fixing the spec
```

`make-graph.sh` finds the tool with `find-graphink.sh` and runs `graphink create` and two
`graphink render`s. The same by hand, with the path `find-graphink.sh` printed:

```bash
graphink create graph.json -o graph.graphink
graphink render graph.graphink -o graph.png             # one pixel per point
graphink render graph.graphink -o graph.pdf             # vector
graphink render graph.graphink -o graph@2x.png --scale 2    # or --dpi 300, for a sharp image
graphink render graph.graphink --info                   # page and pixel size only
```

## Look

Read `graph.png` with your image-viewing tool and check, in this order:

1. Nothing is cut off at the page edges, and nothing important sits outside the plot area by
   accident.
2. No label overlaps a line, a point or another label; every label is next to what it names.
3. Lines cross where the model says; fills cover the intended regions; the axes read correctly.
4. The title and axis titles say what is plotted, with units.

## Fix

Change the spec, not the output, and run `make-graph.sh ... --force` again until the PNG passes
every check. Typical fixes: move a label (`at`, `position`), widen a margin (`page.margins`) for
text outside the plot, extend an axis range, or split a crowded label into a `label` object. Hand
over the `.graphink` (the person can keep editing it in Graphink) with the PNG or PDF.
