# Icon study provenance

Created on 2026-11-12 for this GraphSketcher design request by the implementation
agent. The seven glyphs were constructed directly as hand-authored SVG path,
rectangle and circle coordinates on a 24-unit grid. No existing Omni artwork
was traced, copied, embedded or transformed. No SF Symbols, icon pack, stock
vector, generative raster image or downloaded visual reference was used.
The inventory reads existing file metadata and caller text to establish scope;
it does not incorporate those assets into the new designs.

`representative-icons.svg` is the editable geometric master. `export-icons.py`
extracts each named group and renders it with the locally available librsvg /
Cairo toolchain. PDF/PNG and themed sheet exports are derived from that master.
Only the sheet captions use the system Helvetica/Arial/sans-serif fallback;
exported glyphs contain no text/font resources. The hand-drawn Text T is a path.

The new files are a distinct design contribution. This note does not assign a
new license, change the repository's licensing or certify legal clearance.
The coordinator/project owner retains publication and licensing decisions.
Existing source headers, original art, OmniSourceLicense.html, bundled notices,
third-party provenance, GSAppIcon.icns, GSDocIcon.icns, help imagery and iPad art
remain unchanged. The file hashes in asset-inventory.json provide a baseline
for all 85 Mac App/Images files, including legacy/unreferenced candidates.

The project's handoffs and Checks/THIRD-PARTY-PROVENANCE.md were read for ownership,
identity and notice-preservation constraints. Their recorded native/build
acceptance is historical and is not claimed for this icon study.

## Authorized production extension

The follow-up authorized all 18 toolbar names, 35 used inspector images and
the used error-bar sheet diagram. All 54 masters in Production were drawn
as new paths/rectangles/circles, extending the original seven-symbol study.
Four section symbols follow the original icon+label sidebar proposal. Original
inspector metadata supplies only canvas dimensions and control semantics;
no original visual geometry was imported. Small numeric/title cues are drawn
paths; no SF Symbols or font glyphs are embedded in production PDFs.

Production/meanings.json maps each legacy name to its master, point dimensions,
template policy and control meaning. The exact loader contract is separately
stored at GraphSketcher/App/Images/Modern/manifest.json. Exported PDFs use the
existing librsvg/Cairo pipeline; the committed light/dark proof is rasterized
from those PDFs with Poppler and recolored using their alpha. Pillow's bundled
font labels the proof only. No new dependencies were installed.

ErrorBarSheet.xib references the tall error-bar illustration, reached when
RSGraphView.makeErrorBars: cannot create error bars automatically and presents
the constant-delta sheet. The new illustration preserves its 12×51pt size.
Uncalled fancy-checkbox files, all cursors, the experimental badge and branding
were excluded. Original image hashes are checked before handoff.

The review sheet's local checks.json and individual sample exports are
transient study evidence, not production deliverables. Current production
validation is reproducible through check-production-icons.py and
check-production-rendering.py; no absolute checkout paths are stored in the
resource manifest, masters or meanings index.

## Detach revision

After the user's visual rejection of the first Detach glyph, its SVG was
redrawn as two open chain links with separation marks. The paths were authored
directly for this project on the same 24-unit grid with the family's 1.5-unit
round stroke; no external icon geometry was imported. Only its PDF was
re-exported through the existing librsvg command, and the vector/integrity and
rendering checks passed.
