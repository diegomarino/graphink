#!/usr/bin/env python3
"""Run focused headless model typography/default/serialization checks."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import uuid

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__, epilog='Example: UI/check-style-defaults.py --products build/Debug/Products/Debug --output /private/tmp/gs-style-checks')
parser.add_argument('--products', required=True, type=Path, help='Existing reviewed Debug Model + Omni framework directory; no build is performed.')
parser.add_argument('--output', required=True, type=Path, help='New evidence directory; existing paths are refused.')
args = parser.parse_args()
products, output = args.products.resolve(), args.output.resolve()
if output.exists():
    parser.error('Output already exists; choose a new path to preserve evidence.')
if not (products / 'GraphSketcherModel.framework/GraphSketcherModel').exists():
    parser.error('Model framework missing; pass the reviewed Products/Debug directory.')
info = plistlib.loads((ROOT / 'GraphSketcher/App/Info.plist').read_bytes())
output.mkdir(parents=True)
(output / 'outputs').mkdir()
# Compile the current model category into the harness; all graph/XML code stays
# in the supplied built framework. The harness verifies its selected method IMP.
command = ['xcrun', 'clang', '-fno-objc-arc', '-fblocks', '-DOMNI_BUILDING_FOR_MAC=1',
           '-include', 'Cocoa/Cocoa.h', '-include', str(ROOT / 'GraphSketcher/Model/GraphSketcherModel_Prefix.h'),
           '-F', str(products), '-framework', 'Cocoa', '-framework', 'QuartzCore',
           '-framework', 'GraphSketcherModel', '-framework', 'OmniBase',
           '-framework', 'OmniFoundation', '-framework', 'OmniUnzip',
           '-framework', 'OmniQuartz', '-framework', 'OmniAppKit',
           '-Wl,-rpath,'+str(products), str(ROOT / 'UI/StyleDefaultsChecks.m'),
           str(ROOT / 'GraphSketcher/Model/OFPreference-RSExtensions.m'),
           '-o', str(output / 'checks')]
(output / 'compile-command.json').write_text(json.dumps(command, indent=2)+'\n')
compiled = subprocess.run(command, capture_output=True)
(output / 'compile.log').write_bytes(compiled.stdout+compiled.stderr)
if compiled.returncode:
    raise SystemExit(f'Compilation failed; inspect {output / "compile.log"}')
checks = []
for stage, modes in [('baseline', ['baseline']), ('custom', ['custom-seed', 'custom-read']),
                     ('common', ['common-seed', 'common-read']), ('defaults', ['defaults'])]:
    bundle = output / stage / 'StyleDefaultsChecks.app/Contents'
    (bundle / 'MacOS').mkdir(parents=True)
    (bundle / 'Frameworks').symlink_to(products)
    fixture = dict(info)
    fixture.update(CFBundleExecutable='checks', CFBundleIdentifier='com.graphsketcher.stylechecks.'+uuid.uuid4().hex,
                   CFBundleVersion='1', CFBundleShortVersionString='1.0', NSHumanReadableCopyright='GraphSketcher typography test fixture (2026)',
                   LSMinimumSystemVersion='12.0', OFControllerClass='OFController')
    # Fixtures never declare document types, UTIs, URL schemes or services: running one registers it
    # with Launch Services, where it would claim .graphink/.ograph (Checks/check-fixture-bundles.py).
    for key in ('NSMainNibFile', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations', 'CFBundleURLTypes', 'NSServices'):
        fixture.pop(key, None)
    # Copy nested dictionaries before constructing the historical empty-default case.
    fixture = plistlib.loads(plistlib.dumps(fixture))
    if stage == 'baseline':
        defaults = fixture['OFRegistrations']['NSUserDefaults']['defaultsDictionary']
        for key in defaults:
            if key.startswith('Default') and key.endswith('Font'):
                defaults[key] = {}
    (bundle / 'Info.plist').write_bytes(plistlib.dumps(fixture))
    (bundle / 'MacOS/checks').write_bytes((output / 'checks').read_bytes())
    (bundle / 'MacOS/checks').chmod(0o755)
    for mode in modes:
        result = subprocess.run([str(bundle / 'MacOS/checks'), mode, str(output / 'outputs')], capture_output=True)
        log = result.stdout+result.stderr
        (output / (mode+'.log')).write_bytes(log)
        # Omni assertions can log and still exit zero; reject them explicitly.
        passed = result.returncode == 0 and log.count(('PASS '+mode+'\n').encode()) == 1 and not any(
            marker in log for marker in (b'ASSERT failed', b'PRECONDITION failed', b'POSTCONDITION failed', b'Assertion Failed', b'Exception raised:', b'FAIL '))
        checks.append({'mode':mode, 'exit':result.returncode, 'passed':passed})
        print(log.decode(errors='replace'), end='')
        if not passed:
            raise SystemExit(f'FAIL {mode}; evidence retained at {output}')
record = {'checks':checks, 'frameworks':{p.name:hashlib.sha256((p/p.stem).read_bytes()).hexdigest()
          for p in products.glob('*.framework')}, 'sources':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
          for p in [ROOT/'GraphSketcher/App/Info.plist', ROOT/'GraphSketcher/Model/OFPreference-RSExtensions.m', ROOT/'UI/StyleDefaultsChecks.m']}}
(output/'verification.json').write_text(json.dumps(record,indent=2)+'\n')
print('PASS focused typography checks; no app nib, window, event loop or production preference domain used')
