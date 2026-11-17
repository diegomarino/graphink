#!/usr/bin/env python3
"""Export two original vector pointers and a labeled compositing proof with existing tools."""
from pathlib import Path
import hashlib
import json
import subprocess
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DEST = ROOT / 'GraphSketcher/App/Images/ModernCursors'
for tool in ('draw', 'fill'):
    source = HERE / f'gs-{tool}-cursor.svg'
    subprocess.run(['rsvg-convert', '--format', 'pdf', '--dpi-x', '72', '--dpi-y', '72', '--output', str(DEST / f'gs-{tool}-cursor.pdf'), str(source)], check=True)
    for scale in (1, 2):
        subprocess.run(['rsvg-convert', '--width', str(20*scale), '--height', str(20*scale), '--output', str(HERE / f'gs-{tool}-cursor{ "@2x" if scale==2 else ""}.png'), str(source)], check=True)
proof = Image.new('RGB', (720, 300), '#e9edf1')
draw = ImageDraw.Draw(proof)
draw.text((16, 10), 'Graphink cursor proof - actual 20pt / 2x / enlarged tip guide', fill='black')
for row, color in enumerate(('#ffffff', '#18202b', '#2781a7')):
    top = 36 + row*84
    draw.rectangle((0,top,719,top+80), fill=color)
    ink = 'black' if row==0 else 'white'
    draw.text((12,top+8), ('Light', 'Dark', 'Colored')[row], fill=ink)
    for col, tool in enumerate(('draw','fill')):
        image = Image.open(HERE / f'gs-{tool}-cursor.png').convert('RGBA')
        image2 = Image.open(HERE / f'gs-{tool}-cursor@2x.png').convert('RGBA')
        x=140+col*290
        proof.paste(image, (x,top+28), image)
        proof.paste(image2, (x+46,top+18), image2)
        enlarged=image.resize((60,60), Image.Resampling.NEAREST)
        proof.paste(enlarged,(x+112,top+8),enlarged)
        hot=(2,18) if tool=='draw' else (2,3)
        cx,cy=x+112+hot[0]*3,top+8+hot[1]*3
        draw.line((cx-5,cy,cx+5,cy),fill='#e43e79',width=1)
        draw.line((cx,cy-5,cx,cy+5),fill='#e43e79',width=1)
        draw.text((x,top+62), f'{tool.title()}: tip {hot}', fill=ink)
proof.save(HERE / 'cursor-proof.png')
files = sorted(list(HERE.glob('*.svg')) + list(HERE.glob('*.png')) + list(DEST.glob('*.pdf')))
(HERE / 'checks.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}, indent=2)+'\n')
print('PASS exported two 20pt vector PDFs, 1x/2x PNGs and illustrative surface/hotspot proof')
