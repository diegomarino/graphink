#!/usr/bin/env python3
"""Check the graphink command-line tool shipped in Graphink.app and in graphink-cli.zip.

The tool under test is the one the build embeds, Graphink.app/Contents/Helpers/graphink, and the same
binary from graphink-cli.zip (made by .github/scripts/package-cli.sh from that app and unpacked here).
Both copies are checked as shipped: signed, identified as com.diegomarino.Graphink.cli, without
entitlements, linking only system libraries and the frameworks beside it, and with an embedded
Info.plist that claims no document types.

With the app's helper: every example (Examples/**/*.graphink) and the 35 historical .ograph samples
render to PNG and PDF read-only (every input is hashed before and after). Example renders are compared
with their shipped previews: the PDF, rasterized the way Examples/Tools/GenerateCatalog.m made the
previews, must match them pixel for pixel; the direct PNG (the app's raster export, drawn into a
Generic RGB bitmap) may differ only by antialiasing and color rounding. The agent skill's example specs
(skills/graphink/assets/examples) are created, checked with docs/format/check-opc.py and the RELAX NG
schema, reopened and rendered, and the skill's make-graph.sh makes one of them with the helper found on
PATH. Every best-fit line a spec creates (a "fit") is checked against a least-squares fit computed here from
the points stored in the document. Invalid specs and arguments must be refused with a message and write nothing.

With the zip's copy: every PNG is byte-identical to the helper's and every created document has the
same contents.xml.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPECS = ROOT / 'skills/graphink/assets/examples'
SKILL_SCRIPTS = ROOT / 'skills/graphink/scripts'
IDENTIFIER = 'com.diegomarino.Graphink.cli'
CLAIMS = ('CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations', 'CFBundleURLTypes', 'NSServices')
NOISE = re.compile(r'^(\*\*\* Assertions are ON \*\*\*|    OBEnableExpensiveAssertions = NO|.* graphink\[\d+:\d+\] xml validates)$')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def png_width(path):
    data = Path(path).read_bytes()[:24]
    assert data[:8] == b'\x89PNG\r\n\x1a\n' and data[12:16] == b'IHDR', f'{path}: not a PNG'
    return int.from_bytes(data[16:20], 'big')


def run(command, log, expect=0):
    proc = subprocess.run([str(c) for c in command], capture_output=True, text=True, timeout=300)
    Path(log).write_text('$ ' + ' '.join(map(str, command)) + '\n' + proc.stdout + proc.stderr)
    if expect is not None and proc.returncode != expect:
        raise AssertionError(f'Exit {proc.returncode} (expected {expect}); see {log}')
    return proc


def messages(proc):
    """stderr without the Debug frameworks' banner and the writer's schema note."""
    return [line for line in proc.stderr.splitlines() if line and not NOISE.match(line)]


def least_squares(points):
    """Slope, intercept and R² of the ordinary least-squares line y = mx + b, from deviations about the means."""
    n = len(points)
    mx, my = sum(x for x, _ in points) / n, sum(y for _, y in points) / n
    sxx = sum((x - mx) ** 2 for x, _ in points)
    sxy = sum((x - mx) * (y - my) for x, y in points)
    syy = sum((y - my) ** 2 for _, y in points)
    m = sxy / sxx
    return m, my - m * mx, (sxy * sxy / (sxx * syy) if syy else 0)


def check_fits(contents, summary, name):
    """Each best-fit line stored in contents.xml (line class="fit") must run along the least-squares line of its
    data points, from the stored vertices; create's summary must report each one as the app's status bar does.
    Returns [{data, slope, intercept, r2, from, to}] per line."""
    root = ET.fromstring(contents)
    vertices = {v.get('id'): (float(v.get('x', 0)), float(v.get('y', 0))) for v in root.iterfind('.//{*}vertex')}
    fits = []
    for line in root.iterfind('.//{*}line'):
        if line.get('class') != 'fit':
            continue
        data = [vertices[i] for i in line.find('{*}data').get('ids').split()]
        (x1, y1), (x2, y2) = vertices[line.get('v1')], vertices[line.get('v2')]
        m, b, r2 = least_squares(data)
        stored_m = (y2 - y1) / (x2 - x1)
        stored_b = y1 - stored_m * x1
        scale = max(1.0, *(abs(y) for _, y in data))
        assert abs(stored_m - m) <= 1e-9 * max(1.0, abs(m)) and abs(stored_b - b) <= 1e-9 * scale, \
            f'{name}: stored fit y = {stored_m!r}x + {stored_b!r}, least squares y = {m!r}x + {b!r}'
        fits.append({'data': len(data), 'slope': m, 'intercept': b, 'r2': r2, 'from': x1, 'to': x2})
    reported = [line for line in summary.splitlines() if 'Best-fit line:' in line]
    assert len(reported) == len(fits), f'{name}: {len(fits)} fit lines stored, {len(reported)} reported: {summary}'
    return fits


def embedded_info_plist(binary):
    """The __TEXT,__info_plist section of a thin 64-bit Mach-O."""
    data = Path(binary).read_bytes()
    magic, _, _, _, ncmds, _, _, _ = struct.unpack_from('<8I', data, 0)
    assert magic == 0xFEEDFACF, f'{binary}: not a thin 64-bit Mach-O'
    offset = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<2I', data, offset)
        if cmd == 0x19 and data[offset + 8:offset + 24].rstrip(b'\0') == b'__TEXT':  # LC_SEGMENT_64
            nsects = struct.unpack_from('<I', data, offset + 64)[0]
            for index in range(nsects):
                section = offset + 72 + index * 80
                if data[section:section + 16].rstrip(b'\0') == b'__info_plist':
                    length, start = struct.unpack_from('<QI', data, section + 40)
                    return plistlib.loads(data[start:start + length])
        offset += size
    raise AssertionError(f'{binary}: no embedded Info.plist')


def check_shipped(tool, version, log_dir, name):
    """The tool as it ships: signature, identity, no entitlements, dependencies, embedded Info.plist."""
    run(['codesign', '--verify', '--strict', tool], log_dir / f'{name}-codesign-verify.log')
    signature = run(['codesign', '-dv', tool], log_dir / f'{name}-codesign.log').stderr
    assert f'Identifier={IDENTIFIER}' in signature, f'{tool}: not signed as {IDENTIFIER}'
    entitlements = run(['codesign', '-d', '--entitlements', '-', '--xml', tool], log_dir / f'{name}-entitlements.log').stdout
    # Debug signatures carry Xcode's get-task-allow (package-release.sh refuses it in a release); never the sandbox,
    # which would confine the tool to a container instead of the user's files.
    assert 'com.apple.security.app-sandbox' not in entitlements, f'{tool}: is sandboxed'
    frameworks = tool.parent.parent / 'Frameworks'
    linked = run(['otool', '-L', tool], log_dir / f'{name}-otool.log').stdout.splitlines()[1:]
    for line in linked:
        path = line.strip().split(' (')[0]
        match = re.match(r'@rpath/([^/]+\.framework)/', path)
        assert path.startswith(('/System/Library/', '/usr/lib/')) or (match and (frameworks / match.group(1)).is_dir()), f'{tool}: links {path}'
    rpaths = run(['otool', '-l', tool], log_dir / f'{name}-load-commands.log').stdout
    assert re.findall(r'path (\S+) \(offset', rpaths) == ['@executable_path/../Frameworks'], f'{tool}: unexpected rpaths'
    info = embedded_info_plist(tool)
    assert info.get('CFBundleIdentifier') == IDENTIFIER and info.get('OFControllerClass') == 'GICController', f'{tool}: {info}'
    assert not set(CLAIMS) & set(info), f'{tool}: Info.plist declares {set(CLAIMS) & set(info)}'
    assert info.get('CFBundleShortVersionString') == version, f'{tool}: version {info.get("CFBundleShortVersionString")}, the app is {version}'
    assert (tool.parent.parent / 'Resources/StyleFonts/Kalam-Bold.ttf').is_file(), f'{tool}: no style fonts beside it'
    return {'linked': [line.strip().split(' (')[0] for line in linked], 'version': info['CFBundleShortVersionString']}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--products', required=True, type=Path, help='<build root>/Debug/Products/Debug from .github/scripts/build.sh')
    parser.add_argument('--output', required=True, type=Path, help='a new evidence directory')
    args = parser.parse_args()
    out = args.output.absolute()
    if out.exists():
        parser.error('--output already exists')
    app = args.products.absolute() / 'Graphink.app'
    helper = app / 'Contents/Helpers/graphink'
    if not helper.is_file():
        parser.error(f'No {helper}; build the app first')
    out.mkdir(parents=True)
    logs = out / 'logs'
    logs.mkdir()
    report = {'passed': False}
    version = plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']

    historical = re.findall(r'^([a-f0-9]{64})  (GraphSketcher/.+\.ograph)$', (ROOT / 'Checks/historical-samples.sha256').read_text(), re.M)
    assert len(historical) == 35, 'Expected 35 historical samples'
    examples = sorted(p.relative_to(ROOT) for p in (ROOT / 'Examples').rglob('*.graphink'))
    inputs = [Path(p) for _, p in historical] + examples
    before = {str(p): digest(ROOT / p) for p in inputs}
    assert all(before[p] == h for h, p in historical), 'Historical samples differ from Checks/historical-samples.sha256'

    # 0. Both shipped copies: the app's helper and the unpacked zip.
    run([ROOT / '.github/scripts/package-cli.sh', app, out / 'dist'], logs / 'package-cli.log')
    run(['ditto', '-x', '-k', out / 'dist/graphink-cli.zip', out / 'unpacked'], logs / 'unzip.log')
    unpacked = out / 'unpacked/graphink-cli/Contents/Helpers/graphink'
    report['shipped'] = {'helper': check_shipped(helper, version, logs, 'helper'), 'zip': check_shipped(unpacked, version, logs, 'zip')}
    assert digest(helper) == digest(unpacked), 'The zip holds a different binary than the app'

    imagediff = out / 'ImageDiff'
    run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-framework', 'Foundation', '-framework', 'CoreGraphics',
         '-framework', 'ImageIO', HERE / 'ImageDiff.m', '-o', imagediff], logs / 'imagediff-build.log')

    # 1. Command line: version, help and usage errors.
    proc = run([helper, '--version'], logs / 'version.log')
    assert proc.stdout.startswith(f'graphink {version} (build '), proc.stdout
    for topic in ([], ['render'], ['create']):
        assert 'Usage: graphink' in run([helper, 'help', *topic], logs / f'help{"-".join([""] + topic)}.log').stdout
    for name, command in {'none': [], 'unknown': ['draw'], 'help-unknown': ['help', 'draw'], 'render-none': ['render'],
                          'create-none': ['create'], 'create-type': ['create', SPECS / 'function-plot.json', '-o', out / 'x.png']}.items():
        proc = run([helper, *command], logs / f'usage-{name}.log', expect=2)
        assert 'Usage: graphink' in proc.stderr or 'graphink create:' in proc.stderr, f'{name}: {proc.stderr}'

    # 2. Render every input to PNG and PDF; compare examples with their previews.
    renders, comparisons, warnings = out / 'renders', {}, {}
    renders.mkdir()
    for path in inputs:
        stem = re.sub(r'[^A-Za-z0-9.-]+', '_', str(path))
        for ext in ('png', 'pdf'):
            proc = run([helper, 'render', ROOT / path, '-o', renders / f'{stem}.{ext}'], logs / f'{stem}.{ext}.log')
            # The production reader logs the known defects of some historical samples (docs/BUILDING.md, Known limits).
            if path.suffix == '.ograph':
                warnings[str(path)] = sorted({re.sub(r'^.*\] ', '', m) for m in messages(proc)} | set(warnings.get(str(path), [])))
            else:
                assert not messages(proc), f'{path}: unexpected messages rendering .{ext}: {messages(proc)}'
        assert (renders / f'{stem}.pdf').read_bytes().startswith(b'%PDF-'), f'{path}: not a PDF'
        preview = ROOT / path.parent / 'Previews' / (path.stem + '.png')
        if preview.exists():
            # Previews are 1x, except the welcome document's (2x): match the preview's own scale.
            scale = png_width(preview) / png_width(renders / f'{stem}.png')
            assert scale in (1, 2), f'{preview}: unexpected preview scale {scale}'
            png = renders / f'{stem}.png'
            if scale != 1:
                png = renders / f'{stem}@{scale:g}x.png'
                run([helper, 'render', ROOT / path, '-o', png, '--scale', f'{scale:g}'], logs / f'{stem}.png-scaled.log')
            run([imagediff, '--rasterize-pdf', renders / f'{stem}.pdf', renders / f'{stem}.pdf.png', f'{scale:g}'], logs / f'{stem}.rasterize.log')
            pdf_diff = json.loads(run([imagediff, renders / f'{stem}.pdf.png', preview, out / f'{stem}.pdf-diff.png'], logs / f'{stem}.pdf-diff.log').stdout)
            png_diff = json.loads(run([imagediff, png, preview, out / f'{stem}.png-diff.png'], logs / f'{stem}.png-diff.log').stdout)
            comparisons[str(path)] = {'pdfRaster': pdf_diff, 'png': png_diff}
            assert pdf_diff['sameSize'] and png_diff['sameSize'], f'{path}: render size differs from its preview'
            assert pdf_diff['differing'] == 0, f'{path}: the PDF differs from the shipped preview: {pdf_diff}'
            # The PNG is drawn straight into a Generic RGB bitmap like the app's export, the previews through a PDF into
            # DeviceRGB: colored edges and text antialias slightly differently. The exact PDF comparison above is the
            # geometry check; this one bounds the raster path (a moved label or a cropped page fails it).
            assert png_diff['over64'] <= png_diff['pixels'] // 1000 and png_diff['meanChannelDiff'] < 2, f'{path}: the PNG differs from the shipped preview beyond color space: {png_diff}'
    report['rendered'] = [str(p) for p in inputs]
    report['historicalReaderMessages'] = {p: m for p, m in warnings.items() if m}
    report['previewComparisons'] = comparisons
    # Examples/Tools/pre-credit holds the generator's pinned inputs, which have no previews.
    previewed = [str(p) for p in examples if 'pre-credit' not in p.parts]
    assert sorted(comparisons) == previewed, f'Expected a preview for every example: {sorted(set(previewed) - set(comparisons))}'

    # 3. Resolution options: pixel size = round(points * dpi / 72).
    sample = ROOT / 'Examples/Templates/function-plot.graphink'
    for option, value, pixels in (('--scale', '2', '2160 × 1600'), ('--dpi', '300', '4500 × 3333'), ('--dpi', '150', '2250 × 1667')):
        proc = run([helper, 'render', sample, '-o', renders / f'resolution{option}{value}.png', option, value], logs / f'resolution{option}{value}.log')
        assert pixels in proc.stdout, f'{option} {value}: expected {pixels}: {proc.stdout}'
    assert '1080 × 800 pt' in run([helper, 'render', sample, '--info'], logs / 'info.log').stdout

    # 4. Create the example specs; check, reopen and render each.
    created = out / 'created'
    created.mkdir()
    report['created'] = {}
    specs = sorted(SPECS.glob('*.json'))
    assert len(specs) >= 4, f'Expected the example specs in {SPECS}'
    for spec in specs:
        doc = created / (spec.stem + '.graphink')
        proc = run([helper, 'create', spec, '-o', doc], logs / f'create-{spec.stem}.log')
        assert 'reopened with the production reader' in proc.stdout and not messages(proc), f'{spec.name}: {proc.stdout} {messages(proc)}'
        run([sys.executable, ROOT / 'docs/format/check-opc.py', doc], logs / f'opc-{spec.stem}.log')
        with zipfile.ZipFile(doc) as package:
            (created / (spec.stem + '-contents.xml')).write_bytes(package.read('contents.xml'))
            assert package.read('preview.pdf').startswith(b'%PDF-') if 'preview.pdf' in package.namelist() else True
        run(['xmllint', '--noout', '--relaxng', ROOT / 'GraphSketcher/Model/XML/GraphSketcher.rng', created / (spec.stem + '-contents.xml')], logs / f'schema-{spec.stem}.log')
        run([helper, 'render', doc, '-o', created / (spec.stem + '.png')], logs / f'render-{spec.stem}.log')
        fits = check_fits((created / (spec.stem + '-contents.xml')).read_bytes(), proc.stdout, spec.name)
        report['created'][spec.name] = {'document': str(doc), 'sha256': digest(doc), 'summary': proc.stdout.strip(), 'fits': fits}
    assert any(c['fits'] for c in report['created'].values()), 'Expected an example spec with a best-fit line'

    # 4a. Best-fit lines: extents, a connected series, a fit given before its series, no label, a style preset.
    # Each document is checked like the examples, and its fit against an independent least-squares fit.
    fit_dir = out / 'fits'
    fit_dir.mkdir()
    scatter = [[1, 2.1], [2, 3.9], [3, 6.2], [4, 7.8], [5, 10.1], [6, 12.2]]
    axes = {'x': {'min': 0, 'max': 8}, 'y': {'min': -5, 'max': 20}}
    fit_cases = {
        'data': ([{'type': 'series', 'id': 's', 'points': scatter}, {'type': 'fit', 'series': 's'}], (1, 6)),
        'axis': ([{'type': 'series', 'id': 's', 'points': scatter}, {'type': 'fit', 'series': 's', 'extent': 'axis', 'label': False}], (0, 8)),
        'range': ([{'type': 'fit', 'series': 's', 'extent': [0.5, 7.5], 'color': 'red', 'dash': 'dotted', 'label': {'position': 0.2, 'bold': True}},
                   {'type': 'series', 'id': 's', 'points': scatter}], (0.5, 7.5)),
        'connected': ([{'type': 'series', 'id': 'a', 'points': scatter, 'connect': 'straight', 'marker': 'square'},
                       {'type': 'series', 'id': 'b', 'points': [[1, 15], [3, 11], [5, 9], [7, 4]], 'color': 'orange'},
                       {'type': 'fit', 'series': 'a'}, {'type': 'fit', 'series': 'b'}], (1, 6)),
        'style': ([{'type': 'series', 'id': 's', 'points': scatter}, {'type': 'fit', 'series': 's'}], (1, 6)),
    }
    report['fits'] = {}
    for name, (objects, extent) in fit_cases.items():
        spec = fit_dir / f'{name}.json'
        spec.write_text(json.dumps({'graphink': 1, **axes, **({'style': 'chalkboard'} if name == 'style' else {}), 'objects': objects}))
        doc = fit_dir / f'{name}.graphink'
        proc = run([helper, 'create', spec, '-o', doc], logs / f'fit-create-{name}.log')
        assert 'reopened with the production reader' in proc.stdout and not messages(proc), f'fit {name}: {proc.stdout} {messages(proc)}'
        run([sys.executable, ROOT / 'docs/format/check-opc.py', doc], logs / f'fit-opc-{name}.log')
        with zipfile.ZipFile(doc) as package:
            contents = package.read('contents.xml')
        (fit_dir / f'{name}-contents.xml').write_bytes(contents)
        run(['xmllint', '--noout', '--relaxng', ROOT / 'GraphSketcher/Model/XML/GraphSketcher.rng', fit_dir / f'{name}-contents.xml'], logs / f'fit-schema-{name}.log')
        run([helper, 'render', doc, '-o', fit_dir / f'{name}.png'], logs / f'fit-render-{name}.log')
        fits = check_fits(contents, proc.stdout, f'fit {name}')
        assert len(fits) == sum(o['type'] == 'fit' for o in objects), f'fit {name}: {fits}'
        assert (fits[0]['from'], fits[0]['to']) == extent, f'fit {name}: extent {fits[0]["from"]}..{fits[0]["to"]}, expected {extent}'
        # The equation label: owned by the fit line, unless the spec says "label": false.
        root = ET.fromstring(contents)
        fit_ids = {line.get('id') for line in root.iterfind('.//{*}line') if line.get('class') == 'fit'}
        labelled = {label.get('owner') for label in root.iterfind('.//{*}label')} & fit_ids
        expected_labels = set() if name == 'axis' else fit_ids
        assert labelled == expected_labels, f'fit {name}: equation labels on {sorted(labelled)}, expected {sorted(expected_labels)}'
        report['fits'][name] = {'fits': fits, 'summary': proc.stdout.strip()}

    # 4b. The skill's make-graph.sh, finding the helper through PATH as an agent would.
    path = out / 'path'
    path.mkdir()
    (path / 'graphink').symlink_to(helper)
    made = out / 'make-graph'
    made.mkdir()
    env = {'PATH': f'{path}:/usr/bin:/bin', 'HOME': str(out), 'GRAPHINK_APP_DIRS': ''}
    proc = subprocess.run([SKILL_SCRIPTS / 'make-graph.sh', specs[0], made / specs[0].stem], capture_output=True, text=True, env=env, timeout=300)
    (logs / 'make-graph.log').write_text(proc.stdout + proc.stderr)
    outputs = [made / f'{specs[0].stem}.{ext}' for ext in ('graphink', 'png', 'pdf')]
    assert proc.returncode == 0 and proc.stdout.split() == [str(p) for p in outputs], f'make-graph.sh: {proc.returncode} {proc.stdout} {proc.stderr}'
    assert all(p.is_file() and p.stat().st_size for p in outputs), 'make-graph.sh did not write its three outputs'
    run([sys.executable, ROOT / 'docs/format/check-opc.py', outputs[0]], logs / 'make-graph-opc.log')
    assert png_width(outputs[1]) == png_width(created / f'{specs[0].stem}.png'), 'make-graph.sh rendered another size'
    found = subprocess.run([SKILL_SCRIPTS / 'find-graphink.sh'], capture_output=True, text=True, env=env, timeout=60)
    assert found.returncode == 0 and found.stdout.strip() == str(path / 'graphink'), f'find-graphink.sh: {found.returncode} {found.stdout} {found.stderr}'

    # 5. Refusals: each must exit 1 or 2 with one clear line and write nothing.
    bad = out / 'bad'
    bad.mkdir()
    cases = {
        'unknown-key': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [{'type': 'line', 'points': [[0, 0], [1, 1]], 'colour': 'red'}]}, 'objects[0]: unknown key "colour"'),
        'bad-point': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [{'type': 'line', 'points': [[0, 0], [1]]}]}, 'objects[0].points[1] must be a point'),
        'bad-formula': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [{'type': 'function', 'f': 'sinx', 'from': 0, 'to': 1}]}, 'unknown name "sinx"'),
        'bad-range': ({'graphink': 1, 'x': {'min': 2, 'max': 1}, 'y': {'min': 0, 'max': 1}}, 'max > min'),
        'bad-version': ({'graphink': 2, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}}, 'must be 1'),
        'bad-color': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [{'type': 'point', 'at': [0, 0], 'color': 'mauve'}]}, 'objects[0].color must be #RRGGBB'),
        'bad-style': ({'graphink': 1, 'style': 'neon', 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}}, 'style must be one of paper, sketch, chalkboard, studio, editorial'),
        'fit-unknown-series': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [
            {'type': 'series', 'id': 'a', 'points': [[0, 0], [1, 1]]}, {'type': 'fit', 'series': 'b'}]}, 'objects[1].series: no series has the id "b" (ids: a)'),
        'fit-one-point': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [
            {'type': 'series', 'id': 'a', 'points': [[0.5, 0.5]]}, {'type': 'fit', 'series': 'a'}]}, 'objects[1]: series "a" has 1 point; a best-fit line needs at least 2'),
        'fit-same-point': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [
            {'type': 'series', 'id': 'a', 'points': [[0.5, 0.5], [0.5, 0.5]]}, {'type': 'fit', 'series': 'a'}]}, 'objects[1]: series "a" has 1 point'),
        'fit-same-x': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [
            {'type': 'series', 'id': 'a', 'points': [[0.5, 0.2], [0.5, 0.8]]}, {'type': 'fit', 'series': 'a'}]}, 'objects[1]: every point of series "a" has x = 0.5'),
        'fit-log-axis': ({'graphink': 1, 'x': {'min': 1, 'max': 100, 'log': True}, 'y': {'min': 0, 'max': 1}, 'objects': [
            {'type': 'series', 'id': 'a', 'points': [[1, 0.2], [10, 0.8]]}, {'type': 'fit', 'series': 'a'}]}, 'objects[1]: a best-fit line needs linear axes'),
        'fit-label-text': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [
            {'type': 'series', 'id': 'a', 'points': [[0, 0], [1, 1]]}, {'type': 'fit', 'series': 'a', 'label': {'text': 'trend'}}]}, 'objects[1].label: a best-fit line\'s label is its equation'),
        'fit-bad-extent': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [
            {'type': 'series', 'id': 'a', 'points': [[0, 0], [1, 1]]}, {'type': 'fit', 'series': 'a', 'extent': [1, 0]}]}, 'objects[1].extent: to must be greater than from'),
        'fit-extent-outside': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [
            {'type': 'series', 'id': 'a', 'points': [[0.2, 0.2], [0.8, 0.8]]}, {'type': 'fit', 'series': 'a', 'extent': [-1, 1]}]}, 'objects[1].extent must stay within the x axis range (0 to 1)'),
        'fit-extent-off-y': ({'graphink': 1, 'x': {'min': 0, 'max': 10}, 'y': {'min': 0, 'max': 1}, 'objects': [
            {'type': 'series', 'id': 'a', 'points': [[4, 0.2], [5, 0.8]]}, {'type': 'fit', 'series': 'a', 'extent': 'axis'}]}, 'objects[1].extent: the line reaches y = -2.2 at x = 0, outside the y axis range (0 to 1)'),
        'fit-duplicate-id': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [
            {'type': 'series', 'id': 'a', 'points': [[0, 0]]}, {'type': 'series', 'id': 'a', 'points': [[1, 1]]}]}, 'objects[1].id: "a" is already the id of objects[0]'),
        'fit-no-series': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [{'type': 'fit'}]}, 'objects[0]: "series" is required'),
    }
    for name, (spec, expected) in cases.items():
        path = bad / f'{name}.json'
        path.write_text(json.dumps(spec))
        proc = run([helper, 'create', path, '-o', bad / f'{name}.graphink'], logs / f'refuse-{name}.log', expect=1)
        assert any(expected in line for line in messages(proc)) and len(messages(proc)) == 1, f'{name}: {messages(proc)}'
        assert not (bad / f'{name}.graphink').exists(), f'{name}: wrote a document'
    first = created / (specs[0].stem + '.graphink')
    run([helper, 'create', specs[0], '-o', first], logs / 'refuse-overwrite.log', expect=1)
    # The reader detects the container from the bytes, so a document named .pdf still opens: it must not be replaced.
    disguised = bad / 'document.pdf'
    disguised.write_bytes(first.read_bytes())
    run([helper, 'render', disguised, '-o', disguised, '--force'], logs / 'refuse-input.log', expect=1)
    assert disguised.read_bytes() == first.read_bytes(), 'graphink render wrote over its input'
    # The input is matched by file identity, not by its spelling: another case (the default APFS ignores case),
    # a hard link and a symbolic link all name the same file.
    other_case = bad / 'DOCUMENT.pdf'
    same_file = [bad / 'hard-link.pdf', bad / 'symbolic-link.pdf'] + ([other_case] if other_case.exists() else [])
    (bad / 'hard-link.pdf').hardlink_to(disguised)
    (bad / 'symbolic-link.pdf').symlink_to(disguised.name)
    for alias in same_file:
        proc = run([helper, 'render', disguised, '-o', alias, '--force'], logs / f'refuse-input-{alias.stem}.log', expect=1)
        assert any('Refusing to write over the input' in line for line in messages(proc)), f'{alias.name}: {messages(proc)}'
        assert disguised.read_bytes() == first.read_bytes(), f'graphink render wrote over its input through {alias.name}'
    assert (bad / 'symbolic-link.pdf').is_symlink(), 'graphink render replaced the symbolic link to its input'
    report['inputIdentity'] = [alias.name for alias in same_file]
    # create never replaces its own spec (a JSON spec may be named .graphink) nor a directory, even with --force.
    spec_copy = bad / 'spec.graphink'
    spec_copy.write_bytes(specs[0].read_bytes())
    for alias in [spec_copy] + ([bad / 'SPEC.graphink'] if (bad / 'SPEC.graphink').exists() else []):
        run([helper, 'create', spec_copy, '-o', alias, '--force'], logs / f'refuse-create-over-spec-{alias.stem}.log', expect=1)
        assert spec_copy.read_bytes() == specs[0].read_bytes(), f'graphink create wrote over its spec through {alias.name}'
    folder = bad / 'folder.graphink'
    folder.mkdir()
    run([helper, 'create', specs[0], '-o', folder, '--force'], logs / 'refuse-create-directory.log', expect=1)
    (bad / 'folder.png').mkdir()
    run([helper, 'render', first, '-o', bad / 'folder.png', '--force'], logs / 'refuse-render-directory.log', expect=1)
    assert folder.is_dir() and not any(folder.iterdir()) and (bad / 'folder.png').is_dir(), 'a directory output was replaced'
    # --force does replace an ordinary existing file.
    (bad / 'replaced.graphink').write_bytes(b'old')
    run([helper, 'create', specs[0], '-o', bad / 'replaced.graphink', '--force'], logs / 'create-force.log')
    run([sys.executable, ROOT / 'docs/format/check-opc.py', bad / 'replaced.graphink'], logs / 'create-force-opc.log')
    run([helper, 'render', first, '-o', out / 'x.svg'], logs / 'refuse-type.log', expect=2)
    run([helper, 'render', first, '-o', out / 'x.png', '--dpi', '5000'], logs / 'refuse-dpi.log', expect=2)
    # --dpi and --scale take a positive number and nothing else.
    for index, (option, value) in enumerate((('--dpi', 'abc'), ('--dpi', '0'), ('--dpi', '-72'), ('--dpi', '72abc'), ('--dpi', ''),
                                             ('--dpi', 'inf'), ('--dpi', 'nan'), ('--scale', 'foo'), ('--scale', '0'), ('--scale', '-1'),
                                             ('--scale', '2x'), ('--scale', '0.001'))):
        proc = run([helper, 'render', first, '-o', out / 'x.png', option, value], logs / f'refuse-resolution-{index}.log', expect=2)
        assert len(messages(proc)) == 1, f'{option} {value!r}: {messages(proc)}'
        run([helper, 'render', first, '--info', option, value], logs / f'refuse-resolution-info-{index}.log', expect=2)
    run([helper, 'render', first, '-o', out / 'x.png', '--dpi', '72', '--scale', '1'], logs / 'refuse-dpi-and-scale.log', expect=2)
    run([helper, 'render', out / 'missing.graphink', '-o', out / 'x.png'], logs / 'refuse-missing.log', expect=1)
    assert not (out / 'x.png').exists() and not (out / 'x.svg').exists()
    assert digest(first) == report['created'][specs[0].name]['sha256'], 'A refused overwrite changed the document'

    # 6. The zip's copy draws and creates exactly what the app's helper does.
    zipped = out / 'zip-renders'
    zipped.mkdir()
    for path in inputs:
        stem = re.sub(r'[^A-Za-z0-9.-]+', '_', str(path))
        run([unpacked, 'render', ROOT / path, '-o', zipped / f'{stem}.png'], logs / f'zip-{stem}.png.log')
        assert digest(zipped / f'{stem}.png') == digest(renders / f'{stem}.png'), f'{path}: the zip renders a different PNG'
    for spec in specs:
        doc = zipped / (spec.stem + '.graphink')
        run([unpacked, 'create', spec, '-o', doc], logs / f'zip-create-{spec.stem}.log')
        with zipfile.ZipFile(doc) as package:
            assert package.read('contents.xml') == (created / (spec.stem + '-contents.xml')).read_bytes(), f'{spec.name}: the zip creates a different document'

    after = {str(p): digest(ROOT / p) for p in inputs}
    report['inputsUnchanged'] = after == before
    assert report['inputsUnchanged'], 'An input document changed'
    report['passed'] = True
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    worst = max(c['png']['meanChannelDiff'] for c in comparisons.values())
    print(f'PASS graphink {version} from Graphink.app and graphink-cli.zip: rendered {len(inputs)} documents read-only '
          f'({len(comparisons)} examples match their previews; PNG mean channel difference at most {worst:.3f}), '
          f'created {len(specs)} specs and {len(fit_cases)} best-fit cases (stored fits equal least squares), {len(cases)} bad specs refused, the input refused as {", ".join(report["inputIdentity"])}; evidence: {out}')


if __name__ == '__main__':
    try:
        main()
    except AssertionError as exc:
        print('FAIL: ' + str(exc), file=sys.stderr)
        sys.exit(1)
