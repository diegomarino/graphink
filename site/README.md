# Graphink landing page

Static site for GitHub Pages, served from this folder. It is not published yet:
the Pages workflow (`.github/workflows/pages.yml`) is added when the site is
published. Plain HTML/CSS, no build step, no JavaScript,
no external fonts, CDNs or trackers. All URLs inside the site are relative, so it
works under the `/graphink/` project path.

Preview locally:

    cd site && python3 -m http.server 8000   # then open http://localhost:8000/

## Repository-specific values

If the repository owner, name or default branch changes, update these and
nothing else:

| Value | Where |
| --- | --- |
| `https://diegomarino.github.io/graphink/` | `index.html` `<link rel="canonical">`, `og:url`, both `og:image`, `twitter:image` |
| `/graphink/` | `404.html` `<base href>` (404 is served at arbitrary paths) |
| `https://github.com/diegomarino/graphink` | repo links in `index.html` and `404.html` |
| `releases/latest/download/Graphink.dmg` | download buttons in `index.html` (see below) |
| `/blob/main/`, `/tree/main/` (default branch `main`) | deep links to `LICENSE` and `Examples` |

    grep -rn -e 'diegomarino' -e '/graphink/' -e 'main/' site/*.html

## Asset provenance (copied, not hotlinked)

| Site file | Source in repository |
| --- | --- |
| `assets/brand/graphink-lockup-{light,dark}{,@2x}.png` | `UI/Graphink/` |
| `assets/brand/app-icon-256.png`, `favicon-32.png` (site root) | `UI/LogoStudy/Delivery/macOS/GraphSketcher.iconset/` |
| `favicon.svg` | B1 symbol geometry from `UI/LogoStudy/Delivery/Branding/bezier-g-nodes-medium-symbol-*.svg`, light/dark colours combined |
| `assets/img/examples/*-{540,1080}.webp`, `*-540.png` | Previews from `Examples/Microeconomics/Previews/` (01, 03, 04, 06, 07, 08; re-encoded 2026-11-16 after the Pindyck & Rubinfeld credits and notation) and `Examples/Data/Previews/`. WebP q 0.85 via headless Chromium, PNG fallback via `sips -Z 540` |
| `assets/img/examples/{function-plot,scatter-plot,time-series}-{540,1080}.webp`, `-540.png` | `Examples/Templates/Previews/` (re-encoded 2026-11-17, same pipeline; these templates carry no credit, see `CreditFor`) |
| `assets/img/graphink-window-{1072,2144}.webp`, `graphink-window-720.png` | Original screenshot supplied by the project owner (2026-11-15); WebP encoded with headless Chromium (q 0.86 / 0.82), PNG fallback via `sips -Z 720` |
| `assets/img/og-image-1200x630.jpg`, `og-image-1200x1200.jpg` | Social preview images (2026-11-18): an HTML page in the site's graph-paper style with the light lockup, the hero tagline, `graphink-window-2144.webp` and the 07 and 08 lesson previews (`*-1080.webp`), rendered with headless Chromium at 1× and saved as JPEG q 90. The 1200×630 image is `og:image` and `twitter:image` (key content stays inside the central 1200×600 for 2:1 crops); the square is a second `og:image` for chat apps. The composer lives in `tools/site/og/` (see its README); re-run it when the tagline or window screenshot changes |
| `OmniSourceLicense.html` | `OmniSourceLicense.html` (byte-identical) |
| `legal/ThirdPartyNotices.html` | `GraphSketcher/App/English.lproj/ThirdPartyNotices.html` (byte-identical; its `../OmniSourceLicense.html` link resolves to the copy above) |

Re-copy these when the originals change; keep the legal files byte-identical.

## Download link contract

Both download buttons point to
`https://github.com/diegomarino/graphink/releases/latest/download/Graphink.dmg`.
GitHub redirects that to the asset named exactly `Graphink.dmg` in the newest
release, so every release must attach a Release-configuration DMG under that
fixed name (versioned copies may be attached too). `/releases/latest` skips
drafts and pre-releases. The page also says the app isn't notarized and explains
**Open Anyway**; remove that sentence once releases are notarized.

## Example credits

Each preview carries its credit on the canvas (`CreditFor` in
`Examples/Tools/GenerateCatalog.m`); the data charts also carry their publisher
citations and the OECD acknowledgment requirement, which the OECD terms say must
be kept and passed on when the chart is shared. Gallery captions show only the
title, so always publish the unmodified, uncropped preview and never crop out the
credit lines.
