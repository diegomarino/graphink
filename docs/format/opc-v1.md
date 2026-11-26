# Graphink OPC v1 profile

New `.graphink` documents are a small Open Packaging Conventions (OPC) package around the
unchanged native graph XML described in [graphink.md](graphink.md). This page fixes the exact
v1 contract: members, media types, relationships, the Graphink control part, the strict
supported subset and the save policy. Its limits are listed at the end.

## Why OPC, and what is deferred

The legacy format had no document version and no required-feature list: an unknown native XML
namespace aborts, and unknown fields are silently dropped. Three options were compared:

- **A.** Extend the legacy XML in place. Cheapest for defaults alone, but making evolution safe
  needs a version and required-feature gate anyway.
- **B.** A small versioned envelope around the existing native XML payload. It adds an explicit
  compatibility check before any model decoding, without rewriting the rich-text and native
  color serialization.
- **C.** A new structured payload (for example JSON). It would need new codecs for every graph
  domain and full parity with the legacy reader, with no demonstrated product benefit.

B was chosen (2026-11-13), as a genuinely OPC-conformant profile rather than an ad-hoc
manifest: OPC gives a standard part, content-type and relationship model and generic
inspection tools, for five members instead of two. The control part holds the document and
payload versions, the required features and the creation defaults; the native XML namespace
and the app version are not used as the document contract.

Deferred, reserved only as concepts for a later profile upgrade: embedded resources (images,
fonts) as ordinary typed parts addressed by logical IDs from the graph payload, with geometry
staying in the payload; a policy for preserving optional data. v1 refuses unknown optional data
instead. User-supplied fonts will need no licence proof or metadata.

## Parts, media types and relationships (exact)

| ZIP member (case-sensitive canonical spelling) | Content type |
| --- | --- |
| `[Content_Types].xml` | OPC media-types stream, not a part |
| `_rels/.rels` | `application/vnd.openxmlformats-package.relationships+xml` |
| `graphink/document.xml` | `application/vnd.graphink.document+xml` |
| `graphink/_rels/document.xml.rels` | `application/vnd.openxmlformats-package.relationships+xml` |
| `contents.xml` | `application/vnd.graphink.native-graph+xml` |
| optional `preview.pdf` | `application/pdf` |

The two Graphink media types are profile identifiers, not a claim of IANA
registration. No other entries/directories/relationships are supported in v1.
Content types root: `{http://schemas.openxmlformats.org/package/2006/content-types}Types`.
Exactly one Default, `Extension="rels"`, with the standard relationship type;
exactly two Overrides, `/graphink/document.xml` and `/contents.xml`, plus the
`/preview.pdf` Override iff that member exists. No unused/extra mappings.

Both relationship roots are
`{http://schemas.openxmlformats.org/package/2006/relationships}Relationships`.
Each Relationship has unique XML-ID `Id`, exact `Type` below, `Target`, and
absent or `Internal` TargetMode. No external targets, extra attributes/children,
MCE extensions or xml:base are supported. IDs are local to their relationship
part, not graph object IDs. Writers use the shown IDs; readers accept any unique
valid XML-ID and discover parts by relationship Type, not that ID spelling.

| Source | Type | Writer Id / Target |
| --- | --- | --- |
| package | `urn:graphink:relationships:document` | `rDocument` / `graphink/document.xml` |
| `/graphink/document.xml` | `urn:graphink:relationships:graph` | `rGraph` / `../contents.xml` |
| `/graphink/document.xml`, optional | `urn:graphink:relationships:preview` | `rPreview` / `../preview.pdf` |

Exactly one document and graph relationship, zero/one preview relationship.
Preview part, mapping and relationship must agree. Resolve internal relative URI
references against the **source part** (package root for `_rels/.rels`), not the
`_rels` directory. Normalize dot segments without escaping package root; compare
resolved part names under OPC ASCII case-insensitive equivalence. Require the
canonical destination members above. Targets are unescaped ASCII relative paths:
no scheme, authority, query, fragment, backslash or percent escapes in this
restricted profile. Valid OPC references outside that subset are unsupported,
not candidates for legacy fallback. OPC part-name/namespace rules still apply.

## Control part (exact)

UTF-8 XML, namespace `urn:graphink:document:1`; the prefix is immaterial.

```xml
<g:document xmlns:g="urn:graphink:document:1" version="1"
            required-features="creation-defaults-v1">
  <g:payload format="native-graph-xml" version="1"/>
  <g:creation-defaults version="1" font-name="HelveticaNeue">
    <g:line-color><color space="srgb" r="0.1" g="0.2" b="0.3" a="0.8"/></g:line-color>
    <g:fill-color><color space="srgb" r="0.1" g="0.2" b="0.3" a="0.25"/></g:fill-color>
    <g:text-color><color space="srgb" r="0.1" g="0.2" b="0.3"/></g:text-color>
  </g:creation-defaults>
</g:document>
```

One payload child, then optional creation-defaults. Document `version="1"` and
payload `format="native-graph-xml" version="1"` are mandatory and independent
of app-version. Native graph namespace remains
`http://www.omnigroup.com/namespace/OmniGraphSketcher/v1`; exactly one graph and
no pasteboard model. Keep existing native model/attributed serialization.

`required-features` is a mandatory whitespace-separated set (empty string when
none). The v1 feature tokens are:

- `creation-defaults-v1`, present iff the creation-defaults element exists;
- `equation-lines-v1` (added 2026-11-26, #27), present iff the native graph has at least one
  `line class="equation"` ([graphink.md](graphink.md) §4). The gate also refuses, as malformed,
  an equation line whose `v1` and `v2` are not the ids of two distinct `vertex` elements of the
  same graph (each id carried by exactly one graph child), or without exactly one `equation`
  child with a known `family` and finite `a`, `b`, `c`.

Writers list the tokens sorted, one space apart (`creation-defaults-v1 equation-lines-v1`).
A token without its data, data without its token, or a duplicate token is malformed. Unknown
tokens or unsupported document/payload/defaults versions/formats are **unsupported** and
refused before native graph decoding, not silently ignored. A reader that predates a token
therefore refuses the whole document: every reader up to f2ebd22 reports
"Unsupported Graphink package profile" (unknown required document feature) for a package with
equation lines, and decodes nothing. Namespace versions
other than the control namespace above are unsupported. No use of app-version
as the new contract version and no native XML namespace bump.

Creation-defaults `version="1"` is mandatory; optional nonblank `font-name` is a
concrete native PostScript face string, retained even when the face is unavailable
(native creation fallback, no restyling of loaded text). Optional line-color,
fill-color, text-color wrappers occur at most once in that order and contain one
**unqualified** native `color` element. With a default Graphink namespace, write
`xmlns=""` on color; using a `g:` prefix as above avoids that requirement.

Color codec is **the existing NSColor `appendXML:` / `colorFromXML:` representation**,
not an sRGB-only conversion or preference dump. Retain native `space`, alpha,
secure base64 `archive`, catalog/name and component/pattern representations.
Current compact attributes: `w r g b h s v c m y k a space catalog name archive
tiff png` (brightness b is also an accepted HSV input). Archives/pattern data
must be valid native representations; do not accept the native decoder's white
fallback as successful validation of corrupt input. Complex-color fidelity must
be checked with native generated fixtures, including P3/CMYK/catalog/pattern/
extended RGB. A doc-only structural checker cannot establish that fidelity.

Missing defaults or fields use existing preferences. Empty defaults may be read
with the feature token; writers omit an empty block. No theme identity/binding,
font-size/width/shape/dash/geometry/range settings, global preference dump or font
embedding feature. RSGraph owns concrete values and undo; load must not restyle
objects, register undo or dirty the document. Preset application snapshots
existing attributes and defaults together in one undo; native explicit values
remain unchanged until an intentional edit.

## Strict supported subset and failure policy

All ZIP entries must be enumerated and validated before exact member lookup.
Reject duplicate ZIP names and OPC-equivalent names, missing or inconsistent
parts/types/relationships, invalid paths and malformed XML as malformed data.
Refuse unknown control fields/attributes/elements, unknown optional parts/types/
relationships, external targets, unsupported features/versions and valid OPC
forms outside the documented reader subset with a clear **unsupported profile**
error. This includes unknown optional data: **no passthrough or preservation is
promised; the whole load is refused before model/editor replacement.** No generic
OPC consumer claim. No silently dropping recognized data on save.

Profile physical subset: single-volume, non-interleaved, non-ZIP64 ZIP; regular
file entries only, canonical ASCII names, Stored (0) or Deflate (8), no encryption,
comments, extra fields or data descriptors. Producer uses Deflate, version-needed
20, flags 0 (including bit 11), made-by high byte 0/MS-DOS and external attributes
0. Local/central names, flags, methods, CRC, sizes and offsets agree; ZIP starts
at byte 0 and ends at EOCD. Reader may accept version-needed 10 for Stored and
20 for Stored/Deflate; other valid mappings are unsupported. Per-entry maximum
64 MiB, total uncompressed and complete archive maximum 128 MiB: explicit v1
reader limits, not general OPC limits. Validate before allocation/decompression.

OPC mapping and Annex B obligations are separate from profile restrictions. A
Graphink-owned post-close normalization of producer central metadata may be
needed with existing OmniZIP's UNIX attributes; it must not change entry data,
CRC, size or offsets. Independent validation precedes atomic destination
replacement. No Omni edits, signing, encryption or new dependencies.

A ZIP containing any Graphink control part, its document relationship or Graphink
control media type is a **recognized new envelope**, even if incomplete/broken.
A ZIP containing `[Content_Types].xml` or `_rels/.rels` also enters package
validation rather than legacy XML decoding. Never retry a recognized bad/newer
package as legacy XML. Model URL reads (including exporters) use these gates;
raw `graphFromData:` and LinkBack XML APIs keep their existing XML contract.

## Save mode, adoption and resources

New documents use OPC from creation; previewless autosave/recovery writes all
five required entries, never the legacy nil-preview plain-XML branch. A preview
is optional derived PDF, never a fabricated blank graph image. Track source/
target mode on the document across temporary safe-save/autosave paths.
Legacy direct XML/ZIP `.ograph` and phase-1 `.graphink` normal Save retains legacy
representation and the same path. Explicit Save As `.graphink` adopts OPC.
Before a preset/default action on legacy content needs these defaults, complete
explicit Save As **before any action mutation/undo/dirty state**; cancellation
leaves prior state intact. Keep global Make Current Settings Default separate.
Save a complete coherent snapshot to a sibling temporary file, independently
validate it, then safely replace the target. Failure preserves the previous file;
recovery must preserve mode/defaults and required parts. Main-thread AppKit
snapshot behavior remains. This is not implementation or UI acceptance evidence.

No custom resource registry, image objects or embedded fonts in v1. Future
resources can add ordinary typed parts/relationships through an explicit profile
upgrade, retaining model geometry in the payload. User-supplied fonts require no
license proof/mandatory metadata/allowlist/unknown-license block; provenance and
license metadata are optional. Our distributed app/example assets retain proper
rights/notices. No such assets are introduced here.

## Normative basis

Packaging: [ECMA-376 Part 2, fifth edition](https://ecma-international.org/publications-and-standards/standards/ecma-376/),
§§4, 6.2, 6.4–6.5, 7.2–7.3 and Annex B; standard content-types and relationships
schemas. Graphink restrictions/semantics above are additional profile rules.
Current XML behavior/native fidelity: [phase-1 contract](graphink.md).

## Prototype fixture and executable checks

[Original five-entry fixture](fixtures/opc-v1/minimal.graphink),
[source parts and commands](fixtures/opc-v1/README.md), and
[independent checker](check-opc.py) now exist. Standard OPC schemas are unmodified
ECMA archive extracts; the Graphink control XSD is original. The native color
slot deliberately delegates native semantic decoding. The checker examines raw
local/central/EOCD bytes, decompression/CRC, URI resolution, part/type coverage,
standard schemas, control restrictions and native payload RNG; it shares no
production package helper. Its negative self-checks include preserved extraction
requirements and a made-low-zero regression.

Independent Annex B readback: B.2 requires local/central consistency; B.5 lists
producer bit 11 as zero, and §7.3.4 maps non-ASCII names to percent-encoded ZIP
names. B.2 describes MS-DOS as the made-by host default and MS-DOS external-attribute
defaults. **This Graphink profile explicitly fixes host and external attributes
to zero**; do not turn that chosen producer subset into a claim that every other
OPC consumer must reject every platform-specific archive. The header checker
also enforces our narrower no-extra/no-descriptor/non-ZIP64 output contract.


### Made-by lower-byte correction

The checker originally imposed `madeLow >= versionNeeded`. That inequality was
an unsupported checker assumption, removed after checking ECMA fifth-edition
Annex B.2 and [PKWARE APPNOTE 6.3.10 §§4.4.2.3, 4.4.3.1](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT).
Made-low describes producer-supported specification metadata; version-needed
identifies extraction features. Neither cited rule states the inequality or a
made-low minimum for this non-ZIP64 case. Preserve made-low (including pinned
Omni's zero); do not infer a mandatory conformance failure from it. This does not
assert the metadata is informative. Deflate still requires version-needed 20,
and local/central agreement, flags, CRC/sizes/offsets and producer host/external
requirements remain. The normalization whitelist is unchanged: **host high byte
and external attributes only**, never made-low. See the regression fixture under
`fixtures/opc-v1/`.

## Limits

- The profile was implemented at source `083c933` (2026-11-13) and is checked on every build:
  `check-opc.py` on the fixture and on every New From document, the OPC package checks in
  `UI/StylePresets/check-package-documents.py`, and save/reopen in the document checks.
- The prototype fixture and checker are independent of the product code. Passing them does not
  by itself establish that every emitted package conforms; emitted packages are checked
  separately.
- Strict refusal is deliberate: unknown optional data, unsupported versions or features and
  valid OPC forms outside this subset are refused, not preserved.
- Legacy `.ograph` and phase-1 `.graphink` keep their legacy behavior on normal Save (see
  [graphink.md](graphink.md) §6, including the seven baseline-identical legacy smoke failures).
  They have no feature list, so a graph with equation lines is never written to them: the save
  is refused as unsupported, and Save As `.graphink` adopts this profile.
- Native light appearance, legacy Save As cancellation, full-screen restoration and the live
  font and color panels are covered by offscreen checks only; human acceptance in the native app
  is manual.
