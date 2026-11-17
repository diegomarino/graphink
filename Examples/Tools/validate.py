#!/usr/bin/env python3
"""Check the example catalog's economics, sampled-curve geometry and semantic native roundtrips (stdlib only)."""
import argparse
import itertools
import json
import math
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

NS = '{http://www.omnigroup.com/namespace/OmniGraphSketcher/v1}'
DATA = Path(__file__).resolve().parents[1] / 'Data'
sys.path.insert(0, str(DATA))
import prepare  # noqa: E402  (raw-table parsing only; shares and indices are recomputed below)
TOL = 1e-9

# Original synthetic models (Examples/Microeconomics/README.md, "Original synthetic models" #1-#7), derived here independently of the generator.
def D(q): return 14 - q             # inverse demand
def S(q): return 2 + q / 2          # baseline supply
def D_inv(p): return 14 - p
def S_inv(p): return 2 * (p - 2)
def MR(q): return 14 - 2 * q
FC = 32
def TC(q): return FC + 24 * q - 6 * q ** 2 + q ** 3
def MC(q): return 24 - 12 * q + 3 * q ** 2
def AVC(q): return (TC(q) - FC) / q
def ATC(q): return TC(q) / q
def BUDGET(x): return (24 - 2 * x) / 3
def IC(k): return lambda x: k / x
# Graph-type template placeholders (illustrative only), restated independently of GenerateCatalog.m.
def CUBIC(x): return (x ** 3 - 75 * x) / 50
def LORENZ(p): return p * p / 100
def PPF(x): return 8 * math.sqrt(max(0.0, 1 - x * x / 81))
def PPF_LEVEL(x, y): return (x / 9) ** 2 + (y / 8) ** 2
SERIES_A = [42, 45, 44, 48, 51, 53, 52, 56, 59, 61, 47, 52, 58, 62, 65]  # 2010-2024
SCATTER_X = [.8, 1.2, 1.7, 2.1, 2.6, 3, 3.4, 3.9, 4.3, 4.8, 5.2, 5.6, 6.1, 6.5, 7, 7.4, 7.9, 8.3, 8.8, 9.2]
SCATTER_NOISE = [.6, -.5, .3, -.8, .9, -.2, .4, -.7, .1, .8, -.6, .2, -.9, .5, -.3, .7, -.4, .6, -.8, .3]
HAND_LINE = [(.5, 1.85), (9.5, 8.15)]
BARS = [40, 65, 30, 80, 55]


def area(points):
    return abs(sum(x * points[(i + 1) % len(points)][1] - y * points[(i + 1) % len(points)][0]
                   for i, (x, y) in enumerate(points))) / 2


def close(a, b):
    if isinstance(a, (float, int)) and isinstance(b, (float, int)):
        assert math.isclose(a, b, abs_tol=0.0001), (a, b)
    elif isinstance(a, dict):
        assert a.keys() == b.keys(), (a.keys(), b.keys())
        for key in a:
            close(a[key], b[key])
    elif isinstance(a, list):
        assert len(a) == len(b), (len(a), len(b))
        for x, y in zip(a, b):
            close(x, y)
    else:
        assert a == b, (a, b)


def samples(a, b, step, extra=()):
    xs = {a, b, *extra}
    x = math.ceil(a / step - 1e-9) * step
    while x <= b + 1e-9:
        xs.add(round(x / step) * step)
        x += step
    return sorted(v for v in xs if a - 1e-9 <= v <= b + 1e-9)


def on(fn, points):
    try:
        return all(math.isclose(y, fn(x), abs_tol=TOL) for x, y in points)
    except ZeroDivisionError:
        return False


def same(a, b):
    return len(a) == len(b) and all(math.isclose(p, q, abs_tol=TOL) for u, v in zip(a, b) for p, q in zip(u, v))


def same_points(found, expected):
    return len(found) == len(expected) and all(any(same([f], [e]) for f in found) for e in expected)


def crossings(a, b):
    """Intersection points of two polylines, deduplicated."""
    found = []
    for (p1, p2), (q1, q2) in itertools.product(zip(a, a[1:]), zip(b, b[1:])):
        rx, ry, sx, sy = p2[0] - p1[0], p2[1] - p1[1], q2[0] - q1[0], q2[1] - q1[1]
        den = rx * sy - ry * sx
        if abs(den) < 1e-12:
            continue
        t = ((q1[0] - p1[0]) * sy - (q1[1] - p1[1]) * sx) / den
        u = ((q1[0] - p1[0]) * ry - (q1[1] - p1[1]) * rx) / den
        if -1e-9 <= t <= 1 + 1e-9 and -1e-9 <= u <= 1 + 1e-9:
            point = (p1[0] + t * rx, p1[1] + t * ry)
            if not any(math.dist(point, f) < 1e-6 for f in found):
                found.append(point)
    return found


def local_extrema(ys, tol=1e-9):
    """Indices where the vertical direction changes; a U-shaped curve has exactly one."""
    signs = [(1 if b - a > tol else -1 if a - b > tol else 0) for a, b in zip(ys, ys[1:])]
    signs = [s for s in signs if s]
    return sum(1 for s, t in zip(signs, signs[1:]) if s != t)


STEMS = ['04-binding-price-ceiling', '05-binding-price-floor', '06-monopoly', '07-cost-curves',
         '08-budget-and-indifference', '09-elasticity-along-demand', '10-income-and-substitution-effects', '11-isoquants-and-isocost', '12-competitive-firm-short-run', '13-import-tariff', '14-monopsony', '15-third-degree-price-discrimination', '16-cournot-duopoly', '17-gains-from-trade', '18-negative-externality',
         'template-function-plot', 'template-time-series', 'template-scatter-plot',
         'template-bar-chart', 'template-log-scale', 'template-number-line', 'template-market-equilibrium',
         'template-lorenz-curve', 'template-production-possibilities', 'irpf-concentration-2024',
         'house-prices-and-wages', 'tax-revenue-share-of-gdp']
AXES = {'04-binding-price-ceiling': (14, 16), '05-binding-price-floor': (14, 16), '06-monopoly': (14, 16),
        '07-cost-curves': (7, 90), '08-budget-and-indifference': (13, 10), 'template-market-equilibrium': (14, 16),
        '09-elasticity-along-demand': (14, 16), '10-income-and-substitution-effects': (13, 10), '11-isoquants-and-isocost': (20, 12),
        '12-competitive-firm-short-run': (7, 90), '13-import-tariff': (14, 16), '14-monopsony': (14, 16),
        '15-third-degree-price-discrimination': (16, 16), '16-cournot-duopoly': (14, 14), '17-gains-from-trade': (10, 16),
        '18-negative-externality': (14, 16),
        'template-function-plot': (10, 10), 'template-time-series': (2025, 100), 'template-scatter-plot': (10, 10),
        'template-bar-chart': (6, 100), 'template-log-scale': (9, 1000), 'template-number-line': (5, 1),
        'template-lorenz-curve': (100, 100), 'template-production-possibilities': (10, 10),
        'irpf-concentration-2024': (100, 100), 'house-prices-and-wages': (2026, 180), 'tax-revenue-share-of-gdp': (2025, 40)}
# One bottom-right credit line per document (GenerateCatalog.m CreditFor); lessons 01-03 are credited separately.
PINDYCK = 'Concepts: Pindyck & Rubinfeld, Microeconomics 7e, '
INSPIRED = 'Inspired by a chart by Jon González (@jongonzlz) · rebuilt from the official data'
CREDITS = {'01-market-equilibrium': PINDYCK + '§2.1, §2.2', '02-demand-and-supply-shifts': PINDYCK + '§2.3',
           '03-tax-incidence-and-welfare': PINDYCK + '§9.1, §9.6',
           '04-binding-price-ceiling': PINDYCK + '§2.7, §9.1', '05-binding-price-floor': PINDYCK + '§9.2, §9.3',
           '06-monopoly': PINDYCK + '§10.1, §10.4', '07-cost-curves': PINDYCK + '§7.2', '08-budget-and-indifference': PINDYCK + '§3.1–3.3',
           '09-elasticity-along-demand': PINDYCK + '§2.4', '10-income-and-substitution-effects': PINDYCK + '§4.2',
           '11-isoquants-and-isocost': PINDYCK + '§6.3, §7.3', '12-competitive-firm-short-run': PINDYCK + '§8.4, §8.5',
           '13-import-tariff': PINDYCK + '§9.5', '14-monopsony': PINDYCK + '§10.5, §10.6',
           '15-third-degree-price-discrimination': PINDYCK + '§11.2', '16-cournot-duopoly': PINDYCK + '§12.2',
           '17-gains-from-trade': PINDYCK + '§16.4, §16.5', '18-negative-externality': PINDYCK + '§18.1, §18.2',
           'template-market-equilibrium': PINDYCK + '§2.1',
           # Pindyck & Rubinfeld has no Lorenz curve: this template keeps its OpenStax source.
           'template-lorenz-curve': 'Concepts: OpenStax, Principles of Microeconomics 3e, §15.4',
           'template-production-possibilities': PINDYCK + '§16.4', 'irpf-concentration-2024': INSPIRED, 'house-prices-and-wages': INSPIRED,
           'tax-revenue-share-of-gdp': INSPIRED + ' · OECD terms: keep and pass on this acknowledgment'}
# Pindyck & Rubinfeld notation (2026-11-16): label texts changed in the delivered lessons 01-03 and the kept Supply and
# Demand template, old -> new (GenerateCatalog.m Relabels and the template's axis titles). Nothing else may change.
AXIS_RELABELS = {'Quantity Q (units/week)': 'Quantity Q (units per week)', 'Price P ($/unit)': 'Price P (dollars per unit)'}
RELABELS = {
    '01-market-equilibrium': {**AXIS_RELABELS, '01  /  Draw two curves. Label the point where they meet.': 'Draw two curves. Label the point where they meet.', 'Q* = 8\nP* = $6': 'Q0 = 8\nP0 = $6'},
    '02-demand-and-supply-shifts': {**AXIS_RELABELS, '02  /  Modify one curve. Compare with the original equilibrium.': 'Modify one curve. Compare with the original equilibrium.', 'D0': 'D', 'D1': 'D′', 'S0': 'S', 'S1': 'S′',
        'D1 = 17 − Q; keep S0\nED = (10, $7)\nHigher willingness to pay': 'D′: P = 17 − Q; keep S\nED = (10, $7)\nHigher willingness to pay',
        'S1 = 5 + Q/2; keep D0\nES = (6, $8)\nHigher input costs': 'S′: P = 5 + Q/2; keep D\nES = (6, $8)\nHigher input costs'},
    '03-tax-incidence-and-welfare': {**AXIS_RELABELS, '03  /  Fill the gains, transfers and lost trades.': 'Fill the gains, transfers and lost trades.', 'Pc = 8': 'Pb = 8', 'Pp = 5': 'Ps = 5', 'Qt = 6\nPc = $8  /  Pp = $5': 'Q1 = 6\nPb = $8  /  Ps = $5',
        'Buyers bear $2 per unit.\nSellers bear $1 per unit.\nSellers remit the tax.': 'Buyers bear Pb − P0 = $2.\nSellers bear P0 − Ps = $1.\nSellers remit t = Pb − Ps.'},
    'template-market-equilibrium': AXIS_RELABELS,
}
# Lesson note drawn in the credit's gray since 2026-11-16 (GenerateCatalog.m PaleNote); 01-03 get the color through --credit-lessons.
PALE_NOTE = 'Manually authored geometry and values; edits do not recalculate the economics.'
PALE_RGB = ('0.36', '0.41', '0.46')
# Generic graph-type templates carry no credit label (no sourced concept).
UNCREDITED = {'template-function-plot', 'template-time-series', 'template-scatter-plot', 'template-bar-chart',
              'template-log-scale', 'template-number-line'}
AXIS_MIN = {'house-prices-and-wages': (2008, 0), 'tax-revenue-share-of-gdp': (1965, 0), 'template-function-plot': (-10, -10),
            'template-time-series': (2010, 0), 'template-log-scale': (0, 1), 'template-number-line': (-5, -1)}
TITLES = {'07-cost-curves': ('Output q (units per week)', 'Cost (dollars per unit of output)'),
          '08-budget-and-indifference': ('Food F (units per week)', 'Clothing C (units per week)'),
          '06-monopoly': ('Quantity Q (units per week)', '$/Q (dollars per unit)'),
          '10-income-and-substitution-effects': ('Food F (units per week)', 'Clothing C (units per week)'),
          '11-isoquants-and-isocost': ('Labor L (hours per week)', 'Capital K (machine-hours per week)'),
          '12-competitive-firm-short-run': ('Output q (units per week)', 'Price and cost (dollars per unit)'),
          '14-monopsony': ('Quantity Q (units per week)', '$/Q (dollars per unit)'),
          '15-third-degree-price-discrimination': ('Quantity Q (units per week)', '$/Q (dollars per unit)'),
          '16-cournot-duopoly': ("Firm 2's output Q2 (units per week)", "Firm 1's output Q1 (units per week)"),
          '17-gains-from-trade': ('Food F (units per week)', 'Clothing C (units per week)'),
          'irpf-concentration-2024': ('Cumulative share of returns, ranked by taxable base (%)', 'Cumulative share (%)'),
          'house-prices-and-wages': ('Year (quarters as decimal years)', 'Real index (2015 = 100)'),
          'tax-revenue-share-of-gdp': ('Year', 'Total tax revenue (% of GDP)'),
          'template-function-plot': ('x', 'y'), 'template-time-series': ('Year', 'Value'),
          'template-scatter-plot': ('Variable X', 'Variable Y'), 'template-bar-chart': ('Category', 'Value'),
          'template-log-scale': ('Period', 'Value (log scale)'), 'template-number-line': ('x', 'y (hidden)'),
          'template-lorenz-curve': ('Cumulative share of population (%)', 'Cumulative share of income (%)'),
          'template-production-possibilities': ('Good X (units)', 'Good Y (units)')}
# Supply-and-demand template: exactly the delivered lesson curves and their names; no annotations, guides, markers or fills.
TEMPLATES = {
    'template-market-equilibrium': ([[(0, 14), (8, 6), (14, 0)], [(0, 2), (8, 6), (14, 9)]], {'D', 'S'}),
}


def label_text(label):
    return '\n'.join(''.join(e.text or '' for e in p.iter(NS + 'lit')) for p in label.iter(NS + 'p'))


def parse(path):
    with zipfile.ZipFile(path) as package:
        root = ET.fromstring(package.read('contents.xml'))
        preview = package.read('preview.pdf')
    assert root.tag == NS + 'document'
    graph = root.find(NS + 'graph')
    assert graph is not None
    identifiers = [e.get('id') for e in root.iter() if e.get('id') is not None]
    assert len(identifiers) == len(set(identifiers)) and all(identifiers)
    objects = {e.get('id'): e for e in root.iter() if e.get('id')}
    for element in root.iter():
        for key in ('idref', 'owner', 'arrow-parent', 'v1', 'v2', 'label', 'ids', 'elements'):
            assert all(r in objects for r in element.get(key, '').split()), (key, element.attrib)
    vertices = {v.get('id'): (float(v.get('x', 0)), float(v.get('y', 0))) for v in graph.findall(NS + 'vertex')}
    assert all(math.isfinite(n) for point in vertices.values() for n in point)
    axes = graph.findall(NS + 'axis')
    assert [a.get('dimension') for a in axes] == ['x', 'y']
    owned = {a.find(NS + 'title').get('label') for a in axes}
    owned |= {l.get('idref') for a in axes for l in a.iter(NS + 'label') if l.get('idref')}
    texts = {}
    for label in graph.findall(NS + 'label'):
        texts[label.get('id')] = label_text(label)
    lines = []
    for line in graph.findall(NS + 'line'):
        assert line.get('class') == 'connect' and line.get('method') == 'straight', 'Delivered curves stay straight-sampled'
        refs = line.find(NS + 'vertices').get('ids').split()
        assert all(objects[r].tag == NS + 'vertex' for r in refs)
        lines.append({'id': line.get('id'), 'points': [vertices[r] for r in refs], 'dash': line.get('dash')})
    fills = [[vertices[r] for r in f.find(NS + 'vertices').get('ids').split()] for f in graph.findall(NS + 'fill')]
    markers = {vertices[v.get('id')] for v in graph.findall(NS + 'vertex') if v.get('shape') == 'circle'}
    shapes = {vertices[v.get('id')]: v.get('shape', 'none') for v in graph.findall(NS + 'vertex')}
    return {'labels': graph.findall(NS + 'label'), 'preview': preview, 'axes': axes, 'shapes': shapes, 'texts': texts, 'titles': [texts[a.find(NS + 'title').get('label')] for a in axes],
            'user': {i: t for i, t in texts.items() if i not in owned}, 'lines': lines, 'fills': fills, 'markers': markers}


def line_on(doc, fn, required):
    """The single document line lying on fn that contains every required point (sorted by x)."""
    matches = [l['points'] for l in doc['lines'] if len(l['points']) >= 2 and on(fn, l['points'])
               and all(any(math.isclose(p[0], r[0], abs_tol=TOL) and math.isclose(p[1], r[1], abs_tol=TOL)
                           for p in l['points']) for r in required)]
    assert len(matches) == 1, ('Expected one line on model with points', required, len(matches))
    xs = [p[0] for p in matches[0]]
    assert xs == sorted(xs), 'Curve vertices must be ordered along the curve'
    return matches[0]


def has_text(doc, *needles):
    joined = '\n'.join(doc['user'].values())
    for needle in needles:
        assert needle in joined, ('Missing annotation', needle)


def check_price_control(doc, kind):
    p_star, q_star = 6, 8
    assert math.isclose(D(q_star), S(q_star)) and D(q_star) == p_star
    control = 5 if kind == 'ceiling' else 8
    assert (control < p_star) if kind == 'ceiling' else (control > p_star), 'Control must bind'
    qd, qs = D_inv(control), S_inv(control)
    traded = min(qd, qs)
    gap = abs(qd - qs)
    assert (qs, qd, gap, traded) == ((6, 9, 3, 6) if kind == 'ceiling' else (12, 6, 6, 6))
    demand = line_on(doc, D, [(0, 14), (14, 0), (qd, control)] + ([(8, 6)]))
    supply = line_on(doc, S, [(0, 2), (14, 9), (qs, control), (8, 6)])
    policy = line_on(doc, lambda x: control, [(0, control), (14, control), (qd, control), (qs, control)])
    assert len(crossings(policy, demand)) == 1 and len(crossings(policy, supply)) == 1
    # Efficient rationing: lost surplus = integral of D - S over the trades that no longer happen.
    n = 20000
    dwl = sum((D(traded + (i + .5) * (q_star - traded) / n) - S(traded + (i + .5) * (q_star - traded) / n))
              for i in range(n)) * (q_star - traded) / n
    assert math.isclose(dwl, 3, abs_tol=1e-6)
    assert len(doc['fills']) == 1 and same(doc['fills'][0], [(6, 5), (6, 8), (8, 6)])
    assert math.isclose(area(doc['fills'][0]), dwl), 'DWL fill is the lost-trade triangle'
    assert doc['markers'] == {(qs, control), (qd, control), (8, 6)}
    if kind == 'ceiling':
        has_text(doc, 'Pmax = $5', 'Q1 = 6', 'Q2 = 9', 'Excess demand = 3', 'DWL = 3', 'E (8, 6)', 'Pmax = $5 < P0 = $6')
    else:
        has_text(doc, 'Pmin = $8', 'Q1 = 6', 'Q2 = 12', 'Excess supply = 6', 'DWL = 3', 'E (8, 6)', 'Pmin = $8 > P0 = $6')


def check_monopoly(doc):
    qm = next(q / 1000 for q in range(0, 7001) if math.isclose(MR(q / 1000), 2))
    pm = D(qm)
    profit = lambda q: D(q) * q - 2 * q
    grid = [q / 100 for q in range(0, 1401)]
    assert max(grid, key=profit) == qm == 6 and pm == 8 and profit(qm) == 36
    qc = D_inv(2)
    cs_m, cs_c = (14 - pm) * qm / 2, (14 - 2) * qc / 2
    dwl = cs_c - (cs_m + profit(qm))
    assert (qc, cs_m, cs_c, dwl) == (12, 18, 72, 18)
    line_on(doc, D, [(0, 14), (qm, pm), (qc, 2), (14, 0)])
    mr = line_on(doc, MR, [(0, 14), (qm, 2), (7, 0)])
    assert min(y for _, y in mr) >= 0, 'MR is clipped where it would be negative'
    line_on(doc, lambda q: 2, [(0, 2), (qm, 2), (qc, 2), (14, 2)])
    expected = [[(0, 8), (0, 14), (6, 8)], [(0, 2), (6, 2), (6, 8), (0, 8)], [(6, 2), (6, 8), (12, 2)]]
    assert len(doc['fills']) == 3 and all(same(f, e) for f, e in zip(doc['fills'], expected))
    assert [area(f) for f in doc['fills']] == [cs_m, profit(qm), dwl]
    assert doc['markers'] == {(qm, pm), (qm, 2), (qc, 2)}
    has_text(doc, 'D = AR', 'Pm = 8', 'Qm = 6', 'Qc = 12, Pc = 2', 'CS = 18', 'Profit = 36', 'DWL = 18', 'CS = 72', 'DWL = 72 − 54 = 18', 'MR = 14 − 2Q')


def check_costs(doc):
    for q in samples(1, 7, .01):
        h = 1e-6
        assert math.isclose((TC(q + h) - TC(q - h)) / (2 * h), MC(q), abs_tol=1e-5), 'MC is the derivative of TC'
        assert ATC(q) - AVC(q) > 0 and MC(q) > 0
    assert (MC(2), AVC(3), MC(3), ATC(4), MC(4)) == (12, 15, 15, 24, 24)
    want = samples(1, 7, .25, (2, 3, 4))
    curves = {}
    for name, fn, minimum in (('MC', MC, 2), ('AVC', AVC, 3), ('ATC', ATC, 4)):
        line = line_on(doc, fn, [(want[0], fn(want[0])), (want[-1], fn(want[-1])), (minimum, fn(minimum))])
        assert [x for x, _ in line] == want, (name, 'sampled every 0.25 on [1, 7]')
        ys = [y for _, y in line]
        assert local_extrema(ys) == 1, (name, 'false extremum in sampled curve')
        assert line[ys.index(min(ys))] == (minimum, fn(minimum)), (name, 'sampled minimum is the analytic minimum')
        assert max(ys) <= AXES['07-cost-curves'][1], (name, 'stays inside the y axis')
        curves[name] = line
    for a, b, expected in (('MC', 'AVC', [(3, 15)]), ('MC', 'ATC', [(4, 24)]), ('AVC', 'ATC', [])):
        found = crossings(curves[a], curves[b])
        assert len(found) == len(expected) and all(math.dist(f, e) < 1e-9 for f, e in zip(found, expected)), (a, b, found)
    assert doc['markers'] == {(2, 12), (3, 15), (4, 24)} and not doc['fills']
    has_text(doc, 'TC = 32 + 24q − 6q² + q³', 'MC = 24 − 12q + 3q²', 'AVC = 24 − 6q + q²', 'ATC = 32/q + AVC',
             '(2, 12)', '(3, 15)', '(4, 24)', 'MC', 'ATC', 'AVC')


def check_budget(doc):
    x_star, y_star = 6, 4
    assert 2 * x_star + 3 * y_star == 24 and x_star * y_star == 24
    utility = lambda x: x * BUDGET(x)
    assert max((x / 1000 for x in range(0, 12001)), key=utility) == x_star
    assert math.isclose(-24 / x_star ** 2, -2 / 3), 'MRS equals price ratio at the optimum'
    budget = line_on(doc, BUDGET, [(0, 8), (x_star, y_star), (12, 0)])
    curves = {}
    for k in (12, 24, 36):
        want = samples(k / 10, 12, .25, (6,))
        line = line_on(doc, IC(k), [(k / 10, 10), (12, k / 12)])
        assert [x for x, _ in line] == want, (k, 'sampled every 0.25 plus endpoints and x = 6')
        ys = [y for _, y in line]
        slopes = [(b[1] - a[1]) / (b[0] - a[0]) for a, b in zip(line, line[1:])]
        assert all(s < 0 for s in slopes) and slopes == sorted(slopes), (k, 'decreasing and convex polyline')
        assert local_extrema(ys) == 0 and max(ys) <= 10 + TOL and min(x for x, _ in line) > 0
        curves[k] = line
    for a, b in itertools.combinations(curves, 2):
        assert not crossings(curves[a], curves[b]), ('indifference curves cross', a, b)
    gap = {k: [y - BUDGET(x) for x, y in line] for k, line in curves.items()}
    assert min(gap[24]) == 0 and all(g > 0 for (x, _), g in zip(curves[24], gap[24]) if x != x_star), 'U=24 touches only at E'
    assert [tuple(map(float, p)) for p in crossings(curves[24], budget)] == [(6.0, 4.0)]
    assert min(gap[36]) > 0 and not crossings(curves[36], budget), 'U=36 is unaffordable'
    assert len(crossings(curves[12], budget)) == 2, 'U=12 cuts the budget twice'
    assert len(doc['fills']) == 1 and same(doc['fills'][0], [(0, 0), (12, 0), (0, 8)]) and area(doc['fills'][0]) == 48
    assert doc['markers'] == {(x_star, y_star)}
    has_text(doc, 'Budget', 'U1 = 12', 'U2 = 24', 'U3 = 36', 'E (6, 4)', 'Budget: 2F + 3C = 24', 'MRS = C/F = 4/6 = 2/3',
             'PF/PC = 2/3', 'F* = 6', 'C* = 4', 'not\nconsumer surplus')


# Lessons 09-18 (Pindyck & Rubinfeld notation): each economic result is derived here, then compared with the drawing.
def polygon(doc, points):
    """The single fill whose vertices are exactly `points`, in order."""
    found = [f for f in doc['fills'] if same(f, points)]
    assert len(found) == 1, ('Expected one fill', points, len(found))
    return found[0]


def check_elasticity(doc):
    ep = lambda q: -1 * D(q) / q  # dQ/dP = -1 on P = 14 - Q
    assert (ep(4), ep(7), ep(10)) == (-2.5, -1, -0.4)
    revenue = lambda q: D(q) * q
    assert max((q / 100 for q in range(0, 1401)), key=revenue) == 7 and revenue(7) == 49
    elastic = line_on(doc, D, [(0, 14), (4, 10), (7, 7)])
    inelastic = line_on(doc, D, [(7, 7), (10, 4), (14, 0)])
    assert all(abs(ep(q)) > 1 for q, _ in elastic if 0 < q < 7) and all(abs(ep(q)) < 1 for q, _ in inelastic if q > 7), 'unit elastic only at Q = 7'
    assert len(doc['fills']) == 1 and area(polygon(doc, [(0, 0), (7, 0), (7, 7), (0, 7)])) == revenue(7)
    assert doc['markers'] == {(4, 10), (7, 7), (10, 4)}
    has_text(doc, 'Ep = −2.5', 'Ep = −1', 'Ep = −0.4', 'Elastic: |Ep| > 1', 'Inelastic: |Ep| < 1', 'R = P · Q = 49', 'Ep = −P / Q')


def check_income_substitution(doc):
    income, pc, before, after = 24, 3, 8, 2
    best = lambda pf, m: (m / (2 * pf), m / (2 * pc))  # U = FC spends half on each good
    a, b = best(before, income), best(after, income)
    u1 = a[0] * a[1]
    d = (math.sqrt(u1 * pc / after), math.sqrt(u1 * after / pc))  # cheapest bundle on U1 at the new prices
    assert (a, b, d, u1, b[0] * b[1]) == ((1.5, 4), (6, 4), (3, 2), 6, 24)
    assert (d[0] - a[0], b[0] - d[0]) == (1.5, 3), 'substitution +1.5, income +3'
    assert after * d[0] + pc * d[1] == 12
    curves = {}
    for k, extra, lo in ((6, (1.5, 3), .625), (24, (6,), 2.4)):
        line = line_on(doc, IC(k), [(lo, k / lo), (12, k / 12)])
        assert [x for x, _ in line] == samples(lo, 12, .25, extra)
        curves[k] = line
    old = line_on(doc, lambda f: (income - before * f) / pc, [(0, 8), a, (3, 0)])
    new = line_on(doc, lambda f: (income - after * f) / pc, [(0, 8), b, (12, 0)])
    comp = line_on(doc, lambda f: (12 - after * f) / pc, [(0, 4), d, (6, 0)])
    for line, curve, touch in ((old, curves[6], a), (comp, curves[6], d), (new, curves[24], b)):
        assert same_points(crossings(line, curve), [touch]), ('budget touches its indifference curve once', touch)
        assert all(y >= (line[0][1] + (line[-1][1] - line[0][1]) * x / line[-1][0]) - 1e-9 for x, y in curve), 'curve on or above'
    assert not doc['fills'] and doc['markers'] == {a, d, b}
    has_text(doc, 'U1 = 6', 'U2 = 24', 'PF = $8', 'PF = $2', 'Compensated: 2F + 3C = 12', 'Substitution +1.5\nIncome +3\nTotal effect +4.5')


def check_isoquant(doc):
    q1, w, r = 32, 2, 4
    l_star = math.sqrt(q1 * r / w)
    assert (l_star, q1 / l_star, w * l_star + r * q1 / l_star) == (8, 4, 32)
    iso = line_on(doc, lambda l: q1 / l, [(2.75, q1 / 2.75), (20, 1.6), (8, 4)])
    assert [x for x, _ in iso] == samples(2.75, 20, .25, (4, 8, 16))
    costs = {}
    for c, required in ((24, [(0, 6), (12, 0)]), (32, [(0, 8), (8, 4), (16, 0)]), (40, [(0, 10), (4, 8), (16, 2), (20, 0)])):
        costs[c] = line_on(doc, lambda l, c=c: (c - w * l) / r, required)
    assert not crossings(costs[24], iso), 'C0 cannot reach q1'
    assert same_points(crossings(costs[32], iso), [(8, 4)]) and same_points(crossings(costs[40], iso), [(4, 8), (16, 2)])
    line_on(doc, lambda l: l / 2, [(0, 0), (8, 4), (20, 10)])
    assert not doc['fills'] and doc['markers'] == {(8, 4), (4, 8), (16, 2)}
    has_text(doc, 'q1 = 32', 'C0 = $24', 'C1 = $32', 'C2 = $40', 'A (8, 4)', 'Expansion path', 'L* = 8\nK* = 4', 'w/r = 2/4 = 1/2')


def check_competitive_firm(doc):
    price = 39
    q_star = next(q / 100 for q in range(100, 701) if math.isclose(MC(q / 100), price))
    profit = (price - ATC(q_star)) * q_star
    assert (q_star, ATC(q_star), AVC(q_star), round(profit, 9)) == (5, 25.4, 19, 68)
    assert min(AVC(q / 100) for q in range(100, 701)) == AVC(3) == 15, 'shutdown at minimum AVC'
    assert MC(4) == ATC(4) == 24, 'P = $24 gives zero profit'
    want = samples(1, 7, .25, (2, 3, 4, 5))
    for fn, minimum in ((MC, 2), (AVC, 3), (ATC, 4)):
        line = line_on(doc, fn, [(1, fn(1)), (7, fn(7)), (minimum, fn(minimum))])
        assert [x for x, _ in line] == want and local_extrema([y for _, y in line]) == 1
    p_line = line_on(doc, lambda q: price, [(0, price), (q_star, price), (7, price)])
    assert same_points(crossings(p_line, line_on(doc, MC, [(1, MC(1))])), [(q_star, price)])
    rect = polygon(doc, [(0, 25.4), (5, 25.4), (5, 39), (0, 39)])
    assert math.isclose(area(rect), profit)
    assert doc['markers'] == {(5, 39), (5, 25.4), (3, 15)}
    has_text(doc, 'P = AR = MR = $39', 'π = $68', 'q* = 5', 'Shutdown (3, 15)', 'ATC(5) = 32/5 + 19 = 25.4', 'π = (39 − 25.4) · 5 = 68')


def check_tariff(doc):
    pw, tariff = 3, 1
    qs, qd, qs2, qd2 = S_inv(pw), D_inv(pw), S_inv(pw + tariff), D_inv(pw + tariff)
    assert (qs, qd, qs2, qd2) == (2, 11, 4, 10)
    a = [(0, 3), (2, 3), (4, 4), (0, 4)]
    b, c, d = [(2, 3), (4, 3), (4, 4)], [(10, 3), (11, 3), (10, 4)], [(4, 3), (10, 3), (10, 4), (4, 4)]
    cs = lambda p: (14 - p) * D_inv(p) / 2
    ps = lambda p: (p - 2) * S_inv(p) / 2
    assert cs(pw) - cs(pw + tariff) == 10.5 and ps(pw + tariff) - ps(pw) == 3
    assert [area(polygon(doc, f)) for f in (a, b, c, d)] == [3, 1, .5, 6] and len(doc['fills']) == 4
    assert area(a) + area(b) + area(c) + area(d) == 10.5, 'ΔCS = −(A + B + C + D)'
    line_on(doc, D, [(0, 14), (8, 6), (10, 4), (11, 3), (14, 0)])
    line_on(doc, S, [(0, 2), (2, 3), (4, 4), (8, 6), (14, 9)])
    line_on(doc, lambda q: pw, [(0, 3), (2, 3), (4, 3), (10, 3), (11, 3), (14, 3)])
    line_on(doc, lambda q: pw + tariff, [(0, 4), (4, 4), (10, 4), (14, 4)])
    assert doc['markers'] == {(2, 3), (11, 3), (4, 4), (10, 4), (8, 6)}
    has_text(doc, 'Pw = $3', 'Pw + T = $4', 'Qs = 2', 'Q′s = 4', 'Q′d = 10', 'Qd = 11', 'ΔCS = −(A + B + C + D) = −10.5', 'DWL = B + C = 1 + 0.5 = 1.5')


def check_monopsony(doc):
    me = lambda q: 2 + q  # d/dQ of (2 + Q/2)·Q
    qm = next(q / 1000 for q in range(0, 14001) if math.isclose(me(q / 1000), D(q / 1000)))
    assert (qm, S(qm), D_inv(6), S(8)) == (6, 5, 8, 6)
    net = lambda q: (14 * q - q * q / 2) - S(q) * q  # buyer's value minus expenditure
    assert max((q / 100 for q in range(0, 1401)), key=net) == qm
    line_on(doc, D, [(0, 14), (6, 8), (8, 6), (14, 0)])
    line_on(doc, S, [(0, 2), (6, 5), (8, 6), (14, 9)])
    line_on(doc, me, [(0, 2), (6, 8), (12, 14)])
    dwl = polygon(doc, [(6, 5), (6, 8), (8, 6)])
    transfer = polygon(doc, [(0, 5), (6, 5), (6, 6), (0, 6)])
    assert (area(dwl), area(transfer), len(doc['fills'])) == (3, 6, 2)
    assert doc['markers'] == {(6, 8), (6, 5), (8, 6)}
    has_text(doc, 'MV', 'S = AE', 'ME', 'ME = MV', 'P*m = 5', 'Q*m = 6', 'Pc = 6, Qc = 8', 'DWL = 3', 'Transfer = 6')


def check_discrimination(doc):
    d1, d2 = (lambda q: 14 - q), (lambda q: 8 - q / 2)
    mr1, mr2, mc = (lambda q: 14 - 2 * q), (lambda q: 8 - q), 2
    q1, q2 = (14 - mc) / 2, 8 - mc
    assert (q1, d1(q1), q2, d2(q2)) == (6, 8, 6, 5)
    e1, e2 = -1 * d1(q1) / q1, -2 * d2(q2) / q2
    assert math.isclose(d1(q1) * (1 + 1 / e1), mc) and math.isclose(d2(q2) * (1 + 1 / e2), mc), 'P(1 + 1/E) = MC'
    mrt = lambda q: 14 - 2 * q if q <= 3 else 10 - 2 * q / 3  # horizontal sum of MR1 and MR2
    assert mrt(12) == mc
    line_on(doc, d1, [(0, 14), (6, 8), (14, 0)]); line_on(doc, mr1, [(0, 14), (6, 2), (7, 0)])
    line_on(doc, d2, [(0, 8), (6, 5), (16, 0)]); line_on(doc, mr2, [(0, 8), (6, 2), (8, 0)])
    line_on(doc, mrt, [(0, 14), (3, 8), (12, 2), (15, 0)]); line_on(doc, lambda q: mc, [(0, 2), (6, 2), (12, 2), (16, 2)])
    assert not doc['fills'] and doc['markers'] == {(6, 8), (6, 5), (6, 2), (12, 2)}
    has_text(doc, 'D1 = AR1', 'D2 = AR2', 'MR1', 'MR2', 'MRT', 'MC', 'P1 = 8', 'P2 = 5', 'QT = 12', 'P1/P2 = (1 + 1/E2)/(1 + 1/E1)')


def check_cournot(doc):
    # x = Q2, y = Q1 as in the book's figure; each firm maximizes (12 - Q1 - Q2) Q with P = 14 - Q and MC = 2.
    best = lambda other: max((q / 100 for q in range(0, 1201)), key=lambda q: (12 - q - other) * q)
    assert [best(o) for o in (0, 4, 12)] == [6, 4, 0]
    r1 = line_on(doc, lambda q2: 6 - q2 / 2, [(0, 6), (4, 4), (12, 0)])
    r2 = [l['points'] for l in doc['lines'] if same(l['points'], [(6, 0), (4, 4), (0, 12)])]
    assert len(r2) == 1 and all(math.isclose(q2, 6 - q1 / 2) for q2, q1 in r2[0]), 'Q*2(Q1) = 6 − Q1/2'
    assert same_points(crossings(r1, r2[0]), [(4, 4)])
    line_on(doc, lambda q2: 6 - q2, [(0, 6), (3, 3), (6, 0)]); line_on(doc, lambda q2: 12 - q2, [(0, 12), (6, 6), (12, 0)])
    assert (14 - 6 - 2) * 3 == 18 and (14 - 8 - 2) * 4 == 16, 'collusion and Cournot profits per firm'
    assert not doc['fills'] and doc['markers'] == {(4, 4), (3, 3), (6, 6)}
    has_text(doc, 'Q*1(Q2)', 'Q*2(Q1)', 'Cournot equilibrium (4, 4)', 'Collusion curve', 'Competitive equilibrium (P = MC; π = 0)')


def check_trade(doc):
    ppf, mrt = (lambda f: max(0, 12 - f * f / 4)), (lambda f: f / 2)
    a, b, world = (4, 8), (6, 3), 3
    assert ppf(a[0]) == a[1] and mrt(a[0]) == a[1] / a[0] == 2, 'autarky: MRT = MRS on U1'
    assert ppf(b[0]) == b[1] and mrt(b[0]) == world
    income = world * b[0] + b[1]
    d = (income / (2 * world), income / 2)  # U = FC at world prices
    assert (income, d, d[0] * d[1]) == (21, (3.5, 10.5), 36.75) and d[1] > ppf(d[0]), 'D lies outside the PPF'
    frontier = line_on(doc, ppf, [(0, 12), a, b])
    assert math.isclose(frontier[-1][0], math.sqrt(48)) and abs(frontier[-1][1]) < 1e-9, 'PPF ends on the F axis'
    u1 = line_on(doc, IC(32), [(2, 16), a, (10, 3.2)])
    u2 = line_on(doc, IC(36.75), [d, (10, 3.675)])
    trade = line_on(doc, lambda f: income - world * f, [(2.5, 13.5), d, b, (7, 0)])
    assert same_points(crossings(u1, frontier), [a]) and same_points(crossings(u2, trade), [d])
    line_on(doc, lambda f: 16 - 2 * f, [(1.5, 13), a, (6.5, 3)])
    assert not doc['fills'] and doc['markers'] == {a, b, d}
    has_text(doc, 'PPF', 'U1 = 32', 'U2 = 36.75', 'World prices', 'Pre-trade prices', 'Imports 7.5', 'Exports 2.5', 'Exports 2.5 F\nImports 7.5 C')


def check_externality(doc):
    mec = 3
    msc = lambda q: S(q) + mec
    q1 = next(q / 100 for q in range(0, 1401) if math.isclose(S(q / 100), D(q / 100)))
    q_star = next(q / 100 for q in range(0, 1401) if math.isclose(msc(q / 100), D(q / 100)))
    assert (q1, D(q1), q_star, D(q_star)) == (8, 6, 6, 8)
    line_on(doc, D, [(0, 14), (6, 8), (8, 6), (14, 0)])
    line_on(doc, S, [(0, 2), (6, 5), (8, 6), (14, 9)])
    line_on(doc, msc, [(0, 5), (6, 8), (8, 9), (14, 12)])
    assert len(doc['fills']) == 1 and area(polygon(doc, [(6, 8), (8, 9), (8, 6)])) == 3
    assert doc['markers'] == {(8, 6), (6, 8)}
    has_text(doc, 'S = MC', 'MSC', 'MEC = $3', 'P* = 8', 'P1 = 6', 'Q* = 6', 'Q1 = 8', 'DWL = 3', 'Market Q1 = 8\nEfficient Q* = 6')


NEW_LESSON_CHECKS = {'09-elasticity-along-demand': check_elasticity, '10-income-and-substitution-effects': check_income_substitution,
                     '11-isoquants-and-isocost': check_isoquant, '12-competitive-firm-short-run': check_competitive_firm,
                     '13-import-tariff': check_tariff, '14-monopsony': check_monopsony,
                     '15-third-degree-price-discrimination': check_discrimination, '16-cournot-duopoly': check_cournot,
                     '17-gains-from-trade': check_trade, '18-negative-externality': check_externality}


def check_template(doc, stem):
    expected, names = TEMPLATES[stem]
    assert len(doc['lines']) == len(expected) and all(any(same(l['points'], e) for l in doc['lines']) for e in expected)
    assert not doc['fills'] and not doc['markers'], 'Templates carry no fills or markers'
    assert set(doc['user'].values()) == names | {CREDITS[stem]}, ('Templates carry only curve names and the credit', doc['user'].values())


def axis_flags(doc, dimension):
    axis = next(a for a in doc['axes'] if a.get('dimension') == dimension)
    flag = lambda tag: axis.find(NS + tag).get('visible') == 'true'
    return {'scale': axis.get('scale'), 'placement': axis.get('placement'), 'axis': axis.get('visible') == 'true',
            'ticks': flag('ticks'), 'tickLabels': flag('tick-labels'), 'grid': flag('grid'), 'title': flag('title')}


def only_labels(doc, stem, names):
    credit = {CREDITS[stem]} if stem in CREDITS else set()
    assert sorted(doc['user'].values()) == sorted(names | credit), ('Template labels', stem, doc['user'].values())


def lone_line(doc, points, dash=None):
    """The document line whose vertices are exactly `points`, in order."""
    found = [l for l in doc['lines'] if same(l['points'], points)]
    assert len(found) == 1, ('Expected one line', points[:3], len(found))
    if dash is not None:
        assert (found[0]['dash'] not in (None, 'solid')) == dash, ('dash', found[0]['dash'])
    return found[0]['points']


def check_function_plot(doc, stem):
    for dim in 'xy':
        f = axis_flags(doc, dim)
        assert f['placement'] == 'origin' and f['grid'] and f['scale'] == 'linear', ('Four quadrants, origin axes, grid', dim, f)
        assert not f['title'], ('Axes are named at their ends, not by edge titles far from the origin', dim)
    want = [(x, CUBIC(x)) for x in samples(-10, 10, .25)]
    assert len(doc['lines']) == 1 and same(doc['lines'][0]['points'], want), 'f(x) sampled every 0.25 on [-10, 10]'
    ys = [y for _, y in want]
    assert local_extrema(ys) == 2, 'one maximum and one minimum, no false extrema'
    turns = [want[i] for i in range(1, len(ys) - 1) if (ys[i] - ys[i - 1]) * (ys[i + 1] - ys[i]) < 0]
    assert sorted(set(turns)) == [(-5, 5), (5, -5)] and max(map(abs, ys)) <= 10, ('turning points are the analytic extrema', turns)
    zeros = crossings(want, [(-10, 0), (10, 0)])
    assert len(zeros) == 3 and all(abs(z[0] - r) < .05 for z, r in zip(sorted(zeros), (-math.sqrt(75), 0, math.sqrt(75)))), zeros
    assert {(x > 0, y > 0) for x, y in want if x and y} == {(True, True), (True, False), (False, True), (False, False)}, 'all four quadrants'
    assert not doc['fills'] and not doc['markers']
    only_labels(doc, stem, {'f(x)', 'x', 'y'})


def check_time_series(doc, stem):
    assert axis_flags(doc, 'x')['placement'] == 'edge'
    series = [(2010 + i, v) for i, v in enumerate(SERIES_A)]
    lone_line(doc, series, dash=False)
    assert doc['markers'] == set(series) and all(float(x).is_integer() for x, _ in series), 'Plain-number years with points'
    lone_line(doc, [(2020, 0), (2020, 88)], dash=True)
    assert len(doc['lines']) == 2 and not doc['fills']
    only_labels(doc, stem, {'Event', 'Series A'})


def check_scatter_plot(doc, stem):
    cloud = [(x, round((1.5 + .7 * x + n) * 100) / 100) for x, n in zip(SCATTER_X, SCATTER_NOISE)]
    assert same_points(doc['markers'], cloud) and len(doc['markers']) == len(cloud), 'Placeholder cloud'
    line = lone_line(doc, HAND_LINE, dash=True)
    assert len(doc['lines']) == 1 and not doc['fills']
    at = lambda x: line[0][1] + (x - line[0][0]) * (line[1][1] - line[0][1]) / (line[1][0] - line[0][0])
    above = sum(y > at(x) for x, y in cloud)
    assert 8 <= above <= 12 and all(abs(y - at(x)) < 1 for x, y in cloud), 'Hand line runs through the middle of the cloud'
    only_labels(doc, stem, {'Series A', 'Trend line drawn by hand\n(not a computed fit)'})


def check_bar_chart(doc, stem):
    assert axis_flags(doc, 'y')['placement'] == 'origin', 'Value axis starts at 0'
    x = axis_flags(doc, 'x')
    assert not x['ticks'] and not x['tickLabels'], 'Categories are labels, not numeric ticks'
    want = [[(c - .3, 0), (c - .3, v), (c + .3, v), (c + .3, 0)] for c, v in zip(range(1, 6), BARS)]
    assert len(doc['fills']) == len(want) and all(same(f, w) for f, w in zip(doc['fills'], want)), 'Bars are filled rectangles from 0'
    assert all(math.isclose(area(f), .6 * v) for f, v in zip(doc['fills'], BARS))
    assert not doc['lines'] and not doc['markers']
    only_labels(doc, stem, {f'Category {i}' for i in range(1, 6)})


def check_log_scale(doc, stem):
    y = axis_flags(doc, 'y')
    assert y['scale'] == 'logarithmic' and y['placement'] == 'edge' and axis_flags(doc, 'x')['scale'] == 'linear'
    series = [(t, 1.5 * 2 ** t) for t in range(10)]
    lone_line(doc, series, dash=False)
    logs = [math.log10(v) for _, v in series]
    assert all(math.isclose(b - a, math.log10(2)) for a, b in zip(logs, logs[1:])), 'Constant growth: straight on the log axis'
    assert doc['markers'] == set(series) and len(doc['lines']) == 1 and not doc['fills']
    assert AXIS_MIN['template-log-scale'][1] <= series[0][1] and series[-1][1] <= AXES['template-log-scale'][1]
    only_labels(doc, stem, {'Series A', 'Constant growth rate:\na straight line on a log scale'})


def check_number_line(doc, stem):
    y, x = axis_flags(doc, 'y'), axis_flags(doc, 'x')
    assert not any(y[k] for k in ('axis', 'ticks', 'tickLabels', 'grid', 'title')), 'A single horizontal axis'
    assert x['axis'] and x['ticks'] and x['tickLabels'] and x['placement'] == 'origin'
    lone_line(doc, [(-2, 0), (3, 0)], dash=False)
    assert doc['shapes'][(-2, 0)] == 'circle' and doc['shapes'][(3, 0)] == 'hollow', 'Closed at -2, open at 3'
    assert len(doc['lines']) == 1 and not doc['fills']
    only_labels(doc, stem, {'[−2, 3)   −2 ≤ x < 3', 'closed', 'open'})


def check_lorenz_curve(doc, stem):
    lone_line(doc, [(0, 0), (100, 100)])
    curve = lone_line(doc, [(x, LORENZ(x)) for x in samples(0, 100, 2)], dash=False)
    slopes = [(b[1] - a[1]) / (b[0] - a[0]) for a, b in zip(curve, curve[1:])]
    assert all(s >= 0 for s in slopes) and slopes == sorted(slopes) and len(set(slopes)) == len(slopes), 'Monotonic and convex'
    assert local_extrema([y for _, y in curve]) == 0 and curve[0] == (0, 0) and curve[-1] == (100, 100)
    assert all(y < x for x, y in curve[1:-1]), 'Below the line of equality'
    assert len(crossings(curve, [(0, 0), (100, 100)])) == 2, 'Meets equality only at the ends'
    assert len(doc['fills']) == 1 and same(doc['fills'][0], curve), 'Fill is the area between the curve and equality'
    exact = 100 * 100 / 2 - 100 ** 3 / 300  # ∫(p - p²/100) dp on [0, 100]
    assert abs(area(doc['fills'][0]) - exact) / exact < .01, (area(doc['fills'][0]), exact)
    assert not doc['markers']
    only_labels(doc, stem, {'Line of equality', 'Lorenz curve'})


def check_production_possibilities(doc, stem):
    assert len(doc['lines']) == 1
    frontier = doc['lines'][0]['points']
    assert frontier[0] == (0, 8) and frontier[-1] == (9, 0) and len(frontier) == 38, 'Every 2.5° of the ellipse angle plus A'
    assert all(math.isclose(PPF_LEVEL(x, y), 1, abs_tol=1e-9) for x, y in frontier), 'Every vertex on the frontier'
    slopes = [(b[1] - a[1]) / (b[0] - a[0]) for a, b in zip(frontier, frontier[1:])]
    assert all(s < 0 for s in slopes[1:]) and slopes[0] <= 0 and slopes == sorted(slopes, reverse=True), 'Decreasing and concave'
    assert local_extrema([y for _, y in frontier]) == 0
    a, b, c = (5.4, 6.4), (3, 3), (8, 7)
    assert same_points(doc['markers'], [a, b, c]) and len(doc['markers']) == 3
    assert any(same([p], [a]) for p in frontier) and PPF_LEVEL(*b) < 1 < PPF_LEVEL(*c), 'A on, B inside, C outside'
    assert not doc['fills']
    only_labels(doc, stem, {'A  Efficient', 'B  Inefficient', 'C  Unattainable', 'PPF'})


TEMPLATE_CHECKS = {'template-function-plot': check_function_plot, 'template-time-series': check_time_series,
                   'template-scatter-plot': check_scatter_plot, 'template-bar-chart': check_bar_chart,
                   'template-log-scale': check_log_scale, 'template-number-line': check_number_line,
                   'template-lorenz-curve': check_lorenz_curve, 'template-production-possibilities': check_production_possibilities}


def check_irpf(doc):
    """Recompute concentration-curve points from the raw AEAT tables and compare with the document."""
    tables = [prepare.aeat_table(DATA / 'Sources/aeat-irpf-2024' / name) for name in
              ('435-base-imponible-general.html', '460-base-imponible-ahorro.html', '595-cuota-resultante.html')]
    rows = [(tables[0][b][0], tables[0][b][2] + tables[1][b][2], tables[2][b][2]) for b in prepare.BRACKETS]
    assert all(tables[0][b][0] == tables[1][b][0] == tables[2][b][0] for b in prepare.BRACKETS)
    totals = [sum(r[i] for r in rows) for i in range(3)]
    published = (tables[0]['Total'][0], tables[0]['Total'][2] + tables[1]['Total'][2], tables[2]['Total'][2])
    assert all(abs(a - b) <= 1 for a, b in zip(totals, published)), ('Brackets add up to the published totals (to 1 euro)', totals, published)
    points, running = [(0.0, 0.0, 0.0)], [0.0, 0.0, 0.0]
    for r in rows:
        running = [a + b for a, b in zip(running, r)]
        points.append(tuple(100 * a / t for a, t in zip(running, totals)))
    assert all(math.isclose(a, 100, abs_tol=1e-9) for a in points[-1]), 'Curves end at (100, 100)'
    points[-1] = (100.0, 100.0, 100.0)
    for column in (1, 2):
        expected = [(p[0], p[column]) for p in points]
        assert sum(same(l['points'], expected) for l in doc['lines']) == 1, ('Vertices equal recomputed shares', column)
    assert len(doc['lines']) == 4, 'Diagonal, base, tax and one guide'
    xs = [p[0] for p in points]
    assert all(b > a for a, b in zip(xs, xs[1:])), 'Returns axis strictly increasing'
    assert all(b >= a for a, b in zip([p[2] for p in points], [p[2] for p in points[1:]])), 'Tax curve monotonic'
    for (_, b0, _), (_, b1, _), r in zip(points, points[1:], rows):
        assert (b1 < b0) == (r[1] < 0), 'Base curve falls only where a bracket has a negative net base'
    for p, r in zip(points[1:-1], rows):
        assert (p[2] < p[1]) == (p[1] > 0), ('Tax curve lies below the base curve exactly where the cumulative base is positive', p)
    line_on(doc, lambda x: x, [(0, 0), (100, 100)])
    assert len(doc['fills']) == 2
    assert same(doc['fills'][0], [(0, 0), (100, 100)] + [(p[0], p[1]) for p in reversed(points[1:-1])])
    assert same(doc['fills'][1], [(p[0], p[1]) for p in points] + [(p[0], p[2]) for p in reversed(points[1:-1])])
    mid, top = points[5], points[7]
    assert tables[0]['(12 - 21]'] and math.isclose(mid[0], 100 * sum(r[0] for r in rows[:5]) / totals[0])
    assert same_points(doc['markers'], [(mid[0], mid[1]), (mid[0], mid[2])])
    pct = lambda v: f'{v:.1f}%'
    has_text(doc, 'Fuente: AEAT, Estadística de los declarantes del IRPF 2024 (actualizada el 01/07/2026); elaboración propia.',
             'Territorio de Régimen Fiscal Común', f'{totals[0] / 1e6:.1f} million returns', f'€{totals[1] / 1e9:.0f} bn taxable base',
             f'€{totals[2] / 1e9:.0f} bn tax due', pct(mid[1]) + ' of base', pct(mid[2]) + ' of tax',
             f'{pct(mid[0])} of returns\n{pct(mid[1])} of the taxable base\n{pct(mid[2])} of the tax due',
             f'{pct(100 - top[0])} of returns\n{pct(100 - top[1])} of the taxable base\n{pct(100 - top[2])} of the tax due')


def check_housing(doc):
    """Deflate, smooth and rebase the raw INE series independently, then compare with the document."""
    raw = {c: json.loads((DATA / 'Sources/ine' / (c + '.json')).read_text())['Data'] for c in ('IPV769', 'ETCL1527', 'IPC251852')}
    ipv = {(d['Anyo'], d['FK_Periodo'] - 18): d['Valor'] for d in raw['IPV769']}
    wage = {(d['Anyo'], d['FK_Periodo'] - 18): d['Valor'] for d in raw['ETCL1527']}
    cpi = {(d['Anyo'], d['FK_Periodo']): d['Valor'] for d in raw['IPC251852']}
    quarters = [(y, q) for y in range(2008, 2026) for q in range(1, 5)]
    assert all(k in ipv and k in wage for k in quarters) and (2026, 1) not in ipv and (2026, 1) not in cpi
    cpi_q = {(y, q): (cpi[(y, 3 * q - 2)] + cpi[(y, 3 * q - 1)] + cpi[(y, 3 * q)]) / 3 for y, q in quarters}
    real = {name: {k: s[k] / cpi_q[k] for k in quarters} for name, s in (('house', ipv), ('wage', wage))}
    base = {name: sum(r[(2015, q)] for q in range(1, 5)) / 4 for name, r in real.items()}
    expected = {name: [(y + (q - 1) / 4, 100 * sum(r[quarters[i - j]] for j in range(4)) / 4 / base[name])
                       for i, (y, q) in enumerate(quarters) if i >= 3] for name, r in real.items()}
    for name in ('house', 'wage'):
        assert sum(same(l['points'], expected[name]) for l in doc['lines']) == 1, ('Vertices equal recomputed real indices', name)
    assert len(doc['lines']) == 3, 'Two series and the 100 reference line'
    house, wages = expected['house'], expected['wage']
    assert len(house) == 69 and house[0][0] == 2008.75 and house[-1][0] == 2025.75
    for series in (house, wages):
        assert math.isclose(dict(series)[2015.75], 100, abs_tol=1e-9), '2015 average = 100 (2015 Q4 four-quarter average)'
        assert all(0 < v < AXES['house-prices-and-wages'][1] for _, v in series)
    line_on(doc, lambda x: 100, [(2008, 100), (2026, 100)])
    low = min(house, key=lambda p: p[1])
    assert same_points(doc['markers'], [house[0], low, house[-1], wages[-1]]) and not doc['fills']
    has_text(doc, 'Elaboración propia con datos extraídos del sitio web del INE: www.ine.es',
             f'House prices {house[-1][1]:.1f}\nWages {wages[-1][1]:.1f}\nin 2025 Q4',
             f'From {house[0][1]:.1f} in 2008 Q4 to a\nlow of {low[1]:.1f} in {int(low[0])} Q{round((low[0] - int(low[0])) * 4) + 1}.',
             f'{house[-1][1]:.1f}', f'{wages[-1][1]:.1f}', 'four-quarter moving average', '2025.75 is 2025 Q4')


def check_revenue(doc):
    """Every plotted value must equal the OECD CSV observation exactly (same decimal value, no rounding)."""
    import csv
    with (DATA / 'Sources/oecd-revenue-statistics/ESP-total-tax-revenue-pct-gdp.csv').open(newline='') as f:
        rows = sorted(csv.DictReader(f), key=lambda r: int(r['TIME_PERIOD']))
    assert all(r['REF_AREA'] == 'ESP' and r['STANDARD_REVENUE'] == '_T' and r['UNIT_MEASURE'] == 'PT_B1GQ' and r['OBS_STATUS'] == 'A' for r in rows)
    source = [(float(r['TIME_PERIOD']), float(r['OBS_VALUE'])) for r in rows]
    assert [int(x) for x, _ in source] == list(range(1965, 2025)), 'Annual 1965-2024'
    lines = [l['points'] for l in doc['lines']]
    assert lines == [source], 'Single line whose vertices equal the source values exactly'
    by_year = dict(source)
    high, low = max(source, key=lambda p: p[1]), min(source, key=lambda p: p[1])
    assert same_points(doc['markers'], [low, (2007, by_year[2007]), (2009, by_year[2009]), high, source[-1]]) and not doc['fills']
    assert all(0 < v < AXES['tax-revenue-share-of-gdp'][1] for _, v in source)
    value = lambda p: f'{p[1]:.1f}% in {int(p[0])}'
    has_text(doc, 'OECD (2025), Revenue Statistics in OECD member countries - Comparative tax revenues',
             '(accessed on 15 November 2026)', 'DSD_REV_COMP_OECD@DF_RSOECD,2.0/ESP.TAX_REV.S13._T._T.PT_B1GQ.A',
             'Redistributions must keep\nthis OECD acknowledgment.', value(low), value(high), value(source[-1]),
             value((2007, by_year[2007])), value((2009, by_year[2009])),
             f'{source[-1][1]:.1f}% of GDP in 2024\nfrom {source[0][1]:.1f}% in 1965',
             f'From 2007 to 2009 it fell\n{by_year[2007] - by_year[2009]:.1f} points.')


DATA_CHECKS = {'irpf-concentration-2024': check_irpf, 'house-prices-and-wages': check_housing,
               'tax-revenue-share-of-gdp': check_revenue}


def curved_report(directory, stem, doc):
    """Measure what the native curved connection would draw through each sampled line; documents keep straight."""
    probe = json.loads((directory / (stem + '-curved-probe.json')).read_text())
    if stem in CURVED_TEMPLATES:
        return curved_template_report(probe, stem)
    if not probe or stem not in ('07-cost-curves', '08-budget-and-indifference'):
        return {}  # data charts are measured series, not formulas; they stay straight-connected
    fns = {'07-cost-curves': [MC, AVC, ATC], '08-budget-and-indifference': [IC(12), IC(24), IC(36)]}[stem]
    report = {}
    for entry in probe:
        pts = [tuple(p) for p in entry['points']]
        fn = next(f for f in fns if on(f, [pts[0], pts[-1]]))
        name = {MC: 'MC', AVC: 'AVC', ATC: 'ATC'}.get(fn) or 'U=%g' % round(fn(1))
        err = max(abs(y - fn(x)) for x, y in pts)
        result = {'maxAbsError': err, 'extrema': local_extrema([y for _, y in pts], 1e-7)}
        if stem == '08-budget-and-indifference' and name == 'U=24':
            result['minGapToBudget'] = min(y - BUDGET(x) for x, y in pts)
        report[name] = result
    return report


# Templates whose sampled curve could be switched to the native curved connection by a user.
CURVED_TEMPLATES = {'template-function-plot': (CUBIC, 2), 'template-lorenz-curve': (LORENZ, 0),
                    'template-production-possibilities': (PPF, 0)}


def curved_template_report(probe, stem):
    """Overshoot and extrema of the native curved connection through the sampled template curve (never saved)."""
    fn, extrema = CURVED_TEMPLATES[stem]
    entry = next(e for e in probe if len(e['points']) > 100)
    pts = [tuple(p) for p in entry['points']]
    result = {'maxAbsError': max(abs(y - fn(x)) for x, y in pts if 0 <= x <= 9 or stem != 'template-production-possibilities'),
              'extrema': local_extrema([y for _, y in pts], 1e-7), 'expectedExtrema': extrema}
    if stem == 'template-lorenz-curve':
        result['minBelowEquality'] = min(x - y for x, y in pts[1:-1])
        result['minY'] = min(y for _, y in pts)
    if stem == 'template-production-possibilities':
        result['maxLevel'] = max(PPF_LEVEL(x, y) for x, y in pts)
        result['minX'], result['minY'] = min(x for x, _ in pts), min(y for _, y in pts)
    # A user switching the line to "curved" must not get a false extremum or an overshoot past the axes or equality.
    assert result['extrema'] == extrema, (stem, 'curved connection adds extrema', result)
    assert result.get('minY', 0) >= -1e-9 and result.get('minX', 0) >= -1e-9, (stem, 'curved connection overshoots an axis', result)
    assert result.get('minBelowEquality', 1) > 0 and result.get('maxLevel', 1) < 1.01, (stem, 'curved connection overshoots', result)
    return {'curve': result}


def validate(directory, report=None):
    for stem in STEMS:
        path = directory / (stem + '.graphink')
        assert path.is_file(), f'Missing generated document: {path}'
        doc = parse(path)
        assert doc['preview'] == (directory / (stem + '.pdf')).read_bytes(), 'Packaged preview differs from rendered PDF'
        assert tuple(float(a.get('min')) for a in doc['axes']) == AXIS_MIN.get(stem, (0, 0)), stem
        assert tuple(float(a.get('max')) for a in doc['axes']) == AXES[stem], stem
        assert tuple(doc['titles']) == TITLES.get(stem, ('Quantity Q (units per week)', 'Price P (dollars per unit)')), doc['titles']
        if stem in UNCREDITED:
            assert stem not in CREDITS and not any(t.startswith(('Concepts:', 'Inspired by')) for t in doc['user'].values()), stem
        else:
            assert list(doc['user'].values()).count(CREDITS[stem]) == 1, ('Exactly one credit label', stem)
        if not stem.startswith('template-'):
            # Lessons and data charts: the grid is on only for the tax-revenue chart (templates check their own).
            grids = [a.find(NS + 'grid').get('visible') == 'true' for a in doc['axes']]
            assert grids == ([True, True] if stem == 'tax-revenue-share-of-gdp' else [False, False]), ('Grid on only for the tax-revenue chart', stem, grids)
        if stem in TEMPLATE_CHECKS:
            TEMPLATE_CHECKS[stem](doc, stem)
        elif stem.startswith('template-'):
            check_template(doc, stem)
        elif stem in DATA_CHECKS:
            has_text(doc, 'OFFICIAL DATA, VALUES AS PUBLISHED' if stem == 'tax-revenue-share-of-gdp' else 'OFFICIAL DATA, OUR CALCULATIONS')
            DATA_CHECKS[stem](doc)
        else:
            has_text(doc, 'SYNTHETIC TEACHING MODEL', PALE_NOTE)
            note = [l for l in doc['labels'] if label_text(l) == PALE_NOTE]
            fills = [c for c in note[0].iter(NS + 'color')] if len(note) == 1 else []
            assert len(fills) == 1 and (fills[0].get('r'), fills[0].get('g'), fills[0].get('b')) == PALE_RGB, ('Note in the pale credit gray', stem)
            {'04-binding-price-ceiling': lambda d: check_price_control(d, 'ceiling'),
             '05-binding-price-floor': lambda d: check_price_control(d, 'floor'),
             '06-monopoly': check_monopoly, '07-cost-curves': check_costs,
             '08-budget-and-indifference': check_budget, **NEW_LESSON_CHECKS}[stem](doc)
        if report is not None:
            measured = curved_report(directory, stem, doc)
            if measured:
                report[stem] = measured
        before = json.loads((directory / (stem + '-before.json')).read_text())
        close(before['defaults'], {'font-name': 'HelveticaNeue', 'line-color': [.12, .18, .24, 1],
                                   'text-color': [.12, .18, .24, 1], 'fill-color': [.12, .18, .24, .17]})
        for suffix in ('-reopen', '-roundtrip'):
            close(before, json.loads((directory / (stem + suffix + '.json')).read_text()))
        assert (directory / (stem + '.pdf')).read_bytes().startswith(b'%PDF-')
        assert (directory / (stem + '.png')).read_bytes().startswith(b'\x89PNG')
    print(f'PASS: {len(STEMS)} editable graphs, model economics, sampled-curve extrema/crossings, resolved IDs, '
          'native semantic roundtrips and preview outputs.')


def self_check(directory, evidence=None):
    if evidence is None:
        evidence = Path(tempfile.mkdtemp(prefix='graphink-catalog-negative-', dir='/private/tmp'))
    else:
        evidence.mkdir()
    mutations = {'nonbinding-ceiling': '04-binding-price-ceiling', 'false-cost-extremum': '07-cost-curves',
                 'crossing-indifference': '08-budget-and-indifference', 'template-annotation': 'template-market-equilibrium',
                 'dented-frontier': 'template-production-possibilities', 'lorenz-above-equality': 'template-lorenz-curve',
                 'linear-log-axis': 'template-log-scale', 'unlabelled-hand-line': 'template-scatter-plot',
                 'closed-open-end': 'template-number-line', 'compensated-off-u1': '10-income-and-substitution-effects',
                 'shifted-reaction-curve': '16-cournot-duopoly',
                 'unresolved-reference': '06-monopoly', 'drifted-house-index': 'house-prices-and-wages',
                 'tax-above-base': 'irpf-concentration-2024', 'truncated-credit': 'tax-revenue-share-of-gdp'}
    for name, stem in mutations.items():
        candidate = evidence / name
        shutil.copytree(directory, candidate)
        path = candidate / (stem + '.graphink')
        with zipfile.ZipFile(path) as package:
            parts = [(info, package.read(info)) for info in package.infolist()]
            root = ET.fromstring(package.read('contents.xml'))
        graph = root.find(NS + 'graph')
        vertices = graph.findall(NS + 'vertex')
        if name == 'nonbinding-ceiling':
            for v in vertices:
                if float(v.get('y')) == 5 and float(v.get('x')) in (0, 14):
                    v.set('y', '7')
        elif name == 'false-cost-extremum':
            v = next(v for v in vertices if float(v.get('x')) == 5.5 and math.isclose(float(v.get('y')), AVC(5.5)))
            v.set('y', str(AVC(5.5) - 2.5))
        elif name == 'crossing-indifference':
            v = next(v for v in vertices if float(v.get('x')) == 6.25 and math.isclose(float(v.get('y')), 24 / 6.25))
            v.set('y', str(BUDGET(6.25) - .01))
        elif name == 'template-annotation':
            label = next(l for l in graph.findall(NS + 'label') if label_text(l) == 'S')
            next(label.iter(NS + 'lit')).text = 'Tax revenue = 18'
        elif name == 'dented-frontier':
            v = next(v for v in vertices if math.isclose(float(v.get('x')), 9 * math.cos(math.radians(30))))
            v.set('y', str(float(v.get('y')) - .3))
        elif name == 'lorenz-above-equality':
            v = next(v for v in vertices if float(v.get('x')) == 50 and float(v.get('y')) == 25)
            v.set('y', '55')
        elif name == 'linear-log-axis':
            next(a for a in graph.findall(NS + 'axis') if a.get('dimension') == 'y').set('scale', 'linear')
        elif name == 'unlabelled-hand-line':
            label = next(l for l in graph.findall(NS + 'label') if 'drawn by hand' in label_text(l))
            for lit in label.iter(NS + 'lit'):
                lit.text = (lit.text or '').replace('drawn by hand', 'of best fit')
        elif name == 'compensated-off-u1':
            v = next(v for v in vertices if float(v.get('x')) == 3 and float(v.get('y')) == 2)
            v.set('y', '2.2')
        elif name == 'shifted-reaction-curve':
            v = next(v for v in vertices if float(v.get('x')) == 0 and float(v.get('y')) == 6)
            v.set('y', '6.5')
        elif name == 'closed-open-end':
            next(v for v in vertices if v.get('shape') == 'hollow').set('shape', 'circle')
        elif name == 'drifted-house-index':
            v = next(v for v in vertices if float(v.get('x')) == 2020.25 and float(v.get('y')) > 110)
            v.set('y', str(float(v.get('y')) + 0.05))
        elif name == 'truncated-credit':
            label = next(l for l in graph.findall(NS + 'label') if label_text(l) == CREDITS[stem])
            next(label.iter(NS + 'lit')).text = INSPIRED
        elif name == 'tax-above-base':
            v = next(v for v in vertices if 70 < float(v.get('x')) < 71 and float(v.get('y')) < 20)
            v.set('y', '40')
        else:
            graph.find(NS + 'fill/' + NS + 'vertices').set('ids', 'missing')
        with zipfile.ZipFile(path, 'w') as package:
            for info, data in parts:
                package.writestr(info, ET.tostring(root, encoding='utf-8', xml_declaration=True)
                                 if info.filename == 'contents.xml' else data)
        try:
            validate(candidate)
        except (AssertionError, KeyError, StopIteration):
            continue
        raise AssertionError('Validator accepted mutation: ' + name)
    print('PASS: validator rejected ' + ', '.join(mutations) + '; evidence: ' + str(evidence))
    return str(evidence)


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog='Example: python3 Examples/Tools/validate.py --input-dir /private/tmp/catalog-run/artifacts')
    parser.add_argument('--input-dir', type=Path, required=True)
    parser.add_argument('--self-check', action='store_true', help='Also reject corrupted copies; retain negative evidence under /private/tmp')
    args = parser.parse_args()
    report = {}
    validate(args.input_dir, report)
    print(json.dumps(report, indent=2))
    if args.self_check:
        self_check(args.input_dir)


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, ET.ParseError, zipfile.BadZipFile, KeyError, StopIteration) as exc:
        print('ERROR: ' + repr(exc), file=sys.stderr)
        sys.exit(1)
