#!/usr/bin/env python3
"""Run the exact GraphDocument extension method with native NSDocument fixture writes."""
import argparse
from pathlib import Path
import re
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', required=True, type=Path, help='New evidence directory; existing paths refused')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
if args.output.exists():
    parser.error('--output already exists')
args.output.mkdir(parents=True)
source = (root / 'GraphSketcher/App/GraphDocument.m').read_text()
method = re.search(r'- \(NSString \*\)fileNameExtensionForType:.*?\n\}', source, re.S)
assert method, 'GraphDocument extension override is missing'
panel = re.search(r'- \(BOOL\)prepareSavePanel:.*?\n\}', source, re.S)
body = method[0] + ('\n' + panel[0] if panel else '')
(args.output / 'ProductionExtensionMethod.h').write_text('@implementation ExtensionDocument (ProductionExtension)\n' + body + '\n@end\n')
contents = args.output / 'ExtensionChecks.app/Contents'
(contents / 'MacOS').mkdir(parents=True)
info = plistlib.loads((root / 'GraphSketcher/App/Info.plist').read_bytes())
# The fixture keeps the app's document types and UTIs because they are what it checks. Running it
# registers it with Launch Services: rank None so it is never offered as a handler, and unregistered
# after the run (Checks/check-fixture-bundles.py).
for document_type in info['CFBundleDocumentTypes']:
    document_type['NSDocumentClass'] = 'ExtensionDocument'
    document_type['LSHandlerRank'] = 'None'
fixture_info = {key: info[key] for key in ('CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations')}
fixture_info.update(CFBundleExecutable='checks', CFBundleIdentifier='com.graphsketcher.ExtensionChecks', CFBundlePackageType='APPL')
(contents / 'Info.plist').write_bytes(plistlib.dumps(fixture_info))
command = ['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-Wno-deprecated-declarations', '-framework', 'AppKit', '-framework', 'UniformTypeIdentifiers', '-I', str(root / 'GraphSketcher/App'), str(root / 'GraphSketcher/App/RSDocumentController.m'), '-I', str(args.output), str(root / 'Checks/GraphinkExtensionChecks.m'), '-o', str(contents / 'MacOS/checks')]
subprocess.run(command, check=True)
try:
    result = subprocess.run([str(contents / 'MacOS/checks'), str(args.output.resolve())], capture_output=True)
finally:
    subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-u', str(contents.parent)], check=True)
(args.output / 'checks.log').write_bytes(result.stdout + result.stderr)
print((result.stdout + result.stderr).decode())
assert result.returncode == 0 and b'PASS production extension method' in result.stdout
