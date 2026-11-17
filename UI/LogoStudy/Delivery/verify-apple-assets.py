#!/usr/bin/env python3
"""Compile B1 catalogs and render its Icon Composer document without launching apps."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent


def run(*args):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode}): {result.stderr}\n{result.stdout}')
    return result.stdout


def main():
    developer = Path(run('xcode-select', '-p').strip())
    tool = developer.parent / 'Applications/Icon Composer.app/Contents/Executables/ictool'
    report = {'status': 'Asset-only compilation and rendering passed; app/device/store acceptance not performed',
              'icon_composer': json.loads(run(tool, '--version')), 'catalogs': [], 'appearances': []}
    with tempfile.TemporaryDirectory(prefix='gs-apple-assets-') as temporary:
        temporary = Path(temporary)
        for platform, relative, minimum in (('macosx', 'macOS', '12.0'), ('iphoneos', 'iPad', '15.0')):
            target = temporary / platform
            target.mkdir()
            args = ['xcrun', 'actool', HERE / relative / 'Assets.xcassets', '--compile', target,
                    '--platform', platform, '--minimum-deployment-target', minimum,
                    '--app-icon', 'AppIcon', '--output-partial-info-plist', temporary / f'{platform}.plist',
                    '--output-format', 'human-readable-text']
            if platform == 'iphoneos':
                args.extend(['--target-device', 'ipad'])
            output = run(*args)
            assert (target / 'Assets.car').is_file(), output
            assert 'com.apple.actool.errors' not in output, output
            report['catalogs'].append({'platform': platform, 'minimum_tested': minimum,
                                       'result': 'Assets.car compiled', 'app_build': False})
        sheet = Image.new('RGB', (1200, 590), '#eef1f4')
        draw = ImageDraw.Draw(sheet)
        font = ImageFont.truetype('/System/Library/Fonts/HelveticaNeue.ttc', 15)
        for row, platform in enumerate(('macOS', 'iOS')):
            for col, appearance in enumerate(('Default', 'Dark', 'ClearLight', 'ClearDark', 'TintedLight', 'TintedDark')):
                target = temporary / f'{platform}-{appearance}.png'
                run(tool, HERE / 'GraphSketcher.icon', '--export-image', '--output-file', target,
                    '--platform', platform, '--rendition', appearance, '--width', '1024',
                    '--height', '1024', '--scale', '1')
                with Image.open(target).convert('RGBA') as image:
                    assert image.size == (1024, 1024) and image.getchannel('A').getbbox(), target
                    image.thumbnail((176, 176))
                    sheet.paste(image, (12+col*200, 28+row*280), image)
                draw.text((12+col*200, 216+row*280), f'{platform} / {appearance}', font=font, fill='#202932')
                report['appearances'].append({'platform': platform, 'appearance': appearance, 'pixels': [1024, 1024]})
        sheet.save(HERE / 'preview-apple-appearances.png')
    # Pin every delivered input/proof; docs may be edited after verification without affecting art.
    report['files'] = {str(p.relative_to(HERE)): hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in sorted(HERE.rglob('*')) if p.is_file() and
                       p.name not in ('.DS_Store', 'checks.json', 'apple-validation.json', 'HANDOFF.md')}
    (HERE / 'apple-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: 2 asset catalogs compiled and 12 native Icon Composer appearances rendered.')


if __name__ == '__main__':
    main()
