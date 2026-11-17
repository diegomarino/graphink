#!/usr/bin/env python3
"""Check the original economic geometry and semantic native roundtrips (stdlib only)."""
import argparse
import json
import math
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

NS = '{http://www.omnigroup.com/namespace/OmniGraphSketcher/v1}'
STEMS = ['01-market-equilibrium', '02-demand-and-supply-shifts', '03-tax-incidence-and-welfare']


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


def validate(directory):
    for index, stem in enumerate(STEMS):
        path = directory / (stem + '.graphink')
        assert path.is_file(), f'Missing generated document: {path}'
        with zipfile.ZipFile(path) as package:
            root = ET.fromstring(package.read('contents.xml'))
            preview = package.read('preview.pdf')
        assert preview == (directory / (stem + '.pdf')).read_bytes(), 'Packaged preview differs from rendered PDF'
        assert root.tag == NS + 'document'
        graph = root.find(NS + 'graph')
        assert graph is not None
        identifiers = [e.get('id') for e in root.iter() if e.get('id') is not None]
        assert len(identifiers) == len(set(identifiers)) and all(identifiers)
        objects = {e.get('id'): e for e in root.iter() if e.get('id')}
        for element in root.iter():
            for key in ('idref', 'owner', 'arrow-parent', 'v1', 'v2', 'label', 'ids', 'elements'):
                assert all(r in objects for r in element.get(key, '').split()), (key, element.attrib)
        vertices = {v.get('id'): (float(v.get('x', 0)), float(v.get('y', 0)))
                    for v in graph.findall(NS + 'vertex')}
        assert all(math.isfinite(n) for point in vertices.values() for n in point)
        axes = graph.findall(NS + 'axis')
        assert [a.get('dimension') for a in axes] == ['x', 'y']
        assert all(float(a.get('max')) > float(a.get('min')) for a in axes)
        assert [float(a.get('max')) for a in axes] == ([18, 18] if index == 1 else [14, 16])
        texts = [''.join(e.text or '' for e in label.iter(NS + 'lit')) for label in graph.findall(NS + 'label')]
        # Axis titles as first delivered, or in Pindyck & Rubinfeld wording since 2026-11-16 (Examples/Tools/generate.py RELABELS).
        assert ('Quantity Q (units/week)' in texts and 'Price P ($/unit)' in texts) or \
            ('Quantity Q (units per week)' in texts and 'Price P (dollars per unit)' in texts)
        assert any('Manually authored' in t for t in texts)
        lines = []
        for line in graph.findall(NS + 'line'):
            assert line.get('class') == 'connect' and line.get('method') == 'straight'
            refs = line.find(NS + 'vertices').get('ids').split()
            assert all(objects[r].tag == NS + 'vertex' for r in refs)
            lines.append([vertices[r] for r in refs])
        expected = [([(0, 14), (8, 6), (14, 0)], [(0, 2), (8, 6), (14, 9)]),
                    ([(0, 14), (6, 8), (8, 6), (14, 0)], [(0, 2), (8, 6), (10, 7), (18, 11)]),
                    ([(0, 14), (6, 8), (8, 6), (14, 0)], [(0, 2), (6, 5), (8, 6), (14, 9)])][index]
        assert all(curve in lines for curve in expected), (stem, 'Missing baseline geometry')
        marker_points = {vertices[v.get('id')] for v in graph.findall(NS + 'vertex') if v.get('shape') == 'circle'}
        assert marker_points == [{(8, 6)}, {(8, 6), (10, 7), (6, 8)}, {(8, 6), (6, 8), (6, 5)}][index]
        for axis in axes:
            assert objects[axis.find(NS + 'title').get('label')].tag == NS + 'label'
        if index == 1:
            assert [(0, 17), (10, 7), (17, 0)] in lines
            assert [(0, 5), (6, 8), (18, 14)] in lines
            assert any('Two separate shocks' in t for t in texts)
        fills = graph.findall(NS + 'fill')
        assert len(fills) == (4 if index == 2 else 0)
        if index == 2:
            polygons = [[vertices[r] for r in f.find(NS + 'vertices').get('ids').split()] for f in fills]
            assert polygons == [[(0, 8), (0, 14), (6, 8)], [(0, 2), (0, 5), (6, 5)],
                                [(0, 5), (6, 5), (6, 8), (0, 8)], [(6, 5), (6, 8), (8, 6)]]
            assert list(map(area, polygons)) == [18, 9, 18, 3]
            assert [(0, 5), (6, 8), (14, 12)] in lines
        before = json.loads((directory / (stem + '-before.json')).read_text())
        close(before['defaults'], {'font-name': 'HelveticaNeue', 'line-color': [.12, .18, .24, 1],
                                   'text-color': [.12, .18, .24, 1], 'fill-color': [.12, .18, .24, .17]})
        for suffix in ('-reopen', '-roundtrip'):
            close(before, json.loads((directory / (stem + suffix + '.json')).read_text()))
        assert (directory / (stem + '.pdf')).read_bytes().startswith(b'%PDF-')
        assert (directory / (stem + '.png')).read_bytes().startswith(b'\x89PNG')
    print('PASS: three editable graphs, expected curves/areas, resolved IDs, native semantic roundtrips and preview outputs.')


def self_check(directory, evidence=None):
    if evidence is None:
        evidence = Path(tempfile.mkdtemp(prefix='graphink-examples-negative-', dir='/private/tmp'))
    else:
        evidence.mkdir()
    for name in ('wrong-intersection', 'unresolved-reference', 'wrong-fill-boundary'):
        candidate = evidence / name
        shutil.copytree(directory, candidate)
        path = candidate / (STEMS[2 if name == 'wrong-fill-boundary' else 0] + '.graphink')
        with zipfile.ZipFile(path) as package:
            parts = [(info, package.read(info)) for info in package.infolist()]
            root = ET.fromstring(package.read('contents.xml'))
        graph = root.find(NS + 'graph')
        if name == 'wrong-intersection':
            v = next(v for v in graph.findall(NS + 'vertex') if v.get('x') == '8' and v.get('y') == '6')
            v.set('x', '9')
        elif name == 'unresolved-reference':
            graph.find(NS + 'line/' + NS + 'vertices').set('ids', 'missing')
        else:
            boundary = graph.findall(NS + 'fill')[2].find(NS + 'vertices')
            refs = boundary.get('ids').split()
            boundary.set('ids', ' '.join([refs[0], refs[2], refs[1], refs[3]]))
        with zipfile.ZipFile(path, 'w') as package:
            for info, data in parts:
                package.writestr(info, ET.tostring(root, encoding='utf-8', xml_declaration=True)
                                 if info.filename == 'contents.xml' else data)
        try:
            validate(candidate)
        except AssertionError:
            continue
        raise AssertionError('Validator accepted mutation: ' + name)
    print('PASS: validator rejected wrong intersection, unresolved reference and wrong fill boundary; evidence: ' + str(evidence))
    return str(evidence)


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog='Example: python3 Examples/Microeconomics/validate.py --input-dir /private/tmp/examples-run/artifacts')
    parser.add_argument('--input-dir', type=Path, required=True)
    parser.add_argument('--self-check', action='store_true', help='Also reject three corrupted copies; retain negative evidence under /private/tmp')
    args = parser.parse_args()
    validate(args.input_dir)
    if args.self_check:
        self_check(args.input_dir)


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, ET.ParseError, zipfile.BadZipFile, KeyError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        sys.exit(1)
