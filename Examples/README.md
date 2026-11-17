# Graphink example and template documents

| Folder | Kind | Contents |
| --- | --- | --- |
| [Microeconomics](Microeconomics/README.md) | examples | Eighteen annotated teaching lessons (01–18) with PDF/PNG previews |
| [Data](Data/README.md) | examples | Three charts rebuilt from AEAT, OECD and INE data, with raw sources and credits |
| [Templates](Templates/README.md) | templates | Nine graph-type starting structures with generic, editable placeholders |
| [Tools](Tools/) | — | Generator, validator and manifest writer for the lessons, the templates and the data charts |

Every `.graphink` file is saved by the production OPC writer and holds editable
native vertices, lines, labels and fills. Nothing here is loaded by the app directly.
File ▸ New From bundles byte copies under `GraphSketcher/App/Resources/NewFrom/`.

## Manifest: `NewFrom-manifest.plist`

An XML property list in the same shape as New From's `NewFrom.plist`
(read by `GraphSketcher/App/RSNewFromCatalog.m`), so its entries can be
copied over mechanically:

```xml
<dict>
  <key>FormatVersion</key><integer>1</integer>
  <key>Groups</key>
  <array>
    <dict>
      <key>Identifier</key><string>examples</string>   <!-- or templates -->
      <key>Title</key><string>Examples</string>
      <key>Items</key>
      <array>
        <dict>
          <key>File</key><string>Examples/04-binding-price-ceiling.graphink</string>
          <key>Title</key><string>Binding Price Ceiling</string>
          <key>SHA256</key><string>…</string>
          <key>Description</key><string>One line for menus, tooltips or a picker.</string>
          <key>Source</key><string>Microeconomics/04-binding-price-ceiling.graphink</string>
          <key>Credits</key><array><string>https://openstax.org/…</string></array>
        </dict>
      </array>
    </dict>
  </array>
</dict>
```

- `File`, `Title`, `SHA256` and each group's `Identifier`/`Title` mean exactly what they
  mean in `NewFrom.plist`. `File` is the path inside the bundled `NewFrom/` folder:
  `Microeconomics/` and `Data/` map to `Examples/`, and `Templates/` stays `Templates/`.
- `Description`, `Source` (path under `Examples/`) and `Credits` (conceptual sources, or the
  publisher citations and reuse notes required for data charts)
  live only in this file. The app rejects unknown keys, so drop these three when copying
  items into `NewFrom.plist`.
- Item order is the intended menu order. Every hash is that of the credited document.
- `python3 Examples/Tools/manifest.py` checks that every hash matches its file and that
  the manifest matches the item table in the script. `--write` regenerates it after a
  document or description changes.
- `python3 Examples/Tools/sync-new-from.py --write` byte-copies every `Source` into
  `GraphSketcher/App/Resources/NewFrom/<File>` and rewrites the bundled `NewFrom.plist` groups
  with `File`, `Title` and `SHA256` only, in manifest order. Lessons stay in **Examples**, the
  `Data/` charts get their own **Data Charts** group, and **Templates** follow. Without
  `--write` it only checks; `Checks/check-new-from.py` runs that check too. The app
  does not show `Description` or `Credits`, so every document carries its own credits:
  one small line at the bottom right of the page (conceptual sources for lessons and the
  economics templates; generic graph-type templates carry none; inspiration and OECD terms for the data charts, beside their publisher
  source labels).

The lesson models, numbers and layouts are original, and their sources are cited for the
concepts only. The data charts use official data under each publisher's reuse terms,
credited as [Data/README.md](Data/README.md) describes, including the OECD sub-licence
acknowledgment. No figure, artwork or third-party chart was copied.
