#!/usr/bin/env python3
"""Generate the offscreen native OPC first-launch example into a NEW evidence directory."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import zipfile
sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
STEM = 'welcome-to-graphink'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, log, **kwargs):
    proc = subprocess.run([str(v) for v in command], capture_output=True, text=True, **kwargs)
    log.write_text(proc.stdout + proc.stderr)
    assert proc.returncode == 0, f'Command exited {proc.returncode}; inspect {log}'
    return proc


def close(a, b, path='snapshot'):
    if isinstance(a, (float, int)) and not isinstance(a, bool) and isinstance(b, (float, int)):
        assert math.isclose(a, b, abs_tol=0.0001), (path, a, b)
    elif isinstance(a, dict):
        assert a.keys() == b.keys(), (path, a.keys() ^ b.keys())
        for key in a:
            close(a[key], b[key], path + '/' + key)
    elif isinstance(a, list):
        assert len(a) == len(b), (path, len(a), len(b))
        for i, (x, y) in enumerate(zip(a, b)):
            close(x, y, f'{path}[{i}]')
    else:
        assert a == b, (path, a, b)


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog='Example: python3 Examples/InitialFTUX/generate.py --products /private/tmp/GraphSketcher-build.XXXX/Debug/Products/Debug --output /private/tmp/new-ftux-run. No UI, installs, source edits or overwrites. Exit 0: checks passed; 1: failure (see output/error.log); 2: invalid arguments.')
    parser.add_argument('--products', required=True, type=Path, help='Debug or Release products built from this worktree')
    parser.add_argument('--output', required=True, type=Path, help='New directory; existing paths are refused, even if empty')
    args = parser.parse_args()
    products, out = args.products.resolve(), args.output.absolute()
    if out.exists():
        parser.error('--output already exists; choose a new evidence directory')
    if not (products / 'GraphSketcherModel.framework').is_dir():
        parser.error('--products must contain GraphSketcherModel.framework')
    out.mkdir(parents=True)
    receipt = {'products': str(products), 'evidence': str(out), 'command': [sys.executable, *sys.argv], 'passed': False,
               'scope': 'Production OPC writer/reader, real same-model preview, creation defaults, label clearances, offscreen semantic/edit/undo checks. No interactive acceptance.',
               'limits': ['PDF CreationDate/ModDate reflect generation time; PDF and package bytes are not stable across runs.',
                          'No interactive UI, Finder/Quick Look, accessibility or human acceptance.']}
    originals = {}
    try:
        assert __debug__, 'Assertions must be enabled; do not use Python -O'
        receipt['sourceHEAD'] = run(['git', 'rev-parse', 'HEAD'], out / 'source-head.log', cwd=ROOT).stdout.strip()
        receipt['sourceDirty'] = run(['git', 'status', '--porcelain', '--', 'GraphSketcher/Model', 'GraphSketcher/OmniStyle', 'Examples/InitialFTUX'], out / 'source-status.log', cwd=ROOT).stdout.strip()
        assert not receipt['sourceDirty'], 'Model or generator sources have uncommitted changes; commit first'
        checker = ROOT / 'docs/format/check-opc.py'
        receipt['checker'] = {'path': str(checker), 'sha256': digest(checker)}
        receipt['frameworkSHA256'] = {p.name: digest(p / p.stem) for p in products.glob('*.framework')}
        receipt['generatorSHA256'] = {p.name: digest(p) for p in [HERE / 'GenerateInitialExample.m', HERE / 'generate.py', HERE / 'layout.json']}
        report = (ROOT / 'Checks/historical-samples.sha256').read_text()
        originals = {p: h for h, p in re.findall(r'^([a-f0-9]{64})  (GraphSketcher/.+\.ograph)$', report, re.M)}
        assert len(originals) == 35, 'Expected 35 original samples in Checks/historical-samples.sha256'
        receipt['originalsBefore'] = {p: digest(ROOT / p) for p in originals}
        assert receipt['originalsBefore'] == originals, 'Original corpus changed before generation'
        artifacts = out / 'artifacts'
        artifacts.mkdir()
        bundle = out / 'InitialExample.tool' / 'Contents'
        (bundle / 'MacOS').mkdir(parents=True)
        (bundle / 'Frameworks').symlink_to(products, target_is_directory=True)
        info = plistlib.loads((ROOT / 'GraphSketcher/App/Info.plist').read_bytes())
        info.update(CFBundleIdentifier='com.graphink.initialexample.offscreen', CFBundleExecutable='InitialExample', CFBundleVersion='11.0', CFBundleShortVersionString='1.0', NSHumanReadableCopyright='Copyright 2026 Graphink examples contributors', OFControllerClass='ExampleController', NSPrincipalClass='NSApplication', LSMinimumSystemVersion='12.0')
        # The generator never opens documents: declaring types or UTIs would register it with Launch Services
        # as a handler for .graphink/.ograph (Checks/check-fixture-bundles.py lists these keys).
        for key in ('NSMainNibFile', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations', 'CFBundleURLTypes', 'NSServices'):
            info.pop(key, None)
        (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
        exe = bundle / 'MacOS/InitialExample'
        command = ['xcrun', 'clang', '-fno-objc-arc', '-fblocks', '-Wall', '-Werror', '-Wno-error=deprecated-declarations', '-DOMNI_BUILDING_FOR_MAC=1', '-F', products]
        for fw in ['Cocoa', 'QuartzCore', 'GraphSketcherModel', 'OmniBase', 'OmniFoundation', 'OmniAppKit', 'OmniQuartz', 'OmniUnzip']:
            command += ['-framework', fw]
        command += ['-Wl,-rpath,' + str(products), '-o', exe, HERE / 'GenerateInitialExample.m']
        receipt['compileCommand'] = list(map(str, command))
        run(command, out / 'compile.log')
        proc = run([exe, HERE / 'layout.json', artifacts], out / 'native.log', timeout=60)
        assert 'COMPLETE examples=1 failed=0' in proc.stdout and proc.stdout.count('PASS example=') == 1, 'Missing completion markers; inspect native.log'
        assert not re.search(r'FATAL ASSERTION|Assertion Failed|ASSERT failed|^FAIL ', proc.stdout + proc.stderr, re.M), 'Native assertions found; inspect native.log'
        before, reopen, roundtrip = (json.loads((artifacts / f'{STEM}-{n}.json').read_text()) for n in ('before', 'reopen', 'roundtrip'))
        # Identifiers are assigned on first save, so compare objects by content, and reopen/roundtrip exactly.
        kinds = lambda s: sorted(o['kind'] for o in s['objects'].values())
        assert kinds(before) == kinds(reopen), 'Object kinds/counts changed on reopen'
        close(reopen, roundtrip)
        for key in ('defaults', 'canvas', 'whitespace', 'autoWhitespace', 'background', 'fillCount'):
            close(before[key], reopen[key], key)
        layout = json.loads((HERE / 'layout.json').read_text())
        texts = sorted(o['text'] for o in layout['objects'] if o['kind'] == 'label') + sorted(o['number'] for o in layout['objects'] if o['kind'] == 'target')
        assert sorted(o['text'] for o in reopen['objects'].values() if o['kind'] == 'label') == sorted(texts), 'Reopened labels differ from layout text'
        path = artifacts / (STEM + '.graphink')
        with zipfile.ZipFile(path) as package:
            assert package.read('preview.pdf') == (artifacts / (STEM + '.pdf')).read_bytes(), 'Packaged preview differs from rendered PDF'
            (out / 'contents.xml').write_bytes(package.read('contents.xml'))
        receipt['checkerCommand'] = [sys.executable, str(checker), str(path)]
        run(receipt['checkerCommand'], out / 'opc.log')
        receipt['schemaCommand'] = ['xmllint', '--noout', '--relaxng', str(ROOT / 'GraphSketcher/Model/XML/GraphSketcher.rng'), str(out / 'contents.xml')]
        run(receipt['schemaCommand'], out / 'schema.log')
        receipt['artifactSHA256'] = {p.name: digest(p) for p in sorted(artifacts.iterdir())}
        receipt['passed'] = True
    except Exception as exc:
        (out / 'error.log').write_text(str(exc) + '\n')
        raise
    finally:
        receipt['originalsAfter'] = {p: digest(ROOT / p) for p in originals}
        receipt['originalsUnchanged'] = bool(originals) and receipt['originalsAfter'] == originals
        if not receipt['originalsUnchanged']:
            receipt['passed'] = False
        (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    assert receipt['originalsUnchanged'], 'Original sample hashes changed; no restore attempted; inspect ' + str(out / 'receipt.json')
    print('PASS initial example generation; evidence: ' + str(out))


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, subprocess.SubprocessError, zipfile.BadZipFile, KeyError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        sys.exit(1)
