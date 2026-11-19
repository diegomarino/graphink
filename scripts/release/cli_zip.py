#!/usr/bin/env python3
"""Has the command-line tool changed since the previous release? Compares two graphink-cli.zip by content.

Every release attaches graphink-cli.zip, but the Homebrew cask graphink-cli moves only when the tool
really changed (the binary or the frameworks it bundles), so `brew upgrade` offers nothing otherwise.
The zip bytes always differ (timestamps, signatures, version numbers), so each file is normalized first:

- code signatures and AppleDouble files are left out (_CodeSignature/, __MACOSX/, and in Mach-O files the signature blob, the load
  command that points to it and the __LINKEDIT sizes that include it);
- in Mach-O files, LC_UUID is zeroed and the embedded Info.plist (__TEXT,__info_plist) is compared
  without its version keys;
- Info.plist files are compared without their version keys (VERSION_KEYS);
- everything else byte for byte.

    cli_zip.py manifest ZIP            the normalized manifest (JSON: path -> sha256)
    cli_zip.py compare NEW OLD         print "changed" or "unchanged" and the paths that differ;
                                       exit 0 either way, 1 on an unreadable zip
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


def normalized_plist(data):
    info = plistlib.loads(data)
    for key in VERSION_KEYS:
        info.pop(key, None)
    return plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=True)


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
    except (OSError, zipfile.BadZipFile, plistlib.InvalidFileException, struct.error) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
