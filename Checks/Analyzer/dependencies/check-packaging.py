#!/usr/bin/env python3
"""Check the documented bootstrap and real source guard against disposable Git fixtures."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PIN = '2be207ce6f7b4f77498bb48dd5e27403fb689eb7'
PATCHES = sorted((ROOT / 'Patches/OmniGroup').glob('000[1234]-*.patch'))
assert len(PATCHES) == 4
BOOTSTRAP = (ROOT / 'Patches/OmniGroup/README.md').read_text().split("bash <<'BOOTSTRAP'\n", 1)[1].split('\nBOOTSTRAP', 1)[0]
GUARD = (ROOT / 'Checks/check-documents.sh').read_text().split('sources_match_head() {', 1)[1].split('\n}', 1)[0]
EVIDENCE = Path(tempfile.mkdtemp(prefix='graphink-dependency-packaging-', dir='/private/tmp'))


def run(command, cwd, good=True):
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            env={**os.environ, 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_ALLOW_PROTOCOL': 'file'})
    if good:
        assert result.returncode == 0, result.stdout
    return result


def fixture(name, count):
    path = EVIDENCE / name
    path.mkdir()
    run(['git', 'init', '-q'], path)
    run(['git', 'config', 'user.name', 'Analyzer Fixture'], path)
    run(['git', 'config', 'user.email', 'analyzer-fixture@example.invalid'], path)
    shutil.copytree(ROOT / 'Patches', path / 'Patches')
    shutil.copyfile(ROOT / '.gitmodules', path / '.gitmodules')
    (path / 'Checks').mkdir()
    shutil.copyfile(ROOT / 'Checks/check-documents.sh', path / 'Checks/check-documents.sh')
    if count >= 0:
        run(['git', 'clone', '--shared', '--no-checkout', str(ROOT / 'OmniGroup'), 'OmniGroup'], path)
        run(['git', '-C', 'OmniGroup', 'checkout', '-q', PIN], path)
    else:
        run(['git', 'config', 'submodule.OmniGroup.url', str(ROOT / 'OmniGroup')], path)
    run(['git', 'add', 'Patches', 'Checks', '.gitmodules'], path)
    run(['git', 'update-index', '--add', '--cacheinfo', '160000', PIN, 'OmniGroup'], path)
    run(['git', 'commit', '-qm', 'Create isolated dependency fixture'], path)
    for patch in PATCHES[:max(count, 0)]:
        run(['git', '-C', 'OmniGroup', 'apply', str(patch)], path)
    return path


def guard(path):
    return run(['bash', '-c', 'sources_match_head() {' + GUARD + '\n}\nsources_match_head'], path, False).returncode == 0


fresh = fixture('uninitialized', -1)
run(['bash', '-c', BOOTSTRAP], fresh)
assert guard(fresh)
print('PASS uninitialized local bootstrap+full-guard', flush=True)

for count in range(5):
    path = fixture(f'prefix-{count}', count)
    assert guard(path) == (count == 4), count
    for attempt in range(2):
        run(['bash', '-c', BOOTSTRAP], path)
        assert guard(path), (count, attempt)
    print(f'PASS prefix={count} upgrade+repeat+full-guard', flush=True)

for name in ('unrelated', 'patched-extra', 'staged', 'untracked', 'parent-patch-edit', 'parent-patch-staged', 'parent-patch-untracked', 'wrong-pin'):
    path = fixture(name, 4)
    if name == 'unrelated':
        with (path / 'OmniGroup/README.md').open('a') as output:
            output.write('\nUnrelated fixture edit.\n')
    elif name in ('patched-extra', 'staged'):
        target = 'Frameworks/OmniFoundation/XML/OFXMLSignature.m'
        with (path / 'OmniGroup' / target).open('a') as output:
            output.write('\n// Extra fixture edit.\n')
        if name == 'staged':
            run(['git', '-C', 'OmniGroup', 'add', target], path)
    elif name == 'untracked':
        (path / 'OmniGroup/untracked-fixture').write_text('fixture\n')
    elif name in ('parent-patch-edit', 'parent-patch-staged'):
        target = path / 'Patches/OmniGroup' / PATCHES[-1].name
        target.write_text(target.read_text() + '\n')
        if name == 'parent-patch-staged':
            run(['git', 'add', 'Patches'], path)
    elif name == 'parent-patch-untracked':
        (path / 'Patches/OmniGroup/untracked-fixture').write_text('fixture\n')
    else:
        run(['git', '-C', 'OmniGroup', '-c', 'user.name=Analyzer Fixture', '-c', 'user.email=analyzer-fixture@example.invalid', 'commit', '--allow-empty', '-qm', 'Wrong fixture pin'], path)
    before_head = run(['git', '-C', 'OmniGroup', 'rev-parse', 'HEAD'], path).stdout
    before_status = run(['git', '-C', 'OmniGroup', 'status', '--porcelain'], path).stdout
    before = run(['git', '-C', 'OmniGroup', 'diff', 'HEAD'], path).stdout
    assert not guard(path), name
    result = run(['bash', '-c', BOOTSTRAP], path, False)
    assert result.returncode != 0, name
    assert run(['git', '-C', 'OmniGroup', 'diff', 'HEAD'], path).stdout == before, name
    assert run(['git', '-C', 'OmniGroup', 'rev-parse', 'HEAD'], path).stdout == before_head, name
    assert run(['git', '-C', 'OmniGroup', 'status', '--porcelain'], path).stdout == before_status, name
    print(f'PASS reject={name} preservation', flush=True)
print(f'Fixture evidence: {EVIDENCE}')
