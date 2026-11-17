#!/usr/bin/env python3
"""Run real-model width regressions with a unique fixture preference domain; no app launch."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import uuid

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--products', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path, help='New evidence directory; existing paths refused.')
args = parser.parse_args()
products, output = args.products.resolve(), args.output.resolve()
if output.exists():
    parser.error('Output exists; choose a new evidence directory.')
if not (products/'GraphSketcherModel.framework/GraphSketcherModel').exists():
    parser.error('Model framework missing from --products.')
bundle = output/'WidthDefaultsChecks.app/Contents'
(bundle/'MacOS').mkdir(parents=True)
info = plistlib.loads((root/'GraphSketcher/App/Info.plist').read_bytes())
info.update(CFBundleExecutable='checks', CFBundleIdentifier='com.graphsketcher.widthchecks.'+uuid.uuid4().hex,
            CFBundleVersion='1', CFBundleShortVersionString='1.0', OFControllerClass='OFController',
            LSMinimumSystemVersion='12.0', NSHumanReadableCopyright='Copyright 2026 width regression fixture')
# Fixtures never declare document types, UTIs, URL schemes or services: running one registers it
# with Launch Services, where it would claim .graphink/.ograph (Checks/check-fixture-bundles.py).
for key in ('NSMainNibFile', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations', 'CFBundleURLTypes', 'NSServices'):
    info.pop(key, None)
(bundle/'Info.plist').write_bytes(plistlib.dumps(info))
command = ['xcrun', 'clang', '-fno-objc-arc', '-fblocks', '-DOMNI_BUILDING_FOR_MAC=1',
           '-include', 'Cocoa/Cocoa.h', '-include', str(root/'GraphSketcher/Model/GraphSketcherModel_Prefix.h'),
           '-F', str(products), '-framework', 'Cocoa', '-framework', 'GraphSketcherModel',
           '-framework', 'OmniBase', '-framework', 'OmniFoundation', '-framework', 'OmniAppKit',
           '-Wl,-rpath,'+str(products), str(root/'Checks/WidthDefaultsChecks.m'), '-o', str(bundle/'MacOS/checks')]
(output/'compile-command.json').write_text(json.dumps(command, indent=2)+'\n')
result = subprocess.run(command, capture_output=True)
(output/'compile.log').write_bytes(result.stdout+result.stderr)
if result.returncode:
    raise SystemExit('Compilation failed; inspect '+str(output/'compile.log'))
result = subprocess.run([str(bundle/'MacOS/checks')], capture_output=True)
log = result.stdout+result.stderr
(output/'checks.log').write_bytes(log)
print(log.decode(errors='replace'))
passed = result.returncode == 0 and b'PASS width defaults:' in log and not any(m in log for m in [b'ASSERT failed', b'PRECONDITION failed', b'Exception raised:', b'FAIL '])
(output/'verification.json').write_text(json.dumps({'passed': passed, 'nativeLaunch': False, 'products': str(products),
    'modelSHA256': hashlib.sha256((products/'GraphSketcherModel.framework/GraphSketcherModel').read_bytes()).hexdigest(),
    'sources': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [root/'GraphSketcher/Model/RSGraphEditor.m', root/'Checks/WidthDefaultsChecks.m']}}, indent=2)+'\n')
raise SystemExit(0 if passed else 1)
