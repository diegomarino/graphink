#!/usr/bin/env python3
"""Run windowless in-memory creation/default/control regressions; persistence is not exercised."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
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
# Compile current preset and Data inspector sources; graph/XML code comes from
# the supplied frameworks. No application nib or window is loaded.
command = ['xcrun', 'clang', '-fno-objc-arc', '-fblocks', '-DOMNI_BUILDING_FOR_MAC=1',
           '-include', 'Cocoa/Cocoa.h', '-include', str(ROOT / 'GraphSketcher/Model/GraphSketcherModel_Prefix.h'),
           '-F', str(products), '-framework', 'Cocoa', '-framework', 'QuartzCore',
           '-framework', 'GraphSketcherModel', '-framework', 'OmniBase',
           '-framework', 'OmniFoundation', '-framework', 'OmniUnzip',
           '-framework', 'OmniQuartz', '-framework', 'OmniAppKit', '-framework', 'OmniInspector',
           '-Wl,-rpath,'+str(products), '-I', str(ROOT/'GraphSketcher/App'), '-framework', 'CoreText', str(ROOT / 'UI/StylePresets/CreationDefaultsChecks.m'),
           str(ROOT / 'GraphSketcher/App/RSStylePresets.m'),
           '-include', str(ROOT/'GraphSketcher/App/GraphSketcher_Prefix.h'),
           str(ROOT/'GraphSketcher/App/Inspectors/DataInspector.m'),
           *[str(ROOT/'GraphSketcher/App'/f) for f in ['RSTool.m','RSTextTool.m','RSDrawTool.m','RSFillTool.m','RSSelector.m','Inspectors/StyleInspector.m','NSSegmentedControl-RSExtensions.m']],
           '-o', str(output / 'checks')]
(output / 'compile-command.json').write_text(json.dumps(command, indent=2)+'\n')
compiled = subprocess.run(command, capture_output=True)
(output / 'compile.log').write_bytes(compiled.stdout+compiled.stderr)
if compiled.returncode:
    raise SystemExit(f'Compilation failed; inspect {output / "compile.log"}')
bundle = output / 'StylePresetChecks.app/Contents'
(bundle/'MacOS').mkdir(parents=True)
(bundle/'Frameworks').symlink_to(products)
fixture = dict(info)
fixture.update(CFBundleExecutable='checks', CFBundleIdentifier='com.graphsketcher.presetchecks.'+uuid.uuid4().hex,
               CFBundleVersion='1', CFBundleShortVersionString='1.0', LSMinimumSystemVersion='12.0', NSHumanReadableCopyright='Graphink preset test fixture (2026)', OFControllerClass='OFController')
# Fixtures never declare document types, UTIs, URL schemes or services: running one registers it
# with Launch Services, where it would claim .graphink/.ograph (Checks/check-fixture-bundles.py).
for key in ('NSMainNibFile', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations', 'CFBundleURLTypes', 'NSServices'):
    fixture.pop(key, None)
(bundle/'Info.plist').write_bytes(plistlib.dumps(fixture))
(bundle/'MacOS/checks').write_bytes((output/'checks').read_bytes())
(bundle/'MacOS/checks').chmod(0o755)
import shutil
shutil.copytree(ROOT/'GraphSketcher/App/Resources/StyleFonts',bundle/'Resources/StyleFonts')
r = subprocess.run([str(bundle/'MacOS/checks')], capture_output=True)
log=r.stdout+r.stderr
(output/'checks.log').write_bytes(log)
print(log.decode(errors='replace'))
if r.returncode or b'PASS document creation defaults in memory' not in log or any(m in log for m in [b'ASSERT failed',b'PRECONDITION failed',b'Exception raised:',b'FAIL ']):
    raise SystemExit('FAIL preset checks; inspect '+str(output))
(output/'verification.json').write_text(json.dumps({'passed':True,'products':str(products),'sources':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'GraphSketcher/App/RSStylePresets.m',ROOT/'UI/StylePresets/CreationDefaultsChecks.m',ROOT/'GraphSketcher/App/Inspectors/DataInspector.m']}},indent=2)+'\n')
