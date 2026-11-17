#!/usr/bin/env python3
"""Export the seven-glyph review study; never writes product resources."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

SVG = 'http://www.w3.org/2000/svg'
ET.register_namespace('', SVG)
ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')
SOURCE = Path(__file__).with_name('representative-icons.svg')
IDS = ('modify', 'draw', 'fill', 'text', 'lock', 'group', 'inspector')


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog='Example: python3 UI/Design/export-icons.py --output /private/tmp/gs-icon-review')
    parser.add_argument('--output', required=True, type=Path,
                        help='New directory for previews, individual SVG/PDF/PNG files and checks.json; existing paths are refused.')
    args = parser.parse_args()
    converter = shutil.which('rsvg-convert')
    if not converter:
        parser.error('rsvg-convert is required; use an environment with librsvg installed.')
    try:
        from PIL import Image
    except ImportError:
        parser.error('Pillow is required for export checks; use a Python environment with Pillow installed.')
    if args.output.exists():
        parser.error('Output exists; choose a new directory to preserve the previous review.')
    tree = ET.parse(SOURCE)
    groups = tree.getroot().find(f'{{{SVG}}}defs')
    if groups is None or [g.get('id') for g in groups] != ['icon-' + name for name in IDS]:
        parser.error('Expected seven named glyph groups in source defs; restore the source or update the exporter.')
    args.output.mkdir(parents=True)
    checks = {'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
              'renderer': subprocess.check_output([converter, '--version'], text=True).splitlines()[0],
              'icons': {}}

    def render(source, target, *flags):
        subprocess.run([converter, *flags, '--output', str(target), str(source)], check=True)

    for theme in ('light', 'dark'):
        sheet = copy.deepcopy(tree.getroot())
        if theme == 'dark':
            style = sheet.find(f'{{{SVG}}}style')
            for light, dark in {'#f3f4f6': '#171c22', '#ffffff': '#232b34',
                                '#202932': '#edf2f6', '#626e79': '#a5b2bf',
                                '#dce1e6': '#394552', '#dce8f1': '#354c60',
                                '#456a85': '#90b5cf'}.items():
                style.text = style.text.replace(light, dark)
        path = args.output / f'preview-{theme}.svg'
        ET.ElementTree(sheet).write(path, encoding='utf-8', xml_declaration=True)
        png = path.with_suffix('.png')
        render(path, png)
        with Image.open(png) as im:
            assert im.size == (1100, 624), (png, im.size)
    for group, name in zip(groups, IDS):
        icon = ET.Element(f'{{{SVG}}}svg', {'width': '24pt', 'height': '24pt',
                              'viewBox': '0 0 24 24', 'color': '#000000',
                              'role': 'img', 'aria-label': group.get('data-label')})
        ET.SubElement(icon, f'{{{SVG}}}title').text = group.get('data-label')
        icon.append(copy.deepcopy(group))
        svg = args.output / f'gs-{name}.svg'
        ET.ElementTree(icon).write(svg, encoding='utf-8', xml_declaration=True)
        render(svg, svg.with_suffix('.pdf'), '--format', 'pdf', '--dpi-x', '72', '--dpi-y', '72')
        sizes = []
        for scale in (1, 2):
            png = args.output / f'gs-{name}{"@2x" if scale == 2 else ""}.png'
            render(svg, png, '--width', str(24 * scale), '--height', str(24 * scale))
            with Image.open(png).convert('RGBA') as im:
                bbox = im.getchannel('A').getbbox()
                assert im.size == (24 * scale, 24 * scale), (png, im.size)
                assert bbox and min(bbox[:2]) >= scale and max(bbox[2:]) <= 23 * scale, (png, bbox)
                assert im.getextrema()[:3] == ((0, 0),) * 3, png
                sizes.append({'scale': scale, 'pixels': list(im.size), 'alpha_bounds': bbox})
        checks['icons'][name] = sizes
    checks['files'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in sorted(args.output.iterdir())}
    (args.output / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')
    print(json.dumps({'output': str(args.output.resolve()), 'glyphs': len(IDS),
                      'checks': str((args.output / 'checks.json').resolve())}))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ET.ParseError, subprocess.CalledProcessError, AssertionError) as error:
        print(f'Export failed: {error}. Partial outputs are preserved; fix the source/tool and use a new output directory.', file=sys.stderr)
        sys.exit(1)
