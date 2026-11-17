#!/usr/bin/env python3
"""Build a design-only light/dark sidebar study using the icon export primitives."""
from pathlib import Path
import copy
import subprocess
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

HERE = Path(__file__).resolve().parent
WIDTH, HEIGHT = 1680, 940
SVG = 'http://www.w3.org/2000/svg'
source = ET.parse(HERE / 'representative-icons.svg').getroot()
defs = copy.deepcopy(source.find(f'{{{SVG}}}defs'))
ET.register_namespace('', SVG)
parts = [f'<svg xmlns="{SVG}" xmlns:xlink="http://www.w3.org/1999/xlink" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-labelledby="title desc">',
         '<title id="title">GraphSketcher sidebar study — light and dark</title>',
         '<desc id="desc">Two 520 by 440 graph canvases with 280 point scrolling sidebars, four icon and label sections, existing Style controls, scroll continuation, and seven original glyphs. Design only.</desc>',
         ET.tostring(defs, encoding='unicode'),
         '<style>text{font-family:Helvetica,Arial,sans-serif}path,line,rect,circle{stroke-linecap:round;stroke-linejoin:round}</style>',
         '<rect width="1680" height="940" fill="#e9edf1"/>']


def rect(x, y, w, h, fill, stroke='none', r=0):
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}"/>')


def text(x, y, value, color, size=12, weight=400, anchor='start'):
    parts.append(f'<text x="{x}" y="{y}" fill="{color}" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}">{escape(value)}</text>')


def path(d, color, width=1.5, fill='none'):
    parts.append(f'<path d="{d}" stroke="{color}" stroke-width="{width}" fill="{fill}"/>')


def use(name, x, y, color, scale=1):
    parts.append(f'<use xlink:href="#icon-{name}" transform="translate({x} {y}) scale({scale})" color="{color}"/>')


text(32, 32, 'GRAPHSKETCHER / SIDEBAR STUDY 02', '#526170', 11, 500)
text(32, 65, 'A graph first. Its controls within reach.', '#202932', 26, 500)
text(1648, 35, 'Design artifact · no product replacement', '#526170', 12, anchor='end')

for offset, theme in [(32, 'Light'), (848, 'Dark')]:
    dark = theme == 'Dark'
    c = dict(bg='#1e2329' if dark else '#f4f5f7',
             canvas='#161b20' if dark else '#ffffff',
             field='#2a3139' if dark else '#ffffff',
             ink='#e8edf2' if dark else '#26313b',
             muted='#a6b0bb' if dark else '#64717d',
             border='#414b56' if dark else '#cbd2d9',
             grid='#2c343d' if dark else '#e8edf1',
             accent='#8eb7d9' if dark else '#356b95',
             selected='#344b5e' if dark else '#dce8f2')
    x, y = offset, 128
    sx = x + 520
    text(x, 99, theme.upper(), '#526170', 11, 600)
    text(x+800, 99, '520 × 440pt canvas + 280pt sidebar', '#526170', 11, anchor='end')
    rect(x, y-24, 800, 24, c['bg'], c['border'])
    text(x+14, y-8, 'Untitled — GraphSketcher', c['muted'], 11)
    rect(x, y, 520, 440, c['canvas'], c['border'])
    # An illustrative graph, with a selected curve and its data nodes.
    for gx in range(80, 481, 50):
        path(f'M{x+gx} {y+48}V{y+370}', c['grid'], 1)
    for gy in range(70, 371, 50):
        path(f'M{x+64} {y+gy}H{x+480}', c['grid'], 1)
    path(f'M{x+64} {y+44}V{y+370}H{x+484}', c['muted'], 1)
    for i in range(5):
        text(x+80+i*100, y+390, str(i*2), c['muted'], 10, anchor='middle')
    for i in range(4):
        text(x+51, y+374-i*100, str(i*2), c['muted'], 10, anchor='end')
    text(x+274, y+421, 'Time (s)', c['ink'], 12, anchor='middle')
    text(x+82, y+28, 'Distance (m)', c['muted'], 12)
    path(f'M{x+80} {y+345}C{x+155} {y+325} {x+190} {y+240} {x+240} {y+210}S{x+385} {y+150} {x+450} {y+75}', c['accent'], 2)
    for gx, gy in [(80,345),(160,293),(240,210),(350,157),(450,75)]:
        parts.append(f'<circle cx="{x+gx}" cy="{y+gy}" r="4" fill="{c["canvas"]}" stroke="{c["accent"]}" stroke-width="1.5"/>')
    text(x+360, y+124, 'Series A', c['ink'], 13)
    rect(sx, y, 280, 440, c['bg'], c['border'])
    # Four labeled targets, not icon-only tabs; 14pt outer padding.
    for i, label in enumerate(('Style', 'Axes', 'Canvas', 'Data')):
        tx = sx+14+i*63
        if i == 0: rect(tx, y+12, 63, 48, c['selected'], c['border'], 5)
        parts.append(f'<g transform="translate({tx+22} {y+17})">')
        if i == 0:
            path('M1 4h18M1 10h18M1 16h18', c['ink'])
            for cx,cy in [(6,4),(14,10),(9,16)]:
                parts.append(f'<circle cx="{cx}" cy="{cy}" r="2" fill="{c["bg"]}" stroke="{c["ink"]}" stroke-width="1.5"/>')
        elif i == 1:
            path('M2 1v17h17M5 13l5-6 6-3', c['ink'])
        elif i == 2:
            rect(2,2,16,16,'none',c['ink'],1)
            path('M6 2v4M2 6h4m8 12v-4m4 0h-4', c['ink'])
        else:
            for yy in (4,10,16):
                parts.append(f'<circle cx="3" cy="{yy}" r="1.5" fill="{c["ink"]}"/>')
                path(f'M8 {yy}h10', c['ink'])
        parts.append('</g>')
        text(tx+31.5, y+52, label, c['ink'], 11, 500, 'middle')
    path(f'M{sx} {y+72}h280', c['border'], 1)
    clip = 'style-' + theme.lower()
    parts.append(f'<defs><clipPath id="{clip}"><rect x="{sx+1}" y="{y+73}" width="278" height="366"/></clipPath></defs>')

    def field(fx, fy, fw, label, menu=False):
        rect(fx, fy-17, fw, 24, c['field'], c['border'], 4)
        text(fx+8, fy, label, c['ink'], 11)
        if menu: path(f'M{fx+fw-16} {fy-5}l3 3 3-3', c['muted'], 1)

    def controls(top, shift=0):
        # Same content drawn twice: top viewport and explicitly labeled continuation.
        base = top-shift
        text(sx+16, base+23, 'Style', c['ink'], 14, 600)
        text(sx+264, base+23, '1 curve selected', c['muted'], 10, anchor='end')
        labels = ('Width', 'Color', 'Opacity', 'Point type', 'Point shape', 'Line type',
                  'Dash', 'Arrows', 'Label', 'Font', 'Font size', 'Label distance', 'Position')
        for i, label in enumerate(labels):
            ry = base+55+i*32
            text(sx+16, ry, label, c['muted'], 11)
            fx = sx+112
            if label == 'Width': field(fx,ry,140,'2.0 pt')
            elif label == 'Color':
                field(fx,ry,140,'')
                rect(fx+6,ry-12,20,14,c['accent'],r=2)
                text(fx+34,ry,'Selected color',c['ink'],11)
            elif label == 'Opacity':
                path(f'M{fx+4} {ry-4}h80',c['border'],3)
                path(f'M{fx+4} {ry-4}h64',c['accent'],3)
                parts.append(f'<circle cx="{fx+68}" cy="{ry-4}" r="5" fill="{c["field"]}" stroke="{c["border"]}"/>')
                text(fx+100,ry,'80%',c['ink'],11)
            elif label == 'Point type': field(fx,ry,140,'Shape',True)
            elif label == 'Point shape': field(fx,ry,140,'Circle',True)
            elif label == 'Line type': field(fx,ry,140,'Curved',True)
            elif label == 'Dash': field(fx,ry,140,'Solid',True)
            elif label == 'Arrows':
                for dx, caption in [(0,'Start'),(72,'End')]:
                    rect(fx+dx,ry-12,13,13,c['field'],c['border'],3)
                    text(fx+dx+19,ry-1,caption,c['ink'],11)
            elif label == 'Label': field(fx,ry,140,'Series A')
            elif label == 'Font': field(fx,ry,140,'Helvetica…',True)
            elif label == 'Font size': field(fx,ry,140,'13 pt')
            elif label == 'Label distance': field(fx,ry,140,'8 pt')
            elif label == 'Position':
                text(fx,ry,'X',c['ink'],11);field(fx+14,ry,49,'6.0')
                text(fx+73,ry,'Y',c['ink'],11);field(fx+87,ry,53,'4.2')
        return base+55+12*32+7

    parts.append(f'<g clip-path="url(#{clip})">')
    bottom = controls(y+73)
    parts.append('</g>')
    # A visible scrollbar and cropped row show this is a scrolling inspector.
    rect(sx+270,y+84,4,344,c['grid'],r=2)
    rect(sx+270,y+84,4,250,c['muted'],r=2)
    text(x, y+465, '520 × 440pt graph area · sidebar scrolls independently', '#526170', 11)
    text(sx, 612, 'SCROLL CONTINUATION / SAME STYLE PANEL', '#526170', 10, 500)
    rect(sx,624,280,184,c['bg'],c['border'],6)
    cont = 'continuation-'+theme.lower()
    parts.append(f'<defs><clipPath id="{cont}"><rect x="{sx+1}" y="625" width="278" height="182"/></clipPath></defs>')
    parts.append(f'<g clip-path="url(#{cont})">')
    controls(624,55+8*32-24)
    parts.append('</g>')
    rect(sx+270,636,4,160,c['grid'],r=2)
    rect(sx+270,680,4,114,c['muted'],r=2)
    text(x, 639, 'Existing controls, reorganized for legibility.', '#26313b', 14, 500)
    text(x, 665, '14–16pt padding; fixed icon + label section selector.', '#526170', 12)
    text(x, 690, 'Style nib: 240 × 449pt · Axes nib: 240 × 559pt.', '#526170', 12)
    text(x, 715, 'Both need vertical scrolling below the section selector.', '#526170', 12)
    text(x, 740, 'Control appearance is illustrative; native semantics follow integration.', '#526170', 11)
    # Both themes get the exact seven representative glyphs, on their own surface.
    rect(x,828,800,88,c['bg'],c['border'],8)
    for i,name in enumerate(('modify','draw','fill','text','lock','group','inspector')):
        gx=x+54+i*114
        use(name,gx-12,842,c['ink'])
        text(gx,891,name.title(),c['muted'],11,anchor='middle')

parts.append('</svg>')
svg = HERE / 'sidebar-mockup.svg'
png = HERE / 'sidebar-mockup-light-dark.png'
svg.write_text('\n'.join(parts)+'\n')
subprocess.run(['rsvg-convert','--width',str(WIDTH*2),'--height',str(HEIGHT*2),
                '--output',str(png),str(svg)],check=True)
from PIL import Image
with Image.open(png) as image:
    assert image.size == (3360,1880), image.size
assert bottom > 128+440, 'The content must actually exceed the viewport.'
assert all(label in svg.read_text() for label in ('Style','Axes','Canvas','Data','Width','Opacity','Font size','Label distance','Position'))
print(svg)
print(png)
