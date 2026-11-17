#!/usr/bin/env python3
"""Write or check Examples/NewFrom-manifest.plist, the catalog File ▸ New From entries are produced from."""
import argparse
import hashlib
import plistlib
import sys
from pathlib import Path

EXAMPLES = Path(__file__).resolve().parents[1]
MANIFEST = EXAMPLES / 'NewFrom-manifest.plist'
OPENSTAX = 'https://openstax.org/books/principles-microeconomics-3e/pages/'


def pindyck(sections):
    return f'Pindyck, R. S. and Rubinfeld, D. L., Microeconomics, 7th edition, Pearson Prentice Hall, 2009, {sections} (concepts only).'


INSPIRED = 'Inspired by a chart by Jon González (@jongonzlz); rebuilt from the original public data with our own design and wording.'
# (group, repository Source under Examples/, Title, Description, Credits); File inside NewFrom/ is derived via BUNDLED
ITEMS = [
    ('examples', 'Microeconomics/01-market-equilibrium.graphink', 'Market Equilibrium',
     'Demand P = 14 − Q meets supply P = 2 + Q/2 at Q0 = 8, P0 = $6.',
     [pindyck('§2.1, §2.2')]),
    ('examples', 'Microeconomics/02-demand-and-supply-shifts.graphink', 'Demand and Supply Shifts',
     'Two separate shocks from one baseline: demand gives (10, $7), supply gives (6, $8).',
     [pindyck('§2.3')]),
    ('examples', 'Microeconomics/03-tax-incidence-and-welfare.graphink', 'Tax Incidence and Welfare',
     'A $3 per-unit tax: Pb = $8, Ps = $5; CS 18, PS 9, revenue 18 and deadweight loss 3.',
     [pindyck('§9.1, §9.6')]),
    ('examples', 'Microeconomics/04-binding-price-ceiling.graphink', 'Binding Price Ceiling',
     'Pmax = $5: Q1 = 6 supplied, Q2 = 9 demanded, excess demand 3 and deadweight loss 3.',
     [pindyck('§2.7, §9.1')]),
    ('examples', 'Microeconomics/05-binding-price-floor.graphink', 'Binding Price Floor',
     'Pmin = $8: Q1 = 6 demanded, Q2 = 12 supplied, excess supply 6 and deadweight loss 3.',
     [pindyck('§9.2, §9.3')]),
    ('examples', 'Microeconomics/06-monopoly.graphink', 'Monopoly Output and Price',
     'MR = MC at Q = 6, price $8 from demand; profit 36 and deadweight loss 18.',
     [pindyck('§10.1, §10.4')]),
    ('examples', 'Microeconomics/07-cost-curves.graphink', 'Marginal and Average Cost',
     'MC, AVC and ATC from one total cost; MC crosses AVC at (3, 15) and ATC at (4, 24).',
     [pindyck('§7.2')]),
    ('examples', 'Microeconomics/08-budget-and-indifference.graphink', 'Budget Line and Indifference Curves',
     'Budget 2F + 3C = 24 touches U2 = FC = 24 at the best affordable bundle (6, 4).',
     [pindyck('§3.1–3.3')]),
    ('examples', 'Microeconomics/09-elasticity-along-demand.graphink', 'Elasticity Along a Linear Demand',
     'On P = 14 − Q, Ep = −P/Q: elastic above Q = 7, unit elastic at (7, 7) where revenue peaks at 49, inelastic below.',
     [pindyck('§2.4')]),
    ('examples', 'Microeconomics/10-income-and-substitution-effects.graphink', 'Income and Substitution Effects',
     'PF falls from $8 to $2: food rises 1.5 along U1 (substitution) and 3 more to U2 (income).',
     [pindyck('§4.2')]),
    ('examples', 'Microeconomics/11-isoquants-and-isocost.graphink', 'Isoquants and Isocost Lines',
     'Isoquant q1 = LK = 32 touches the $32 isocost at A (8, 4), where MRTS = w/r = 1/2.',
     [pindyck('§6.3, §7.3')]),
    ('examples', 'Microeconomics/12-competitive-firm-short-run.graphink', 'A Competitive Firm in the Short Run',
     'At P = $39 the firm of lesson 07 produces q* = 5 where P = MC, with profit 68; it shuts down below $15.',
     [pindyck('§8.4, §8.5')]),
    ('examples', 'Microeconomics/13-import-tariff.graphink', 'An Import Tariff',
     'A $1 tariff on a $3 world price cuts imports from 9 to 6: revenue 6 and deadweight loss 1.5.',
     [pindyck('§9.5')]),
    ('examples', 'Microeconomics/14-monopsony.graphink', 'The Monopsonist Buyer',
     'ME = MV at Q*m = 6, price P*m = $5 from supply; competitive buyers would take 8 at $6. Deadweight loss 3.',
     [pindyck('§10.5, §10.6')]),
    ('examples', 'Microeconomics/15-third-degree-price-discrimination.graphink', 'Third-Degree Price Discrimination',
     'MR1 = MR2 = MC = $2: the less elastic group pays $8, the more elastic group $5.',
     [pindyck('§11.2')]),
    ('examples', 'Microeconomics/16-cournot-duopoly.graphink', 'Cournot Duopoly',
     'Reaction curves Q*1(Q2) and Q*2(Q1) cross at (4, 4), between collusion (3, 3) and competition (6, 6).',
     [pindyck('§12.2')]),
    ('examples', 'Microeconomics/17-gains-from-trade.graphink', 'The Gains from Trade',
     'At world prices the country produces at B (6, 3) on its PPF and consumes at D (3.5, 10.5), outside it.',
     [pindyck('§16.4, §16.5')]),
    ('examples', 'Microeconomics/18-negative-externality.graphink', 'A Negative Externality',
     'A $3 marginal external cost: the market trades 8, the efficient output is 6, deadweight loss 3.',
     [pindyck('§18.1, §18.2')]),
    ('examples', 'Data/irpf-concentration-2024.graphink', 'Income Tax Concentration in Spain, 2024',
     'Concentration curves of taxable base and tax due across income tax returns, with the equality line.',
     ['Fuente: AEAT, Estadística de los declarantes del IRPF 2024 (actualizada el 01/07/2026); elaboración propia.',
      'https://sede.agenciatributaria.gob.es/AEAT/Contenidos_Comunes/La_Agencia_Tributaria/Estadisticas/Publicaciones/sites/irpf/2024/home.html',
      INSPIRED]),
    ('examples', 'Data/tax-revenue-share-of-gdp.graphink', 'Tax Revenue as a Share of GDP, Spain',
     'Total tax revenue of Spanish general government as % of GDP, 1965–2024, as published by the OECD.',
     ['OECD (2025), Revenue Statistics in OECD member countries - Comparative tax revenues, OECD Data Explorer, '
      'https://sdmx.oecd.org/public/rest/data/OECD.CTP.TPS,DSD_REV_COMP_OECD@DF_RSOECD,2.0/ESP.TAX_REV.S13._T._T.PT_B1GQ.A '
      '(accessed on 15 November 2026).',
      'OECD terms: anyone who shares or sub-licenses work made with these data must keep this OECD acknowledgment '
      'requirement and pass it on to further sub-licensees.',
      INSPIRED]),
    ('examples', 'Data/house-prices-and-wages.graphink', 'House Prices and Wages in Real Terms, Spain',
     'INE house price index and wage cost per worker, deflated by the CPI, 2015 = 100, 2008–2025.',
     ['Elaboración propia con datos extraídos del sitio web del INE: www.ine.es (IPV, ETCL, IPC; últimos datos 2025T4 y 2025M12).',
      'https://www.ine.es', INSPIRED]),
    # Templates, in menu order. Generic graph types cite no concept source, so their Credits are empty.
    ('templates', 'Templates/function-plot.graphink', 'Function Plot',
     'Four quadrants: axes crossing at the origin, symmetric ranges, a grid and one placeholder function.', []),
    ('templates', 'Templates/time-series.graphink', 'Time Series',
     'Years on the x axis, one line with points (Series A) and a marker for an event.', []),
    ('templates', 'Templates/scatter-plot.graphink', 'Scatter Plot',
     'A cloud of placeholder points with a trend line drawn by hand, not a computed fit.', []),
    ('templates', 'Templates/bar-chart.graphink', 'Bar Chart',
     'Five filled bars with category labels on a value axis starting at 0.', []),
    ('templates', 'Templates/log-scale.graphink', 'Logarithmic Scale',
     'A logarithmic y axis with a placeholder series growing at a constant rate.', []),
    ('templates', 'Templates/number-line.graphink', 'Number Line',
     'A single horizontal axis with ticks and an interval closed at one end and open at the other.', []),
    ('templates', 'Templates/market-equilibrium.graphink', 'Supply and Demand',
     'Blank axes with one demand and one supply curve, ready to label.',
     [pindyck('§2.1')]),
    ('templates', 'Templates/lorenz-curve.graphink', 'Lorenz Curve',
     'A 0–100% square with the line of equality and a placeholder Lorenz curve, the gap between them shaded.',
     [OPENSTAX + '15-4-income-inequality-measurement-and-causes']),
    ('templates', 'Templates/production-possibilities.graphink', 'Production Possibilities Frontier',
     'A concave frontier with labelled efficient, inefficient and unattainable points.',
     [pindyck('§16.4')]),
]
GROUP_TITLES = {'examples': 'Examples', 'templates': 'Templates'}
BUNDLED = {'Microeconomics/': 'Examples/', 'Data/': 'Examples/', 'Templates/': 'Templates/'}


def build():
    groups = []
    for identifier, title in GROUP_TITLES.items():
        items = []
        for group, source, name, description, credits in ITEMS:
            if group != identifier:
                continue
            prefix = next(p for p in BUNDLED if source.startswith(p))
            items.append({'File': BUNDLED[prefix] + source[len(prefix):], 'Title': name,
                          'SHA256': hashlib.sha256((EXAMPLES / source).read_bytes()).hexdigest(),
                          'Description': description, 'Source': source, 'Credits': credits})
        groups.append({'Identifier': identifier, 'Title': title, 'Items': items})
    return {'FormatVersion': 1, 'Groups': groups}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='Rewrite the manifest; default only checks it')
    args = parser.parse_args()
    expected = build()
    if args.write:
        MANIFEST.write_bytes(plistlib.dumps(expected, sort_keys=False))
    actual = plistlib.loads(MANIFEST.read_bytes())
    assert actual == expected, 'Manifest differs from files or item table; rerun with --write and review the diff'
    for group in actual['Groups']:
        for item in group['Items']:
            assert item['File'].endswith('.graphink') and '..' not in item['File'] and not item['File'].startswith('/')
            assert all(len(item[k]) > 0 for k in ('Title', 'Description'))
            assert item['Credits'] or group['Identifier'] == 'templates', 'Only generic templates may omit credits'
    print(f"PASS: {MANIFEST.relative_to(EXAMPLES.parent)} matches {sum(len(g['Items']) for g in actual['Groups'])} documents")


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, StopIteration) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        sys.exit(1)
