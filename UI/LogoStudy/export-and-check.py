#!/usr/bin/env python3
"""Export and verify this pending logo study using installed librsvg and Poppler."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops

HERE = Path(__file__).resolve().parent
NS = '{http://www.w3.org/2000/svg}'


def run(*args):
    return subprocess.check_output(args, text=True)


def alpha_bounds(path, size):
    with Image.open(path).convert('RGBA') as image:
        assert image.size == size, (path, image.size, size)
        bounds = image.getchannel('A').getbbox()
        assert bounds and bounds[0] > 0 and bounds[1] > 0, (path, bounds)
        assert bounds[2] < size[0] and bounds[3] < size[1], (path, bounds)
        return list(bounds)


def main():
    exports = HERE / 'Exports'
    exports.mkdir(exist_ok=True)
    masters = sorted((HERE / 'Masters').glob('*.svg'))
    assert {p.stem for p in masters} == {f'{direction}-{form}-{theme}'
            for direction in ('curve', 'axes', 'heritage', 'bezier-g', 'bezier-gs', 'bezier-g-nodes',
                              'bezier-g-nodes-large', 'bezier-g-nodes-warm', 'bezier-g-nodes-large-warm',
                              'bezier-g-nodes-medium', 'bezier-g-nodes-black')
            for form in ('symbol', 'lockup') for theme in ('light', 'dark')}
    report = {'status': 'Study pending human choice',
              'renderer': run('rsvg-convert', '--version').splitlines()[0], 'masters': {}}
    with tempfile.TemporaryDirectory(prefix='gs-logo-proof-') as temporary:
        temporary = Path(temporary)
        sheets = [HERE / name for name in ('preview-sheet.svg', 'preview-round-02.svg', 'preview-g-nodes.svg', 'preview-g-variants.svg', 'preview-g-b-refinement.svg')]
        previous = json.loads((HERE / 'checks.json').read_text()).get('sha256', {})
        for source in masters + sheets:
            root = ET.parse(source).getroot()
            w, h = int(root.get('width')), int(root.get('height'))
            assert root.get('viewBox') == f'0 0 {w} {h}'
            assert 'pending human choice' in root.find(NS + 'title').text
            assert not any(root.iter(NS + 'image'))
            # Control hull + stroke proves every symbol curve lies inside its 32-unit grid.
            if source in masters:
                group = root.find(NS + 'g')
                for element in group.iter():
                    if element.tag == NS + 'path':
                        assert re.fullmatch(r'[MLCZ0-9 .]+', element.get('d'))
                        coordinates = [float(n) for n in re.findall(r'\d+(?:\.\d+)?', element.get('d'))]
                        assert len(coordinates) % 2 == 0
                        assert all(2 <= n <= 30 for n in coordinates)
                    elif element.tag == NS + 'circle':
                        radius = float(element.get('r'))
                        assert all(1 < float(element.get(c)) - radius and
                                   float(element.get(c)) + radius < 31 for c in ('cx', 'cy'))
                if source.stem.startswith('bezier-g-nodes-'):
                    path = next(group.iter(NS + 'path'))
                    reference = ET.parse(HERE / 'Masters' / 'bezier-g-nodes-symbol-light.svg').getroot()
                    assert path.attrib == next(reference.iter(NS + 'path')).attrib
                    stroke = next(g for g in group.iter(NS + 'g') if g.get('stroke-width'))
                    assert stroke.get('stroke-width') == '1.75'

                    commands = [(command, [float(n) for n in values.split()])
                                for command, values in re.findall(r'([MCL])([^MCL]*)', path.get('d'))]
                    anchors = [tuple(values[-2:]) for _, values in commands]
                    circles = [(float(c.get('cx')), float(c.get('cy')))
                               for c in group.iter(NS + 'circle')]
                    assert len(anchors) == 7 and circles == anchors, (source, circles, anchors)
                    cubics = [values for command, values in commands if command == 'C']
                    assert len(cubics) == 4
                    for left, right in zip(cubics, cubics[1:]):
                        incoming = (left[4] - left[2], left[5] - left[3])
                        outgoing = (right[0] - left[4], right[1] - left[5])
                        assert abs(incoming[0]*outgoing[1] - incoming[1]*outgoing[0]) < 1e-9
                        assert sum(a*b for a, b in zip(incoming, outgoing)) > 0
                if 'lockup' in source.stem:

                    assert root.find(NS + 'text').text == 'GraphSketcher'
                    assert root.find(NS + 'text').get('font-family') == 'Helvetica Neue'
            pdf = exports / (source.stem + '.pdf')
            # Preserve byte-identical existing PDF exports when their master and PDF hashes agree.
            if (not pdf.exists() or
                    hashlib.sha256(source.read_bytes()).hexdigest() != previous.get(str(source.relative_to(HERE))) or
                    hashlib.sha256(pdf.read_bytes()).hexdigest() != previous.get(str(pdf.relative_to(HERE)))):
                run('rsvg-convert', '--format', 'pdf', '--dpi-x', '72', '--dpi-y', '72',
                    '--output', str(pdf), str(source))
            info = run('pdfinfo', str(pdf))
            assert re.search(r'Pages:\s+1\b', info)
            assert f'{w} x {h} pts' in info
            if source in sheets:
                run('rsvg-convert', '--output', str(source.with_suffix('.png')), str(source))
                run('pdftoppm', '-scale-to-x', str(w), '-scale-to-y', str(h), '-singlefile',
                    '-png', str(pdf), str(temporary / (source.stem + '-pdf')))
                with Image.open(temporary / (source.stem + '-pdf.png')) as proof:
                    assert proof.size == (w, h)
                continue
            sizes = []
            for scale in (1, 2):
                size = (w * scale, h * scale)
                png = exports / f'{source.stem}{"@2x" if scale == 2 else ""}.png'
                run('rsvg-convert', '--width', str(size[0]), '--height', str(size[1]),
                    '--output', str(png), str(source))
                bounds = alpha_bounds(png, size)
                # A padded viewport reveals paint that a tight export would silently clip.
                padded = ET.fromstring(source.read_text())
                padded.set('viewBox', f'-8 -8 {w+16} {h+16}')
                padded.set('width', str((w+16)*scale))
                padded.set('height', str((h+16)*scale))
                padded_svg = temporary / 'padded.svg'
                ET.ElementTree(padded).write(padded_svg)
                run('rsvg-convert', '--output', str(temporary / 'padded.png'), str(padded_svg))
                with Image.open(temporary / 'padded.png').convert('RGBA') as image:
                    box = image.getchannel('A').getbbox()
                    assert box and box[0] > 8*scale and box[1] > 8*scale
                    assert box[2] < (w+8)*scale and box[3] < (h+8)*scale
                # Independent PDF rasterization checks both appearances at both scales.
                run('pdftoppm', '-scale-to-x', str(size[0]), '-scale-to-y', str(size[1]),
                    '-singlefile', '-png', str(pdf), str(temporary / 'pdf'))
                with Image.open(temporary / 'pdf.png').convert('RGBA') as image:
                    # Poppler defaults to white; its ink bounds remain valid for light ink too.
                    difference = ImageChops.difference(image.convert('RGB'), Image.new('RGB', size, 'white'))
                    box = difference.getbbox()
                    assert box and box[0] > 0 and box[1] > 0 and box[2] < size[0] and box[3] < size[1]
                sizes.append({'scale': scale, 'pixels': list(size), 'alpha_bounds': bounds,
                              'pdf_ink_bounds': list(box)})
            report['masters'][source.name] = sizes
        report['sha256'] = {str(p.relative_to(HERE)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in sorted(HERE.rglob('*')) if p.suffix in ('.svg', '.png', '.pdf')}
        (HERE / 'checks.json').write_text(json.dumps(report, indent=2) + '\n')
        # Leave independent PDF sheet proofs outside the owned deliverables for visual QA.
        for sheet in sheets:
            proof = Path('/private/tmp') / ('gs-logo-' + sheet.stem + '-pdf-proof.png')
            proof.write_bytes((temporary / (sheet.stem + '-pdf.png')).read_bytes())
    print('PASS: 44 masters; 88 PNGs; 49 one-page PDFs; actual G anchors and tangent continuity; geometry, padded bounds and 1x/2x PDF/PNG ink checks.')


if __name__ == '__main__':
    main()
