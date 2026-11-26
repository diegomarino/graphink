#!/usr/bin/env python3
"""Independent restricted Graphink OPC v1 structural/ZIP checker; stdlib + xmllint."""
import argparse
import base64
import binascii
import collections
import hashlib
import io
import json
import math
from pathlib import Path
import re
import struct
import sys
import subprocess
import tempfile
import warnings
import zipfile
import zlib
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
G = 'urn:graphink:document:1'
NATIVE = 'http://www.omnigroup.com/namespace/OmniGraphSketcher/v1'
RELTYPE = 'application/vnd.openxmlformats-package.relationships+xml'
TYPES = {'/graphink/document.xml': 'application/vnd.graphink.document+xml',
         '/contents.xml': 'application/vnd.graphink.native-graph+xml'}
MEMBERS = ['[Content_Types].xml', '_rels/.rels', 'graphink/document.xml',
           'graphink/_rels/document.xml.rels', 'contents.xml']
MAX_PART, MAX_TOTAL = 64 * 1024 * 1024, 128 * 1024 * 1024
DEFAULTS_FEATURE, EQUATIONS_FEATURE = 'creation-defaults-v1', 'equation-lines-v1'
FAMILIES = {'linear', 'square', 'cube', 'sine', 'gaussian', 'logistic'}
DECIMAL = re.compile(r'[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?')


class Refusal(Exception):
    def __init__(self, message, kind='malformed'):
        super().__init__(message)
        self.kind = kind


def need(ok, message, kind='malformed'):
    if not ok:
        raise Refusal(message, kind)


def scan_zip(data):
    """Read actual central/local records independently of zipfile and product code."""
    need(22 <= len(data) <= MAX_TOTAL, 'Archive size outside profile limits', 'unsupported')
    need(data[-22:-18] == b'PK\x05\x06', 'Expected terminal EOCD without archive comment')
    _, disk, cd_disk, on_disk, count, cd_size, cd_offset, comment = struct.unpack_from('<4s4H2LH', data, len(data)-22)
    need(disk == cd_disk == comment == 0 and on_disk == count, 'Split/commented archive unsupported', 'unsupported')
    need(count != 65535 and cd_size != 0xffffffff and cd_offset != 0xffffffff, 'ZIP64 unsupported', 'unsupported')
    need(count in (5, 6), 'Profile requires exactly five or six entries', 'unsupported')
    need(cd_offset + cd_size == len(data)-22, 'Central directory extent mismatch')
    records, names, central_metadata, offset, total = [], set(), [], cd_offset, 0
    for _ in range(count):
        need(offset + 46 <= len(data)-22, 'Truncated central header')
        rec = struct.unpack_from('<4s6H3L5H2L', data, offset)
        sig, made, version, flags, method, time, date, crc, packed, size, nl, el, cl, disk, internal, external, local = rec
        need(sig == b'PK\x01\x02', 'Bad central header signature')
        need(offset + 46 + nl + el + cl <= cd_offset + cd_size, 'Central variable fields out of bounds')
        raw_name = data[offset+46:offset+46+nl]
        need(raw_name.isascii() and b'\0' not in raw_name, 'Non-ASCII/NUL ZIP name unsupported', 'unsupported')
        name = raw_name.decode('ascii')
        need(name.lower() not in names, 'Duplicate or OPC-equivalent ZIP names')
        names.add(name.lower())
        need(name in MEMBERS + ['preview.pdf'], 'Unknown/noncanonical part unsupported: ' + name, 'unsupported')
        need(method in (0, 8) and flags == 0 and el == cl == disk == 0, 'Unsupported compression/flags/extra/comment/disk', 'unsupported')
        need(version in ((10, 20) if method == 0 else (20,)), 'Unsupported extraction version', 'unsupported')
        # Made-by low byte is producer metadata, not an extraction-feature gate.
        need(made >> 8 == 0 and external == 0, 'Producer metadata must be MS-DOS with zero external attributes')
        need(size <= MAX_PART and packed <= MAX_TOTAL, 'Part exceeds reader limit', 'unsupported')
        total += size
        need(total <= MAX_TOTAL, 'Total decoded size exceeds reader limit', 'unsupported')
        records.append((name, raw_name, version, flags, method, time, date, crc, packed, size, local))
        central_metadata.extend([offset+5, *range(offset+38, offset+42)])
        offset += 46 + nl + el + cl
    need(offset == cd_offset + cd_size, 'Unexpected central directory bytes')
    need(set(r[0] for r in records) == set(MEMBERS) | ({'preview.pdf'} if count == 6 else set()), 'Missing required member')
    blobs, cursor = {}, 0
    for name, raw_name, version, flags, method, time, date, crc, packed, size, local in sorted(records, key=lambda r: r[-1]):
        need(local == cursor and local + 30 <= cd_offset, 'Local offset/gap/overlap mismatch')
        sig, lv, lf, lm, lt, ld, lc, lp, ls, nl, el = struct.unpack_from('<4s5H3L2H', data, local)
        need(sig == b'PK\x03\x04', 'Bad local signature')
        need((lv, lf, lm, lt, ld, lc, lp, ls) == (version, flags, method, time, date, crc, packed, size), 'Local/central record disagreement')
        need(el == 0 and data[local+30:local+30+nl] == raw_name, 'Local name/extra mismatch')
        start, end = local + 30 + nl, local + 30 + nl + packed
        need(end <= cd_offset, 'Compressed part extends beyond local area')
        compressed = data[start:end]
        try:
            if method == 0:
                decoded = compressed
            else:
                inflater = zlib.decompressobj(-15)
                decoded = inflater.decompress(compressed, size+1)
                need(inflater.eof and not inflater.unused_data and not inflater.unconsumed_tail, 'Invalid/oversized Deflate stream')
        except zlib.error as exc:
            raise Refusal('Invalid Deflate stream: ' + str(exc)) from exc
        need(len(decoded) == size and binascii.crc32(decoded) & 0xffffffff == crc, 'Uncompressed size or CRC mismatch')
        blobs[name] = decoded
        cursor = end
    need(cursor == cd_offset, 'Unaccounted local bytes/data descriptor')
    return blobs, set(central_metadata)


def xml(data):
    need(not re.search(br'<!\s*(?:DOCTYPE|ENTITY)\b', data, re.I), 'DTD/entities outside profile', 'unsupported')
    try:
        return ET.fromstring(data)
    except ET.ParseError as exc:
        raise Refusal('Malformed XML: ' + str(exc)) from exc


def attrs(element, allowed, required=()):
    need(not (set(element.attrib) - set(allowed)), 'Unknown attributes: ' + element.tag, 'unsupported')
    need(set(required) <= set(element.attrib), 'Missing required attributes: ' + element.tag)
    need(not (element.text or '').strip(), 'Unexpected element text: ' + element.tag, 'unsupported')
    need(all(not (child.tail or '').strip() for child in element), 'Unexpected mixed text', 'unsupported')


def resolve(source, target):
    need(bool(target), 'Empty relationship target')
    need(target.isascii() and not any(c in target for c in '%\\?#:') and not target.startswith('/') and '//' not in target,
         'URI outside self-contained relative-path profile', 'unsupported')
    stack = source.strip('/').split('/')[:-1] if source != '/' else []
    for segment in target.split('/'):
        if segment == '.':
            continue
        if segment == '..':
            need(bool(stack), 'Target escapes package root')
            stack.pop()
        else:
            need(segment and not segment.endswith('.'), 'Invalid OPC path segment')
            stack.append(segment)
    return '/' + '/'.join(stack)


def relationships(data, source, expected):
    root = xml(data)
    need(root.tag == '{'+REL+'}Relationships', 'Wrong Relationships namespace/root')
    attrs(root, [])
    ids, found = set(), {}
    for child in root:
        need(child.tag == '{'+REL+'}Relationship', 'Unknown relationship element', 'unsupported')
        attrs(child, ['Id', 'Type', 'Target', 'TargetMode'], ['Id', 'Type', 'Target'])
        need(not len(child), 'Relationship cannot have children', 'unsupported')
        need(child.get('TargetMode', 'Internal') == 'Internal', 'External target unsupported', 'unsupported')
        key, role = child.get('Id'), child.get('Type')
        need(key and key not in ids and role not in found, 'Duplicate/empty relationship identity or role')
        ids.add(key)
        need(role in expected, 'Unknown relationship role', 'unsupported')
        found[role] = resolve(source, child.get('Target')).lower()
    need(found == expected, 'Missing or wrongly resolved relationship')


def color(element):
    need(element.tag == 'color' and not len(element) and not (element.text or '').strip(), 'Native color must be an unqualified empty color element', 'unsupported')
    keys = set('w r g b h s v c m y k a space catalog name archive tiff png'.split())
    need(set(element.attrib) <= keys, 'Unknown native color attribute', 'unsupported')
    for key in set(element.attrib) & set('w r g b h s v c m y k a'.split()):
        try:
            value = float(element.get(key))
        except ValueError as exc:
            raise Refusal('Invalid color number') from exc
        need(math.isfinite(value), 'Nonfinite color component')
        if key == 'a':
            need(0 <= value <= 1, 'Invalid color alpha')
    for key in ('archive', 'tiff', 'png'):
        if key in element.attrib:
            try:
                need(bool(base64.b64decode(element.get(key), validate=True)), 'Empty encoded native color data')
            except (ValueError, binascii.Error) as exc:
                raise Refusal('Invalid color base64') from exc
    present = set(element.attrib)
    representations = [{'w'}, {'r', 'g', 'b'}, {'h', 's', 'v'}, {'h', 's', 'b'}, {'c', 'm', 'y', 'k'}, {'catalog', 'name'}, {'archive'}, {'tiff'}, {'png'}]
    need(any(group <= present for group in representations), 'Incomplete native color representation')


def control(data):
    root = xml(data)
    need(root.tag == '{'+G+'}document', 'Unsupported Graphink control namespace/root', 'unsupported')
    attrs(root, ['version', 'required-features'], ['version', 'required-features'])
    need(root.get('version') == '1', 'Unsupported document version', 'unsupported')
    features = root.get('required-features').split()
    need(len(features) == len(set(features)), 'Duplicate required feature')
    need(set(features) <= {DEFAULTS_FEATURE, EQUATIONS_FEATURE}, 'Unsupported required feature', 'unsupported')
    children = list(root)
    need(children and children[0].tag == '{'+G+'}payload', 'Missing payload declaration')
    payload = children[0]
    attrs(payload, ['format', 'version'], ['format', 'version'])
    need(not len(payload), 'Unknown payload declaration content', 'unsupported')
    need(payload.get('format') == 'native-graph-xml' and payload.get('version') == '1', 'Unsupported payload format/version', 'unsupported')
    need(len(children) <= 2 and all(c.tag == '{'+G+'}creation-defaults' for c in children[1:]), 'Unknown control elements', 'unsupported')
    need((DEFAULTS_FEATURE in features) == (len(children) == 2), 'Defaults feature/block mismatch')
    if len(children) == 2:
        defaults = children[1]
        attrs(defaults, ['version', 'font-name'], ['version'])
        need(defaults.get('version') == '1', 'Unsupported defaults version', 'unsupported')
        need('font-name' not in defaults.attrib or bool(defaults.get('font-name').strip()), 'Blank font face')
        names = [c.tag for c in defaults]
        order = ['{'+G+'}'+s+'-color' for s in ('line', 'fill', 'text')]
        need(len(names) == len(set(names)) and all(n in order for n in names), 'Unknown/duplicate defaults color', 'unsupported')
        need(names == sorted(names, key=order.index), 'Noncanonical defaults child order')
        for wrapper in defaults:
            attrs(wrapper, [])
            need(len(wrapper) == 1, 'Color wrapper must contain one native color')
            color(wrapper[0])
    return set(features)


def equation_lines(graph):
    """Count the graph's equation lines, refusing an invalid one (graphink.md section 4)."""
    count = 0
    # v1 and v2 must each name exactly one graph object, and it must be a vertex.
    ids = collections.Counter(child.get('id') for child in graph if child.get('id') is not None)
    vertices = {child.get('id') for child in graph if child.tag == '{'+NATIVE+'}vertex'}
    for line in graph.findall('{'+NATIVE+'}line'):
        if line.get('class') != 'equation':
            continue
        v1, v2 = line.get('v1'), line.get('v2')
        need(v1 != v2 and all(v in vertices and ids[v] == 1 for v in (v1, v2)), 'Equation line needs two distinct vertices as endpoints')
        equations = [child for child in line if child.tag == '{'+NATIVE+'}equation']
        need(len(equations) == 1 and not len(equations[0]), 'Equation line needs exactly one equation')
        equation = equations[0]
        attrs(equation, ['family', 'a', 'b', 'c'], ['family', 'a', 'b', 'c'])
        need(equation.get('family') in FAMILIES, 'Unknown equation family')
        for key in 'abc':
            value = equation.get(key)
            need(DECIMAL.fullmatch(value) is not None and math.isfinite(float(value)), 'Equation parameters must be finite numbers')
        count += 1
    return count


def validate(data, expected_payload=None):
    blobs, metadata = scan_zip(data)
    has_preview = 'preview.pdf' in blobs
    root = xml(blobs['[Content_Types].xml'])
    need(root.tag == '{'+CT+'}Types', 'Wrong content-types namespace/root')
    attrs(root, [])
    defaults, overrides = {}, {}
    for child in root:
        if child.tag == '{'+CT+'}Default':
            attrs(child, ['Extension', 'ContentType'], ['Extension', 'ContentType'])
            key = child.get('Extension').lower()
            need(key not in defaults, 'Duplicate Default extension')
            defaults[key] = child.get('ContentType')
        elif child.tag == '{'+CT+'}Override':
            attrs(child, ['PartName', 'ContentType'], ['PartName', 'ContentType'])
            key = child.get('PartName').lower()
            need(key not in overrides, 'Duplicate/equivalent Override name')
            overrides[key] = child.get('ContentType')
        else:
            raise Refusal('Unknown content-types element', 'unsupported')
        need(not len(child), 'Content-types mapping cannot have children', 'unsupported')
    need(defaults == {'rels': RELTYPE} and overrides == TYPES | ({'/preview.pdf': 'application/pdf'} if has_preview else {}), 'Unsupported content-type mappings', 'unsupported')
    role = 'urn:graphink:relationships:'
    relationships(blobs['_rels/.rels'], '/', {role+'document': '/graphink/document.xml'})
    relationships(blobs['graphink/_rels/document.xml.rels'], '/graphink/document.xml', {role+'graph': '/contents.xml'} | ({role+'preview': '/preview.pdf'} if has_preview else {}))
    features = control(blobs['graphink/document.xml'])
    graph = xml(blobs['contents.xml'])
    need(graph.tag == '{'+NATIVE+'}document', 'Unsupported native payload namespace/root', 'unsupported')
    need(len(graph.findall('{'+NATIVE+'}graph')) == 1 and not graph.findall('{'+NATIVE+'}model'), 'Expected exactly one native graph, no pasteboard model')
    need((EQUATIONS_FEATURE in features) == (equation_lines(graph.find('{'+NATIVE+'}graph')) > 0), 'Equation lines/feature mismatch')
    if expected_payload is not None:
        need(blobs['contents.xml'] == expected_payload, 'Native payload bytes changed')
    if has_preview:
        need(blobs['preview.pdf'].startswith(b'%PDF-'), 'Preview is not a PDF')
    with tempfile.TemporaryDirectory(prefix='graphink-opc-schema-') as folder:
        for member, schema in [(MEMBERS[0], HERE/'schemas/opc-contentTypes.xsd'), (MEMBERS[1], HERE/'schemas/opc-relationships.xsd'),
                               (MEMBERS[3], HERE/'schemas/opc-relationships.xsd'), (MEMBERS[2], HERE/'schemas/graphink-document-v1.xsd'),
                               (MEMBERS[4], HERE.parents[1]/'GraphSketcher/Model/XML/GraphSketcher.rng')]:
            path = Path(folder)/'part.xml'
            path.write_bytes(blobs[member])
            flag = '--relaxng' if schema.suffix == '.rng' else '--schema'
            proc = subprocess.run(['xmllint', '--nonet', '--noout', flag, str(schema), str(path)], capture_output=True, text=True)
            need(proc.returncode == 0, 'Schema refused ' + member + ': ' + proc.stderr.strip())
    return blobs, metadata


def pack(parts):
    """Documentation prototype using Python ZIP, never a production exporter."""
    stream = io.BytesIO()
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', UserWarning)
        with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_DEFLATED, allowZip64=False) as archive:
            for name, content in parts:
                info = zipfile.ZipInfo(name, (2026, 11, 13, 0, 0, 0))
                info.create_system, info.create_version, info.extract_version = 0, 20, 20
                archive.writestr(info, content, compress_type=zipfile.ZIP_DEFLATED)
    data = bytearray(stream.getvalue())
    # Python supplies external attributes when zero; clear only those central fields.
    central = struct.unpack_from('<L', data, len(data)-6)[0]
    for _ in parts:
        struct.pack_into('<L', data, central+38, 0)
        nl, el, cl = struct.unpack_from('<3H', data, central+28)
        central += 46 + nl + el + cl
    return bytes(data)


def fixture_parts():
    root = HERE/'fixtures/opc-v1/parts'
    return [(n, (root/n).read_bytes()) for n in MEMBERS]


def self_check():
    parts = fixture_parts()
    good = pack(parts)
    validate(good, (HERE/'minimal.graphink').read_bytes())
    no_defaults = xml(dict(parts)[MEMBERS[2]])
    no_defaults.remove(no_defaults[1])
    no_defaults.set('required-features', '')
    validate(pack([(n, ET.tostring(no_defaults) if n == MEMBERS[2] else b) for n, b in parts]))
    partial_defaults = xml(dict(parts)[MEMBERS[2]])
    for child in list(partial_defaults[1]):
        partial_defaults[1].remove(child)
    validate(pack([(n, ET.tostring(partial_defaults) if n == MEMBERS[2] else b) for n, b in parts]))
    # Equation lines (in memory only; the fixture files are unchanged).
    with_equation = dict(parts)
    line = b'<line id="e5" class="connect" method="straight"><vertices ids="e3 e4"/></line>'
    with_equation[MEMBERS[4]] = with_equation[MEMBERS[4]].replace(line, line + b'\n    <line id="e8" class="equation" v1="e3" v2="e4"><equation family="sine" a="0" b="5" c="2"/></line>')
    with_equation[MEMBERS[2]] = with_equation[MEMBERS[2]].replace(b'creation-defaults-v1"', b'creation-defaults-v1 equation-lines-v1"')
    need(with_equation[MEMBERS[2]] != parts[2][1] and with_equation[MEMBERS[4]] != parts[4][1], 'Equation self-check fixture edit')
    validate(pack([(n, with_equation[n]) for n in MEMBERS]))

    def equation_case(member, old, new):
        changed = dict(with_equation)
        need(changed[member].count(old) == 1, 'Equation self-check edit')
        changed[member] = changed[member].replace(old, new)
        return pack([(n, changed[n]) for n in MEMBERS])
    cases = {
        'equation-without-feature': equation_case(MEMBERS[2], b' equation-lines-v1"', b'"'),
        'feature-without-equation': pack([(n, with_equation[MEMBERS[2]] if n == MEMBERS[2] else b) for n, b in parts]),
        'equation-family': equation_case(MEMBERS[4], b'family="sine"', b'family="tangent"'),
        'equation-parameter': equation_case(MEMBERS[4], b' c="2"', b' c="inf"'),
        'equation-missing-parameter': equation_case(MEMBERS[4], b' a="0"', b''),
        'equation-same-endpoints': equation_case(MEMBERS[4], b'v2="e4"', b'v2="e3"'),
        'equation-missing-endpoint': equation_case(MEMBERS[4], b'v2="e4"', b'v2="e99"'),
        'equation-label-endpoint': equation_case(MEMBERS[4], b'v2="e4"', b'v2="e6"'),
        'equation-line-endpoint': equation_case(MEMBERS[4], b'v1="e3"', b'v1="e5"'),
    }
    for name, fn in {
        'document-version': lambda p: [(n, b.replace(b'version="1" required', b'version="2" required') if n == MEMBERS[2] else b) for n, b in p],
        'required-feature': lambda p: [(n, b.replace(b'creation-defaults-v1"', b'future-feature"') if n == MEMBERS[2] else b) for n, b in p],
        'optional-control': lambda p: [(n, b.replace(b'<g:payload ', b'<g:unknown/><g:payload ') if n == MEMBERS[2] else b) for n, b in p],
        'unknown-part': lambda p: p + [('extra.bin', b'x')],
        'duplicate-part': lambda p: p + [p[-1]],
        'equivalent-part': lambda p: p + [('CONTENTS.XML', p[-1][1])],
        'escaped-root': lambda p: [(n, b.replace(b'../contents.xml', b'../../contents.xml') if n == MEMBERS[3] else b) for n, b in p],
        'external-target': lambda p: [(n, b.replace(b'../contents.xml', b'https://example.invalid/x') if n == MEMBERS[3] else b) for n, b in p],
        'wrong-namespace': lambda p: [(n, b.replace(REL.encode(), b'urn:wrong') if n == MEMBERS[1] else b) for n, b in p],
    }.items():
        cases[name] = pack(fn(parts))
    _, metadata = scan_zip(good)
    central = min(metadata)-5
    low_zero = bytearray(good)
    offset = central
    for _ in parts:
        low_zero[offset+4] = 0
        nl, el, cl = struct.unpack_from('<3H', low_zero, offset+28)
        offset += 46 + nl + el + cl
    validate(bytes(low_zero), (HERE/'minimal.graphink').read_bytes())
    need(bytes(low_zero) == (HERE/'fixtures/opc-v1/made-low-zero.graphink').read_bytes(), 'Low made-by regression fixture drift')
    need(central+4 not in metadata, 'Normalization must not change made-by low byte')
    needed_too_low = bytearray(good)
    struct.pack_into('<H', needed_too_low, 4, 10)
    struct.pack_into('<H', needed_too_low, central+6, 10)
    cases['deflate-needed-too-low'] = bytes(needed_too_low)
    for name, position, fmt, value in [('external-attributes', central+38, '<L', 1), ('made-by-host', central+5, '<B', 3),
                                     ('local-crc', 14, '<L', 0), ('central-size', central+24, '<L', 1),
                                     ('central-offset', central+42, '<L', 1), ('bit11', central+8, '<H', 2048)]:
        changed = bytearray(good)
        struct.pack_into(fmt, changed, position, value)
        cases[name] = bytes(changed)
    for name, broken in cases.items():
        try:
            validate(broken)
        except Refusal:
            continue
        raise Refusal('Self-check accepted negative case: ' + name)
    return len(cases)


def read_package(path):
    need(path.stat().st_size <= MAX_TOTAL, 'Archive exceeds reader limit', 'unsupported')
    return path.read_bytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog='Examples: check-opc.py fixtures/opc-v1/minimal.graphink --expect-payload minimal.graphink; check-opc.py --self-check; check-opc.py --make-fixture /private/tmp/new.graphink. Exit 0 structural checks; 1 malformed; 2 usage/unsupported. No native color fidelity or app acceptance implied.')
    parser.add_argument('input', nargs='?', type=Path, help='Existing package to read without modification')
    parser.add_argument('--expect-payload', type=Path, help='Require byte-identical contents.xml')
    parser.add_argument('--before-normalization', type=Path, help='Prove only made-by host/external-attribute bytes changed from this ZIP')
    parser.add_argument('--make-fixture', type=Path, help='Create original five-entry documentation prototype at a NEW path')
    parser.add_argument('--self-check', action='store_true', help='Run valid fixture and intentionally invalid header/control/URI cases')
    args = parser.parse_args()
    need(sum([args.input is not None, args.make_fixture is not None, args.self_check]) == 1, 'Choose input, --make-fixture or --self-check', 'unsupported')
    if args.self_check:
        print(json.dumps({'passed': True, 'negativeCasesRefused': self_check(), 'scope': 'structural/profile only'}))
        return
    if args.make_fixture:
        need(not args.make_fixture.exists(), 'Output exists; choose a new path')
        data = pack(fixture_parts())
        validate(data, (HERE/'minimal.graphink').read_bytes())
        with args.make_fixture.open('xb') as out:
            out.write(data)
        path = args.make_fixture
    else:
        path, data = args.input, read_package(args.input)
    blobs, metadata = validate(data, args.expect_payload.read_bytes() if args.expect_payload else None)
    if args.before_normalization:
        before = read_package(args.before_normalization)
        need(len(before) == len(data), 'Normalization changed archive length')
        changed = {i for i, (a, b) in enumerate(zip(before, data)) if a != b}
        need(changed <= metadata, 'Normalization changed bytes outside producer metadata')
    print(json.dumps({'passed': True, 'input': str(path), 'sha256': hashlib.sha256(data).hexdigest(),
                      'parts': {n: hashlib.sha256(b).hexdigest() for n, b in blobs.items()},
                      'scope': 'raw ZIP + standard/profile XML schemas; native color decoding/rendering not verified'}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except Refusal as exc:
        print(json.dumps({'passed': False, 'kind': exc.kind, 'error': str(exc)}), file=sys.stderr)
        raise SystemExit(2 if exc.kind == 'unsupported' else 1)
    except (OSError, subprocess.SubprocessError) as exc:
        print(json.dumps({'passed': False, 'kind': 'prerequisite', 'error': str(exc), 'action': 'Check input paths and existing xmllint availability; see --help'}), file=sys.stderr)
        raise SystemExit(2)
