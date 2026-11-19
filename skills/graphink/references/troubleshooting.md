# Troubleshooting

`graphink` reports a problem as one line on stderr, prefixed `graphink create:` or `graphink render:`,
and writes nothing. Exit status 1 is a spec, file or drawing problem; 2 is a command-line mistake.

## Finding the tool (`scripts/find-graphink.sh`)

| Exit | Meaning | What to do |
| --- | --- | --- |
| 3 | Not installed | Show the person the steps it prints (Homebrew `graphink-cli`, the app, or the zip) and wait for them. Do not run `sudo` or an installer yourself. |
| 4 | Not a Mac | graphink needs macOS. Say that the graph has to be made on a Mac; do not write `.graphink` files by hand. |

If macOS says it "cannot verify" graphink, the build is not notarized: the person allows it once in
System Settings > Privacy & Security > Open Anyway, then you run the command again.

## Spec errors (`graphink create`, exit 1)

The message names the place in the spec: `objects[2]` is the third object, `objects[2].points[1]` the
second point of its `points`, `x` and `y` the axes, `page` the page, `spec` the top level.

| Message | Fix |
| --- | --- |
| `objects[0]: unknown key "colour" (allowed: ...)` | Use one of the keys listed (`color`). Every key is spelled as in [spec.md](spec.md). |
| `objects[0].points must be a list of points [[x, y], ...], not nothing` | The key is missing or misspelled; add it. Other required keys say `"key" is required`. |
| `objects[2].points[1] must be a point [x, y], not a number` | Every point is a two-number list (`[3, 4]`; a third element is a label only in `series` and `bars`). |
| `objects[0].points needs at least 2 points` (3 for a `fill`) | Add points, or use a `point` object for a single one. |
| `x.min must be a number, not a string` | Write numbers without quotes; convert dates to numbers (years, months 1–12). |
| `... must be finite` | No `NaN`, no infinities; compute the value first. |
| `Each axis needs max > min` | Swap or fix the range. |
| `A logarithmic axis needs min > 0` | Raise `min`, or drop `"log": true`. |
| `objects[0].f: cannot read "sinx": unknown name "sinx" (use x, pi, e and ...)` and other formula errors | Function arguments need parentheses (`sin(x)`), multiplication needs `*` (`2*x`). Names: spec.md, `function`. |
| `objects[0]: f has fewer than two finite points between A and B` | The formula is undefined on that interval (`ln(x)` from 0, `sqrt(x)` below 0): change `from`/`to`. |
| `objects[0].color must be #RRGGBB, #RRGGBBAA or one of ...` | Use a palette name or a hex color. |
| `spec.style must be one of paper, sketch, chalkboard, studio, editorial` | Use one of these, or leave `style` out. |
| `objects[0].dash must be one of ...`, `... marker must be one of ...` | Use a listed value. |
| `objects[0].csv has no numeric rows in columns ...`, `no column named "..."` | Check `columns` against the header row, and that the chosen cells are numbers. |
| `objects[0].labels has N entries for M points` | One label (or `null`) per point. |
| `page width and height must be 100-5000 points` | Keep the page in that range (default 1080 × 800). |
| `page.margins leave no room for the plot` | Smaller margins, or a larger page. |
| `spec.graphink must be 1` | Set `"graphink": 1`. |
| `... is not a JSON object` | The file must be one JSON object `{...}`: check commas and quotes. |

## File and command-line errors

| Message | Fix |
| --- | --- |
| `OUT already exists; pass --force to replace it` | Add `--force` if replacing it is intended (make-graph.sh passes it to all three outputs). |
| `Refusing to write over the input IN (OUT is the same file)` | Choose another output name. The same file under another spelling (case, a link) counts. |
| `OUT is a directory; it is never replaced` | Name a file, not a folder, even with `--force`. |
| `Cannot read IN: ...` | Check the path; `render` reads `.graphink` and GraphSketcher `.ograph`. |
| `unknown output type .svg (use .pdf, .png, .jpg or .tiff)` (exit 2) | SVG is not supported yet; use PDF for vector output. |
| `--dpi needs a positive number, not 'abc'` (exit 2) | Pass a number such as `300` (or `--scale 2`). |
| `the resolution must be 1-1200 DPI` (exit 2) | Lower `--dpi` or `--scale`. |
| `N × M px is too large; lower --dpi or --scale` | The image would exceed 400 million pixels. |
| `OUTPUT must end in .graphink` (exit 2) | `create` writes `.graphink` only; render it for other formats. |
| `Cannot register the style fonts of ...` | The tool was copied out of its bundle. Run it from `Graphink.app/Contents/Helpers`, the unpacked `graphink-cli` folder, or a link to either. |

## When the PNG looks wrong

| You see | Change |
| --- | --- |
| Text cut off at an edge | Widen that side's `page.margins`, or move the label inward. |
| A label on top of a line | Move it (`at` for free labels, `position` 0–1 for a line's label). |
| A line missing on a log axis | Every point must be at or above the y axis `min`. |
| Curves that should meet do not | Use the same solved coordinate in both, so they share a vertex. |
| A curved line overshoots | Use straight segments through more points, or a `function`. |
| Tick numbers crowded or sparse | Change `step` (5–12 ticks). |
