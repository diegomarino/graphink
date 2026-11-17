#!/usr/bin/env python3
"""Compile and run windowless native package/GraphDocument regression fixtures.

Run with host access for NSDocument's safe-save file coordination. No Graphink
launch, nib, field editor, window, persistent preference write or user file is used.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__, epilog="Example: python3 UI/StylePresets/check-package-documents.py --products /path/Products/Debug --output /private/tmp/graphink-package-new")
parser.add_argument('--products',required=True,type=Path,help='Exact source build Products/Debug or Products/Release')
parser.add_argument('--output',required=True,type=Path,help='New evidence directory; existing paths refused')
args=parser.parse_args();products=args.products.resolve();output=args.output.resolve()
if output.exists():parser.error('Choose a new output directory; evidence is preserved.')
for framework in ('GraphSketcherModel','OmniBase','OmniFoundation','OmniUnzip','OmniQuartz','OmniAppKit','OmniInspector','LinkBack'):
    if not (products/(framework+'.framework')).exists():parser.error('Missing framework: '+framework)
output.mkdir(parents=True)

def execute(command,log):
    result=subprocess.run([str(x) for x in command],capture_output=True)
    data=result.stdout+result.stderr;log.write_bytes(data)
    if result.returncode:raise SystemExit(f'Failed ({result.returncode}); inspect {log}')
    return data

base=['xcrun','clang','-fno-objc-arc','-fblocks','-DOMNI_BUILDING_FOR_MAC=1','-include','Cocoa/Cocoa.h',
      '-include',ROOT/'GraphSketcher/App/GraphSketcher_Prefix.h','-F',products,'-Wl,-rpath,'+str(products),'-I',ROOT/'GraphSketcher/App']
for name in ('Cocoa','QuartzCore','CoreText','UniformTypeIdentifiers','GraphSketcherModel','OmniBase','OmniFoundation','OmniUnzip','OmniQuartz','OmniAppKit','OmniInspector','LinkBack'):
    base+=['-framework',name]
receipts=[]
for name,sources,marker in [
    ('ArchiveChecks',[],b'PASS: native codec'),
    ('DocumentArchiveChecks',['GraphDocument.m','RSDocumentController.m','RSSelector.m','RSStylePresets.m','RSTool.m','RSTextTool.m'],b'PASS production GraphDocument:')]:
    bundle=output/(name+'.app/Contents');(bundle/'MacOS').mkdir(parents=True)
    (bundle/'Frameworks').symlink_to(products)
    info=plistlib.loads((ROOT/'GraphSketcher/App/Info.plist').read_bytes())
    info.update(CFBundleExecutable='checks',CFBundleIdentifier='com.graphink.windowlesschecks.'+uuid.uuid4().hex,
                CFBundleVersion='1',CFBundleShortVersionString='1.0',LSMinimumSystemVersion='12.0',
                NSHumanReadableCopyright='Graphink windowless test fixture (2026)',OFControllerClass='OFController')
    # Fixtures never declare document types, UTIs, URL schemes or services: running one registers it
    # with Launch Services, where it would claim .graphink/.ograph (Checks/check-fixture-bundles.py).
    for key in ('NSMainNibFile', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations', 'CFBundleURLTypes', 'NSServices'):
        info.pop(key, None)
    (bundle/'Info.plist').write_bytes(plistlib.dumps(info))
    shutil.copytree(ROOT/'GraphSketcher/App/Resources/StyleFonts',bundle/'Resources/StyleFonts')
    executable=bundle/'MacOS/checks'
    paths=[ROOT/'UI/StylePresets'/(name+'.m'),*[ROOT/'GraphSketcher/App'/p for p in sources]]
    command=base+paths+['-o',executable]
    (output/(name+'-compile.json')).write_text(json.dumps([str(x) for x in command],indent=2)+'\n')
    execute(command,output/(name+'-compile.log'))
    data=execute([executable,output/(name+'-outputs')],output/(name+'.log'))
    if marker not in data or any(x in data for x in (b'ASSERT failed',b'PRECONDITION failed',b'FAIL:',b'Exception raised:')):
        raise SystemExit('Native fixture assertion/failure: '+name)
    receipts.append(dict(name=name,passed=True,sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}))
archive_exe=output/'ArchiveChecks.app/Contents/MacOS/checks'
execute(['python3',ROOT/'UI/StylePresets/check-archives.py','--checks',archive_exe,'--package',output/'ArchiveChecks-outputs/native.graphink','--output',output/'adverse'],output/'adverse.log')
receipt={'scope':'Windowless production model/GraphDocument/tool routes; no application UI acceptance',
         'source':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
         'source_dirty':subprocess.check_output(['git','status','--short','--ignore-submodules'],cwd=ROOT,text=True),
         'products':str(products),'model_sha256':hashlib.sha256((products/'GraphSketcherModel.framework/GraphSketcherModel').read_bytes()).hexdigest(),'checks':receipts}
(output/'verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('PASS native package and document fixtures: '+str(output))
