#!/usr/bin/env python3
"""Render every example to native SVG, inspect editable text, and compare offscreen WebKit with PDF.

This reports differences; it deliberately sets no fidelity allowlist or acceptance threshold.
The existing PDF/PNG comparators are independent and remain unchanged.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SVG = '{http://www.w3.org/2000/svg}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--products', required=True, type=Path)
    parser.add_argument('--tool', type=Path, help='Development helper override; default: the helper in --products')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--structure-only', action='store_true', help='Skip WebKit/PDF raster comparison')
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists(): parser.error('--output must be fresh')
    out.mkdir(parents=True)
    tool = args.tool.resolve() if args.tool else args.products.resolve() / 'Graphink.app/Contents/Helpers/graphink'
    fonts = tool.parent.parent / 'Resources/StyleFonts'
    report = {'documents': [], 'passed': False, 'scale': 2, 'fonts': 'Kalam supplied by checker CSS; SVG only names fonts'}

    def run(command, name, expect=0):
        proc = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=120)
        (out / (name + '.log')).write_text(proc.stdout + proc.stderr)
        assert proc.returncode == expect, f'{name}: exit {proc.returncode}, expected {expect}; see {out / (name + ".log")}'
        return proc

    if not args.structure_only:
        run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-framework', 'Cocoa', '-framework', 'WebKit', ROOT / 'Checks/SVGRasterize.m', '-o', out / 'SVGRasterize'], 'webkit-compile')
        run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-framework', 'Foundation', '-framework', 'CoreGraphics', '-framework', 'ImageIO', ROOT / 'tools/cli/ImageDiff.m', '-o', out / 'ImageDiff'], 'imagediff-compile')

    def check(document, name):
        original = hashlib.sha256(document.read_bytes()).hexdigest()
        svg = out / (name + '.svg')
        run([tool, 'render', document, '-o', svg], name + '-svg')
        tree = ET.parse(svg).getroot()
        assert tree.tag == SVG + 'svg', name
        _, _, width, height = map(float, tree.attrib['viewBox'].split())
        paths = tree.findall('.//' + SVG + 'path')
        texts = tree.findall('.//' + SVG + 'text')
        assert paths and texts, f'{name}: missing geometry or editable text'
        assert not tree.findall('.//' + SVG + 'image'), f'{name}: rasterized SVG'
        assert not tree.findall('.//' + SVG + 'use'), f'{name}: outlined glyph references'
        entry = {'document': str(document.relative_to(ROOT)) if document.is_relative_to(ROOT) else document.name,
                 'name': name, 'paths': len(paths), 'textRuns': len(texts), 'fonts': sorted({t.attrib.get('font-family', '') for t in texts}),
                 'rotatedGroups': sum('rotate(' in g.attrib.get('transform', '') and 'rotate(0)' not in g.attrib.get('transform', '') for g in tree.findall('.//' + SVG + 'g'))}
        if not args.structure_only:
            pdf = out / (name + '.pdf')
            run([tool, 'render', document, '-o', pdf], name + '-pdf')
            run([out / 'ImageDiff', '--rasterize-pdf', pdf, out / (name + '-pdf.png'), '2'], name + '-pdf-raster')
            run([out / 'SVGRasterize', svg, width, height, out / (name + '-svg.png'), fonts], name + '-webkit')
            entry['diff'] = json.loads(run([out / 'ImageDiff', out / (name + '-pdf.png'), out / (name + '-svg.png'), out / (name + '-diff.png')], name + '-diff').stdout)
            assert entry['diff']['sameSize'], f'{name}: raster size mismatch'
        assert original == hashlib.sha256(document.read_bytes()).hexdigest(), f'{name}: input changed'
        report['documents'].append(entry)
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(entry), flush=True)

    for index, document in enumerate(sorted((ROOT / 'Examples').rglob('*.graphink'))):
        check(document, f'{index:02d}-{document.stem}')

    # Exercise XML escaping, multiple lines, rotation and the bundled handwriting font via the
    # production creator. These are new, disposable documents, never historical samples.
    spec = {'graphink': 1, 'style': 'sketch', 'x': {'min': 0, 'max': 10, 'title': 'X & <axis>'}, 'y': {'min': 0, 'max': 10, 'title': 'Rotated Y'},
            'objects': [{'type': 'label', 'text': 'First <&> "line"\nSecond line', 'at': [3, 6], 'size': 24, 'bold': True}]}
    (out / 'text.json').write_text(json.dumps(spec) + '\n')
    run([tool, 'create', out / 'text.json', '-o', out / 'text.graphink'], 'text-create')
    check(out / 'text.graphink', 'text-fixture')
    tree = ET.parse(out / 'text-fixture.svg')
    texts = tree.findall('.//' + SVG + 'text')
    joined = ''.join(''.join(t.itertext()) for t in texts)
    assert 'First <&> "line"' in joined and 'Second line' in joined, 'Multiline text or XML escaping lost'
    assert any(t.attrib.get('font-family') == 'Kalam' and t.attrib.get('font-weight') == '700' for t in texts), 'Kalam bold traits lost'
    assert report['documents'][-1]['rotatedGroups'] > 0, 'Axis title rotation lost'
    # Paper's emphasized face is Helvetica Neue Medium, which has no bold trait bit.
    # Exporting only the bold bit silently turns every Medium heading into Regular.
    spec['style'] = 'paper'
    (out / 'medium.json').write_text(json.dumps(spec) + '\n')
    run([tool, 'create', out / 'medium.json', '-o', out / 'medium.graphink'], 'medium-create')
    check(out / 'medium.graphink', 'medium-fixture')
    medium = ET.parse(out / 'medium-fixture.svg').findall('.//' + SVG + 'text')
    assert any(t.attrib.get('font-family') == 'Helvetica Neue' and t.attrib.get('font-weight') == '500' for t in medium), 'Helvetica Neue Medium weight lost'
    saved = (out / 'text-fixture.svg').read_bytes()
    run([tool, 'render', out / 'text.graphink', '-o', out / 'text-fixture.svg'], 'overwrite-refused', expect=1)
    assert saved == (out / 'text-fixture.svg').read_bytes(), 'Existing output modified'
    run([tool, 'render', out / 'text.graphink', '-o', out / 'text-fixture.svg', '--force'], 'overwrite-force')
    assert saved == (out / 'text-fixture.svg').read_bytes(), 'SVG export is nondeterministic'
    run([tool, 'render', out / 'text.graphink', '-o', out / 'text-fixture.svg', '--force', '--dpi', '300'], 'vector-dpi')
    assert saved == (out / 'text-fixture.svg').read_bytes(), 'Raster DPI changed the SVG'
    alias = out / 'input.svg'
    alias.symlink_to(out / 'text.graphink')
    original = (out / 'text.graphink').read_bytes()
    run([tool, 'render', out / 'text.graphink', '-o', alias, '--force'], 'input-alias-refused', expect=1)
    assert original == (out / 'text.graphink').read_bytes(), 'Input overwritten through an SVG alias'
    paths = [p for d in report['documents'] for p in ET.parse(out / (d['name'] + '.svg')).findall('.//' + SVG + 'path')]
    assert any('C ' in p.attrib['d'] for p in paths), 'Cubic geometry not exercised'
    assert any('stroke-dasharray' in p.attrib for p in paths), 'Dashed strokes lost'
    assert any(0 < float(p.attrib.get('fill-opacity', 1)) < 1 for p in paths), 'Translucent fills lost'
    assert any(p.attrib.get('stroke-linecap') == 'round' for p in paths), 'Round caps lost'
    report['passed'] = True
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'PASS {len(report["documents"])} SVG exports with editable text', flush=True)


if __name__ == '__main__':
    main()
