#!/usr/bin/env python3
"""Generate the example catalog's offscreen native OPC examples and templates into a NEW evidence directory."""
import argparse
import contextlib
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import zipfile
sys.dont_write_bytecode = True
from validate import validate, self_check, STEMS, CREDITS, RELABELS, PALE_NOTE, label_text, NS
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CHECKER_SHA256 = '940c6583b6456247b2984861990128de02a07afe86b9126f6ff227649deddd16'
# Delivered lessons from Examples/Microeconomics stay byte-identical; templates are new documents, not edits.
DELIVERED = ['Examples/Microeconomics/' + s + '.graphink' for s in
             ('01-market-equilibrium', '02-demand-and-supply-shifts', '03-tax-incidence-and-welfare')]
# The supply-and-demand template is kept as delivered (templates v2): this run's regenerated copy must have the same
# contents.xml apart from the credit label's text (writer host stamp and tick-label order normalized), so a credit
# change is the only change it can deliver.
KEPT_TEMPLATES = {'template-market-equilibrium': 'Examples/Templates/market-equilibrium.graphink'}
# Credits for 01-03 are added to these exact pre-credit documents (the dd04bb6 versions, pinned in pre-credit/), so
# reruns never stack credits on already credited files. SHA-256 values from the Debug generation record of 01-03.
PRE_CREDIT = HERE / 'pre-credit'
PRE_CREDIT_SHA256 = {
    '01-market-equilibrium.graphink': '15a1d0ee0312da78a37cabcd8c0eb11d7cc69bd6724b5863285d9f9d0dce9cbf',
    '02-demand-and-supply-shifts.graphink': '849d16a63e1fdd6f1e4ed5a0354d635d7c4eeeda69ec63801ac9f5923c4f9057',
    '03-tax-incidence-and-welfare.graphink': '085657dcb3a5f9ab114c635563e845bec08009e833662bf482dbb52f59a2341e',
}


def without_credit(xml, credit, relabeled=()):
    """contents.xml with the credit label and the relabeled labels removed, canonicalized for an exact comparison.

    relabeled: texts of labels whose text was deliberately changed (RELABELS); each must occur exactly once and is
    compared by its ID only (the axis title or user label stays, with the same ID and owner).

    Only writer artifacts are normalized: the host stamp on <document> (os-version, machine-model), and the
    order of axis-owned tick labels and their references, which follows dictionary hash order. Those tick
    labels are compared as a sorted set; every other element keeps its order."""
    root = ET.fromstring(xml)
    for key in ('os-version', 'machine-model'):
        root.attrib.pop(key, None)
    graph = root.find(NS + 'graph')
    # credit=None removes whichever concept credit the document carries (kept templates may predate a credit change).
    matches = (lambda text: text.startswith('Concepts: ')) if credit is None else (lambda text: text == credit)
    labels = [l for l in graph.findall(NS + 'label') if matches(label_text(l))]
    assert len(labels) <= 1, 'At most one credit label'
    for label in labels:
        graph.remove(label)
    for text in relabeled:
        found = [l for l in graph.findall(NS + 'label') if label_text(l) == text]
        assert len(found) == 1, ('Relabeled text occurs exactly once', text, len(found))
        graph.remove(found[0])
    ticks = set()
    for parent in root.iter():
        refs = [c for c in parent if c.tag == NS + 'label' and c.get('tick') is not None]
        if refs and len(refs) == len(parent):
            parent[:] = sorted(refs, key=lambda c: (c.get('tick'), c.get('idref')))
            ticks |= {c.get('idref') for c in refs}
    canonical = lambda e: ET.canonicalize(ET.tostring(e, encoding='unicode'), strip_text=True)
    tick_labels = [l for l in graph.findall(NS + 'label') if l.get('id') in ticks]
    for label in tick_labels:
        graph.remove(label)
    return (canonical(root), sorted(map(canonical, tick_labels))), len(labels)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, log, **kwargs):
    proc = subprocess.run([str(v) for v in command], capture_output=True, text=True, **kwargs)
    log.write_text(proc.stdout + proc.stderr)
    assert proc.returncode == 0, f'Command exited {proc.returncode}; inspect {log}'
    return proc


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog='Example: python3 Examples/Tools/generate.py --products /private/tmp/GraphSketcher-build.XXXXXX/Debug/Products/Debug --output /private/tmp/new-catalog-run. Products must come from docs/BUILDING.md builds of a commit whose model sources match this worktree. No UI, installs, source edits or overwrites. Exit 0: bounded checks passed; 1: failure (see output/error.log); 2: invalid arguments.')
    parser.add_argument('--products', required=True, type=Path, help='<build root>/<Config>/Products/<Config> built per docs/BUILDING.md; <build root>/source-sha.txt records the source')
    parser.add_argument('--output', required=True, type=Path, help='New directory; existing paths are refused, even if empty')
    args = parser.parse_args()
    products, out = args.products.resolve(), args.output.absolute()
    if out.exists():
        parser.error('--output already exists; choose a new evidence directory')
    out.mkdir(parents=True)
    receipt = {'source': str(ROOT), 'products': str(products), 'evidence': str(out), 'command': [sys.executable, *sys.argv], 'passed': False,
               'scope': 'Production OPC writer/reader, real same-model preview, creation defaults, offscreen semantic/edit/undo checks, native curved-connection probe. No interactive acceptance.',
               'limits': ['PDF CreationDate/ModDate reflect generation time; PDF and package bytes are not stable across runs.',
                          'No interactive UI, Finder/Quick Look, accessibility or human acceptance; no historical legacy smoke suite.']}
    originals = {}
    try:
        assert __debug__, 'Assertions must be enabled; do not use Python -O'
        configuration = products.name
        build_root = products.parents[2]
        assert products == build_root / configuration / 'Products' / configuration, '--products must be <root>/<Config>/Products/<Config>'
        build_sha = (build_root / 'source-sha.txt').read_text().strip()
        receipt.update(configuration=configuration, buildSourceSHA=build_sha)
        run(['git', 'merge-base', '--is-ancestor', build_sha, 'HEAD'], out / 'ancestor.log', cwd=ROOT)
        run(['git', 'diff', '--exit-code', build_sha, '--', 'GraphSketcher/Model', 'GraphSketcher/OmniStyle'], out / 'model-source.log', cwd=ROOT)
        receipt['sourceHEAD'] = run(['git', 'rev-parse', 'HEAD'], out / 'source-head.log', cwd=ROOT).stdout.strip()
        receipt['omniGroupHEAD'] = run(['git', '-C', 'OmniGroup', 'rev-parse', 'HEAD'], out / 'omnigroup-head.log', cwd=ROOT).stdout.strip()
        checker = ROOT / 'docs/format/check-opc.py'
        receipt['checker'] = {'path': str(checker), 'sha256': digest(checker)}
        assert receipt['checker']['sha256'] == CHECKER_SHA256, 'OPC checker differs from approved SHA256'
        receipt['frameworkSHA256'] = {p.name: digest(p / p.stem) for p in products.glob('*.framework')}
        assert 'GraphSketcherModel.framework' in receipt['frameworkSHA256'], 'Missing model framework'
        # Keyed by repository path: two of these files are named validate.py.
        receipt['generatorSHA256'] = {str(p.relative_to(ROOT)): digest(p) for p in [HERE / 'GenerateCatalog.m', HERE / 'generate.py', HERE / 'validate.py', ROOT / 'Examples/Data/prepare.py', ROOT / 'Examples/Microeconomics/validate.py']}
        receipt['rawSourceSHA256'] = {str(p.relative_to(ROOT)): digest(p) for p in sorted((ROOT / 'Examples/Data/Sources').rglob('*')) if p.is_file()}
        prepared = out / 'prepared-data.json'
        run([sys.executable, ROOT / 'Examples/Data/prepare.py', '--output', prepared], out / 'prepare.log')
        report = (ROOT / 'Checks/historical-samples.sha256').read_text()
        originals = {p: h for h, p in re.findall(r'^([a-f0-9]{64})  (GraphSketcher/.+\.ograph)$', report, re.M)}
        assert len(originals) == 35, 'Expected 35 original samples in Checks/historical-samples.sha256'
        receipt['originalsBefore'] = {p: digest(ROOT / p) for p in originals}
        assert receipt['originalsBefore'] == originals, 'Original corpus changed before generation'
        receipt['deliveredLessonsBefore'] = {p: digest(ROOT / p) for p in DELIVERED}
        receipt['keptTemplatesBefore'] = {p: digest(ROOT / p) for p in KEPT_TEMPLATES.values()}
        artifacts = out / 'artifacts'
        artifacts.mkdir()
        bundle = out / 'NativeExamples.tool' / 'Contents'
        (bundle / 'MacOS').mkdir(parents=True)
        (bundle / 'Frameworks').symlink_to(products, target_is_directory=True)
        info = plistlib.loads((ROOT / 'GraphSketcher/App/Info.plist').read_bytes())
        info.update(CFBundleIdentifier='com.graphink.examples.offscreen', CFBundleExecutable='NativeExamples', CFBundleVersion='11.0', CFBundleShortVersionString='1.0', NSHumanReadableCopyright='Copyright 2026 Graphink examples contributors', OFControllerClass='ExampleController', NSPrincipalClass='NSApplication', LSMinimumSystemVersion='12.0')
        # The generator never opens documents: declaring types or UTIs would register it with Launch Services
        # as a handler for .graphink/.ograph (Checks/check-fixture-bundles.py lists these keys).
        for key in ('NSMainNibFile', 'CFBundleDocumentTypes', 'UTExportedTypeDeclarations', 'UTImportedTypeDeclarations', 'CFBundleURLTypes', 'NSServices'):
            info.pop(key, None)
        (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
        exe = bundle / 'MacOS/NativeExamples'
        command = ['xcrun', 'clang', '-fno-objc-arc', '-fblocks', '-DOMNI_BUILDING_FOR_MAC=1', '-F', products]
        for fw in ['Cocoa', 'QuartzCore', 'GraphSketcherModel', 'OmniBase', 'OmniFoundation', 'OmniAppKit', 'OmniQuartz', 'OmniUnzip']:
            command += ['-framework', fw]
        command += ['-Wl,-rpath,' + str(products), '-o', exe, HERE / 'GenerateCatalog.m']
        receipt['compileCommand'] = list(map(str, command))
        run(command, out / 'compile.log')
        proc = run([exe, artifacts, prepared], out / 'native.log', timeout=120)
        receipt['nativeExit'] = proc.returncode
        assert f'COMPLETE examples={len(STEMS)} failed=0' in proc.stdout and proc.stdout.count('PASS example=') == len(STEMS), 'Missing completion markers; inspect native.log'
        assert not re.search(r'FATAL ASSERTION|Assertion Failed|ASSERT failed|^FAIL ', proc.stdout + proc.stderr, re.M), 'Native assertions found; inspect native.log'
        curved = {}
        with (out / 'validation.log').open('w') as log, contextlib.redirect_stdout(log):
            validate(artifacts, curved)
            receipt['negativeEvidence'] = self_check(artifacts, out / 'negative')
        receipt['curvedConnectionProbe'] = curved
        # Lessons 01-03: the delivered documents plus one credit label, through the same production pipeline.
        originals_dir, credited = out / 'lesson-originals', out / 'credited-lessons'
        originals_dir.mkdir()
        credited.mkdir()
        for path in DELIVERED:
            name = Path(path).name
            blob = (PRE_CREDIT / name).read_bytes()
            assert hashlib.sha256(blob).hexdigest() == PRE_CREDIT_SHA256[name], f'{name}: pinned original differs from its recorded hash'
            (originals_dir / name).write_bytes(blob)
        proc = run([exe, '--credit-lessons', originals_dir, credited], out / 'credit-lessons.log', timeout=120)
        assert 'COMPLETE credited=3 failed=0' in proc.stdout and proc.stdout.count('PASS credited=') == 3, 'Missing credit completion markers'
        assert not re.search(r'FATAL ASSERTION|Assertion Failed|ASSERT failed|^FAIL ', proc.stdout + proc.stderr, re.M), 'Native assertions found; inspect credit-lessons.log'
        spec = importlib.util.spec_from_file_location('lesson_validate', ROOT / 'Examples/Microeconomics/validate.py')
        lesson_validate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(lesson_validate)
        with (out / 'credited-lessons-validation.log').open('w') as log, contextlib.redirect_stdout(log):
            lesson_validate.validate(credited)
        receipt['creditedLessons'] = {}
        for path in DELIVERED:
            stem = Path(path).stem
            new = credited / (stem + '.graphink')
            run([sys.executable, checker, new], out / (stem + '-opc.log'))
            with zipfile.ZipFile(originals_dir / (stem + '.graphink')) as a, zipfile.ZipFile(new) as b:
                # The pale note keeps its text but changes color, so it is compared by ID like the relabeled labels.
                before, found_before = without_credit(a.read('contents.xml'), CREDITS[stem], [*RELABELS[stem].keys(), PALE_NOTE])
                after, found_after = without_credit(b.read('contents.xml'), CREDITS[stem], [*RELABELS[stem].values(), PALE_NOTE])
                (out / (stem + '-contents.xml')).write_bytes(b.read('contents.xml'))
                names = (sorted(a.namelist()), sorted(b.namelist()))
            assert found_before == 0 and found_after == 1, f'{stem}: expected one new credit label'
            assert before == after, f'{stem}: contents.xml differs from the original beyond the credit label and relabels'
            assert names[0] == names[1], f'{stem}: package parts changed'
            run(['xmllint', '--noout', '--relaxng', ROOT / 'GraphSketcher/Model/XML/GraphSketcher.rng', out / (stem + '-contents.xml')], out / (stem + '-schema.log'))
            receipt['creditedLessons'][stem] = {'originalSHA256': PRE_CREDIT_SHA256[stem + '.graphink'], 'creditedSHA256': digest(new),
                                                'credit': CREDITS[stem], 'relabels': RELABELS[stem], 'contentsEqualExceptCreditAndRelabels': True}
        receipt['checkerCommands'] = []
        receipt['schemaCommands'] = []
        for stem in STEMS:
            path = artifacts / (stem + '.graphink')
            command = [sys.executable, checker, path]
            receipt['checkerCommands'].append(list(map(str, command)))
            run(command, out / (stem + '-opc.log'))
            xml = out / (stem + '-contents.xml')
            with zipfile.ZipFile(path) as package:
                xml.write_bytes(package.read('contents.xml'))
            command = ['xmllint', '--noout', '--relaxng', ROOT / 'GraphSketcher/Model/XML/GraphSketcher.rng', xml]
            receipt['schemaCommands'].append(list(map(str, command)))
            run(command, out / (stem + '-schema.log'))
        receipt['keptTemplates'] = {}
        for stem, path in KEPT_TEMPLATES.items():
            with zipfile.ZipFile(ROOT / path) as kept, zipfile.ZipFile(artifacts / (stem + '.graphink')) as fresh:
                # The kept file may predate the current credit and notation: compare whichever applies.
                kept_xml = kept.read('contents.xml')
                kept_texts = {label_text(l) for l in ET.fromstring(kept_xml).find(NS + 'graph').findall(NS + 'label')}
                old_texts = [t for t in RELABELS[stem] if t in kept_texts] or list(RELABELS[stem].values())
                old, new = without_credit(kept_xml, None, old_texts), without_credit(fresh.read('contents.xml'), CREDITS[stem], RELABELS[stem].values())
                assert old[1] == new[1] == 1 and old == new, f'{path}: kept template differs from its regenerated contents beyond the credit'
                (out / (stem + '-kept-contents.xml')).write_bytes(kept.read('contents.xml'))
            run([sys.executable, checker, ROOT / path], out / (stem + '-kept-opc.log'))
            run(['xmllint', '--noout', '--relaxng', ROOT / 'GraphSketcher/Model/XML/GraphSketcher.rng', out / (stem + '-kept-contents.xml')], out / (stem + '-kept-schema.log'))
            receipt['keptTemplates'][path] = {'sha256': digest(ROOT / path), 'contentsEqualToRegeneratedExceptCredit': True}
        receipt['artifactSHA256'] = {p.name: digest(p) for p in sorted(artifacts.iterdir()) if p.is_file()}
        receipt['creditedLessonArtifactSHA256'] = {p.name: digest(p) for p in sorted(credited.iterdir()) if p.is_file()}
        receipt['passed'] = True
    except Exception as exc:
        (out / 'error.log').write_text(str(exc) + '\n')
        raise
    finally:
        receipt['originalsAfter'] = {p: digest(ROOT / p) for p in originals}
        receipt['originalsUnchanged'] = bool(originals) and receipt['originalsAfter'] == originals
        receipt['deliveredLessonsUnchanged'] = receipt.get('deliveredLessonsBefore') == {p: digest(ROOT / p) for p in DELIVERED}
        receipt['keptTemplatesUnchanged'] = receipt.get('keptTemplatesBefore') == {p: digest(ROOT / p) for p in KEPT_TEMPLATES.values()}
        if not (receipt['originalsUnchanged'] and receipt['deliveredLessonsUnchanged'] and receipt['keptTemplatesUnchanged']):
            receipt['passed'] = False
        (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    assert receipt['originalsUnchanged'], 'Original sample hashes changed; no restore attempted; inspect ' + str(out / 'receipt.json')
    assert receipt['deliveredLessonsUnchanged'], 'Delivered lesson bytes changed; inspect ' + str(out / 'receipt.json')
    assert receipt['keptTemplatesUnchanged'], 'Kept template bytes changed; inspect ' + str(out / 'receipt.json')
    print('PASS OPC catalog generation; evidence: ' + str(out))


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, subprocess.SubprocessError, zipfile.BadZipFile, KeyError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        sys.exit(1)
