#!/usr/bin/env python3
"""Assert the coordinator's exact manifest contract and original dimensions."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
MODERN = ROOT / 'GraphSketcher/App/Images/Modern'


def expected_images():
    assets = json.loads((HERE / 'asset-inventory.json').read_text())['assets']
    expected = {}
    for asset in assets:
        if asset['scale'] != 1:
            continue
        family, name = asset['family'], asset['name']
        if family == 'Toolbar':
            size = [24, 24]
        elif family == 'Inspectors' and asset['callers']:
            size = asset.get('pdf_page_points', asset.get('frames', [{}])[0].get('pixels'))
        elif name == 'errorbar-for-sheet':
            size = asset['pdf_page_points']
        else:
            continue
        expected[name] = size
    assert len(expected) == 54, len(expected)
    return expected


def main():
    expected = expected_images()
    payload = json.loads((MODERN / 'manifest.json').read_text())
    assert set(payload) == {'images'}
    images = payload['images']
    assert len(images) == len(expected)
    assert {i['name'] for i in images} == set(expected)
    assert len({i['file'] for i in images}) == len(images)
    meanings = json.loads((HERE / 'Production/meanings.json').read_text())
    assert set(meanings) == set(expected)
    for image in images:
        assert set(image) == {'name', 'file', 'width', 'height', 'template'}, image
        name = image['name']
        assert image['file'] == f'gs-{name}.pdf'
        assert [image['width'], image['height']] == expected[name], image
        assert type(image['template']) is bool
        assert all(type(image[k]) in (float, int) and image[k] > 0 for k in ('width', 'height'))
        assert meanings[name]['meaning'] and meanings[name]['source'] == f'gs-{name}.svg'
        svg = ET.parse(HERE / 'Production' / meanings[name]['source']).getroot()
        assert svg.get('viewBox') == f'0 0 {image["width"]:g} {image["height"]:g}'
        assert all(e.tag.split('}')[-1] in ('svg', 'title', 'desc', 'g', 'path', 'circle', 'rect', 'line', 'ellipse') for e in svg.iter())
        pdf = MODERN / image['file']
        info = subprocess.check_output(['pdfinfo', str(pdf)], text=True)
        assert re.search(r'Pages:\s+1\b', info), name
        size = re.search(r'Page size:\s*([\d.]+) x ([\d.]+) pts', info)
        assert [float(v) for v in size.groups()] == expected[name], (name, size.groups())
        assert len(subprocess.check_output(['pdfimages', '-list', str(pdf)], text=True).strip().splitlines()) == 2, name
    assert {p.name for p in MODERN.iterdir()} == {'manifest.json'} | {i['file'] for i in images}
    for asset in json.loads((HERE / 'asset-inventory.json').read_text())['assets']:
        assert hashlib.sha256((ROOT / asset['path']).read_bytes()).hexdigest() == asset['sha256'], asset['path']
    print(f'PASS: {len(images)} exact manifest entries, SVG masters, vector PDF sizes and 85 original hashes')


if __name__ == '__main__':
    main()
