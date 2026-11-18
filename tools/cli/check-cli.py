#!/usr/bin/env python3
"""Build graphink-render and graphink-create and check them against the repository's documents.

Renders every example (Examples/**/*.graphink) and the 35 historical .ograph samples to PNG and PDF, read-only:
every input is hashed before and after. Example renders are compared with their shipped previews: the PDF,
rasterized the way Examples/Tools/GenerateCatalog.m made the previews, must match them pixel for pixel; the direct
PNG (the app's raster export, drawn into a Generic RGB bitmap) is reported. The skill's example specs
(tools/skills/graphink-documents/examples) are created, checked with docs/format/check-opc.py and the RELAX NG
schema, reopened and rendered. Invalid specs and arguments must be refused with a message.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SKILL_EXAMPLES = ROOT / 'tools/skills/graphink-documents/examples'
NOISE = re.compile(r'^(\*\*\* Assertions are ON \*\*\*|    OBEnableExpensiveAssertions = NO|.* graphink-create\[\d+:\d+\] xml validates)$')


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
        raise SystemExit(f'Exit {proc.returncode} (expected {expect}); see {log}')
    return proc


def messages(proc):
    """stderr without the Debug frameworks' banner and the writer's schema note."""
    return [line for line in proc.stderr.splitlines() if line and not NOISE.match(line)]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--products', required=True, type=Path, help='<build root>/Debug/Products/Debug from .github/scripts/build.sh')
    parser.add_argument('--output', required=True, type=Path, help='a new evidence directory')
    args = parser.parse_args()
    out = args.output.absolute()
    if out.exists():
        parser.error('--output already exists')
    out.mkdir(parents=True)
    report = {'passed': False}

    historical = re.findall(r'^([a-f0-9]{64})  (GraphSketcher/.+\.ograph)$', (ROOT / 'Checks/historical-samples.sha256').read_text(), re.M)
    assert len(historical) == 35, 'Expected 35 historical samples'
    examples = sorted(p.relative_to(ROOT) for p in (ROOT / 'Examples').rglob('*.graphink'))
    inputs = [Path(p) for _, p in historical] + examples
    before = {str(p): digest(ROOT / p) for p in inputs}
    assert all(before[p] == h for h, p in historical), 'Historical samples differ from Checks/historical-samples.sha256'

    tools = out / 'tools'
    run([HERE / 'build.sh', args.products, tools], out / 'build.log')
    render, create = tools / 'bin/graphink-render', tools / 'bin/graphink-create'
    imagediff = out / 'ImageDiff'
    run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-framework', 'Foundation', '-framework', 'CoreGraphics',
         '-framework', 'ImageIO', HERE / 'ImageDiff.m', '-o', imagediff], out / 'imagediff-build.log')
    logs = out / 'logs'
    logs.mkdir()

    # 1. Render every input to PNG and PDF; compare examples with their previews.
    renders, comparisons, warnings = out / 'renders', {}, {}
    renders.mkdir()
    for path in inputs:
        stem = re.sub(r'[^A-Za-z0-9.-]+', '_', str(path))
        for ext in ('png', 'pdf'):
            proc = run([render, ROOT / path, '-o', renders / f'{stem}.{ext}'], logs / f'{stem}.{ext}.log')
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
            if scale != 1:
                run([render, ROOT / path, '-o', renders / f'{stem}.png', '--scale', f'{scale:g}', '--force'], logs / f'{stem}.png-scaled.log')
            run([imagediff, '--rasterize-pdf', renders / f'{stem}.pdf', renders / f'{stem}.pdf.png', f'{scale:g}'], logs / f'{stem}.rasterize.log')
            pdf = json.loads(run([imagediff, renders / f'{stem}.pdf.png', preview, out / f'{stem}.pdf-diff.png'], logs / f'{stem}.pdf-diff.log').stdout)
            png = json.loads(run([imagediff, renders / f'{stem}.png', preview, out / f'{stem}.png-diff.png'], logs / f'{stem}.png-diff.log').stdout)
            comparisons[str(path)] = {'pdfRaster': pdf, 'png': png}
            assert pdf['sameSize'] and png['sameSize'], f'{path}: render size differs from its preview'
            assert pdf['differing'] == 0, f'{path}: the PDF differs from the shipped preview: {pdf}'
            # The PNG is drawn straight into a Generic RGB bitmap like the app's export, the previews through a PDF into
            # DeviceRGB: colored edges and text antialias slightly differently. The exact PDF comparison above is the
            # geometry check; this one bounds the raster path (a moved label or a cropped page fails it).
            assert png['over64'] <= png['pixels'] // 1000 and png['meanChannelDiff'] < 2, f'{path}: the PNG differs from the shipped preview beyond color space: {png}'
    report['rendered'] = [str(p) for p in inputs]
    report['historicalReaderMessages'] = {p: m for p, m in warnings.items() if m}
    report['previewComparisons'] = comparisons
    # Examples/Tools/pre-credit holds the generator's pinned inputs, which have no previews.
    previewed = [str(p) for p in examples if 'pre-credit' not in p.parts]
    assert sorted(comparisons) == previewed, f'Expected a preview for every example: {sorted(set(previewed) - set(comparisons))}'

    # 2. Resolution options: pixel size = round(points * dpi / 72).
    sample = ROOT / 'Examples/Templates/function-plot.graphink'
    for option, value, pixels in (('--scale', '2', '2160 × 1600'), ('--dpi', '300', '4500 × 3333'), ('--dpi', '150', '2250 × 1667')):
        proc = run([render, sample, '-o', renders / f'resolution{option}{value}.png', option, value], logs / f'resolution{option}{value}.log')
        assert pixels in proc.stdout, f'{option} {value}: expected {pixels}: {proc.stdout}'

    # 3. Create the skill's examples; check, reopen and render each.
    created = out / 'created'
    created.mkdir()
    report['created'] = {}
    specs = sorted(SKILL_EXAMPLES.glob('*.json'))
    assert len(specs) >= 4, 'Expected the skill examples'
    for spec in specs:
        doc = created / (spec.stem + '.graphink')
        proc = run([create, spec, '-o', doc], logs / f'create-{spec.stem}.log')
        assert 'reopened with the production reader' in proc.stdout and not messages(proc), f'{spec.name}: {proc.stdout} {messages(proc)}'
        run([sys.executable, ROOT / 'docs/format/check-opc.py', doc], logs / f'opc-{spec.stem}.log')
        with zipfile.ZipFile(doc) as package:
            (created / (spec.stem + '-contents.xml')).write_bytes(package.read('contents.xml'))
            assert package.read('preview.pdf').startswith(b'%PDF-') if 'preview.pdf' in package.namelist() else True
        run(['xmllint', '--noout', '--relaxng', ROOT / 'GraphSketcher/Model/XML/GraphSketcher.rng', created / (spec.stem + '-contents.xml')], logs / f'schema-{spec.stem}.log')
        run([render, doc, '-o', created / (spec.stem + '.png')], logs / f'render-{spec.stem}.log')
        report['created'][spec.name] = {'document': str(doc), 'sha256': digest(doc), 'summary': proc.stdout.strip()}

    # 4. Refusals: each must exit 1 or 2 with one clear line and write nothing.
    bad = out / 'bad'
    bad.mkdir()
    cases = {
        'unknown-key': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [{'type': 'line', 'points': [[0, 0], [1, 1]], 'colour': 'red'}]}, 'objects[0]: unknown key "colour"'),
        'bad-point': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [{'type': 'line', 'points': [[0, 0], [1]]}]}, 'objects[0].points[1] must be a point'),
        'bad-formula': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [{'type': 'function', 'f': 'sinx', 'from': 0, 'to': 1}]}, 'unknown name "sinx"'),
        'bad-range': ({'graphink': 1, 'x': {'min': 2, 'max': 1}, 'y': {'min': 0, 'max': 1}}, 'max > min'),
        'bad-version': ({'graphink': 2, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}}, 'must be 1'),
        'bad-color': ({'graphink': 1, 'x': {'min': 0, 'max': 1}, 'y': {'min': 0, 'max': 1}, 'objects': [{'type': 'point', 'at': [0, 0], 'color': 'mauve'}]}, 'objects[0].color must be #RRGGBB'),
    }
    for name, (spec, expected) in cases.items():
        path = bad / f'{name}.json'
        path.write_text(json.dumps(spec))
        proc = run([create, path, '-o', bad / f'{name}.graphink'], logs / f'refuse-{name}.log', expect=1)
        assert any(expected in line for line in messages(proc)) and len(messages(proc)) == 1, f'{name}: {messages(proc)}'
        assert not (bad / f'{name}.graphink').exists(), f'{name}: wrote a document'
    first = created / (specs[0].stem + '.graphink')
    run([create, specs[0], '-o', first], logs / 'refuse-overwrite.log', expect=1)
    # The reader detects the container from the bytes, so a document named .pdf still opens: it must not be replaced.
    disguised = bad / 'document.pdf'
    disguised.write_bytes(first.read_bytes())
    run([render, disguised, '-o', disguised, '--force'], logs / 'refuse-input.log', expect=1)
    assert disguised.read_bytes() == first.read_bytes(), 'graphink-render wrote over its input'

    run([render, first, '-o', out / 'x.svg'], logs / 'refuse-type.log', expect=2)
    run([render, first, '-o', out / 'x.png', '--dpi', '5000'], logs / 'refuse-dpi.log', expect=2)
    run([render, out / 'missing.graphink', '-o', out / 'x.png'], logs / 'refuse-missing.log', expect=1)
    assert not (out / 'x.png').exists() and not (out / 'x.svg').exists()
    assert digest(first) == report['created'][specs[0].name]['sha256'], 'A refused overwrite changed the document'

    after = {str(p): digest(ROOT / p) for p in inputs}
    report['inputsUnchanged'] = after == before
    assert report['inputsUnchanged'], 'An input document changed'
    report['passed'] = True
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    worst = max(c['png']['meanChannelDiff'] for c in comparisons.values())
    print(f'PASS rendered {len(inputs)} documents read-only ({len(comparisons)} examples match their previews; '
          f'PNG mean channel difference at most {worst:.3f}), created {len(specs)} specs; evidence: {out}')


if __name__ == '__main__':
    try:
        main()
    except AssertionError as exc:
        print('FAIL: ' + str(exc), file=sys.stderr)
        sys.exit(1)
