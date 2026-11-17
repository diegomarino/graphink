#!/usr/bin/env python3
"""Validate cursor source/exports, exact bundle bytes and native NSCursor contracts."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path, help='Actual emitted app or isolated cursor resource fixture')
parser.add_argument('--output', required=True, type=Path, help='New evidence directory; existing paths refused')
args = parser.parse_args()
if args.output.exists():
    parser.error('--output exists')
args.output.mkdir(parents=True)
for name, digest in json.loads((HERE / 'checks.json').read_text()).items():
    assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
for tool, tip in (('draw',(2,18)), ('fill',(2,3))):
    source = ET.parse(HERE / f'gs-{tool}-cursor.svg').getroot()
    assert source.get('viewBox') == '0 0 20 20'
    assert all(node.tag.rsplit('}',1)[-1] in ('svg','title','desc','path') for node in source.iter())
    pdf = ROOT / f'GraphSketcher/App/Images/ModernCursors/gs-{tool}-cursor.pdf'
    packaged = args.app / f'Contents/Resources/ModernCursors/gs-{tool}-cursor.pdf'
    assert packaged.read_bytes() == pdf.read_bytes(), packaged
    info = subprocess.check_output(['pdfinfo',str(pdf)], text=True)
    assert re.search(r'Pages:\s+1\b',info) and re.search(r'Page size:\s+20 x 20 pts',info)
    assert len(subprocess.check_output(['pdfimages','-list',str(pdf)],text=True).strip().splitlines()) == 2
    for scale in (1,2):
        image = Image.open(HERE / f'gs-{tool}-cursor{"@2x" if scale==2 else ""}.png').convert('RGBA')
        assert image.size == (20*scale,20*scale)
        assert image.getpixel((tip[0]*scale,tip[1]*scale))[3] > 0, 'Hotspot must touch visible tip'
command = ['xcrun','clang','-fno-objc-arc','-Wall','-Werror','-I',str(ROOT / 'GraphSketcher/App'),'-framework','AppKit',str(ROOT / 'GraphSketcher/App/RSModernImages.m'),str(ROOT / 'Checks/ModernCursorChecks.m'),'-o',str(args.output / 'checks')]
(args.output / 'command.json').write_text(json.dumps(command,indent=2)+'\n')
subprocess.run(command,check=True)
result = subprocess.run([str(args.output / 'checks'),str(args.app.resolve())],capture_output=True)
(args.output / 'checks.log').write_bytes(result.stdout+result.stderr)
print((result.stdout+result.stderr).decode())
assert result.returncode==0 and b'PASS two exact vector cursor' in result.stdout
print('PASS original SVG/PDF hashes, 20pt vector-only pages, 1x/2x tip coverage and exact packaged bytes')
