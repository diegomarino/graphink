#!/usr/bin/env python3
"""Compile an offscreen model probe and retain disposable evidence; stdlib only."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
NS = '{http://www.omnigroup.com/namespace/OmniGraphSketcher/v1}'


def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, **kwargs)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog='Example: python3 docs/format/check-format.py --products /absolute/Products/Debug --source-sha FULL_SHA. Exit 0: bounded checks passed; 1: check failure; 2: invalid inputs. No UI or installation. Evidence is retained in a new temporary directory.')
    parser.add_argument('--products', required=True, type=Path, help='Existing model/Omni frameworks from an explicitly authorized build')
    parser.add_argument('--input', action='append', default=[], type=Path, help='Additional original XML/ZIP document to check without modifying it; repeatable')
    parser.add_argument('--source-sha', required=True, help='Exact build source SHA (operator attestation, not a rebuild proof)')
    args = parser.parse_args()
    products = args.products.resolve()
    source = run(['git', 'rev-parse', args.source_sha], cwd=ROOT, text=True).stdout.strip()
    paths = ['GraphSketcher/Model', 'GraphSketcher/OmniStyle', 'GraphSketcher/App/Info.plist']
    run(['git', 'diff', '--exit-code', source, '--', *paths], cwd=ROOT)
    for framework in ['GraphSketcherModel', 'OmniBase', 'OmniFoundation', 'OmniAppKit', 'OmniQuartz', 'OmniUnzip']:
        if not (products / (framework + '.framework') / framework).is_file():
            parser.error(f'Missing {framework}.framework in --products; supply the authorized complete build')
    samples = [ROOT / p for p in run(['git', 'ls-files', '*.ograph'], cwd=ROOT, text=True).stdout.splitlines()]
    assert len(samples) == 35, 'Review changed original corpus inventory'
    before = {str(p.relative_to(ROOT)): digest(p) for p in samples}
    out = Path(tempfile.mkdtemp(prefix='graphink-format-', dir='/private/tmp'))
    print(f'Evidence: {out}', flush=True)
    receipt = {'source': source, 'documentationHEAD': run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).stdout.strip(), 'products': str(products), 'frameworkSHA256': {p.name: digest(p / p.stem) for p in products.glob('*.framework')}, 'originalsBefore': before, 'cases': {}, 'extraInputsBefore': {str(p.resolve()): digest(p.resolve()) for p in args.input}}
    try:
        bundle = out / 'FormatProbe.app' / 'Contents'
        (bundle / 'MacOS').mkdir(parents=True)
        info = plistlib.loads((ROOT / 'GraphSketcher/App/Info.plist').read_bytes())
        info.update(LSMinimumSystemVersion='12.0', NSHumanReadableCopyright='Copyright 2026 The Omni Group', CFBundleIdentifier='com.graphsketcher.format.offscreen', CFBundleExecutable='FormatProbe', CFBundleVersion='11.0', CFBundleShortVersionString='1.0', OFControllerClass='FormatController', NSPrincipalClass='NSApplication')
        # Fixtures never declare document types, UTIs, URL schemes or services: running one registers it
        # with Launch Services, where it would claim .graphink/.ograph (Checks/check-fixture-bundles.py).
        for key in ('NSMainNibFile', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations', 'CFBundleURLTypes', 'NSServices'):
            info.pop(key, None)
        (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
        (bundle / 'Frameworks').symlink_to(products, target_is_directory=True)
        exe = bundle / 'MacOS/FormatProbe'
        command = ['xcrun', 'clang', '-fno-objc-arc', '-DOMNI_BUILDING_FOR_MAC=1', '-F', products]
        for fw in ['Cocoa', 'QuartzCore', 'GraphSketcherModel', 'OmniBase', 'OmniFoundation', 'OmniAppKit', 'OmniQuartz', 'OmniUnzip']:
            command += ['-framework', fw]
        command += ['-Wl,-rpath,' + str(products), '-o', exe, ROOT / 'docs/format/FormatChecks.m']
        result = subprocess.run([str(a) for a in command], capture_output=True, text=True)
        (out / 'compile.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0, 'Compile failed; inspect compile.log'

        def probe(name, path):
            stem = out / name
            proc = subprocess.run([str(exe), str(path), str(stem)], capture_output=True, text=True, timeout=30)
            (out / (name + '.log')).write_text(proc.stdout + proc.stderr)
            result = {'exit': proc.returncode, 'stdout': proc.stdout.strip(), 'assertion': 'ASSERT failed' in proc.stderr or 'FATAL ASSERTION' in proc.stderr or 'Assertion Failed' in proc.stderr}
            receipt['cases'][name] = result
            return result

        original = (ROOT / 'docs/format/minimal.graphink').read_text()
        good = probe('minimal', ROOT / 'docs/format/minimal.graphink')
        assert good['exit'] == 0 and not good['assertion'] and 'PASS vertices=2 lines=1 canvas=520x420 x=0:10 y=0:10' in good['stdout']
        assert (out / 'minimal.xml').read_bytes().startswith(b'<?xml')
        with zipfile.ZipFile(out / 'minimal.zip') as archive:
            assert archive.namelist() == ['contents.xml', 'preview.pdf']
            assert archive.read('contents.xml') == (out / 'minimal.xml').read_bytes()
            assert archive.read('preview.pdf').startswith(b'%PDF-')
        # A ZIP without a preview is readable, although native nil-preview writing emits XML.
        no_preview = out / 'no-preview.graphink'
        with zipfile.ZipFile(no_preview, 'w') as archive:
            archive.writestr('contents.xml', original)
        assert probe('zip-no-preview', no_preview)['exit'] == 0
        cases = {
            'unknown': original.replace('<graph>', '<graph mystery="keep-me"><future required="true"/>').replace('<edge-padding', '<creation-defaults version="99" font-name="FutureFace"/><ext:hint xmlns:ext="urn:format-probe"/><edge-padding'),
            'future-v2': original.replace('OmniGraphSketcher/v1', 'OmniGraphSketcher/v2'),
            'foreign-v1': original.replace('http://www.omnigroup.com/namespace/OmniGraphSketcher/v1', 'urn:unrelated/v1'),
            'no-namespace': original.replace(' xmlns="http://www.omnigroup.com/namespace/OmniGraphSketcher/v1"', ''),
            'missing-reference': original.replace('ids="e3 e4"', 'ids="e3 missing"'),
            'duplicate-id': original.replace('id="e4"', 'id="e3"'),
            'unknown-line-class': original.replace('class="connect"', 'class="future"'),
            'missing-graph': original.replace('<graph>', '<future>').replace('</graph>', '</future>'),
            'fallbacks': original.replace(' w="520" h="420" auto-whitespace="false"', '').replace('      <whitespace top="20" right="20" bottom="40" left="40"/>', '').replace('      <edge-padding top="6" right="6" bottom="6" left="6"/>', ''),
            'malformed': '<document><graph>',
        }
        for name, content in cases.items():
            path = out / (name + '.graphink')
            path.write_text(content)
            probe(name, path)
        assert receipt['cases']['unknown']['exit'] == 0
        saved = (out / 'unknown.xml').read_text()
        assert all(token not in saved for token in ['mystery', 'future', 'creation-defaults', 'ext:hint', 'FutureFace'])
        saved = ET.parse(out / 'minimal.xml').getroot()
        graph = saved.find(NS + 'graph')
        vertex = graph.find(NS + 'vertex')
        assert vertex.get('width') == '2' and vertex.find(NS + 'color') is None
        assert [(v.get('x'), v.get('y')) for v in graph.findall(NS + 'vertex')] == [('2', '2'), ('8', '8')]
        label = next(e for e in graph.findall(NS + 'label') if e.get('id') == 'e6')
        assert ''.join(e.text or '' for e in label.iter(NS + 'lit')) == 'Original format example'
        canvas = graph.find(NS + 'canvas')
        assert canvas.find(NS + 'color') is None and canvas.find(NS + 'shadow').get('strength') == '0'
        assert receipt['cases']['malformed']['exit'] != 0
        fallback = ET.parse(out / 'fallbacks.xml').getroot().find(NS + 'graph/' + NS + 'canvas')
        assert fallback.get('w') == '520' and fallback.get('h') == '420' and fallback.get('auto-whitespace') == 'true'
        assert set(fallback.find(NS + 'whitespace').attrib.values()) == {'2'}
        for index, path in enumerate(args.input):
            path = path.resolve()
            if zipfile.is_zipfile(path):
                with zipfile.ZipFile(path) as archive:
                    root = ET.fromstring(archive.read('contents.xml'))
            else:
                root = ET.parse(path).getroot()
            assert root.tag == NS + 'document' and root.find(NS + 'graph') is not None, 'Use the current document namespace and graph root'
            ids = [e.get('id') for e in root.iter() if e.get('id') is not None]
            assert len(ids) == len(set(ids)), 'Duplicate identifiers are unsafe'
            for element in root.iter():
                for key in ['idref', 'owner', 'arrow-parent', 'v1', 'v2', 'label', 'ids', 'elements']:
                    assert all(ref in ids for ref in element.get(key, '').split()), f'Unresolved {key} reference'
            result = probe(f'input-{index + 1:02}', path)
            assert result['exit'] == 0 and not result['assertion'], 'Additional input failed native checks; inspect its log'
        for index, path in enumerate(samples):
            probe(f'legacy-{index + 1:02}', path)
            receipt['cases'][f'legacy-{index + 1:02}']['input'] = str(path.relative_to(ROOT))
            if path.name == 'Very small graph.ograph':
                old = ET.parse(out / f'legacy-{index + 1:02}.xml').getroot()
                preserved = next(v for v in old.findall('.//' + NS + 'vertex') if v.get('id') == 'e2092')
                assert (preserved.get('x'), preserved.get('y'), preserved.get('width'), preserved.get('shape')) == ('2', '7', '4', 'circle')
            assert receipt['cases'][f'legacy-{index + 1:02}']['exit'] == 0 and not receipt['cases'][f'legacy-{index + 1:02}']['assertion'], 'Legacy read/roundtrip failed; inspect log'
    finally:
        receipt['originalsAfter'] = {str(p.relative_to(ROOT)): digest(p) for p in samples}
        receipt['extraInputsAfter'] = {str(p.resolve()): digest(p.resolve()) for p in args.input}
        receipt['originalsUnchanged'] = before == receipt['originalsAfter']
        (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    assert receipt['extraInputsBefore'] == receipt['extraInputsAfter'], 'Additional input hashes changed'
    assert receipt['originalsUnchanged'], 'Original hashes changed; no automatic restore attempted'
    print(json.dumps({'originalsUnchanged': True, 'cases': receipt['cases']}, indent=2))
    print('PASS bounded checks; inspect receipt for intentionally invalid/future case outcomes')


if __name__ == '__main__':
    main()
