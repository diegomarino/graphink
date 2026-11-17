#!/usr/bin/env python3
"""Legacy roundtrip regressions: arrow parents, hidden axis titles and nonfinite snaps through XML, legacy ZIP and OPC.

Compiles Checks/LegacyRoundtripChecks.m against independently built Debug products of this
checkout, in an isolated bundle that keeps the app's real defaults registration (like
check-documents.sh). The seven roundtrip samples are copied into the new evidence directory and
only those copies are opened; original hashes are verified unchanged. No UI is launched.
"""
import argparse
import hashlib
import plistlib
import shutil
import subprocess
from pathlib import Path

SAMPLES = ['GraphSketcher/Model/XML/example.ograph',
           'GraphSketcher/iPad/MoreSamples/changes-in-quantity.ograph',
           'GraphSketcher/iPad/MoreSamples/climate.ograph',
           'GraphSketcher/iPad/MoreSamples/jobs-obama.ograph',
           'GraphSketcher/iPad/MoreSamples/playfair-original.ograph',
           'GraphSketcher/iPad/Resources/English.lproj/Samples/Piecewise Function.ograph',
           'GraphSketcher/iPad/Resources/English.lproj/Samples/Playfair Extension.ograph']
FRAMEWORKS = ['GraphSketcherModel', 'OmniBase', 'OmniFoundation', 'OmniUnzip', 'OmniQuartz', 'OmniAppKit']

parser = argparse.ArgumentParser(description=__doc__, epilog='Example: python3 Checks/check-legacy-roundtrips.py --products /private/tmp/GraphSketcher-build.X/Debug/Products/Debug --output /private/tmp/gs-legacy-roundtrips-new')
parser.add_argument('--products', required=True, type=Path, help='Absolute Debug products directory built from this checkout')
parser.add_argument('--output', required=True, type=Path, help='New evidence directory; existing paths refused')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
products = args.products.resolve()
if not args.products.is_absolute() or any(not (products / f'{name}.framework').exists() for name in FRAMEWORKS):
    parser.error('--products must be an absolute Debug products directory containing the model and Omni frameworks')
if args.output.exists():
    parser.error('--output already exists')
args.output.mkdir(parents=True)

def digests():
    return {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in SAMPLES}
before = digests()
copies = args.output / 'copies'
copies.mkdir()
for path in SAMPLES:
    shutil.copyfile(root / path, copies / Path(path).name)

contents = args.output / 'LegacyRoundtripChecks.app/Contents'
(contents / 'MacOS').mkdir(parents=True)
info = plistlib.loads((root / 'GraphSketcher/App/Info.plist').read_bytes())
# Fixtures never declare document types, UTIs, URL schemes or services: running one registers it
# with Launch Services, where it would claim .graphink/.ograph (Checks/check-fixture-bundles.py).
for key in ('NSMainNibFile', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations', 'CFBundleURLTypes', 'NSServices'):
    info.pop(key, None)
info.update(CFBundleExecutable='checks', CFBundleIdentifier='com.graphsketcher.migration.legacyroundtrips',
            CFBundleVersion='1', CFBundleShortVersionString='1.0', LSMinimumSystemVersion='12.0',
            NSPrincipalClass='NSApplication', OFControllerClass='CheckController',
            NSHumanReadableCopyright='Copyright 2026 The Omni Group')
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
(contents / 'Frameworks').symlink_to(products)
command = ['xcrun', 'clang', '-fno-objc-arc', '-Wall', '-Werror', '-Wno-deprecated-declarations', '-DOMNI_BUILDING_FOR_MAC=1',
           '-F', str(products), '-framework', 'Cocoa'] + [arg for name in FRAMEWORKS for arg in ('-framework', name)] + [
           f'-Wl,-rpath,{products}', '-o', str(contents / 'MacOS/checks'), str(root / 'Checks/LegacyRoundtripChecks.m')]
subprocess.run(command, check=True)
evidence = args.output / 'outputs'
result = subprocess.run([str(contents / 'MacOS/checks'), str(evidence)] + [str(copies / Path(path).name) for path in SAMPLES], capture_output=True)
log = result.stdout + result.stderr
(args.output / 'checks.log').write_bytes(log)
print(log.decode())
assert digests() == before, 'Original sample hashes changed'
print('PASS: original sample hashes unchanged')
assert result.returncode == 0, f'checks exited {result.returncode}'
for marker in (b'FAIL', b'ASSERT', b'PRECONDITION', b'Assertion Failed'):
    assert marker not in log, marker
xml_outputs = sorted(p for p in evidence.glob('*-xml-*.ograph'))
assert len(xml_outputs) == 2 * (3 + len(SAMPLES)), 'Missing generated XML outputs'
for saved in xml_outputs:
    subprocess.run(['xmllint', '--nonet', '--noout', '--relaxng', str(root / 'GraphSketcher/Model/XML/GraphSketcher.rng'), str(saved)], check=True, capture_output=True)
print(f'PASS: {len(xml_outputs)} generated XML outputs validate against the current schema')
lines = result.stdout.decode().splitlines()
assert lines.count('COMPLETE legacy-roundtrip checks') == 1
assert sum(line.startswith('PASS roundtrip-') for line in lines) == 3 * (3 + len(SAMPLES)), 'Roundtrip count'
print(f'PASS legacy roundtrips: 3 fixtures + {len(SAMPLES)} sample copies x XML/ZIP/OPC, arrow-parent fallback and pasteboard')
