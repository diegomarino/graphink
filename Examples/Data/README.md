# Data charts

Three editable documents rebuilt from official public data. Each one is inspired by
a chart by Jon González (@jongonzlz), but his images, titles, annotations and design
are not reused. Chart forms, layout and wording are our own, and no value was read
off his charts. Raw downloads, URLs, table IDs, retrieval date and reuse terms are in
[Sources/SOURCES.md](Sources/SOURCES.md).

| Document | Source | Preview |
| --- | --- | --- |
| [Income Tax Concentration in Spain, 2024](irpf-concentration-2024.graphink) | AEAT, Estadística de los declarantes del IRPF 2024, partidas 435 + 460 and 595 | [PDF](Previews/irpf-concentration-2024.pdf) · [PNG](Previews/irpf-concentration-2024.png) |
| [Tax Revenue as a Share of GDP, Spain 1965–2024](tax-revenue-share-of-gdp.graphink) | OECD Revenue Statistics (DF_RSOECD 2.0), 2025 edition | [PDF](Previews/tax-revenue-share-of-gdp.pdf) · [PNG](Previews/tax-revenue-share-of-gdp.png) |
| [House Prices and Wages in Real Terms, Spain](house-prices-and-wages.graphink) | INE IPV769, ETCL1527, IPC251852 | [PDF](Previews/house-prices-and-wages.pdf) · [PNG](Previews/house-prices-and-wages.png) |

## How the values are built

`prepare.py` reads only `Sources/`. The validator (`Examples/Tools/validate.py`)
recomputes the values independently and compares them with the document's vertices.

- **IRPF concentration.** Returns are counted per bracket and cumulated, giving 10
  brackets plus the origin, so 11 points. Taxable base = partida 435 (general) +
  partida 460 (savings). Tax = partida 595 (cuota resultante de la autoliquidación).
  AEAT's brackets classify returns by general + savings base, each floored at 0.
  The checks are:
  - every point equals the recomputed share;
  - the curves end at (100, 100), and the bracket totals match AEAT's published
    totals to the euro;
  - the returns axis and the tax curve are monotonic;
  - the base curve falls only where a bracket's net base is negative. That happens in
    the first two brackets, so the curve starts just below 0;
  - the tax curve lies below the base curve exactly where the cumulative base is
    positive. Taxation is progressive.

  Coverage is AEAT's Territorio de Régimen Fiscal Común, so the País Vasco and Navarra
  are excluded, and it covers returns filed rather than all residents.
- **Tax revenue.** There are 60 annual values, 1965–2024. 2024 is included because
  the current edition publishes it; the brief named 1965–2023. Each vertex equals the
  OECD CSV value exactly, as published, with no rounding or transformation.
- **House prices and wages.** For each quarter, the IPV index and the ETCL total wage
  cost per worker and month are each divided by the quarterly mean of the monthly CPI.
  Each real series then gets a four-quarter trailing moving average, which removes the
  ETCL's extra-payment seasonality. Finally each is rebased so that its 2015 average
  = 100, which is the 2015 Q4 smoothed point. Quarters are decimal years at the start
  of the quarter, so 2025.75 is 2025 Q4. The series run from 2008 Q4 to 2025 Q4, 69
  points each. Jon González's net-wage estimate is not used.

## Credits and reuse

- **AEAT:** "Fuente: AEAT, Estadística de los declarantes del IRPF 2024 (actualizada el
  01/07/2026); elaboración propia." Reuse is under RD 1495/2011, modalidad básica.
- **INE:** "Elaboración propia con datos extraídos del sitio web del INE: www.ine.es."
  This follows INE's legal notice, which allows commercial reuse.
- **OECD:** "OECD (2025), Revenue Statistics in OECD member countries - Comparative tax
  revenues, OECD Data Explorer, <SDMX URL> (accessed on 15 November 2026)."
  **Redistributions must keep this OECD acknowledgment**: under the OECD terms, any
  sub-licence must carry the same acknowledgment requirement and pass it on.
- **Inspiration:** "Inspired by a chart by Jon González (@jongonzlz)" is credited here
  and in the manifest only.

Each document carries its publisher credit in a small source label, and a credit line
at the bottom right: "Inspired by a chart by Jon González (@jongonzlz) · rebuilt from
the official data", plus "OECD terms: keep and pass on this acknowledgment" on the
tax-revenue chart. Edits in Graphink
do not refresh the data. To update, download a newer file into `Sources/` and rerun
`Examples/Tools/generate.py`.
