# Welcome to Graphink (first-launch example)

[`welcome-to-graphink.graphink`](welcome-to-graphink.graphink) is the original document
Graphink opens, as an untitled copy, the first time it launches with nothing else to show,
and from Help ▸ Getting Started. Previews: [PDF](Previews/welcome-to-graphink.pdf) ·
[PNG](Previews/welcome-to-graphink.png).

Every element is a native, editable object:

- a curve to modify;
- a line with a fill that follows it;
- a label to edit;
- numbered Draw and Fill practice targets (hollow points with number labels);
- callouts for Modify, Draw, Fill, Text, pasting tab-separated data and the axes;
- arrows, which are two-point lines with an arrowhead end.

It contains no images. The wording was written for Graphink; nothing is copied from the
historical `Getting Started.ograph`.

## Editing the content

All text, coordinates, colors and the canvas size live in [`layout.json`](layout.json).
Coordinates are data units (x 0–18, y 0–10), and a label's position is its bottom-left
corner. Edit the file, commit it, then regenerate:

```sh
python3 Examples/InitialFTUX/generate.py --products /private/tmp/<own-build>/Debug/Products/Debug --output /private/tmp/<new-evidence-dir>
```

The generator fails on any of these:

- a label clipped by the canvas;
- overlapping labels;
- a line, fill edge or arrow crossing a label;
- an arrow crossing a line or another arrow;
- an arrow passing within 14 pt of a visible point.

Set `FTUX_DEBUG=1` to print every label rectangle. After a passing run:

1. Inspect the PNG.
2. Copy `artifacts/welcome-to-graphink.graphink` here and to
   `GraphSketcher/App/Resources/NewFrom/Initial/`.
3. Copy the PDF and PNG previews to `Previews/`.
4. Update the SHA256 in `NewFrom.plist`.

`Checks/check-new-from.py` verifies that the copies and the manifest agree. The run's
`receipt.json` stays with the run, in the output directory.

## Production and checks

`GenerateInitialExample.m` uses the same production path as the microeconomics lessons:

- `RSGraphArchive writeXML:defaults:preview:encoding:RSGraphArchiveOPC`;
- a real `RSGraphRenderer` PDF preview;
- the lessons' creation defaults.

It reopens the document twice through `RSGraph graphFromURL:`, checks that every arrow
reopens with its arrowhead, and runs edit/undo probes:

- moving the shared line vertex, which the fill corner must follow;
- moving a curve point;
- editing a label;
- recoloring the fill.

`generate.py` refuses an existing output directory and refuses to run when the model or
generator sources have uncommitted changes. It runs `docs/format/check-opc.py` and the
RELAX NG schema, and checks the 35 historical samples before and after. It records
everything in `receipt.json` in the output directory.

Limits: it was generated with Debug products from this worktree. PDF and package bytes
are not stable across runs because PDF dates use the generation time. Interactive
editing, appearance and accessibility need native acceptance.
