#!/usr/bin/env python3
"""Derive the plotted data-chart series from the raw official downloads in Examples/Data/Sources (stdlib only)."""
import argparse
import csv
import html
import json
import re
import sys
from pathlib import Path

SOURCES = Path(__file__).resolve().parent / 'Sources'
BRACKETS = ['Negativo y Cero', '(0 - 1,5]', '(1,5 - 6]', '(6 - 12]', '(12 - 21]', '(21 - 30]', '(30 - 60]',
            '(60 - 150]', '(150 - 601]', 'Mayor de 601']
BASE_YEAR = 2015


def number(text):
    return float(text.replace('.', '').replace(',', '.'))


def aeat_table(path):
    """Rows of an AEAT 'por tramos de rendimiento' page: bracket -> (all returns, returns with item, amount in euros)."""
    raw = path.read_text(encoding='utf-8')
    text = re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', re.sub(r'<script.*?</script>|<style.*?</style>', '', raw, flags=re.S))))
    assert 'Ejercicio 2024' in text and 'Tipo de Declaración Total' in text, path
    body = text[text.index('INFORMACIÓN SOBRE LA PARTIDA'):text.index('Notas')]
    rows = {}
    for label, values in re.findall(r'(Negativo y Cero|\(\d+(?:,\d+)? - \d+(?:,\d+)?\]|Mayor de \d+|Total) ((?:-?[\d.,]+ ){6}-?[\d.,]+)', body):
        v = [number(x) for x in values.split()]
        rows[label] = (v[0], v[2], v[4])
    assert list(rows) == BRACKETS + ['Total'], (path, list(rows))
    return rows


def irpf():
    base_general = aeat_table(SOURCES / 'aeat-irpf-2024/435-base-imponible-general.html')
    base_savings = aeat_table(SOURCES / 'aeat-irpf-2024/460-base-imponible-ahorro.html')
    tax = aeat_table(SOURCES / 'aeat-irpf-2024/595-cuota-resultante.html')
    brackets = []
    for label in BRACKETS:
        returns = base_general[label][0]
        assert returns == base_savings[label][0] == tax[label][0], 'Return counts must agree across tables'
        brackets.append({'bracket': label, 'returns': returns, 'base': base_general[label][2] + base_savings[label][2],
                         'tax': tax[label][2]})
    totals = {k: sum(b[k] for b in brackets) for k in ('returns', 'base', 'tax')}
    published = {'returns': base_general['Total'][0], 'base': base_general['Total'][2] + base_savings['Total'][2], 'tax': tax['Total'][2]}
    points, cum = [[0.0, 0.0, 0.0]], {'returns': 0.0, 'base': 0.0, 'tax': 0.0}
    for b in brackets:
        for k in cum:
            cum[k] += b[k]
        points.append([100 * cum['returns'] / totals['returns'], 100 * cum['base'] / totals['base'], 100 * cum['tax'] / totals['tax']])
    points[-1] = [100.0, 100.0, 100.0]  # exact by construction; avoids float residue at the end point
    return {'brackets': brackets, 'totals': totals, 'publishedTotals': published, 'points': points}


def ine_series(code):
    data = json.loads((SOURCES / 'ine' / (code + '.json')).read_text())
    assert data['COD'] == code
    return {(d['Anyo'], d['FK_Periodo']): d['Valor'] for d in data['Data'] if d['Valor'] is not None}


def housing():
    ipv = {(y, p - 18): v for (y, p), v in ine_series('IPV769').items()}
    wage = {(y, p - 18): v for (y, p), v in ine_series('ETCL1527').items()}
    cpi = ine_series('IPC251852')
    quarters = sorted(k for k in ipv if k in wage and all((k[0], 3 * k[1] - m) in cpi for m in range(3)))
    rows = []
    for year, q in quarters:
        cpi_q = sum(cpi[(year, 3 * q - m)] for m in range(3)) / 3
        rows.append({'year': year, 'quarter': q, 'x': year + (q - 1) / 4, 'ipv': ipv[(year, q)], 'wage': wage[(year, q)],
                     'cpi': cpi_q, 'realHouse': ipv[(year, q)] / cpi_q, 'realWage': wage[(year, q)] / cpi_q})
    assert [r['x'] for r in rows] == [rows[0]['x'] + i / 4 for i in range(len(rows))], 'Quarters must be consecutive'
    base = {k: sum(r[k] for r in rows if r['year'] == BASE_YEAR) / 4 for k in ('realHouse', 'realWage')}
    points = []
    for i in range(3, len(rows)):
        window = rows[i - 3:i + 1]
        points.append([rows[i]['x']] + [100 * sum(r[k] for r in window) / 4 / base[k] for k in ('realHouse', 'realWage')])
    return {'quarters': rows, 'base': base, 'baseYear': BASE_YEAR, 'points': points,
            'first': [rows[3]['year'], rows[3]['quarter']], 'last': [rows[-1]['year'], rows[-1]['quarter']]}


def revenue():
    with (SOURCES / 'oecd-revenue-statistics/ESP-total-tax-revenue-pct-gdp.csv').open(newline='') as f:
        rows = sorted(csv.DictReader(f), key=lambda r: int(r['TIME_PERIOD']))
    assert {(r['REF_AREA'], r['MEASURE'], r['SECTOR'], r['STANDARD_REVENUE'], r['UNIT_MEASURE'], r['FREQ']) for r in rows} == \
        {('ESP', 'TAX_REV', 'S13', '_T', 'PT_B1GQ', 'A')}, 'Spain, total tax revenue, general government, % of GDP, annual'
    years = [int(r['TIME_PERIOD']) for r in rows]
    assert years == list(range(years[0], years[-1] + 1)), 'Consecutive years'
    return {'points': [[int(r['TIME_PERIOD']), float(r['OBS_VALUE'])] for r in rows], 'status': sorted({r['OBS_STATUS'] for r in rows})}


def compute():
    return {'irpf': irpf(), 'housing': housing(), 'revenue': revenue()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New JSON file for the native generator')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('--output already exists')
    args.output.write_text(json.dumps(compute(), indent=1) + '\n')


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, KeyError, ValueError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        sys.exit(1)
