# Editable microeconomics examples

Original `.graphink` documents, saved through the production OPC writer. Lessons
01–03 are described first; 04–08 follow in
[their own section](#lessons-0408-and-templates).

Lessons 01–03:

| Document | Preview | Practice |
| --- | --- | --- |
| [Market Equilibrium](01-market-equilibrium.graphink) | [PDF](Previews/01-market-equilibrium.pdf) · [PNG](Previews/01-market-equilibrium.png) | Draw / Text |
| [Demand and Supply Shifts](02-demand-and-supply-shifts.graphink) | [PDF](Previews/02-demand-and-supply-shifts.pdf) · [PNG](Previews/02-demand-and-supply-shifts.png) | Modify |
| [Tax Incidence and Welfare](03-tax-incidence-and-welfare.graphink) | [PDF](Previews/03-tax-incidence-and-welfare.pdf) · [PNG](Previews/03-tax-incidence-and-welfare.png) | Fill |

Each document contains editable native vertices, lines, labels and fills. Demand
is P = 14 − Q and baseline supply is P = 2 + Q/2, meeting at (8, 6). The shifts
lesson compares two separate shocks from that baseline: demand gives (10, 7),
supply gives (6, 8). A $3 seller-remitted tax gives Q1 = 6, Pb = 8, Ps = 5;
consumer surplus = 18, producer surplus = 9, revenue = 18 and deadweight loss = 3.
Revenue is a transfer. These are manually authored teaching diagrams; edits do
not recalculate economics. The models behind 01–08 are listed in
[Original synthetic models](#original-synthetic-models). No original sample was
copied or converted.

**Lessons 01–03 were regenerated on 2026-11-15 to add credits.** Each now carries one
small credit line at the bottom right ("Concepts: OpenStax, Principles of
Microeconomics 3e, §…", plus MIT OCW 14.01SC for 02 and 03). Nothing else changed:
`python3 Examples/Tools/generate.py` re-saves the earlier delivered files (pinned in
`Examples/Tools/pre-credit/`, hashes as below) through the production OPC reader and writer with
only that label added. It requires the reopened document to equal the original plus
the credit, and its `contents.xml` to match the original except for the new label, the
writer's host stamp and hash-ordered axis tick labels. It reruns this folder's
`validate.py` on the result. Each run records its hashes in `receipt.json` in its output
directory.

**Since 2026-11-16 every lesson cites Pindyck and Rubinfeld, *Microeconomics*, 7th edition**
(Pearson Prentice Hall, 2009), the textbook most of Graphink's users study from (the Spanish
translation keeps its section numbers). The credit line reads "Concepts: Pindyck & Rubinfeld,
Microeconomics 7e, §…" and replaces the OpenStax and MIT OCW citations above. Sections:
01 §2.1, §2.2 · 02 §2.3 · 03 §9.1, §9.6 · 04 §2.7, §9.1 · 05 §9.2, §9.3 · 06 §10.1, §10.4 ·
07 §7.2 · 08 §3.1–3.3. Only the credit label changed: 01–03 were re-saved from the same
pinned originals, 04–08 regenerated. Concepts are cited; no figure, example or number was
taken from the book.

**The same day the lessons adopted the book's notation**, the standard one in the field:
axis titles "Quantity Q (units per week)" and "Price P (dollars per unit)" ("$/Q" for
monopoly, "Output q" and "Cost (dollars per unit of output)" for costs, "Food F" and
"Clothing C" for the consumer); equilibrium P0 and Q0; shifted curves D′ and S′; buyers'
and sellers' prices Pb and Ps under a tax; Pmax and Pmin with Q1 (traded) and Q2 (the other
side of the market); D = AR, Pm/Qm and Pc/Qc for monopoly; U1–U3, PF, PC and income I for
the consumer. Only label texts changed: geometry, values and fills are as before. For 01–03
the generator applies exactly the replacements in `RELABELS` (`Examples/Tools/validate.py`,
mirrored by `Relabels()` in `GenerateCatalog.m`) and checks that nothing else differs.


## Original synthetic models

All formulas and numbers were devised for these examples. Unless stated otherwise: a static
partial-equilibrium market, a divisible homogeneous good, price-taking buyers and sellers and
fixed other determinants. `Examples/Tools/validate.py` derives every checked quantity from
these models independently of the generator.

1. **Market equilibrium** (lesson 01). Inverse demand D: P = 14 − Q and supply S: P = 2 + Q/2,
   both on Q ∈ [0, 14], meeting at E = (8, 6). At P = 4, Qd = 10 and Qs = 4: a shortage of 6,
   not a second equilibrium.
2. **Shifting one curve at a time** (lesson 02). Baseline D₀ = 14 − Q, S₀ = 2 + Q/2. Demand
   case D₁ = 17 − Q on [0, 17] with S₀ unchanged gives (10, 7); supply case S₁ = 5 + Q/2 on
   [0, 18] with D₀ unchanged gives (6, 8).
3. **Tax incidence and welfare** (lesson 03). Model 1 with an enforced per-unit tax t = 3 remitted
   by sellers, so buyers face S + t = 5 + Q/2. D(6) = 8, S(6) = 5: buyers bear 2/3 of the wedge.
   Before the tax CS = 32 and PS = 16; after it CS = 18, PS = 9, revenue 18 (a transfer) and
   DWL = 3, the triangle (6, 5), (6, 8), (8, 6).
4. **Binding price controls** (lessons 04, 05). Model 1. A ceiling of 5 binds: 6 trades, Qd = 9,
   shortage 3. A floor of 8 binds: 6 trades, Qs = 12, no government purchase of the excess.
5. **Marginal and average cost** (lesson 07). TC(q) = 32 + 24q − 6q² + q³, so
   MC = 24 − 12q + 3q², AVC = 24 − 6q + q², ATC = 32/q + 24 − 6q + q², shown on q ∈ [1, 7].
   MC = 3(q − 2)² + 12 > 0; AVC is smallest at (3, 15) and ATC at (4, 24), where MC crosses each.
6. **Monopoly** (lesson 06). D = 14 − Q, TC = 2Q, no fixed cost or entry. MR = 14 − 2Q, drawn
   only on [0, 7]. MR = MC gives Qm = 6 and demand gives Pm = 8; profit 36, CS 18, DWL 18,
   against a competitive CS of 72.
7. **Budget line and indifference curves** (lesson 08). Income 24, px = 2, py = 3, U = xy.
   Budget y = 8 − 2x/3 on [0, 12]; indifference curves y = k/x for k ∈ {12, 24, 36}. The
   optimum is (6, 4) on U = 24, where the slopes are both −2/3.

## Production and reproduction

Lessons 01–03 were first generated on 2026-11-13 through the production model and OPC
writer (`RSGraphArchive writeXML:defaults:preview:encoding:toURL:error:` with
`RSGraphArchiveOPC`), each package carrying the exact PDF its native renderer drew. Their
creation defaults are HelveticaNeue, dark sRGB ink for lines and text, and that ink at alpha
0.17 for fills; explicit object fonts and colors stay as drawn. Those first outputs are kept,
byte for byte, as `Examples/Tools/pre-credit/*.graphink`, and `Examples/Tools/generate.py`
(see [Production](#production) below) re-saves them with their credit line and notation, so
reruns never stack credits. It reruns this folder's `validate.py` on the result.

Each generation reopens every document twice through the native OPC reader and compares
semantic snapshots (decoded defaults, IDs, references, ordered boundaries, geometry, text,
fonts, colors and axes); checks coordinate, text and fill edits with undo; rejects mutated
copies; checks geometry, welfare areas and that the 35 original samples are unchanged; and
runs `docs/format/check-opc.py` and `xmllint` on every delivered document. Output directories
must be new. Only Debug documents and their PDF/PNG previews are delivered; their rasters are
inspected for readable labels, clipping, curves and colored regions.

## Limits

No Graphink app is launched: interactive editing, accessibility, Finder/Quick Look and human
acceptance are separate, native checks. Native PDF CreationDate/ModDate use generation time,
so PDF and package bytes are not stable across runs.

## Lessons 04–08 and templates

| Document | Preview | Practice |
| --- | --- | --- |
| [Binding Price Ceiling](04-binding-price-ceiling.graphink) | [PDF](Previews/04-binding-price-ceiling.pdf) · [PNG](Previews/04-binding-price-ceiling.png) | Modify |
| [Binding Price Floor](05-binding-price-floor.graphink) | [PDF](Previews/05-binding-price-floor.pdf) · [PNG](Previews/05-binding-price-floor.png) | Modify |
| [Monopoly Output and Price](06-monopoly.graphink) | [PDF](Previews/06-monopoly.pdf) · [PNG](Previews/06-monopoly.png) | Fill |
| [Marginal and Average Cost](07-cost-curves.graphink) | [PDF](Previews/07-cost-curves.pdf) · [PNG](Previews/07-cost-curves.png) | Data |
| [Budget Line and Indifference Curves](08-budget-and-indifference.graphink) | [PDF](Previews/08-budget-and-indifference.pdf) · [PNG](Previews/08-budget-and-indifference.png) | Draw |

These follow models #4–#7 in [Original synthetic models](#original-synthetic-models). The two price-control
views are separate documents. The graph-type templates, including Supply and Demand from
lesson 01, are in [../Templates](../Templates/README.md). Titles, descriptions and conceptual sources for
every document are in [../NewFrom-manifest.plist](../NewFrom-manifest.plist).

- **04 Ceiling Pmax = $5** (D = 14 − Q, S = 2 + Q/2): Q1 = 6 supplied, Q2 = 9 demanded, excess demand 3. With efficient
  rationing the lost surplus is ∫₆⁸(12 − 1.5Q)dQ = 3, shown as the triangle
  (6,5) (6,8) (8,6).
- **05 Floor Pmin = $8**: Q1 = 6 demanded, Q2 = 12 supplied, excess supply 6, and the same DWL triangle of 3. This
  assumes no government purchases and that only the 6 units sold are produced, by the
  lowest-cost sellers.
- **06 Monopoly** (D = 14 − Q, MC = ATC = 2): MR = 14 − 2Q = 2 gives Qm = 6, and demand
  gives Pm = 8. Profit rectangle 36, CS 18, DWL triangle (6,2) (6,8) (12,2) = 18;
  competitive CS is 72 = 18 + 36 + 18. MR is drawn only on [0, 7], and the page says so.
- **07 Costs** (TC = 32 + 24q − 6q² + q³): MC, AVC and ATC are sampled every 0.25 on
  [1, 7], with q = 2, 3, 4 always included. Minima are MC (2, 12), AVC (3, 15) and
  ATC (4, 24). MC crosses AVC and ATC exactly at those minima, and AVC and ATC never cross.
- **08 Budget** (2F + 3C = 24, U = FC; F food, C clothing): indifference curves U1 = 12, U2 = 24, U3 = 36 are sampled every
  0.25 on [k/10, 12], plus x = 6. The optimum is (6, 4), where MRS = 2/3 = px/py. The
  affordable triangle has area 48 and is labeled as not consumer surplus.

**Curves are sampled points joined by straight segments.** The validator checks every
sampled vertex against its formula. It also checks that each sampled cost curve has
exactly one turning point, at the analytic minimum, and that the only polyline crossings
are (3, 15) and (4, 24). Indifference polylines decrease, are convex, never cross each
other, and lie on or above the budget line. U = 24 touches it only at (6, 4), and U = 36
stays clear of it. Straight chords of a convex curve lie above the curve, so the drawn
U = 24 cannot cut the budget line. For comparison, the harness also measures what the
native *curved* connection would draw through the same points. It finds no false
extrema, a largest error of 0.24 $/unit (ATC near q = 1), and a U = 24 gap to the budget
of −4e−15, which is a touch rather than a crossing. Smoothing is therefore acceptable as
a user edit, but the delivered documents keep exact straight segments.

### Production

`Examples/Tools/generate.py` uses the same pipeline as 01–03:
`Examples/Tools/GenerateCatalog.m` extends the original 01–03 generator with eight document
specs and a curved-connection probe. The products must come from a
`docs/BUILDING.md` build of a commit whose `GraphSketcher/Model` and `OmniStyle`
match this checkout. The runner checks this through `<build root>/source-sha.txt`.

```sh
python3 Examples/Tools/generate.py --products "$build_root/Debug/Products/Debug" --output "$(mktemp -d)/catalog-Debug"
python3 Examples/Tools/generate.py --products "$build_root/Release/Products/Release" --output "$(mktemp -d)/catalog-Release"
python3 Examples/Tools/manifest.py
```

Each run does the following:

- Saves through the OPC writer and reopens each package twice.
- Compares semantic snapshots and checks point, label and fill edits with undo.
- Runs `docs/format/check-opc.py` and `xmllint` against `GraphSketcher.rng`.
- Rejects five mutated copies: a non-binding ceiling, a false cost extremum, a crossing
  indifference curve, an annotated template and an unresolved reference.
- Confirms that the 35 original samples and the delivered 01–03 bytes are unchanged.

Since the 2026-11-15 credit batch, every lesson and economics template carries the same one-line
credit at the bottom right. Its text is fixed in `CreditFor` in `GenerateCatalog.m`
(and checked by `validate.py`), and the generator refuses a credit that overlaps
another label or does not fit on one line.

Hashes, commands and probe numbers go to the run's `receipt.json`. The delivered files are the
Debug artifacts, and all eight PNGs were inspected for overlap and clipping. The limits
listed above still apply: no app launch and no interactive or Quick Look acceptance.

## Lessons 09–18 (Pindyck & Rubinfeld, 2026-11-16)

Ten more lessons, one concept each from Pindyck and Rubinfeld, *Microeconomics* 7e, drawn in
the book's notation. Models and numbers are original (several reuse lessons 01–07 on purpose);
the book is cited for the concepts only.

| Document | Concept (§) | Model and result |
| --- | --- | --- |
| [Elasticity Along a Linear Demand](09-elasticity-along-demand.graphink) | §2.4 | P = 14 − Q, Ep = −P/Q: −2.5 at Q = 4, −1 at (7, 7) where R = 49 is largest, −0.4 at Q = 10 |
| [Income and Substitution Effects](10-income-and-substitution-effects.graphink) | §4.2 | U = FC, I = 24, PC = 3, PF 8 → 2: A (1.5, 4) on U1 = 6, D (3, 2) on 2F + 3C = 12, B (6, 4) on U2 = 24; substitution +1.5, income +3 |
| [Isoquants and Isocost Lines](11-isoquants-and-isocost.graphink) | §6.3, §7.3 | q = LK, q1 = 32, w = 2, r = 4: A (8, 4) on C1 = $32; C2 = $40 cuts at (4, 8) and (16, 2); C0 = $24 misses |
| [A Competitive Firm in the Short Run](12-competitive-firm-short-run.graphink) | §8.4, §8.5 | Lesson 07 costs, P = 39: q* = 5, ATC 25.4, π = 68; shutdown at min AVC (3, 15) |
| [An Import Tariff](13-import-tariff.graphink) | §9.5 | Lesson 01 curves, Pw = 3, T = 1: imports 9 → 6; A = 3, B = 1, C = 0.5, D = 6 |
| [The Monopsonist Buyer](14-monopsony.graphink) | §10.5, §10.6 | AE = 2 + Q/2, ME = 2 + Q, MV = 14 − Q: Q*m = 6, P*m = 5; Qc = 8, Pc = 6; DWL 3 |
| [Third-Degree Price Discrimination](15-third-degree-price-discrimination.graphink) | §11.2 | D1 = 14 − Q, D2 = 8 − Q/2, MC = 2: P1 = 8, P2 = 5, Q1 = Q2 = 6, MRT meets MC at QT = 12 |
| [Cournot Duopoly](16-cournot-duopoly.graphink) | §12.2 | Lesson 06 demand and MC, Q2 on x, Q1 on y as in the book: Q*1(Q2) = 6 − Q2/2; Cournot (4, 4), collusion (3, 3), competition (6, 6) |
| [The Gains from Trade](17-gains-from-trade.graphink) | §16.4, §16.5 | PPF C = 12 − F²/4, U = FC: autarky A (4, 8) on U1 = 32; world PF/PC = 3: produce B (6, 3), consume D (3.5, 10.5) on U2 = 36.75 |
| [A Negative Externality](18-negative-externality.graphink) | §18.1, §18.2 | Lesson 01 curves, MEC = 3, MSC = 5 + Q/2: Q1 = 8, Q* = 6, P* = 8, DWL 3 |

They are produced and checked like 04–08 by `Examples/Tools/generate.py`: `validate.py` derives
every quantity above from the model (tangencies, crossings, areas, best responses) and checks the
drawing against it, and its self-check rejects two new mutations (a compensated bundle moved off
U1, a shifted reaction curve). Previews are in `Previews/`. File ▸ New From lists all
eighteen lessons under Examples.

Later on 2026-11-16 the lesson subtitles lost their "NN  /  " number prefix (the number adds
nothing on the page), and notes that pointed to "lesson 03", "04", "06" or "07" now name those
lessons by title. Only those texts changed.
The note "Manually authored geometry and values; edits do not recalculate the economics." is
drawn in the same pale gray as the credit line, since it qualifies the page rather than teaching
from it.
