#!/usr/bin/env python3
"""Equation lines (#27): saved as equations, marked as a required feature, drawn, and refused when invalid.

Compiles Checks/EquationLineChecks.m against independently built Debug products of this checkout, in
an isolated bundle that keeps the app's real defaults registration (like check-legacy-roundtrips.py),
and runs it windowless: every equation family (the five Experimental menu curves as the menu adds
them, then all six families with other parameters) is written as a Graphink package, reopened,
rewritten byte-identically and rendered identically; the curve must draw. Legacy writes are refused.
The emitted packages are then checked here: the `equation-lines-v1` token is present exactly when the
graph has an equation line, docs/format/check-opc.py accepts them, `graphink render` draws a saved
and a resaved document identically, and modified packages (unknown or missing token, invalid
equation) are refused by both the production reader and check-opc.py. No UI is launched.
"""
import argparse
import importlib.util
import plistlib
import subprocess
import zipfile
from pathlib import Path

FRAMEWORKS = ['GraphSketcherModel', 'OmniBase', 'OmniFoundation', 'OmniUnzip', 'OmniQuartz', 'OmniAppKit']
CONTROL, PAYLOAD = 'graphink/document.xml', 'contents.xml'
CASES = ['menu-square', 'menu-cube', 'menu-sine', 'menu-gaussian', 'menu-logistic',
         'linear', 'square', 'cube', 'sine', 'gaussian', 'logistic', 'all']

parser = argparse.ArgumentParser(description=__doc__, epilog='Example: python3 Checks/check-equation-lines.py --products /private/tmp/GraphSketcher-build.X/Debug/Products/Debug --output /private/tmp/gs-equation-lines-new')
parser.add_argument('--products', required=True, type=Path, help='Absolute Debug products directory built from this checkout')
parser.add_argument('--output', required=True, type=Path, help='New evidence directory; existing paths refused')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
products = args.products.resolve()
if not args.products.is_absolute() or any(not (products / f'{name}.framework').exists() for name in FRAMEWORKS):
    parser.error('--products must be an absolute Debug products directory containing the model and Omni frameworks')
tool = products / 'Graphink.app/Contents/Helpers/graphink'
if not tool.is_file():
    parser.error('--products must contain Graphink.app with its graphink helper')
if args.output.exists():
    parser.error('--output already exists')
assert __debug__, 'Assertions must be enabled; do not use Python -O'
args.output.mkdir(parents=True)

# The independent profile checker's own packer and validator (it shares no production code).
spec = importlib.util.spec_from_file_location('check_opc', root / 'docs/format/check-opc.py')
opc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(opc)

contents = args.output / 'EquationLineChecks.app/Contents'
(contents / 'MacOS').mkdir(parents=True)
info = plistlib.loads((root / 'GraphSketcher/App/Info.plist').read_bytes())
# Fixtures never declare document types, UTIs, URL schemes or services (Checks/check-fixture-bundles.py).
for key in ('NSMainNibFile', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations', 'CFBundleURLTypes', 'NSServices'):
    info.pop(key, None)
info.update(CFBundleExecutable='checks', CFBundleIdentifier='com.graphsketcher.migration.equationlines',
            CFBundleVersion='1', CFBundleShortVersionString='1.0', LSMinimumSystemVersion='12.0',
            NSPrincipalClass='NSApplication', OFControllerClass='CheckController',
            NSHumanReadableCopyright='Copyright 2026 The Omni Group')
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
(contents / 'Frameworks').symlink_to(products)
probe = contents / 'MacOS/checks'
subprocess.run(['xcrun', 'clang', '-fno-objc-arc', '-Wall', '-Werror', '-Wno-deprecated-declarations', '-DOMNI_BUILDING_FOR_MAC=1',
                '-F', str(products), '-framework', 'Cocoa'] + [arg for name in FRAMEWORKS for arg in ('-framework', name)] + [
                f'-Wl,-rpath,{products}', '-o', str(probe), str(root / 'Checks/EquationLineChecks.m')], check=True)


def run(command, name):
    result = subprocess.run([str(part) for part in command], capture_output=True)
    log = result.stdout + result.stderr
    (args.output / f'{name}.log').write_bytes(log)
    for marker in (b'FAIL', b'ASSERT', b'PRECONDITION', b'Assertion Failed'):
        assert marker not in log, f'{name}: {marker} in log'
    assert result.returncode == 0, f'{name} exited {result.returncode}:\n{log.decode()}'
    return result.stdout.decode()


evidence = args.output / 'outputs'
stdout = run([probe, evidence], 'checks')
print(stdout)
lines = stdout.splitlines()
assert lines.count('COMPLETE equation-line checks') == 1
assert sorted(line.split()[2].rstrip(':') for line in lines if line.startswith('PASS roundtrip ')) == sorted(CASES), 'Roundtrip cases'


def parts(path):
    with zipfile.ZipFile(path) as archive:
        return {name: archive.read(name) for name in archive.namelist()}


def features(path):
    control = opc.xml(parts(path)[CONTROL])
    return control.get('required-features')


# The token names exactly the optional data present; documents without equation lines are unchanged.
for case in CASES:
    expected = 'creation-defaults-v1 equation-lines-v1' if case == 'all' else 'equation-lines-v1'
    for n in (1, 2):
        package = evidence / f'{case}-{n}.graphink'
        assert features(package) == expected, f'{package.name}: required-features {features(package)!r}'
        opc.validate(package.read_bytes())
    first, second = parts(evidence / f'{case}-1.graphink'), parts(evidence / f'{case}-2.graphink')
    # contents.xml as a multiset of lines: the hidden axis end labels follow hash order (EquationLineChecks.m).
    assert {n: b for n, b in first.items() if n != PAYLOAD} == {n: b for n, b in second.items() if n != PAYLOAD}, f'{case}: resaved package parts differ'
    assert sorted(first[PAYLOAD].splitlines()) == sorted(second[PAYLOAD].splitlines()), f'{case}: resaved payload differs'
for plain in ('plain.graphink', 'removed.graphink'):
    assert features(evidence / plain) == '', f'{plain}: unexpected required features'
    opc.validate((evidence / plain).read_bytes())
print(f'PASS: {len(CASES)} documents x 2 carry equation-lines-v1 (with creation-defaults-v1 when defaults exist), '
      'equal parts when resaved (payload lines as a multiset) and pass check-opc.py; plain and emptied documents carry no feature')

# The app's export path: a saved and a resaved document draw identically, and the curve draws.
renders = args.output / 'renders'
renders.mkdir()
run([tool, 'render', evidence / 'plain.graphink', '-o', renders / 'plain.png'], 'render-plain')
plain_png = (renders / 'plain.png').read_bytes()
for case in CASES:
    for n in (1, 2):
        run([tool, 'render', evidence / f'{case}-{n}.graphink', '-o', renders / f'{case}-{n}.png'], f'render-{case}-{n}')
    first = (renders / f'{case}-1.png').read_bytes()
    assert first == (renders / f'{case}-2.png').read_bytes(), f'{case}: graphink render differs after resave'
    assert first != plain_png, f'{case}: graphink render draws no curve'
print(f'PASS: graphink render of {len(CASES)} saved and resaved documents identical, each different from the empty graph')

# Modified packages: refused by the production reader and by the independent checker.
negatives = args.output / 'negative'
negatives.mkdir()
square, plain = parts(evidence / 'menu-square-1.graphink'), parts(evidence / 'plain.graphink')


def variant(name, source, member, old, new, kind):
    assert source[member].count(old) == 1, f'{name}: {old!r} not found once'
    changed = dict(source, **{member: source[member].replace(old, new)})
    path = negatives / f'{name}.graphink'
    path.write_bytes(opc.pack([(n, changed[n]) for n in opc.MEMBERS]))
    try:
        opc.validate(path.read_bytes())
    except opc.Refusal as refusal:
        assert refusal.kind == kind, f'{name}: check-opc.py refused as {refusal.kind}, expected {kind}'
    else:
        raise AssertionError(f'{name}: check-opc.py accepted it')
    return path, kind


cases = [
    variant('future-token', square, CONTROL, b'"equation-lines-v1"', b'"equation-lines-v2"', 'unsupported'),
    variant('token-missing', square, CONTROL, b'"equation-lines-v1"', b'""', 'malformed'),
    variant('token-without-equations', plain, CONTROL, b'required-features=""', b'required-features="equation-lines-v1"', 'malformed'),
    variant('unknown-family', square, PAYLOAD, b'family="square"', b'family="tangent"', 'malformed'),
    variant('missing-c', square, PAYLOAD, b' c="1"', b'', 'malformed'),
    variant('infinite-a', square, PAYLOAD, b' a="0"', b' a="inf"', 'malformed'),
    variant('no-equation', square, PAYLOAD, b'<equation family="square" a="0" b="0" c="1"/>', b'', 'malformed'),
]
report = run([probe, '--read'] + [path for path, _ in cases], 'read-negative')
print(report)
for (path, kind), line in zip(cases, report.splitlines()):
    code = 'code=2' if kind == 'unsupported' else 'code=1'
    assert line.startswith(f'REFUSED {path.name} domain=GraphinkPackage {code} '), f'{path.name}: {line}'
print(f'PASS: {len(cases)} modified packages refused by the production reader and check-opc.py with the expected kind')
