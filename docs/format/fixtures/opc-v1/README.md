# Original OPC v1 prototype fixture

`minimal.graphink` is a **documentation prototype**, generated with Python's ZIP
writer, not gs-styles product output. Its five original source parts are in
`parts/`. The native XML payload is byte-identical to `../../minimal.graphink`
(relative to this directory), the accepted original phase-1 worked example.
It contains two points (2,2)/(8,8), a straight line, label and group on a fixed
520x420 canvas. Existing objects remain black; the control's blue/alpha creation
values are defaults for later creation, not a restyling instruction.

The package has no preview. It demonstrates the **approved** envelope contract,
not an implemented or verified product reader, native creation behavior, native
complex-color decoding, UI or renderer acceptance. The extracted XML alone was
read/save/reopened with retained phase-1 Debug products at `7da3b69`, exit 0,
without assertions. A phase-1 reader may read `contents.xml` while ignoring OPC
control data; that is not safe forward editing of this new format.

From repository root:

```sh
python3 docs/format/check-opc.py \
  docs/format/fixtures/opc-v1/minimal.graphink \
  --expect-payload docs/format/minimal.graphink
python3 docs/format/check-opc.py --self-check

# Generate the same prototype at a NEW disposable path; existing outputs refuse.
python3 docs/format/check-opc.py --make-fixture /private/tmp/original-opc-v1.graphink

# Standalone standard/profile schema checks of the unpacked original parts:
xmllint --nonet --noout --schema docs/format/schemas/opc-contentTypes.xsd \
  'docs/format/fixtures/opc-v1/parts/[Content_Types].xml'
xmllint --nonet --noout --schema docs/format/schemas/opc-relationships.xsd \
  docs/format/fixtures/opc-v1/parts/_rels/.rels
xmllint --nonet --noout --schema docs/format/schemas/opc-relationships.xsd \
  docs/format/fixtures/opc-v1/parts/graphink/_rels/document.xml.rels
xmllint --nonet --noout --schema docs/format/schemas/graphink-document-v1.xsd \
  docs/format/fixtures/opc-v1/parts/graphink/document.xml
xmllint --nonet --noout --relaxng GraphSketcher/Model/XML/GraphSketcher.rng \
  docs/format/fixtures/opc-v1/parts/contents.xml
```

For actual writer output, use that package path with the same independent
checker. Provide `--expect-payload /absolute/native-generated.xml` to prove
payload bytes match a retained native serialization. Provide
`--before-normalization /absolute/before.zip` to prove equal archive length and
that **only** central made-by host byte and external-attribute bytes changed;
all compressed member data/local headers/CRC/size/offset bytes must remain exact.
The checker shares no production writer/parser helper. It is a restricted profile
checker, not a general OPC consumer or proof of all native semantics. Its color
checks validate current compact structure/base64, not actual NSColor archive,
pattern image or unavailable-catalog behavior; native product tests must cover
those and reject corrupt representations without accepting white fallback.

The self-check currently refuses 16 deliberately invalid ZIP/control/URI cases.
It preserves no unrecognized optional data; the profile refuses it. No network
access, dependencies, font/license checks or asset redistribution are involved
in running the checks. Standard schema provenance is recorded separately under
`schemas/PROVENANCE.md`.


`made-low-zero.graphink` is the original fixture with only the five central
made-by lower bytes changed to zero. Needed-to-extract stays 20; native payload
and compressed bytes remain identical. It reproduces pinned Omni metadata after
the approved host/external-only normalization. It is synthesized, not product
output. The checker accepts it while still rejecting Deflate needed=10 and
excluding made-low from the normalization whitelist. The normative reasoning is in
`opc-v1.md` ("Made-by lower-byte correction").
