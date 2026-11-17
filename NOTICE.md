# Notice

## Authorship

Graph Sketcher was created by Robin Stewart in 2007. The Omni Group developed it further as
OmniGraphSketcher from 2008 to 2014 and open-sourced all GraphSketcher source code in 2014
([graphsketcher/GraphSketcher](https://github.com/graphsketcher/GraphSketcher)). Graphink is
the 2026 continuation of that code for current macOS, by @diegomarino.

OmniGraphSketcher is The Omni Group's name. Graphink is not affiliated with or endorsed by The
Omni Group.

## Which licence covers which files

- **Inherited code: Omni Source License 2007** ([OmniSourceLicense.html](OmniSourceLicense.html)).
  These are the files that exist in upstream GraphSketcher (commit `8fe6ae4`, the first 26
  commits of this repository) and files copied from them (for example the entitlements files,
  the icons in `UI/LegacyMacIcons`). They keep their original
  headers. Where Graphink modified such a file, the file remains under the Omni Source License
  2007; our changes to it are also available under the MIT License.
- **2026 work: MIT License** ([LICENSE](LICENSE)), copyright @diegomarino. Every other file:
  new source files (which carry no licence header), checks, tools, examples, documentation
  and the icon and logo artwork, which are original drawings (see
  `UI/Design/PROVENANCE.md` and `UI/LogoStudy/README.md`).
- **Third-party content: its own licence**, listed below.

## Third-party content

- **OmniGroup frameworks**: the `OmniGroup` submodule, pinned at public revision
  `2be207ce6f7b4f77498bb48dd5e27403fb689eb7` of
  [omnigroup/OmniGroup](https://github.com/omnigroup/OmniGroup), plus the four local patches in
  `Patches/OmniGroup`, under the Omni Source License 2007.
- **Notices shipped in the app** (`GraphSketcher/App/English.lproj/ThirdPartyNotices.html`):
  Nisus LinkBack, SFMT, minizip, Apple NetReachability and mpack (Carnegie Mellon University,
  Bellcore). Their provenance is in `Checks/THIRD-PARTY-PROVENANCE.md`.
- **Kalam** font, Copyright (c) 2014 Indian Type Foundry, SIL Open Font License 1.1, bundled
  unmodified (`GraphSketcher/App/Resources/StyleFonts/OFL.txt`).

## Example data

The data charts use official statistics from AEAT (Agencia Estatal de Administración
Tributaria), INE (Instituto Nacional de Estadística) and the OECD, under their reuse terms.
The raw files, terms and the credits used are in `Examples/Data/Sources/SOURCES.md`.

## Lesson credits

The microeconomics lessons cite Pindyck and Rubinfeld, *Microeconomics*, 7th edition (Pearson
Prentice Hall, 2009), for their concepts and notation. Their models, numbers and drawings are
original; no text or figure from the book is copied.
