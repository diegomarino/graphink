# Templates

Nine starting structures for common graph types. Each has axes and titles, the scaffolding
the graph type needs, and a few editable placeholders. All data is illustrative and generic
("Series A", "Category 1"); none of it is real data. Listed in File ▸ New From menu order:

| Template | Structure | Placeholders | Preview |
| --- | --- | --- | --- |
| [Function Plot](function-plot.graphink) | Four quadrants: axes cross at the origin, x and y from −10 to 10, grid on; the axes are named "x" and "y" at their ends | f(x) = (x³ − 75x)/50, sampled every 0.25 (turning points at (−5, 5) and (5, −5)) | [PDF](Previews/function-plot.pdf) · [PNG](Previews/function-plot.png) |
| [Time Series](time-series.graphink) | x = years as plain numbers (2010–2025), value axis 0–100 | Series A, one line with a point per year; a dashed "Event" marker at 2020 | [PDF](Previews/time-series.pdf) · [PNG](Previews/time-series.png) |
| [Scatter Plot](scatter-plot.graphink) | x and y 0–10 | 20 placeholder points (Series A); a dashed trend line labelled as drawn by hand, not a computed fit | [PDF](Previews/scatter-plot.pdf) · [PNG](Previews/scatter-plot.png) |
| [Bar Chart](bar-chart.graphink) | Value axis from 0 to 100; category labels instead of numeric x ticks | Five filled rectangles, Category 1–5 | [PDF](Previews/bar-chart.pdf) · [PNG](Previews/bar-chart.png) |
| [Logarithmic Scale](log-scale.graphink) | Logarithmic y axis, 1–1000; periods 0–9 | Series A = 1.5 × 2^t, which plots as a straight line | [PDF](Previews/log-scale.pdf) · [PNG](Previews/log-scale.png) |
| [Number Line](number-line.graphink) | One horizontal axis, −5 to 5, ticks every 1, on a short 1080 × 300 page; the y axis is hidden | The interval [−2, 3): closed (filled) end at −2, open (hollow) end at 3 | [PDF](Previews/number-line.pdf) · [PNG](Previews/number-line.png) |
| [Supply and Demand](market-equilibrium.graphink) | Lesson 01 axes, Q 0–14, P 0–16 | D: P = 14 − Q, S: P = 2 + Q/2 | [PDF](Previews/market-equilibrium.pdf) · [PNG](Previews/market-equilibrium.png) |
| [Lorenz Curve](lorenz-curve.graphink) | Square 0–100% plot, line of equality | Lorenz curve L(p) = p²/100 (monotonic, convex), sampled every 2, area to equality filled | [PDF](Previews/lorenz-curve.pdf) · [PNG](Previews/lorenz-curve.png) |
| [Production Possibilities Frontier](production-possibilities.graphink) | Good X and Good Y, 0–10 | Concave frontier (x/9)² + (y/8)² = 1; points A efficient (on), B inefficient (inside), C unattainable (outside) | [PDF](Previews/production-possibilities.pdf) · [PNG](Previews/production-possibilities.png) |

Axis titles on the page edges stay at least 58 pt from the edge, the margin of the kept Supply and
Demand template; wider tick labels move the plot area in instead.

Graphink does not compute fits or formulas: every curve is a set of editable points joined
by straight segments, sampled densely enough to look smooth. The scatter plot's trend line
was placed by eye and says so on the page.

Only the three economics templates carry the one-line credit at the bottom right, naming the
section for the concept: Pindyck and Rubinfeld, *Microeconomics* 7e, §2.1 for supply and demand
and §16.4 for the production possibilities frontier. The book has no Lorenz curve, so that
template keeps OpenStax *Principles of Microeconomics 3e* §15.4. The generic graph types cite
nothing because no source concept applies.

Supply and Demand is kept as delivered with the lessons; each generator run checks that its
regenerated contents equal the kept file except for the credit label and the axis titles, which
changed to Pindyck & Rubinfeld's credit and wording ("Quantity Q (units per week)", "Price P
(dollars per unit)") on 2026-11-16, the only changes it has had. The other eight are produced and
checked by `Examples/Tools/generate.py` with the lessons and data charts:

- **Shapes.** The function has exactly two turning points, at the analytic extrema. The
  Lorenz curve is monotonic, convex, below equality and meets it only at the ends. The PPF
  vertices lie on the ellipse and are decreasing and concave.
- **Curved connection.** If a user switches a curve to Graphink's curved connection, the
  checks confirm it adds no extrema and does not overshoot the axes or the line of
  equality. The PPF bulges out by at most 0.1%.
- **Structure.** The checks cover the log scale, the hidden y axis, the open and closed
  ends, the bars from zero, the hand-drawn label and the exact placeholder labels.
