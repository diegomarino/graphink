#!/usr/bin/env python3
"""Export the owned SVG masters to the coordinator's Modern resource folder."""
import argparse
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
DEFAULT = HERE.parent.parent / 'GraphSketcher/App/Images/Modern'


def main():
    parser = argparse.ArgumentParser(description=__doc__,
        epilog='Example: python3 UI/Design/export-production-icons.py --output /private/tmp/gs-modern-review')
    parser.add_argument('--output', type=Path, default=DEFAULT,
                        help='Destination; regenerates only the named PDFs and manifest.json (default: app Images/Modern).')
    args = parser.parse_args()
    meanings = json.loads((HERE / 'Production/meanings.json').read_text())
    images = []
    for name, item in meanings.items():
        assert name and '/' not in name and '\\' not in name
        assert item['source'] == f'gs-{name}.svg'
        assert item['width'] > 0 and item['height'] > 0 and type(item['template']) is bool
        source = HERE / 'Production' / item['source']
        root = ET.parse(source).getroot()
        assert root.get('viewBox') == f'0 0 {item["width"]:g} {item["height"]:g}'
        images.append(dict(name=name, file=f'gs-{name}.pdf', width=item['width'],
                           height=item['height'], template=item['template']))
    assert len(images) == 54 and len({i['file'] for i in images}) == 54
    args.output.mkdir(parents=True, exist_ok=True)
    for image in images:
        subprocess.run(['rsvg-convert', '--format', 'pdf', '--dpi-x', '72', '--dpi-y', '72',
                        '--output', str(args.output / image['file']),
                        str(HERE / 'Production' / (image['file'][:-4]+'.svg'))], check=True)
    # Publish the index last, after every converter completed successfully.
    (args.output / 'manifest.json').write_text(json.dumps({'images': images}, indent=2)+'\n')
    print(f'Exported {len(images)} PDFs and manifest.json to {args.output}')


if __name__ == '__main__':
    main()
