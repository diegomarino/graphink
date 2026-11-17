#!/usr/bin/env python3
"""Replay the retained analyzer invocations with isolated outputs and local source/header overlays."""
import argparse
import json
from pathlib import Path
import plistlib
import shlex
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
assignment = json.loads(Path(__file__).with_name('assignment.json').read_text())
args.output.mkdir(parents=True, exist_ok=True)
out = args.output.resolve()
files = sorted({entry['relative_file'] for entry in assignment})
# Header maps in the retained invocations point to the immutable source tree.
headers = []
if not args.baseline:
    for name in subprocess.check_output(['git', '-C', str(root / 'OmniGroup'), 'diff', '--name-only'], text=True).splitlines():
        if name.endswith('.h'):
            for prefix in ('/tmp', '/private/tmp'):
                headers.append({'type': 'file', 'name': f'{prefix}/graphink-issues3-6-merge-check/OmniGroup/{name}', 'external-contents': str(root / 'OmniGroup' / name)})
overlay = out / 'headers.json'
overlay.write_text(json.dumps({'version': 0, 'roots': headers}))
lines = Path('/private/tmp/graphink-issues3-6-build.log').read_text().splitlines()
results = []
for file in files:
    matching = [line for line in lines if '--analyze ' in line and f'/{file} ' in line]
    assert matching, file
    command = shlex.split(matching[0])
    command = command[command.index('--') + 1:]
    expanded = []
    for arg in command:
        expanded.extend(shlex.split(Path(arg[1:]).read_text()) if arg.startswith('@') else [arg])
    # Rewrite the build's framework overlay too: nested overlays otherwise use stale file sizes.
    for index, arg in enumerate(expanded[:-1]):
        if arg == '-ivfsoverlay' and not args.baseline:
            original = Path(expanded[index + 1])
            rewritten = original.read_text().replace('/tmp/graphink-issues3-6-merge-check/OmniGroup/', str(root / 'OmniGroup') + '/')
            copied = out / (Path(file).stem + '.framework-headers.json')
            copied.write_text(rewritten)
            expanded[index + 1] = str(copied)
    command = []
    skip = False
    for arg in expanded:
        if skip:
            skip = False
            continue
        if arg in ('-o', '-MF', '-MT', '-ivfsstatcache', '-fbuild-session-file'):
            skip = True
            continue
        if arg in ('-MMD', '-fmodules-validate-once-per-build-session') or arg.startswith('-fbuild-session-file='):
            continue
        if arg.startswith('-fmodules-cache-path='):
            arg = '-fmodules-cache-path=' + str(out / 'ModuleCache')
        if not args.baseline and arg.endswith('/' + file):
            arg = str(root / file)
        command.append(arg)
    plist = out / (Path(file).stem + '.plist')
    command += ['-ivfsoverlay', str(overlay), '-o', str(plist)]
    (out / (Path(file).stem + '.command.json')).write_text(json.dumps(command, indent=2) + '\n')
    run = subprocess.run(command, cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / (Path(file).stem + '.log')).write_text(run.stdout)
    assert run.returncode == 0, f'{file}: compiler failed; see log'
    data = plistlib.loads(plist.read_bytes())
    diagnostics = [{'file': data['files'][d['location']['file']], 'line': d['location']['line'], 'description': d['description'], 'type': d['type']} for d in data['diagnostics']]
    results.append({'source': file, 'diagnostics': diagnostics})
    print(file, len(diagnostics), flush=True)
(out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
