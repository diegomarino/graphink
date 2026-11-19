# Graphink document spec, version 1

`graphink create SPEC.json -o OUT.graphink` reads this JSON and builds the document with Graphink's own
model, then saves it with the app's OPC writer. Every object becomes an ordinary, editable Graphink
object (points, lines, fills, labels): nothing is an image, and nothing is recomputed later.

Unknown keys, wrong types and out-of-range values are refused. The message names the exact place in the
spec, for example `objects[3].points[2] must be a point [x, y], not a number`.

## Top level

```json
{
  "graphink": 1,
  "title": "A $3 Tax on Sellers",
  "subtitle": "Buyers pay $8, sellers keep $5.",
  "style": "paper",
  "page": {"width": 1080, "height": 800, "background": "#FFFFFF", "margins": {"top": 150}},
  "x": {"title": "Quantity Q", "min": 0, "max": 14, "step": 2},
  "y": {"title": "Price P", "min": 0, "max": 16, "step": 2},
  "objects": []
}
```

| Key | Required | Meaning |
| --- | --- | --- |
| `graphink` | yes | Spec version: `1`. |
| `x`, `y` | yes | The axes (below). |
| `objects` | no | What to draw, in order (below). |
| `title`, `subtitle` | no | Text at the top left of the page (29 pt bold, 16 pt). Room is added above the plot. |
| `style` | no | `paper`, `sketch`, `chalkboard`, `studio` or `editorial`: the app's Arrange ▸ Apply Style Preset, applied last. |
| `page` | no | `width`, `height` in points (100–5000, default 1080 × 800), `background` color (default white), `margins` (below). |
| `$comment` | no | Ignored. Use it to record the model, equations or data source. |

**Margins** are the space between the page edge and the plot area, in points:
`{"top", "right", "bottom", "left"}`, any subset. Defaults: top 60 (+70 with a title, +34 with a
subtitle), right 70, and left and bottom large enough for the axis title and tick numbers (at least 70
and 60). Text placed outside the plot area needs margin room: widen a margin rather than letting a label
run off the page.

**Style presets** change colors and fonts the way the app does. They lift data colors that lack contrast
on the new background toward the preset ink and set the face of all text: Kalam for Sketch and
Chalkboard, Helvetica Neue for the others. Editorial also sets the axes for a news-chart look
(horizontal grid lines only, a baseline under the data, no y axis line or tick marks), whatever the
spec's `placement`, `grid` and `ticks` say; the spec's colors stay. Check the rendered PNG after
choosing one.

## Axes

```json
"x": {"title": "Year", "min": 2010, "max": 2025, "step": 5, "grid": true}
```

| Key | Default | Meaning |
| --- | --- | --- |
| `min`, `max` | required | The range, in data units; `max > min`. |
| `step` | automatic | Distance between ticks, in data units. Choose a round number that gives 5–12 ticks. |
| `title` | none | The axis title (15 pt bold). Without one, no room is kept for it. |
| `titleSize` | 15 | Title size in points. |
| `placement` | `origin` | `origin` (axes cross at 0), `edge` (bottom/left of the plot), `both-edges`, or `hidden`. When a range does not include 0 (years, a log axis), the default is `edge`. |
| `grid` | false | Grid lines at this axis's ticks (`x`: vertical lines, `y`: horizontal lines). |
| `log` | false | Logarithmic axis; needs `min > 0`. Graphink draws nothing of a line that dips below a logarithmic y axis's `min`: keep every point at or above it. |
| `ticks`, `tickLabels` | true | Tick marks and tick numbers (false for `hidden`). |

Tick numbers are formatted by Graphink. Put units in
the title: `"Price P (dollars per unit)"`.

## Coordinates

Everything is placed in **data coordinates** (the axis units), except `label` objects with `page`,
which use points from the bottom-left corner of the page. Points outside the axis ranges are allowed
but drawn outside the plot area.

Objects that share an exact coordinate share one Graphink point, as in the bundled examples: in the
app, dragging an equilibrium moves both curves through it. A `point` object at a line's vertex gives
that vertex a marker. Set `"shared": false` on an object to give it its own points. Arrowhead ends are
never shared.

## Colors

`"#RRGGBB"`, `"#RRGGBBAA"`, or a name from the example palette:

| Name | Hex | Use |
| --- | --- | --- |
| `ink` | `#1F2E3D` | text, axes, neutral marks (the default for text and points) |
| `blue` | `#1F61A8` | the default for lines, fills and series |
| `teal` | `#087863` | |
| `orange` | `#B84F14` | |
| `purple` | `#7D4A9E` | |
| `red` | `#B3261E` | |
| `green` | `#2E7D32` | |
| `gray`, `guide` | `#808C99` | guide lines |
| `black`, `white` | | |

## Objects

Every object has a `type`. Lines are drawn above fills, points above lines, and text above everything,
whatever the order in `objects`.

### `line`: a polyline or a smooth curve through points

```json
{"type": "line", "points": [[0, 14], [8, 6], [14, 0]], "color": "blue", "label": "D"}
```

| Key | Default | Meaning |
| --- | --- | --- |
| `points` | required | At least two `[x, y]`. |
| `color` | `blue` | |
| `width` | 2.6 | Stroke width in points (guides: 1). |
| `dash` | `solid` | `solid`, `dotted`, `short-dash`, `dashed`, `long-dash`, `dash-dot`. |
| `curve` | `straight` | `curved` draws Graphink's smooth curve through the points. It can overshoot between points: use it for sketches, not for data or exact functions. |
| `arrow` | `none` | `start`, `end` or `both`: an arrowhead at that end. |
| `label` | none | A label attached to the line, drawn along it (a string, or `{"text", "size", "bold", "color", "position"}`; `position` 0–1 along the line, default 0.5; size 15, bold, the line's color). |
| `shared` | true | See Coordinates. |

### `function`: y = f(x), sampled

```json
{"type": "function", "f": "x^3/20 - x", "from": -6, "to": 6, "samples": 401, "label": "f(x)"}
```

`f` uses `x`, numbers, `pi`, `e`, `+ - * / ^` (power, right-associative), parentheses, unary minus, and
`sin cos tan asin acos atan sinh cosh tanh exp ln log` (base 10) `log2 sqrt abs floor ceil`; function
arguments need parentheses (`sin(x)`, not `sin x`); multiplication needs `*` (`2*x`, not `2x`).
`samples` (2–5000, default 201) points from `from` to `to` are joined with straight segments, which
never invent wiggles; use 200–500 for smooth curves. Where f is not finite or leaves the y range by more
than ten ranges (asymptotes), or falls below the minimum of a logarithmic y axis, the curve is split. Other keys as for `line` (no `curve`, no `arrow`);
the label attaches to the first piece.

### `series`: data points, from a list or CSV text

```json
{"type": "series", "points": [[1.5, 52, "Ana"], [2.5, 61, "Ben"]], "marker": "circle"}
{"type": "series", "csv": "year,value\n2010,4.2\n2011,4.8", "columns": ["year", "value"], "connect": "straight"}
```

| Key | Default | Meaning |
| --- | --- | --- |
| `points` | | `[x, y]` or `[x, y, "label"]`: the third element labels that point. |
| `csv` | | Text, one row per line, separated by commas, semicolons or tabs. Rows whose chosen cells are not both numbers are skipped (notes, blanks). Give `points` or `csv`. |
| `columns` | `[0, 1]` | The x and y columns: numbers from 0, or names from the first row (then the first row is the header). |
| `connect` | `none` | `straight` or `curved` joins the points in order (sort them by x first). |
| `marker` | `circle` when unconnected, else `none` | `none`, `circle`, `hollow`, `square`, `triangle`, `diamond`, `star`, `x`, `cross`. |
| `size` | 1.8 | Marker size (a circle's diameter is 4 × size points). |
| `labels` | none | One entry per point (a string, an object as for `point` labels, or `null`); replaces third elements. |
| `label` | none | For a connected series: a label along the line, as for `line`. |
| `color`, `width`, `dash`, `shared` | | As for `line`. |

Dates are not parsed: convert them to numbers (years, months 1–12, decimal years) first.

### `point`: one marked point

```json
{"type": "point", "at": [8, 6], "label": "E"}
```

`at` (required), `marker` (`circle`), `size` (1.8), `color` (`ink`), `label` (a string or
`{"text", "size", "bold", "color"}`; placed by Graphink beside the point, 15 pt bold ink), `shared`.

### `fill`: a shaded polygon

```json
{"type": "fill", "points": [[0, 14], [0, 8], [6, 8]], "color": "blue", "label": "CS"}
```

`points` (at least 3 corners, in order around the region), `color` (`blue`), `opacity` (0.17; 0.25–0.35
for a small region that must stand out), `label` (centered on the region: a string or
`{"text", "size", "bold", "color", "at"}`; `at` moves it), `shared`.

### `bars`: a bar chart

```json
{"type": "bars", "points": [[1, 40, "North"], [2, 65, "South"]], "width": 0.6}
```

Each `[x, height]` or `[x, height, "category"]` becomes a filled rectangle from `base` (0) to the
height, `width` x-units wide (0.6), centered on x; a category is written under the bar. Use x = 1, 2, 3…,
an x range from 0 to n + 1, and hide the x tick numbers (`"tickLabels": false, "ticks": false`) when
the bars have categories. `color` (`blue`), `opacity` (0.8).

### `label`: free text

```json
{"type": "label", "text": "DWL = 3", "at": [6.2, 6.3], "size": 15, "bold": true, "color": "purple"}
{"type": "label", "text": "Source: …", "page": [58, 20], "size": 10, "color": "gray"}
```

| Key | Default | Meaning |
| --- | --- | --- |
| `text` | required | `\n` starts a new line. |
| `at` or `page` | one required | `at`: data coordinates. `page`: points from the bottom-left page corner (for notes and credits outside the plot). |
| `align` | `left` | The point is the text's bottom-left corner (`left`), bottom center (`center`) or bottom-right (`right`). |
| `size` | 14 | Points. |
| `bold` | false | |
| `color` | `ink` | |
| `rotation` | 0 | Degrees, counterclockwise. |

Text is Helvetica Neue (bold is its medium weight), as in the bundled examples.
