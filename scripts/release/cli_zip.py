#!/usr/bin/env python3
"""Has the command-line tool changed? Compares two graphink-cli.zip by content.

Every release attaches graphink-cli.zip, but the Homebrew cask graphink-cli moves only when the tool
really changed against the zip the cask points to (the binary or the frameworks it bundles), so `brew upgrade` offers nothing otherwise.
The zip bytes always differ (timestamps, signatures, version numbers), so each file is normalized first:

- AppleDouble files and bundle seals are left out (__MACOSX/, _CodeSignature/);
- in Mach-O files, the signature blob, the load command that points to it and the __LINKEDIT sizes
  that include it are left out of the content, and the signature is compared as a summary instead
  (signature_summary: identifier, Team ID, CodeDirectory flags such as adhoc and runtime, requirements,
  entitlements and the signing certificates' names; not the hashes, CMS signature or timestamp), so a
  switch from ad-hoc to Developer ID or a changed entitlement counts as a change;
- in Mach-O files, LC_UUID is zeroed and the embedded Info.plist (__TEXT,__info_plist) is compared
  without its version keys;
- Info.plist files are compared without their version keys (VERSION_KEYS);
- everything else byte for byte.

    cli_zip.py manifest ZIP            the normalized manifest (JSON: path -> sha256; for every Mach-O
                                       also "PATH (signature)" -> its signature summary)
    cli_zip.py compare NEW OLD         print "changed" or "unchanged" and the paths that differ;
                                       exit 0 either way, 1 (one "error:" line) on any failure
"""
import argparse
import hashlib
import json
import plistlib
import struct
import sys
import zipfile

VERSION_KEYS = ('CFBundleShortVersionString', 'CFBundleVersion', 'BuildMachineOSBuild')
MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64, LC_UUID, LC_CODE_SIGNATURE = 0x19, 0x1B, 0x1D
# Code signature blobs (big-endian; xnu osfmk/kern/cs_blobs.h).
SUPERBLOB, CODEDIRECTORY, REQUIREMENTS, ENTITLEMENTS = 0xFADE0CC0, 0xFADE0C02, 0xFADE0C01, 0xFADE7171
SLOT_CODEDIRECTORY, SLOT_REQUIREMENTS, SLOT_ENTITLEMENTS, SLOT_CMS = 0, 2, 5, 0x10000
CS_FLAGS = {0x2: 'adhoc', 0x100: 'hard', 0x200: 'kill', 0x800: 'restrict', 0x1000: 'enforcement',
            0x2000: 'library-validation', 0x10000: 'runtime', 0x20000: 'linker-signed'}
COMMON_NAME = bytes.fromhex('550403')  # OID 2.5.4.3


class FormatError(Exception):
    pass


def normalized_plist(data):
    info = plistlib.loads(data)
    for key in VERSION_KEYS:
        info.pop(key, None)
    return plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=True)


def der(data, offset):
    """(tag, content, end) of the DER element at offset. codesign writes the CMS in BER, so an
    indefinite length (0x80, constructed elements only) runs to its end-of-contents octets."""
    tag, length = data[offset], data[offset + 1]
    offset += 2
    if length == 0x80:
        start = offset
        while data[offset:offset + 2] != b'\0\0':
            if offset >= len(data):
                raise FormatError('unterminated BER element')
            offset = der(data, offset)[2]
        return tag, data[start:offset], offset + 2
    if length & 0x80:
        size = length & 0x7F
        if not 1 <= size <= 4:
            raise FormatError('unsupported DER length')
        length = int.from_bytes(data[offset:offset + size], 'big')
        offset += size
    if offset + length > len(data):
        raise FormatError('truncated DER element')
    return tag, data[offset:offset + length], offset + length


def der_children(data):
    offset, children = 0, []
    while offset < len(data):
        tag, content, offset = der(data, offset)
        children.append((tag, content))
    return children


def certificate_names(cms):
    """The subject common names of the certificates in a CMS SignedData, in the order it lists them.

    Only the SignedData certificates count: a timestamp token sits in an unsigned attribute of the
    signer, so its own certificates and time are never read."""
    if not cms:
        return []
    _, content_info, _ = der(cms, 0)
    explicit = der_children(content_info)[1][1]  # [0] EXPLICIT SignedData
    signed_data = der_children(der(explicit, 0)[1])
    names = []
    for tag, certificates in signed_data:
        if tag != 0xA0:  # [0] IMPLICIT certificates
            continue
        for _, certificate in der_children(certificates):
            tbs = der_children(der_children(certificate)[0][1])
            fields = tbs[1:] if tbs[0][0] == 0xA0 else tbs  # skip the [0] version
            subject = fields[4][1]  # serial, signature, issuer, validity, subject
            for _, rdn in der_children(subject):
                for _, attribute in der_children(rdn):
                    (_, oid), (_, value) = der_children(attribute)[:2]
                    if oid == COMMON_NAME:
                        names.append(value.decode())
    return names


def signature_summary(signature):
    """What a code signature says, without what changes on every signing (hashes, CMS, timestamp)."""
    magic, _, count = struct.unpack_from('>3I', signature, 0)
    if magic != SUPERBLOB:
        raise FormatError('the code signature is not a SuperBlob')
    slots = {}
    for index in range(count):
        slot, offset = struct.unpack_from('>2I', signature, 12 + 8 * index)
        blob_magic, length = struct.unpack_from('>2I', signature, offset)
        slots[slot] = (blob_magic, signature[offset:offset + length])
    if slots.get(SLOT_CODEDIRECTORY, (None,))[0] != CODEDIRECTORY:
        raise FormatError('the code signature has no CodeDirectory')
    directory = slots[SLOT_CODEDIRECTORY][1]
    version, flags, _, ident = struct.unpack_from('>4I', directory, 8)
    team = ''
    if version >= 0x20200:
        team_offset = struct.unpack_from('>I', directory, 48)[0]
        if team_offset:
            team = directory[team_offset:directory.index(b'\0', team_offset)].decode()
    summary = {
        'identifier': directory[ident:directory.index(b'\0', ident)].decode(),
        'team': team,
        'flags': (','.join(name for bit, name in sorted(CS_FLAGS.items()) if flags & bit) or 'none') + f' (0x{flags:x})',
        'requirements': '', 'entitlements': None, 'certificates': [],
    }
    if slots.get(SLOT_REQUIREMENTS, (None,))[0] == REQUIREMENTS:
        summary['requirements'] = hashlib.sha256(slots[SLOT_REQUIREMENTS][1]).hexdigest()
    if slots.get(SLOT_ENTITLEMENTS, (None,))[0] == ENTITLEMENTS:
        entitlements = plistlib.loads(slots[SLOT_ENTITLEMENTS][1][8:])
        summary['entitlements'] = plistlib.dumps(entitlements, fmt=plistlib.FMT_XML, sort_keys=True).decode()
    if SLOT_CMS in slots:
        summary['certificates'] = certificate_names(slots[SLOT_CMS][1][8:])
    return summary


def macho_signature(data):
    """The signature summary of a thin 64-bit Mach-O, or None when it is not signed."""
    ncmds = struct.unpack_from('<I', data, 16)[0]
    offset = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<2I', data, offset)
        if cmd == LC_CODE_SIGNATURE:
            start, length = struct.unpack_from('<2I', data, offset + 8)
            return signature_summary(data[start:start + length])
        offset += size
    return None


def normalized_macho(data):
    """A thin 64-bit Mach-O without its signature, UUID and the version of its embedded Info.plist."""
    out = bytearray(data)
    _, _, _, _, ncmds, _, _, _ = struct.unpack_from('<8I', data, 0)
    offset, end, plist = 32, len(data), b''
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<2I', data, offset)
        if cmd == LC_UUID:
            out[offset + 8:offset + 24] = bytes(16)
        elif cmd == LC_CODE_SIGNATURE:
            end = struct.unpack_from('<I', data, offset + 8)[0]
            out[offset:offset + size] = bytes(size)
        elif cmd == LC_SEGMENT_64:
            name = data[offset + 8:offset + 24].rstrip(b'\0')
            if name == b'__LINKEDIT':
                out[offset + 32:offset + 40] = bytes(8)  # vmsize
                out[offset + 48:offset + 56] = bytes(8)  # filesize
            nsects = struct.unpack_from('<I', data, offset + 64)[0]
            for index in range(nsects):
                section = offset + 72 + index * 80
                if name == b'__TEXT' and data[section:section + 16].rstrip(b'\0') == b'__info_plist':
                    length, start = struct.unpack_from('<QI', data, section + 40)
                    plist = normalized_plist(bytes(data[start:start + length]))
                    out[start:start + length] = bytes(length)
                    out[section + 40:section + 48] = bytes(8)
        offset += size
    return bytes(out[:end]) + plist


def normalized(path, data):
    if '/_CodeSignature/' in f'/{path}' or path.startswith('__MACOSX/'):
        return None
    if data[:4] == struct.pack('<I', MH_MAGIC_64):
        return normalized_macho(data)
    if path.endswith('Info.plist'):
        return normalized_plist(data)
    return data


def manifest(source):
    """{path: sha256 of the normalized file} for every file (and symbolic link target) in a zip."""
    result = {}
    with zipfile.ZipFile(source) as archive:
        for entry in archive.infolist():
            if entry.is_dir():
                continue
            data = archive.read(entry)
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:  # a symbolic link stores its target
                result[entry.filename] = 'link:' + data.decode()
                continue
            content = normalized(entry.filename, data)
            if content is not None:
                result[entry.filename] = hashlib.sha256(content).hexdigest()
            if data[:4] == struct.pack('<I', MH_MAGIC_64):
                result[f'{entry.filename} (signature)'] = json.dumps(macho_signature(data), sort_keys=True)
    return result


def compare(new, old):
    """(changed?, sorted differing paths)."""
    a, b = manifest(new), manifest(old)
    differing = sorted(path for path in a.keys() | b.keys() if a.get(path) != b.get(path))
    return bool(differing), differing


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('manifest').add_argument('zip')
    pair = sub.add_parser('compare')
    pair.add_argument('new')
    pair.add_argument('old')
    args = parser.parse_args(argv)
    try:
        if args.command == 'manifest':
            print(json.dumps(manifest(args.zip), indent=2, sort_keys=True))
        else:
            changed, differing = compare(args.new, args.old)
            print('changed' if changed else 'unchanged')
            for path in differing:
                print(path, file=sys.stderr)
    except Exception as error:  # any failure is one line and exit 1, never a guess at "changed"
        print(f'error: {type(error).__name__}: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
