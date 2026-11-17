# Draw and Fill pointers

User-approved follow-up to the Graphink rebrand, 2026-11-13. FTUX/theme work is
excluded. Sole implementation worktree: `.worktrees/graphink-branding`.

## Inventory and direction

The only active custom-pointer constructors were RSGraphView initWithFrame:
DrawCursor.tiff (16×16, one bitmap, hotspot 0,15) and FillCursor.tiff (16×16,
one bitmap, hotspot 0,2). All seven historical files under Images/Cursors remain
byte-exact, including uncalled MarkerCursor/MarkerCursor_old/PenCursor and
arrow16/ibeam16. No existing notices or source-header licenses were changed.

RSGraphView owns/releases both cursors; chooseCursor selects them only in
RS_draw/RS_fill. Modify returns NSCursor.arrowCursor; Text returns IBeamCursor.
resetCursorRects and updateCursor remain unchanged. RSModifyTool's resize/open/
closed-hand overrides remain untouched. RSMode registerClick chooses the sticky
mode; handleKeyDown temporarily selects D/F (case-insensitive, excluding Command/
Option/Control, refusing a mode switch during drag). handleKeyUp restores the most
recent held tool or last clicked mode. These functions and all tool event logic
are unchanged. RSGraphView forwards key/mode events and refreshes cursor rects.

The new Draw is a fine diagonal pen; Fill is a broad chisel marker, retaining the
original tool metaphors. Rounded black outlines and white fill/keylines follow
the existing native icon family's simplicity while remaining independent of
system template tint. Geometry was authored directly as SVG, without tracing
legacy cursors, stock symbols, external art or generated raster inputs.

Both images are **20 logical points** with native PDF representations. Editable
SVGs, transparent 20/40px PNG proofs and the illustrative surface proof are retained
here. The two PDFs alone are bundled in the small ModernCursors resource folder.
The existing 54-icon manifest and original-85 checks remain unchanged. Separate
GraphinkDrawCursor/GraphinkFillCursor aliases avoid reassigning legacy filenames.
RSModernImages registers and validates both pointers at startup, independently
from its existing 54-image function. Missing/invalid pointer resources fail startup.

## Hotspot calibration and evidence

Apple defines [hotSpot](https://developer.apple.com/documentation/appkit/nscursor/hotspot)
in **logical points from the flipped image's top-left**. Draw's black nib tip is
(2,18); Fill's leading black chisel tip is (2,3). Their white halo fits inside the
20pt image. RSGraphCursor is the single production constructor for these exact
hotspots; RSGraphView retains its cursors normally. Moving the cursor image's
hotspot onto the indicated SVG tip preserves click alignment without modifying
mouse event locations or graph coordinates. Retina scaling multiplies pixel
coverage, never the logical hotspot. PDF representations preserve sharpness.

`cursor-proof.png` composites actual 1x and 2x exports onto light, dark and colored
surfaces, with a nearest-neighbor enlarged guide and pink hotspot crosses. It is
an **illustrative proof, not a captured system cursor or native visual acceptance**.
The native fixture asserts actual NSCursor hotspots/size, vector representations,
non-template state, exact alias/PDF bytes, system-pointer distinction and missing
resource refusal. Source checks assert visible tip coverage at both scales.

```sh
python3 UI/Graphink/Cursors/export-cursors.py
python3 UI/Graphink/Cursors/check-cursors.py --app /absolute/Graphink.app --output /absolute/new-evidence
python3 UI/Design/check-production-icons.py
```

Use only the existing librsvg/Cairo, Pillow, Poppler and Apple tools; no installation
or dependency change. Actual Draw/Fill switching/placement and held D/F are native checks.
A screenshot may omit
the system pointer; an overlay never establishes its actual optical appearance.
