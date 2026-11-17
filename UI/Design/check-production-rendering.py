#!/usr/bin/env python3
"""Check rendered PDF alpha against SVG masters and build a two-theme proof PNG."""
from pathlib import Path
import json
import subprocess
import tempfile
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
MODERN = HERE.parent.parent / 'GraphSketcher/App/Images/Modern'
images = json.loads((MODERN / 'manifest.json').read_text())['images']
proof = Image.new('RGB', (2424, 1508), '#e9edf1')
draw = ImageDraw.Draw(proof)
# Pillow's bundled font only labels the proof; production PDFs contain no fonts.
font = ImageFont.load_default(size=13)
small = ImageFont.load_default(size=11)
with tempfile.TemporaryDirectory(prefix='gs-icon-render-') as temporary:
    temporary = Path(temporary)
    for index, item in enumerate(images):
        name = item['name']
        prefix = temporary / name
        subprocess.run(['pdftocairo', '-r', '144', '-singlefile', '-png', '-transp',
                        str(MODERN / item['file']), str(prefix)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        # Poppler's PNG alpha retains the template's semitransparent context.
        with Image.open(prefix.with_suffix('.png')) as rendered:
            mask = rendered.convert('RGBA').getchannel('A')
        w,h = int(item['width']*2), int(item['height']*2)
        assert mask.size == (w,h), (name, mask.size)
        bounds = mask.getbbox()
        assert bounds and bounds[0] > 0 and bounds[1] > 0 and bounds[2] < w and bounds[3] < h, (name,bounds)
        svg_png = temporary / 'source.png'
        subprocess.run(['rsvg-convert', '--width', str(w), '--height', str(h), '--output',
                        str(svg_png), str(HERE / 'Production' / f'gs-{name}.svg')], check=True)
        with Image.open(svg_png) as source:
            expected = source.convert('RGBA').getchannel('A')
        assert all(abs(a-b) <= 1 for a,b in zip(bounds, expected.getbbox())), name
        # Detect missing/wrong artwork rather than only matching page dimensions.
        assert abs(sum(mask.tobytes())-sum(expected.tobytes())) / sum(expected.tobytes()) < .12, name
        for panel, dark in enumerate((False,True)):
            x = 24+panel*1200+(index%6)*196
            y = 64+(index//6)*158
            bg = '#20272f' if dark else '#ffffff'
            fg = '#edf2f6' if dark else '#202932'
            draw.rounded_rectangle((x,y,x+188,y+150),radius=6,fill=bg)
            draw.text((x+8,y+8),name,fill=fg,font=small)
            draw.text((x+8,y+26),f'{item["width"]:g} × {item["height"]:g}pt · shown at 2×',fill=fg,font=small)
            colored=Image.new('RGB',mask.size,fg)
            proof.paste(colored,(x+(188-w)//2,y+45+(102-h)//2),mask)
    draw.text((24,20),'LIGHT / 54 ORIGINAL PDF RESOURCES / TEMPLATE APPEARANCE PROPOSAL',fill='#26313b',font=font)
    draw.text((1224,20),'DARK / SAME PDF ALPHA / NO PRODUCT LOADER OR NATIVE ACCEPTANCE',fill='#26313b',font=font)
    proof.save(HERE / 'production-contact-sheet.png')
print('PASS: 54 rendered PDFs: nonempty alpha, unclipped margins, SVG agreement; light/dark proof saved')
