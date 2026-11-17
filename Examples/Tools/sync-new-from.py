#!/usr/bin/env python3
"""Copy the Examples/NewFrom-manifest.plist catalog into the app's bundled File ▸ New From folder.

Byte-copies each item's Source to GraphSketcher/App/Resources/NewFrom/<File>, removes bundled
documents that are no longer listed, and rewrites the
Groups of NewFrom.plist with File, Title and SHA256 only (the app rejects unknown keys). The
InitialExample entry is kept as is. Lessons stay in "examples"; data charts (Source under Data/)
get their own "data" group; templates follow. Default only checks; --write updates the bundle.
"""
import argparse
import hashlib
import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'Examples/NewFrom-manifest.plist'
BUNDLE = ROOT / 'GraphSketcher/App/Resources/NewFrom'
BUNDLE_MANIFEST = BUNDLE / 'NewFrom.plist'
# (identifier, title, predicate on the manifest group and Source), in menu order
GROUPS = [
    ('examples', 'Examples', lambda group, source: group == 'examples' and not source.startswith('Data/')),
    ('data', 'Data Charts', lambda group, source: group == 'examples' and source.startswith('Data/')),
    ('templates', 'Templates', lambda group, source: group == 'templates'),
]
BUNDLE_KEYS = ('File', 'Title', 'SHA256')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def catalog_items():
    """(group identifier, item) pairs in manifest order, each Source checked against its SHA256."""
    manifest = plistlib.loads(MANIFEST.read_bytes())
    assert manifest['FormatVersion'] == 1
    pairs = []
    for group in manifest['Groups']:
        for item in group['Items']:
            source = ROOT / 'Examples' / item['Source']
            assert sha(source) == item['SHA256'], f"{item['Source']}: differs from NewFrom-manifest.plist"
            pairs.append((group['Identifier'], item))
    return pairs


def build(pairs):
    current = plistlib.loads(BUNDLE_MANIFEST.read_bytes())
    groups = []
    for identifier, title, belongs in GROUPS:
        items = [{k: item[k] for k in BUNDLE_KEYS} for group, item in pairs if belongs(group, item['Source'])]
        groups.append({'Identifier': identifier, 'Title': title, 'Items': items})
    assert sum(len(g['Items']) for g in groups) == len(pairs), 'Every manifest item belongs to exactly one group'
    return {'FormatVersion': 1, 'InitialExample': current['InitialExample'], 'Groups': groups}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='Copy documents and rewrite NewFrom.plist; default only checks')
    args = parser.parse_args()
    pairs = catalog_items()
    expected = build(pairs)
    if args.write:
        for _, item in pairs:
            target = BUNDLE / item['File']
            target.parent.mkdir(exist_ok=True)
            target.write_bytes((ROOT / 'Examples' / item['Source']).read_bytes())
        BUNDLE_MANIFEST.write_bytes(plistlib.dumps(expected, sort_keys=False))
        # Documents that left the catalog leave the bundle too.
        keep = {item['File'] for _, item in pairs} | {expected['InitialExample']['File']}
        for stale in sorted(BUNDLE.rglob('*.graphink')):
            if stale.relative_to(BUNDLE).as_posix() not in keep:
                stale.unlink()
                print(f'removed {stale.relative_to(ROOT)}')
    assert plistlib.loads(BUNDLE_MANIFEST.read_bytes()) == expected, 'NewFrom.plist differs from the catalog; rerun with --write'
    for _, item in pairs:
        bundled = BUNDLE / item['File']
        assert bundled.read_bytes() == (ROOT / 'Examples' / item['Source']).read_bytes(), f"{item['File']}: not a byte copy of {item['Source']}"
    listed = {item['File'] for _, item in pairs} | {expected['InitialExample']['File']}
    present = {p.relative_to(BUNDLE).as_posix() for p in BUNDLE.rglob('*.graphink')}
    assert present == listed, f'Unlisted or missing bundled documents: {sorted(present ^ listed)}'
    counts = ', '.join(f"{g['Identifier']}={len(g['Items'])}" for g in expected['Groups'])
    print(f'PASS: {BUNDLE_MANIFEST.relative_to(ROOT)} matches the catalog ({counts}); bundled copies byte-identical')


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, KeyError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        sys.exit(1)
