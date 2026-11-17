#!/usr/bin/env python3
"""Build B1 macOS/iPad icon handoff; writes only this Delivery directory."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont, ImageChops

HERE = Path(__file__).resolve().parent
STUDY = HERE.parent
NS = '{http://www.w3.org/2000/svg}'
ET.register_namespace('', NS[1:-1])
PROFILE = Path('/System/Library/ColorSync/Profiles/sRGB Profile.icc').read_bytes()


def run(*args):
    subprocess.run([str(a) for a in args], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


def glyph(theme='light', part=None):
    root = ET.parse(STUDY / 'Masters' / f'bezier-g-nodes-medium-symbol-{theme}.svg').getroot()
    group = copy.deepcopy(root.find(NS + 'g'))
    circles = group.findall(NS + 'circle')
    assert len(circles) == 7 and all(c.get('r') == '1.7' for c in circles)
    assert group.get('stroke-width') == '1.75'
    if part == 'curve':
        for circle in circles:
            group.remove(circle)
    if part == 'nodes':
        group.remove(group.find(NS + 'path'))
    if theme == 'tinted':
        raise ValueError('Use the light master and recolor after extraction')
    return group


def svg(name, content, width=1024, height=1024):
    path = HERE / 'Sources' / f'{name}.svg'
    path.parent.mkdir(exist_ok=True)
    path.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title"><title id="title">GraphSketcher B1 {name} - delivery artwork, integration pending</title>{content}</svg>\n')
    return path


def placed(theme='light', part=None, transform='translate(102.4 102.4) scale(25.6)', mono=False):
    group = glyph(theme, part)
    if mono:
        for element in group.iter():
            for attr in ('fill', 'stroke'):
                if element.get(attr) not in (None, 'none'):
                    element.set(attr, '#ffffff')
    return f'<g transform="{transform}">{ET.tostring(group, encoding="unicode")}</g>'


def render(source, target, size, opaque=False, grayscale=False):
    target.parent.mkdir(parents=True, exist_ok=True)
    run('rsvg-convert', '--width', size, '--height', size, '--output', target, source)
    with Image.open(target) as image:
        image = image.convert('L' if grayscale else ('RGB' if opaque else 'RGBA'))
        image.save(target, icc_profile=None if grayscale else PROFILE)


def iconset(source, name, destination):
    entries = []
    destination.mkdir(parents=True, exist_ok=True)
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            filename = f'icon_{points}x{points}{"@2x" if scale == 2 else ""}.png'
            render(source, destination / filename, points * scale)
            entries.append({'idiom': 'mac', 'size': f'{points}x{points}', 'scale': f'{scale}x', 'filename': filename})
    run('iconutil', '--convert', 'icns', '--output', HERE / 'macOS' / f'{name}.icns', destination)
    return entries


def main():
    light = svg('app-light', '<rect width="1024" height="1024" fill="#ffffff"/>' + placed())
    dark = svg('app-dark', '<rect width="1024" height="1024" fill="#171c22"/>' + placed('dark'))
    dark_layer = svg('app-dark-transparent', placed('dark'))
    tinted = svg('app-tinted', '<rect width="1024" height="1024" fill="#000000"/>' + placed(mono=True))
    mac = svg('app-macos', '<rect x="100" y="100" width="824" height="824" rx="184" fill="#ffffff"/>' + placed())
    document = svg('document', '<path d="M224 96 L640 96 L800 256 L800 928 L224 928 Z" fill="#ffffff" stroke="#a3afb9" stroke-width="12" stroke-linejoin="round"/><path d="M640 96 L640 256 L800 256" fill="none" stroke="#a3afb9" stroke-width="12" stroke-linejoin="round"/>' + placed(transform='translate(224 320) scale(18)'))
    curve = svg('01-curve', placed(part='curve'))
    nodes = svg('02-nodes', placed(part='nodes'))
    mac_entries = iconset(mac, 'GSAppIcon', HERE / 'macOS' / 'GraphSketcher.iconset')
    iconset(document, 'GSDocIcon', HERE / 'macOS' / 'GraphSketcherDocument.iconset')
    mac_catalog = HERE / 'macOS' / 'Assets.xcassets'
    write_json(mac_catalog / 'Contents.json', {'info': {'author': 'xcode', 'version': 1}})
    app_set = mac_catalog / 'AppIcon.appiconset'
    app_set.mkdir(exist_ok=True)
    for entry in mac_entries:
        shutil.copyfile(HERE / 'macOS' / 'GraphSketcher.iconset' / entry['filename'], app_set / entry['filename'])
    write_json(app_set / 'Contents.json', {'images': mac_entries, 'info': {'author': 'xcode', 'version': 1}})
    ipad_catalog = HERE / 'iPad' / 'Assets.xcassets'
    write_json(ipad_catalog / 'Contents.json', {'info': {'author': 'xcode', 'version': 1}})
    ipad_set = ipad_catalog / 'AppIcon.appiconset'
    ipad_entries = []
    for appearance, source in (('any', light), ('dark', dark_layer), ('tinted', tinted)):
        filename = f'AppIcon-{appearance}-1024.png'
        render(source, ipad_set / filename, 1024, opaque=appearance == 'any', grayscale=appearance == 'tinted')
        entry = {'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024', 'filename': filename}
        if appearance != 'any':
            entry['appearances'] = [{'appearance': 'luminosity', 'value': appearance}]
        ipad_entries.append(entry)
    write_json(ipad_set / 'Contents.json', {'images': ipad_entries, 'info': {'author': 'xcode', 'version': 1}})
    for size in (20, 29, 40, 50, 58, 72, 76, 80, 100, 144, 152, 167, 1024):
        render(light, HERE / 'iPad' / 'Legacy' / f'GraphSketcher-{size}.png', size, opaque=True)
    for points in (32, 64, 128, 320):
        for scale in (1, 2):
            render(document, HERE / 'iPad' / 'Documents' / f'Document-ograph-{points}{"@2x" if scale == 2 else ""}.png', points*scale)
    render(document, HERE / 'iPad' / 'Documents' / 'Document-ograph-640.png', 640)
    for points in (32, 128):
        for scale in (1, 2):
            source = HERE / 'iPad' / 'Documents' / f'Document-ograph-{points}{"@2x" if scale == 2 else ""}.png'
            shutil.copyfile(source, source.with_name(f'DocumentIconGraph-{points}{"@2x" if scale == 2 else ""}.png'))
    for theme in ('light', 'dark'):
        for form in ('symbol', 'lockup'):
            stem = f'bezier-g-nodes-medium-{form}-{theme}'
            logo_dir = HERE / 'Branding'
            logo_dir.mkdir(exist_ok=True)
            shutil.copyfile(STUDY / 'Masters' / f'{stem}.svg', logo_dir / f'{stem}.svg')
            for suffix in ('.pdf', '.png', '@2x.png'):
                shutil.copyfile(STUDY / 'Exports' / f'{stem}{suffix}', logo_dir / f'{stem}{suffix}')
    composer = HERE / 'GraphSketcher.icon'
    (composer / 'Assets').mkdir(parents=True, exist_ok=True)
    for source in (curve, nodes):
        shutil.copyfile(source, composer / 'Assets' / source.name)
    color = lambda value: {'solid': value}
    write_json(composer / 'icon.json', {
        'fill-specializations': [{'value': color('srgb:1,1,1,1')}, {'appearance': 'dark', 'value': color('srgb:0.090196,0.109804,0.133333,1')}],
        'groups': [{'name': 'B1 - unchanged curve and actual anchors', 'lighting': 'combined',
            'specular': False, 'blur-material': 0, 'shadow': {'kind': 'neutral', 'opacity': 0},
            'translucency': {'enabled': False, 'value': 0},
            'layers': [{'name': name, 'image-name': filename,
                'fill-specializations': [{'value': color('srgb:0.152941,0.462745,0.603922,1')},
                    {'appearance': 'dark', 'value': color('srgb:0.501961,0.784314,0.909804,1')}],
                'glass': False} for name, filename in (('01 Curve', curve.name), ('02 Nodes', nodes.name))]}],
        'supported-platforms': {'squares': 'shared'}})
    # Native legacy codecs quantize 16/32px edge colors; compare visible pixels on both surfaces.
    round_trips = []
    with tempfile.TemporaryDirectory(prefix='gs-b1-icons-') as temporary:
        for name, original in (('GSAppIcon', 'GraphSketcher'), ('GSDocIcon', 'GraphSketcherDocument')):
            target = Path(temporary) / f'{name}.iconset'
            run('iconutil', '--convert', 'iconset', '--output', target, HERE / 'macOS' / f'{name}.icns')
            for source in (HERE / 'macOS' / f'{original}.iconset').glob('*.png'):
                with Image.open(source).convert('RGBA') as a, Image.open(target / source.name).convert('RGBA') as b:
                    assert a.size == b.size, source
                    assert a.getchannel('A').tobytes() == b.getchannel('A').tobytes(), source
                    for background in ('#ffffff', '#171c22'):
                        first = Image.new('RGBA', a.size, background)
                        second = Image.new('RGBA', b.size, background)
                        first.alpha_composite(a)
                        second.alpha_composite(b)
                        difference = max(high for low, high in ImageChops.difference(first, second).getextrema())
                        if source.name not in ('icon_16x16.png', 'icon_32x32.png'):
                            assert difference == 0, (source, difference)
                        round_trips.append({'icon': name, 'slot': source.name, 'background': background,
                                            'max_channel_difference': difference})
    checks = {'icc_profile_sha256': hashlib.sha256(PROFILE).hexdigest(), 'selection': 'B1', 'integration': 'not performed', 'icns_round_trips': round_trips, 'pngs': {}}
    for png in sorted(HERE.rglob('*.png')):
        with Image.open(png) as image:
            if png.name.startswith('preview-'):
                continue
            assert image.width > 0 and image.height > 0, png
            if 'lockup' in png.name:
                scale = 2 if '@2x' in png.name else 1
                assert image.size == (340*scale, 64*scale), png
            else:
                assert image.width == image.height, png
            box = image.convert('RGBA').getchannel('A').getbbox()
            assert box, png
            if image.mode == 'RGBA' and image.getchannel('A').getextrema() != (255, 255):
                assert min(box[:2]) > 0 and box[2] < image.width and box[3] < image.height, (png, box)
            assert len(image.convert('RGB').getcolors(image.width*image.height) or []) > 1, png
            checks['pngs'][str(png.relative_to(HERE))] = {'size': list(image.size), 'mode': image.mode, 'alpha_bounds': list(box)}
    # Actual-size strip + large icon views; draw labels with the installed system font.
    sheet = Image.new('RGB', (1100, 780), '#eef1f4')
    draw = ImageDraw.Draw(sheet)
    regular = '/System/Library/Fonts/HelveticaNeue.ttc'
    title = ImageFont.truetype(regular, 28)
    label = ImageFont.truetype(regular, 16)
    draw.text((32, 24), 'GraphSketcher B1 / macOS + iPad asset delivery', font=title, fill='#202932')
    draw.text((32, 67), 'Selected geometry preserved. Icon backgrounds and document carrier prepared for integration.', font=label, fill='#626e79')
    for x, source, name in ((32, mac, 'macOS / ICNS + appiconset'), (390, light, 'iPad / 1024 + legacy sizes'), (748, document, 'GraphSketcher documents')):
        temporary = HERE / 'Sources' / f'{source.stem}-preview.png'
        render(source, temporary, 288)
        with Image.open(temporary).convert('RGBA') as image:
            sheet.paste(image, (x, 112), image)
        draw.text((x, 418), name, font=label, fill='#202932')
    draw.text((32, 470), 'macOS app / actual pixels: 16, 32, 64, 128', font=label, fill='#626e79')
    for x, size in ((32,16),(84,32),(152,64),(252,128)):
        path = HERE / 'macOS' / 'GraphSketcher.iconset' / {16:'icon_16x16.png',32:'icon_32x32.png',64:'icon_32x32@2x.png',128:'icon_128x128.png'}[size]
        with Image.open(path).convert('RGBA') as image:
            sheet.paste(image, (x, 510), image)
    draw.rounded_rectangle((440, 475, 1068, 726), radius=18, fill='#171c22')
    render(dark, HERE / 'Sources' / 'app-dark-preview.png', 192, opaque=True)
    with Image.open(HERE / 'Sources' / 'app-dark-preview.png') as image:
        sheet.paste(image, (462, 500))
    draw.text((686, 520), 'Dark appearance', font=label, fill='#edf2f6')
    draw.text((686, 550), 'Also includes grayscale tinted art', font=label, fill='#a5b2bf')
    draw.text((686, 580), 'and editable Icon Composer layers.', font=label, fill='#a5b2bf')
    draw.text((32, 750), 'Artwork/export proof only. Native integration, device testing and store acceptance remain outstanding.', font=label, fill='#626e79')
    sheet.save(HERE / 'preview-delivery.png', icc_profile=PROFILE)
    checks['source_sha256'] = {str(p.relative_to(STUDY)): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in sorted((STUDY / 'Masters').glob('bezier-g-nodes-medium-*.svg'))}
    checks['files'] = {str(p.relative_to(HERE)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in sorted(HERE.rglob('*')) if p.is_file() and p.name not in ('.DS_Store', 'checks.json', 'apple-validation.json', 'HANDOFF.md')}
    write_json(HERE / 'checks.json', checks)
    print(f'PASS: B1 package exported; {len(checks["pngs"])} PNGs checked; both ICNS round-trips preserve exact dimensions/alpha in all 10 slots; native legacy-edge RGB differences recorded.')


if __name__ == '__main__':
    main()
