# Identity, naming and document types

Graphink is a revival of GraphSketcher (originally OmniGraphSketcher). The product has a new
name; most of the code keeps the old one. This note says which is which, and why.

## What is called Graphink

- `Graphink.app`, its Dock and Finder name, the application menu, the About, Hide, Quit and
  Help labels, and current user-facing copy.
- The app identity `com.diegomarino.Graphink` (Mac App Store configurations add
  `.MacAppStore`). The embedded model framework, the Quick Look generator, the Spotlight importer
  and the LinkBack server identifiers use the same prefix.
- The app and document icons (the B1 G, see `UI/LogoStudy/README.md`). The control glyphs are
  the original vector family in `UI/Design`.

## What keeps GraphSketcher, and why

Renaming these would only churn history or break lookups:

- classes and symbols, source paths, the Xcode project, workspace and target names;
- the model framework name `GraphSketcherModel`;
- the native XML namespace `http://www.omnigroup.com/namespace/OmniGraphSketcher/v1`, which is
  part of the file format;
- the inspector identifiers in `Inspectors.plist`;
- the historical help book (`GraphSketcher Help`, which the Help menu resolves explicitly);
- the iPad sources and resources, and the 2014 release notes (`MessageOfTheDay.html`), kept as
  history and not bundled by the Mac app.

## Document types

| Extension | UTI | Declared | Graphink's role |
| --- | --- | --- | --- |
| `.graphink` | `com.diegomarino.graphink.document` (`RSGraphFileType`) | exported | Owner |
| `.ograph` | `com.graphsketcher.graphdocument` (`RSGraphLegacyFileType`) | imported, byte-equal to GraphSketcher's original export | Alternate |

`.graphink` conforms to `public.data` and `public.composite-content`, not to
`public.zip-archive`, so Finder and Archive Utility never treat a document as an archive even
though the OPC container is a ZIP file. The container format is in
[../format/opc-v1.md](../format/opc-v1.md).

Both types open through the same reader, which detects the container from the bytes. Other
installed copies (an old GraphSketcher, a second Graphink build) may register the same
extensions, so the app never trusts the system's mapping: `RSDocumentController` maps each
extension to its type, and `GraphDocument` sets the Save panel's extensions explicitly.

## About and credits

About shows Graphink with the current project links (`https://github.com/diegomarino/graphink`
and the project Pages site), then a separate "Based on GraphSketcher / OmniGraphSketcher" line
linking the original upstream repository `https://github.com/graphsketcher/GraphSketcher`. The
original credits, notices and Omni licence are kept byte for byte.
