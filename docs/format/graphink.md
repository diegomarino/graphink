# Native graph XML and legacy Graphink documents

This describes the native graph XML that every Graphink document carries, and the legacy
containers (`.ograph`, and phase-1 `.graphink`) that hold it directly. It was checked against
the phase-1 model (source `7da3b69`, factual baseline `a4ec649`), whose model, OmniStyle and
registration defaults are unchanged since for everything described here.

In sections 1–7, **current behavior** means that phase-1 model. At that baseline, `.graphink`
was an extension rename, not a schema/UTI change. New documents are stored in the
[OPC v1 profile](opc-v1.md), which wraps this same native graph XML without changing its
namespace. Do not apply the legacy container-writing rules below to new OPC saves.

**Current document types (2026-11-15, bundle-ID change).** `.graphink` is Graphink's own
exported UTI, `com.diegomarino.graphink.document` (`RSGraphFileType`), conforming to
`public.data` and `public.composite-content`. It deliberately does not conform to
`public.zip-archive`: a `.graphink` may also hold phase-1 XML or ZIP bytes, and zip
conformance would let Finder and Archive Utility treat documents as archives. `.ograph`
keeps the original `com.graphsketcher.graphdocument` (`RSGraphLegacyFileType`), now an
import declaration identical to GraphSketcher's export. Graphink is the `Owner` of
`.graphink` and an `Alternate` handler for `.ograph`. No file-level MIME type is defined;
the media types in [OPC v1](opc-v1.md) name parts, not the file. The model accepts both
UTIs, case-insensitively, with the same reader and writer; the container is detected from
the bytes. The extension picks the type: opening, Save and Save As map `.graphink` to the
new UTI and `.ograph` to the original one. Routing is otherwise unchanged. New documents
and Save As default to `.graphink`, and Save keeps an opened `.ograph` path and container.
Checked by `Checks/check-document-types.py`. In the table below, the UTI row is the
phase-1 baseline.

## 1. Phase-1 physical file and application registration

| Item | Current contract |
| --- | --- |
| Document UTI / model type argument | `com.graphsketcher.graphdocument` (model compares case-insensitively); now `.ograph` only, see above |
| Filename extensions | `.graphink` and `.ograph`, same reader and writer |
| Default new/Save As extension | `.graphink`; ordinary Save retains the opened `.ograph` or `.graphink` path |
| XML root | `document`, containing `graph`; document XML is distinct from pasteboard `document/model` |
| XML namespace | `http://www.omnigroup.com/namespace/OmniGraphSketcher/v1` |
| XML encoding emitted | UTF-8 with XML declaration |
| Compressed variant | ZIP file, exact root member `contents.xml`; optional `preview.pdf` |
| Uncompressed variant | The XML bytes directly in the document file, independent of extension |

`graphFromURL:type:undoer:error:` first attempts an OmniUnzip archive, reads
`contents.xml` if successful, otherwise reads the file as XML. ZIP without a
preview is readable. `graphFromData:...` expects XML data, not ZIP bytes. There
is no directory-package requirement, manifest, mimetype member, JSON layer,
external resource directory, or thumbnail member in the current native writer.

`writeToURL:generatedXMLData:previewPDFData:error:` chooses **direct XML whenever
the preview argument is nil** (atomic NSData write), and ZIP containing
`contents.xml` and `preview.pdf` when it is non-nil. An extension does not choose
the container. In GraphDocument, autosave, `SaveFilesAsPlainXML`, disabled
`IncludeQuicklookPreview`, or unavailable graph view can result in nil preview.
Normal interactive saving commits editing and prepares the model before creating
XML and PDF. The main-thread document-save policy protects that AppKit work.
A ZIP writer failure is returned; do not infer rollback/atomic replacement of a
partially written ZIP from the direct-XML atomic option.

The preview is derived display data, never editable graph content. The model
preview accessor returns nil PDF for an otherwise readable ZIP without it.
The app normally renders the actual view bounds to PDF. The offscreen fixture's
blank one-page PDF tests packaging only: **never distribute that blank page as
an example preview**. For examples, prefer direct XML until a real graph PDF
can be produced with the existing renderer/export pipeline. Keep standalone
review PDFs separate from editable source documents and label their provenance.
No UI launch, Finder/Quick Look registration, PDF fidelity or visual acceptance
is established by the model checks here.

Sources: [registration](../../GraphSketcher/App/Info.plist#L299),
[extension and Save As policy](../../GraphSketcher/App/GraphDocument.m#L169),
[document save](../../GraphSketcher/App/GraphDocument.m#L255),
[reader](../../GraphSketcher/Model/XML/RSGraph-XML.m#L188),
[container reader](../../GraphSketcher/Model/XML/RSGraph-XML.m#L286),
[XML wrapper](../../GraphSketcher/Model/XML/RSGraph-XML.m#L350),
[container writer](../../GraphSketcher/Model/XML/RSGraph-XML.m#L439).

## 2. Root metadata, graph identity and ordering

The native wrapper writes `app-id`, `app-version`, `os-name`, `os-version`, and
`machine-model`. These identify the writing process/environment; they are not a
Graphink brand version or a required-features list. `app-version` is the bundle
build version, not the namespace version. Despite the wrapper's comment that
format changes should use the namespace, the reader also uses `app-version` for
one historical conversion: versions below `10.0.0` convert parentless `none`
vertices into circles with width divided by four. Vertices belonging to lines
or fills remain invisible. Do not falsify old version metadata when generating
new documents. The fixture metadata is explicitly illustrative.

Optional `window/frame` precedes `graph`, with `x`, `y`, `w`, `h` in native window
coordinates. This is window placement, not graph data geometry. With no window
record, the model does not require a real window to read/save a graph.

Canonical graph child order is:

1. `canvas`;
2. horizontal and vertical `axis`;
3. all `vertex` elements;
4. `line` elements;
5. `fill` elements;
6. `label` elements, including axis labels;
7. `group` elements.

The reader first allocates/registers all recognized objects carrying `id`, then
reads their properties. Forward references therefore work for axis titles and
tick labels. This does **not** make arbitrary order safe: cursor child searches
advance, and relationship initialization still depends on the canonical order.
Within canvas, axes and rich text, also follow the native writer's child order.
Graph is a document-owned aggregate; it has no required serialized `id` attribute.
Pasteboard `graph-id` metadata belongs to a different archive path.

Every serialized axis/vertex/line/fill/label/group must have one unique, nonempty
ID. IDs identify objects, not positions. The registry normally emits `e1`, `e2`,
… and raises its counter to accommodate loaded `eN` values. Actual historical
examples also use `v1`, `l1`, etc.; the reader is not restricted to `eN`. Use `eN`
for new examples, no whitespace, and resolve every reference to a single object
of the expected type. `ids` and `elements` are whitespace-separated ID lists;
write one ASCII space between IDs, without leading/trailing space. Never clone
an object by duplicating its ID. Model paste/import has a separate collision
remapping path; whole-document loading does not provide that protection.

Serialization order is not a free-form z-order: rendering draws bars, fills,
axes/axis labels, lines, non-bar vertices, then ordinary labels. Groups express
editing relationships, not a nested drawing container or transformation stack.

Sources: [allocation, reading and writing](../../GraphSketcher/Model/XML/RSGraph-XML.m#L629),
[registry](../../GraphSketcher/Model/RSGraph.m#L997),
[cursor behavior](../../OmniGroup/Frameworks/OmniFoundation/XML/OFXMLCursor.m#L231),
[historical point conversion](../../GraphSketcher/Model/BackwardsCompatibility.m#L19),
[draw order](../../GraphSketcher/Model/RSGraphRenderer.m#L3540).

## 3. Coordinates, canvas and axes

Vertex and ordinary label `x`/`y` are **graph data coordinates**, not screen
pixels. Ranges and tick/grid spacing use the same data units. There is no
persisted unit registry, currency, economic variable, equation, function or
constraint-solver schema. Put units (for example quantity or price) in editable
axis titles/labels and explain economic assumptions in accompanying prose.
Intersections that must remain editable need actual vertices and connections;
text saying “equilibrium” does not create an intersection constraint.

Canvas `w`/`h`, whitespace, edge padding, line widths, label distances and font
point sizes use native drawing/view units (logical points on current Mac), not
Retina device pixels. Vertex `width` is a shape size parameter: a circle is
rendered with diameter `4 * width`, not a stroke width or radius. Axis/line width
is stroke thickness. Label rotation and serialized vertex label placement use
degrees; vertex placement is converted to radians internally, with a vertical
bar offset. Other placements below are dimensionless fractions.

For a linear axis, the mapping is `viewMin + (value-min)/(max-min)*viewRange`.
X spans `whitespace.left` to `canvasWidth-whitespace.right`; Y increases upward
from `whitespace.bottom` to `canvasHeight-whitespace.top`. Choose finite values
and nonzero increasing ranges. The mapper also supports `logarithmic`, including
all-negative ranges; avoid ranges crossing zero. This guide's worked subset uses
linear scales only. Auto whitespace and axis-label layout can reposition drawing
margins/labels during editing; serialize deliberate margins and
`auto-whitespace="false"` when a fixed composition matters.

| Element / fields | Read behavior when omitted |
| --- | --- |
| `canvas`: `w`, `h`, `auto-whitespace` | If canvas exists: 520, 420, true |
| canvas `color` | White |
| `whitespace` / `edge-padding` | Missing element: all sides 2 / 6; missing side on present element: 0 |
| `shadow strength` | 0 |
| `axis`: `id`, `dimension` | Authoring requirements: unique ID and `x` or `y`; do not omit |
| axis `min`, `max`, `userModifiedRange` | 0, 10, true |
| axis `scale`, `extent` | `linear`, `full` |
| axis `placement` | Write `origin`, `edge`, or `both-edges` explicitly; absence/unknown value reaches an assertion before fallback |
| axis `width`, `end-shape`, `visible`, `color` | 2, `none`, true, black |
| `ticks` absent | Hidden; spacing 1, user spacing 0, simple layout, inward/outward lengths 3/1 |
| `ticks` present | Same defaults, but visible defaults true; `layout` is `simple`, `at-data`, or `hidden` |
| `grid` absent | Hidden, width 1, RGB .9/.9/.9, not dotted |
| `grid` present | Spacing defaults to axis tick spacing, width 1, visible true, dotted false |
| `tick-labels` absent | Hidden; model creates missing minimum/maximum labels |
| `tick-labels` present | `distance`, `padding`, `visible`; `scientific-notation` = `auto`, `on`, `off` (default auto in this branch) |
| `title` absent | Model creates an invisible default title; distance 18 |
| `title` present | `label` references a label; `distance` 18, `placement` .5, `visible` true |

`extent` also accepts `data-range` and `data-quartiles`. Tick-label defaults for
distance are 3 horizontally, 5 vertically; padding is orientation-specific.
`tick-labels/user-labels/label` uses `tick="minLabel"`, `"maxLabel"`, or a numeric
tick key plus `idref`. The referenced full `label` is a later graph child, not
inline text. `title label="…"` follows the same pattern. Loaded tick visibility
is reset for layout; an axis label's stored visibility is not an absolute
instruction to paint it regardless of range/layout. `grid/extends-past-axis` is
written but not read in the XML category; do not rely on it for persistence.

Sources: [canvas defaults](../../GraphSketcher/Model/XML/RSGraph-XML.m#L517),
[axis XML](../../GraphSketcher/Model/XML/RSAxis-XML.m#L36),
[axis enums](../../GraphSketcher/Model/RSAxis.m#L63),
[mapping](../../GraphSketcher/Model/RSDataMapper.m#L177),
[circle geometry](../../GraphSketcher/Model/RSGraphRenderer.m#L95).

## 4. Graph objects and references

| Object | Serialized fields and semantics |
| --- | --- |
| `vertex` | `id`, `x`, `y`, `width`, optional `shape`, `arrow-parent`, `label-placement`, `label-distance`, `locked`; optional color and `snapped-to/element idref="…" param="…"` |
| `line class="connect"` | Common stroke/color/label fields; `method="none\|straight\|curved"`; child `vertices ids="…"` in connection order |
| `line class="fit"` | Common fields; `v1`, `v2` endpoint vertex references; `data ids="…"` for regression inputs; optional method only recognizes `linear-regression` |
| `fill` | Ordered boundary `vertices ids="…"`, color, optional `label-placement-x`, `label-placement-y` fractions |
| `label` | `id`, data-coordinate `x`, `y`, optional `owner`, `rotation`, `locked`, `visible`; rich `text` child |
| `group` | `id`, `elements="…"`; sets each referenced object's group membership |

Vertex defaults: x/y 0, width 2, shape `none`, no arrow parent, unlocked,
label placement 0 degrees, label distance 5, black. Snap parameter defaults to .5.
Shapes: `none`, `circle`, `triangle`, `square`, `star`, `diamond`, `treasure`,
`cross`, `hollow`, `tickmark`, `bar-vertical`, `bar-horizontal`, `arrow`,
`min-arrow`, `max-arrow`, `both-arrow`. Use only appropriate shapes for the
object's role; arbitrary unknown names can assert. A snapped relationship stores
a target plus parameter, not a symbolic economic equation. For intersections,
use shared vertices where appropriate and existing model snapping/intersection
APIs to create constraints; do not guess spline parameters from a pixel drawing.

Line defaults: width 2, black, solid dash, label placement .5 and distance 2.
Dash names: `solid`, `dots`, `dashes`, `dashes-spaced`, `dashes-long`,
`dashes-dots`, `arrows`, `reverse-arrows`, `railroad`. Missing class allocates a
connect line, but its reader asserts that class is `connect` in Debug: always
write the class. Missing connect method defaults to `curved`; explicitly choose
`straight` for piecewise linear economics diagrams. A curve interpolates model
vertices; it is not a stored analytic function. Fit lines recompute parameters
from their data and can synthesize missing endpoints; do not use them as a
substitute for explicitly constructed economic curves.

Fill defaults: black at alpha .5, label placement (.5,.5). Use at least three
valid boundary vertices in intended perimeter order. Sharing vertices with lines
preserves editable geometry; fills can also follow snapped relationships via the
existing renderer. A fill is not an image or a generic SVG path.

Labels default x/y 0, unlocked; absent visibility does not force hidden. A valid
`owner` attaches one label to a graph element only when that owner has no label.
Unresolved owners are ignored. Axis ownership is separately expressed through
axis title/tick references. Avoid duplicate owners, missing targets or cycles;
the current reader is not a structural validator for arbitrary graphs.

Sources: [vertices](../../GraphSketcher/Model/XML/RSVertex-XML.m#L28),
[lines and subclasses](../../GraphSketcher/Model/XML/RSLine-XML.m#L85),
[fills](../../GraphSketcher/Model/XML/RSFill-XML.m#L28),
[labels](../../GraphSketcher/Model/XML/RSTextLabel-XML.m#L31),
[groups](../../GraphSketcher/Model/XML/RSGroup-XML.m#L25),
[shape names](../../GraphSketcher/Model/XML/RSGraphElement-XML.m#L15).

## 5. Rich text, fonts and colors

Text is native attributed serialization: `text/p/run`, an optional `style`, then
`lit` containing literal text. Preserve significant whitespace inside `lit`;
XML-escape ampersands/angle brackets. Paragraphs and runs carry text structure,
not HTML. Missing `text` reads as `[Unknown]`. Example run (illustrative syntax):

```xml
<run>
  <style>
    <value key="font-family">Helvetica Neue</value>
    <value key="font-name">HelveticaNeue</value>
    <value key="font-size">13</value>
    <value key="font-fill"><color space="srgb" r="0.1" g="0.2" b="0.3" a="0.8"/></value>
  </style>
  <lit>Price &amp; quantity</lit>
</run>
```

`RSText` delegates to OmniStyle attributed-string read/write against
`RSGraph.defaultBaseStyle` (Mac XML base family Lucida Grande, black). That XML
base is distinct from current preferences used to create new labels. Registered
style attributes include face/family/size, weight/italic/condensed traits,
foreground/stroke, underline, paragraph formatting and other native attributes;
let `NSAttributedString` plus the existing serializer generate them. Values can
be omitted when redundant against a base style. Native font availability and
fallback apply; the container does not bundle font files. Explicit decoded runs
must not be restyled by choosing creation defaults. Unknown style keys are
logged/ignored, not preserved as an opaque style dictionary.

Graph object and text colors use native `NSColor` XML via OmniAppKit. Common
representations are `w` plus optional `a`, `r/g/b` plus optional `a`,
`c/m/y/k`, `h/s/v` (also reads brightness `b`), named `catalog/name`, and encoded
`tiff`/`png` pattern data. Optional `space` identifies a color space; supported
native colors can also carry a secure keyed `archive` (base64), with component
fallback. Decoder tries archive first; named colors can fall back to components.
Missing alpha means 1. Use explicit `space="srgb"` and normalized components for
portable hand-authored colors; absent RGB space is interpreted through generic
RGB and converted, so its numeric components need not roundtrip identically.
Do not handcraft Display P3, pattern, extended-range or catalog archives.

Absent color means white for canvas, black for axis/vertex/line, and black .5 for
fill. Black/white colors may be omitted by the graph writer; alpha-bearing
non-default values must survive through the native color representation. Invalid
color representations can fall back to white instead of producing a hard read
error. Color fidelity for every historical file/platform is not established by
these geometry/structure checks. The existing `Checks/DocumentChecks.m`
exercises eight generated current native-color documents separately.

Sources: [RSText](../../GraphSketcher/Model/XML/RSText-XML.m#L19),
[rich text grammar](../../GraphSketcher/OmniStyle/Text/OSStyledTextStorage-XML.m#L25),
[attributed string conversion](../../GraphSketcher/OmniStyle/Text/NSAttributedString-OSExtensions.m#L577),
[style registry](../../GraphSketcher/OmniStyle/Basic/OSStyle-Attributes.m#L118),
[unknown style keys](../../GraphSketcher/OmniStyle/Basic/OSStyle.m#L1130),
[native color reader](../../OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSColor-OAExtensions.m#L134),
[color XML adapter](../../OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSColor-OAExtensions.m#L906).

## 6. Checked compatibility and concrete failure boundaries

`check-format.py` compiles `FormatChecks.m` against authorized existing products,
executes isolated command-line probes, reads with the production model, writes
XML and ZIP with the production writer, and reopens both. No windows, app UI,
original writes, serializer replacement, dependency installation or preference
editing are involved. Assertion logs count as failures for valid inputs even
when the native process returns zero. Negative cases record both exit and logs.

The checker also records its exact commands, product/framework hashes and all 35
original hashes in its output directory (`receipt.json`). It also checks one unchanged
historical vertex from `Very small graph.ograph`
(app-version `9.0.114235`) for position, width and circle shape after native save.
Both configurations at source `7da3b69` produced these results:

| Probe | Debug | Release | Meaning |
| --- | --- | --- | --- |
| Original minimal fixture; ZIP with/without PDF | Read/save/reopen | Read/save/reopen | Both physical forms accepted; nil-preview native output is XML |
| 35 tracked original `.ograph` files | 35 read/save-copy/reopen | 35 read/save-copy/reopen | Original inputs and all hashes unchanged; not first-load visual/color equality |
| Missing optional canvas/vertex/line properties | Native fallbacks checked | Native fallbacks checked | No automatic restyling contract implied |
| Unknown graph attribute/child, namespaced canvas hint, `creation-defaults version="99"` | Accepted then discarded | Accepted then discarded | Required-looking unknown XML has no mandatory semantics |
| Namespace suffix `/v2` | SIGABRT (`-6`) | SIGABRT (`-6`) | Unsupported namespace version reaches `OBFinishPorting`, which calls `abort()` |
| Foreign namespace with same `/v1` suffix | Returns 0 but assertion logged | Returns 0 without that assertion | Neither outcome establishes foreign-namespace support; output normalizes to current namespace |
| Missing namespace | Accepted | Accepted | Permissive reader, not an authoring recommendation |
| Missing line vertex reference | Logs and skips it | Logs and skips it | Line may contain fewer vertices; success return does not mean complete data |
| Duplicate vertex ID | Two input vertices collapse to one | Same | Do not rely on a read error to protect identity |
| Unknown line class | Line omitted, log | Same | Successful graph load can lose unsupported required geometry |
| Missing graph element | Returns an empty model | Same | Not a structural validity guarantee |
| Truncated XML | Nonzero, Debug assertion also logged | Nonzero | Malformed parser input rejected by the probe |

The checked Debug frameworks report assertions enabled. Release lacks that
assertion report, but the version abort is unconditional: `OBFinishPorting` is
not compiled out by Release. The `GraphDocument shouldLoadFile:...` warning
helper exists, yet its invocation in `graphFromData` is commented out. The local
`shouldOpen = YES` does not protect a newer-namespace file from the preceding
abort. There is no required-feature negotiation, safe downgrade guard or generic
unknown-field roundtrip store in phase 1.

Unknown XML is not losslessly forwarded: model writers reconstruct known
properties. The probe proves loss of the specific unknown graph attribute/child,
canvas namespace hint and defaults subtree in both native output forms. Unknown
ZIP members are likewise not copied by the native writer, which constructs only
its two known members. Whitespace, attribute order, environment metadata and
native numeric/color normalization can change; byte-identical roundtrip is not
promised. This is backward **read** evidence using the current model, not a test
of historical binaries or preservation of every original rendering.

**Legacy compatibility remains bounded.** The historical legacy smoke
(`Checks/check-documents.sh --legacy-smoke`) is **not green**: over the 35 originals it
completes with `samples=35 failed=7 roundtrips=68 baseline=4 selfchecks=1`. The same seven
failures occur with the pre-phase-2 model (`7da3b69`) and the unchanged harness; they include
nonfinite snap parameters, first-load label visibility and an arrow-parent reference. This
does not establish lossless historic rendering or excuse those defects.

Normal Save of a legacy `.ograph` or phase-1 `.graphink` keeps its legacy format and path.
Explicit Save As adopts OPC; a defaults action that needs OPC must finish that adoption before
it mutates anything, and cancelling preserves the previous state. The format refuses
unsupported required versions or features and optional control data or parts rather than
silently dropping them. Native graph XML's historical omissions and conversions remain.

### Schema audit

`GraphSketcher/Model/XML/GraphSketcher.rng` is a useful executable regression
schema and is used by the current document-check runner. It includes current
native `space`/`archive` colors and grid attributes; it is not simply an untouched
historical specification. It is also **not the normative definition of reader
acceptance**:

- The RNG groups all five root provenance attributes into one optional block;
  the model accepts partial metadata. A first illustrative fixture with only
  `app-version` read successfully but failed RNG validation. The delivered
  fixture includes the complete metadata block and validates.
- The RNG permits document/model pasteboard content and multiple graph/model
  children; the file reader only looks for a graph. Do not use RNG acceptance
  as proof that this is a usable complete file.
- Grid `extends-past-axis` is allowed/written but not decoded by the XML category.
- Unknown optional fields accepted by the current reader fail the closed schema;
  valid references, cardinality and semantic integrity still need model checks.
- `relaxng.rng` is a Relax NG grammar schema, not another Graphink document format.

Debug native save validation logs diagnostics; `validateXML` returns void and
cannot turn schema errors into a failed save. Use explicit `xmllint` exit status
when schema checking a generated supported subset. No RNG was modified here.

Sources: [namespace branch](../../GraphSketcher/Model/XML/RSGraph-XML.m#L207),
[disconnected warning helper](../../GraphSketcher/App/GraphDocument.m#L142),
[unconditional macro](../../OmniGroup/Frameworks/OmniBase/OBUtilities.h#L101),
[abort implementation](../../OmniGroup/Frameworks/OmniBase/OBUtilities.m#L372),
[save-time diagnostic validation](../../GraphSketcher/Model/XML/RSGraph-XML.m#L98),
[current RNG](../../GraphSketcher/Model/XML/GraphSketcher.rng#L1).

## 7. Original worked example and reproducible checks

[minimal.graphink](minimal.graphink) is an original, direct-XML example, not
copied sample artwork/data. It contains one graph, two axes, two visible circle
vertices `(2,2)` and `(8,8)`, a straight connect line, an editable label at `(2,3)`,
and a group. Canvas is 520 by 420, fixed margins left/bottom 40 and right/top 20,
with both ranges 0…10. The data region is 460 by 360 logical points. Expected
mapped centers are `(132,112)` and `(408,328)`; the label anchor is `(132,148)`.
The line is `y=x` between those endpoints; no analytic equation is stored. Missing
width becomes 2, so circle diameter is 8 logical points; stroke width is 2.
Ticks, grids, tick labels and axis titles are hidden because their optional
children are absent. The model creates hidden axis labels on read/save; a
reserialized file is larger than the compact input. Geometry follows the native
mapping formula above; these checks do not render/visually approve the result.

From the repository root, with Debug products built as in the build guide:

```sh
python3 docs/format/check-format.py \
  --products "$build_root/Debug/Products/Debug" \
  --source-sha "$(cat "$build_root/source-sha.txt")" \
  --input docs/format/minimal.graphink

xmllint --nonet --noout \
  --relaxng GraphSketcher/Model/XML/GraphSketcher.rng \
  docs/format/minimal.graphink
```

Use the same command with `Release/Products/Release` for the Release model.
`--input` is repeatable for example documents; each extra document receives current-root,
unique-ID and resolved-reference checks before native load/save/reopen. It is a
bounded checker, not a new schema engine: expected object types, range validity,
label ownership, geometry, text contents and economic correctness still need
explicit author assertions. All outputs go to a new printed `/private/tmp/graphink-format-*`
directory. Read `receipt.json` and per-case logs; the final bounded PASS does not
turn intentional negative/future probes into accepted inputs. Missing prerequisites
or mismatched source fail instead of borrowing/building/installing products.

For actual example generation, construct `RSGraph` and native objects with an
`RSUndoer`, set explicit axes/geometry/styles, then use the established APIs:

```objc
NSData *xml = [graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
BOOL saved = xml && [graph writeToURL:url generatedXMLData:xml
                     previewPDFData:nil error:&error]; // valid direct XML
RSGraph *reopened = saved ? [RSGraph graphFromURL:url type:RSGraphFileType
                                        undoer:undoer error:&error] : nil;
```

Use actual public headers/frameworks and the isolated bundle registration/defaults
recipe in [the checker](check-format.py), or the more comprehensive
[existing document harness](../../Checks/DocumentChecks.m). Preserve every
NSError/check result. The compact XML fixture illustrates the accepted shape;
it is not a request to build a parallel general-purpose exporter. After producing
an example, assert expected counts, positions, curve/line relationships, fill
boundaries, labels and colors against the reopened native model.

## 8. Superseded canvas-defaults proposal

The original proposed `/document/graph/canvas/creation-defaults` extension and
raw-XML namespace preservation described at baseline `a4ec649` are **superseded**.
They were never shipped/verified at the checked phase-1 source. User approved
B + OPC: defaults now belong to the Graphink control part, not legacy canvas XML.
The exact [OPC v1 contract](opc-v1.md), prototype fixture and independent checker
are authoritative for the implemented format. No blanket
unknown-XML preservation is promised. Phase-1 unknown-field loss remains factual.

## 9. Implemented evolution (OPC v1)

B + OPC was explicitly approved on 2026-11-13. New `.graphink` documents use the
specified five-entry OPC envelope around unchanged native graph XML. Standard
OPC relationships identify parts; versioned Graphink control holds defaults and
required features. The strict v1 profile refuses unsupported optional data instead
of pretending to preserve it. Do not bump the native XML namespace or use the
application build version as the document contract version.

Legacy `.ograph` and phase-1 `.graphink` retain legacy format/path on normal Save.
Explicit Save As adopts OPC; adoption required by a defaults action must finish
before its mutation/undo/dirty state. Previewless autosave must preserve OPC mode.
See [opc-v1.md](opc-v1.md) for the exact implemented acceptance/error/save policy and
its limits. The original phase-1 model did not implement the envelope.

## 10. Example authoring checklist

- Pin source/model products and extension status; use the current UTI/namespace.
- Generate original editable geometry with the native model/serializer; no copied
  legacy samples, screenshot-only graphs or parallel container implementation.
- Supply one graph/canvas, x/y axes, finite meaningful ranges, fixed units in axis
  text, and deliberate auto-whitespace/margins. Use explicit line classes/methods.
- Keep IDs unique and every reference resolved to its expected object type;
  vertices precede lines/fills, labels follow geometry, groups come last.
- Store intersections as editable geometry. Verify expected positions, ordered
  boundary vertices, attached labels, titles, tick labels and text units after
  native reopen. Missing refs/unknown classes can otherwise lose data silently.
- Use native attributed fonts and color encoding. Keep decoded attributes explicit;
  do not infer a persisted preset identity. Use only the approved control-part defaults from [OPC v1](opc-v1.md); example
  documents are generated by `Examples/Tools`.
- New `.graphink` authoring uses implemented OPC v1: five required members,
  optional real preview as the sixth; use the production native model/archive
  writer. Direct XML remains accepted legacy input, not the new-document mode.
  No fabricated/stale/blank preview.
- Use `check-opc.py` for new packages and source-appropriate native geometry/
  defaults assertions; `check-format.py` remains pinned legacy-baseline evidence.
  Preserve original hashes. The historical smoke has seven baseline-identical
  failures, not suite green (§6). Package, model, PDF, native UI and human acceptance
  remain distinct evidence.
