# Static analyzer baselines

The Xcode static analyzer reported 68 diagnostics (A001–A068) on the Mac workspace: 26 in the
app, 21 in the model and OmniStyle, and 21 in OmniGroup and LinkBack. Each was fixed or shown to
be a false positive; no checker or assertion was disabled. Two remain on purpose, A019 and A045,
and two more defects found on the way (model:N001, dependencies:N001) were fixed. The checks in
this directory keep the fixes from regressing; they run in the toolchain and products tiers (see
`docs/CONTRIBUTING-CI.md`).

| Directory | Checks | What they cover |
| --- | --- | --- |
| `app/` | `checks.py`, `menu-checks.py` | A001–A026: exact production methods under ASan, the equation menu dispatch and the font conversion block |
| `model/` | `check-model.py`, `check-production.py`, `XMLChecks.m` | A027–A047 and model:N001: production methods under ASan/UBSan, then the linked model framework and its XML receiver |
| `dependencies/` | `check-regressions.py`, `check-packaging.py`, `reanalyze.py` | A048–A068 and dependencies:N001 in `Patches/OmniGroup/0004-analyzer-contracts-and-lifetimes.patch`, and the four-patch bootstrap |

`model/before.json` and `model/after.json` are the model's analyzer output before and after
(read by `check-production.py`); `dependencies/assignment.json` lists the dependency
diagnostics `reanalyze.py` replays.

## App (A001–A026)

| ID | Location (when found) | Disposition |
| --- | --- | --- |
| A001 | `GraphDocument.m:816` | fixed |
| A002 | `RSMode.m:22` | fixed |
| A003 | `RSInspectorSidebar.m:146` | inaccurate annotation corrected (with the nullable inspector-tab protocol in patch 0004) |
| A004 | `Inspectors/DocumentInspector.m:36` | fixed |
| A005–A018 | `AppController.m:182–205` | fixed: localized with the existing `NSLocalizedString` patterns, English unchanged |
| A019 | `AppController.m:466` | **kept**: false positive. `[alert setHelpAnchor:@"importdata"]` names an anchor declared in `ImportingData.html` and linked from `Menucommands.html`; translating it would break help navigation |
| A020 | `main.m:22` | fixed ownership balance |
| A021, A022 | `RSGraphView.m:130`, `:3101` | fixed |
| A023 | `OpacityControlCell.m:11` | fixed |
| A024 | `RSModifyTool.m:550` | fixed |
| A025 | `RSStylePresets.m:129` | fixed |
| A026 | `Inspectors/AxisInspector.m:218` | fixed |

The five equation menu actions used to parse their menu titles, so translating a title would
have changed the dispatch; they now use the equation enum tags.

## Model and OmniStyle (A027–A047)

| ID | Location (when found) | Disposition |
| --- | --- | --- |
| A027–A029 | `RSHitTester-Snapping.m:349`, `:352`, `RSHitTester.m:756` | intentional presence test: a constraint value of zero is valid; compared with `nil` explicitly |
| A030 | `OmniStyle/Basic/OSURLStyleAttribute.m:81` | false positive: `isEmptyString` is YES for nil; uses the inline `OFIsEmptyString` |
| A031 | `XML/OFObject-XML.m:103` | declaration mismatch: passes an empty string for absent data; still returns nil for empty data |
| A032, A033 | `XML/OFObject-XML.m:197`, `:208` | intentional presence test: optional and required zero integers |
| A034 | `RSGraph.m:1205` | defect fixed: the retained paste ID map is released in `dealloc` |
| A035 | `XML/RSText-XML.m:39` | defect fixed: the "[Unknown]" fallback for missing styled text is localized |
| A036 | `RSNumber.m:461` | intentional presence test: a parsed zero is a success |
| A037–A044 | `OmniStyle/Text/NSAttributedString-OSExtensions.m:417–516` | intentional presence test: zero underline, strikethrough, superscript, baseline, kerning, ligature, obliqueness and expansion are real overrides of a cascaded style |
| A045 | `RSLine.m:300` | **kept**: false positive. The trace assumes `_v1` exists, then invents a write to it through `[_v2 addParent:self]`, which only updates the vertex's own parent array. Guarding it would change connected-element traversal |
| A046 | `RSDataImporter.m:58` | defect fixed: the importer releases its warning in `dealloc` |
| A047 | `RSDataImporter.m:401` | defect fixed: the column type detector returns NO for an empty table instead of writing `votes[0][4]`; its caller shows the existing no-data warning |

**model:N001.** A 4 × 2 table was transposed after its type buffer was sized for two columns,
so the detector wrote four values into a two-element stack buffer. The transposition now
happens before the dimensions are computed.

## OmniGroup and LinkBack (A048–A068)

All dependency changes are in patch 0004; the OmniGroup gitlink stays at the public pin.

| ID | Disposition |
| --- | --- |
| A048, A053, A064 | fixed: require an actual fallback URL, pass the table as the cell's control view, skip the prefix-set lookup for a nil namespace hint |
| A049, A050 | fixed: stale first/last constraints removed; replacement constraints only when visible tabs exist |
| A051, A052, A054, A055–A063, A065 | nullable contract corrected where nil is intentional (registry, color catalog, URL rewriting, local configuration) |
| A066 | fixed: format the canonicalization error before freeing its algorithm string |
| A067 | fixed: refuse external byte input for a transform without a byte-stream callback instead of calling NULL |
| A068 | fixed: `appleScriptBlankInit` declared init-family; its caller still owns and releases the result |

**dependencies:N001.** Declaring `appleScriptBlankInit` init-family exposed the
`NSTextStorage` override ignoring the result of `[self init]`; it now assigns `self`.

