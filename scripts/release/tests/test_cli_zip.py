"""Unit tests for scripts/release/cli_zip.py. Run: python3 -m unittest discover -s scripts/release/tests"""
import contextlib
import io
import pathlib
import plistlib
import struct
import sys
import tempfile
import unittest
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import cli_zip  # noqa: E402


def tlv(tag, *children, indefinite=False):
    """A DER element; indefinite=True writes BER's indefinite length, as codesign does for the CMS."""
    content = b''.join(children)
    if indefinite:
        return bytes([tag, 0x80]) + content + b'\0\0'
    length = len(content)
    encoded = bytes([length]) if length < 0x80 else bytes([0x82]) + length.to_bytes(2, 'big')
    return bytes([tag]) + encoded + content


def certificate(name, serial=1):
    common_name = tlv(0x30, tlv(0x06, bytes.fromhex('550403')), tlv(0x0C, name.encode()))
    subject = tlv(0x30, tlv(0x31, common_name))
    tbs = tlv(0x30, tlv(0xA0, tlv(0x02, b'\x02')), tlv(0x02, bytes([serial])), tlv(0x30), tlv(0x30), tlv(0x30), subject)
    return tlv(0x30, tbs, tlv(0x30), tlv(0x03, b'\0'))


def cms(names, signed=b'signature bytes', timestamp='Timestamp Authority'):
    """A CMS SignedData with these certificates; the signer's timestamp token holds one more certificate."""
    token = tlv(0x30, tlv(0x06, b'\x2a'), tlv(0xA0, tlv(0x30, tlv(0xA0, certificate(timestamp)))))
    signer = tlv(0x30, tlv(0x02, b'\x01'), tlv(0x04, signed), tlv(0xA1, token))
    signed_data = tlv(0x30, tlv(0x02, b'\x01'), tlv(0x31), tlv(0x30, tlv(0x06, b'\x2a')),
                      tlv(0xA0, *(certificate(name, index) for index, name in enumerate(names))), tlv(0x31, signer),
                      indefinite=True)
    return tlv(0x30, tlv(0x06, b'\x2a\x86\x48'), tlv(0xA0, signed_data, indefinite=True), indefinite=True)


def blob(magic, payload):
    return struct.pack('>2I', magic, 8 + len(payload)) + payload


ADHOC = 0x2
RUNTIME = 0x10000


def superblob(identifier='com.diegomarino.Graphink.cli', team='', flags=ADHOC, hashes=b'\x11' * 64,
              entitlements=None, certificates=(), signed=b'signature bytes', timestamp='Timestamp Authority'):
    """A code signature SuperBlob: CodeDirectory (v0x20400), requirements, entitlements, CMS."""
    ident_offset = 88
    team_offset = ident_offset + len(identifier) + 1 if team else 0
    strings = identifier.encode() + b'\0' + (team.encode() + b'\0' if team else b'')
    hash_offset = ident_offset + len(strings)
    fields = struct.pack('>7I4BI', 0x20400, flags, hash_offset, ident_offset, 0, len(hashes) // 32, 0, 32, 2, 0, 12, 0)
    fields += struct.pack('>3I', 0, team_offset, 0) + struct.pack('>4Q', 0, 0, 0, 1)
    directory = blob(0xFADE0C02, fields + strings + hashes)
    parts = [(0, directory), (2, blob(0xFADE0C01, struct.pack('>I', 0)))]
    if entitlements is not None:
        parts.append((5, blob(0xFADE7171, plistlib.dumps(entitlements))))
    parts.append((0x10000, blob(0xFADE0B01, cms(certificates, signed, timestamp) if certificates else b'')))
    offset = 12 + 8 * len(parts)
    index, payload = b'', b''
    for slot, data in parts:
        index += struct.pack('>2I', slot, offset + len(payload))
        payload += data
    return struct.pack('>3I', 0xFADE0CC0, offset + len(payload), len(parts)) + index + payload


DEVELOPER_ID = dict(team='ABCDE12345', flags=RUNTIME, certificates=(
    'Developer ID Application: Diego Marino (ABCDE12345)', 'Developer ID Certification Authority', 'Apple Root CA'))


def macho(code=b'\x01' * 32, uuid=b'\xaa' * 16, version='2026.11.0', build='1', signature=None):
    """A minimal thin 64-bit Mach-O: __TEXT with __text and __info_plist, LC_UUID, __LINKEDIT and a signature."""
    if signature is None:
        signature = superblob()
    plist = plistlib.dumps({'CFBundleIdentifier': 'com.diegomarino.Graphink.cli', 'CFBundleShortVersionString': version, 'CFBundleVersion': build})
    header_size = 32 + (72 + 2 * 80) + 24 + 72 + 16
    text_offset = header_size
    plist_offset = text_offset + len(code)
    linkedit_offset = plist_offset + len(plist)
    signature_offset = linkedit_offset + 8
    total = signature_offset + len(signature)

    def section(name, offset, size):
        return name.ljust(16, b'\0') + b'__TEXT'.ljust(16, b'\0') + struct.pack('<QQIIIIIIII', 0, size, offset, 0, 0, 0, 0, 0, 0, 0)
    text = struct.pack('<2I', 0x19, 72 + 2 * 80) + b'__TEXT'.ljust(16, b'\0') + struct.pack('<QQQQiiII', 0, 0, 0, 0, 5, 5, 2, 0)
    text += section(b'__text', text_offset, len(code)) + section(b'__info_plist', plist_offset, len(plist))
    uuid_command = struct.pack('<2I', 0x1B, 24) + uuid
    linkedit = struct.pack('<2I', 0x19, 72) + b'__LINKEDIT'.ljust(16, b'\0') + struct.pack('<QQQQiiII', 0, total - linkedit_offset, linkedit_offset, total - linkedit_offset, 1, 1, 0, 0)
    code_signature = struct.pack('<4I', 0x1D, 16, signature_offset, len(signature))
    header = struct.pack('<8I', 0xFEEDFACF, 0x0100000C, 0, 2, 4, header_size - 32, 0, 0)
    data = header + text + uuid_command + linkedit + code_signature
    assert len(data) == header_size
    return data + code + plist + b'\0' * 8 + signature


class CliZip(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def zip(self, name, files, date=(2026, 11, 1, 0, 0, 0)):
        path = pathlib.Path(self.dir.name) / name
        with zipfile.ZipFile(path, 'w') as archive:
            for member, data in files.items():
                archive.writestr(zipfile.ZipInfo(member, date), data)
        return path

    def tree(self, **binary):
        return {
            'graphink-cli/Contents/Helpers/graphink': macho(**binary),
            'graphink-cli/Contents/Helpers/_CodeSignature/CodeResources': b'seal ' + binary.get('signature', b'x')[-8:],
            'graphink-cli/Contents/Frameworks/OmniBase.framework/Versions/A/Resources/Info.plist':
                plistlib.dumps({'CFBundleIdentifier': 'com.omnigroup.OmniBase', 'CFBundleVersion': binary.get('build', '1')}),
            'graphink-cli/Contents/Resources/StyleFonts/Kalam-Regular.ttf': b'font',
        }

    def test_signatures_uuids_versions_and_dates_do_not_count(self):
        old = self.zip('old.zip', self.tree())
        new = self.zip('new.zip', self.tree(uuid=b'\xbb' * 16, version='2026.12.0', build='2', signature=superblob(hashes=b'\x22' * 96)), date=(2026, 12, 1, 0, 0, 0))
        self.assertEqual(cli_zip.compare(new, old), (False, []))

    def test_signing_hashes_cms_and_timestamp_do_not_count(self):
        old = self.zip('old.zip', self.tree(signature=superblob(**DEVELOPER_ID)))
        new = self.zip('new.zip', self.tree(signature=superblob(hashes=b'\x33' * 64, signed=b'other bytes', timestamp='Timestamp CA 2', **DEVELOPER_ID)))
        self.assertEqual(cli_zip.compare(new, old), (False, []))

    def test_adhoc_to_developer_id_counts(self):
        old = self.zip('old.zip', self.tree())
        new = self.zip('new.zip', self.tree(signature=superblob(**DEVELOPER_ID)))
        self.assertEqual(cli_zip.compare(new, old), (True, ['graphink-cli/Contents/Helpers/graphink (signature)']))
        summary = cli_zip.macho_signature(macho(signature=superblob(**DEVELOPER_ID)))
        self.assertEqual(summary['team'], 'ABCDE12345')
        self.assertEqual(summary['flags'], 'runtime (0x10000)')
        self.assertEqual(summary['certificates'], list(DEVELOPER_ID['certificates']))
        self.assertEqual(cli_zip.macho_signature(macho())['flags'], 'adhoc (0x2)')

    def test_each_signature_property_counts(self):
        base = cli_zip.macho_signature(macho(signature=superblob(**DEVELOPER_ID)))
        for change in (dict(flags=0), dict(team='ZZZZZ99999'), dict(identifier='com.example.other'),
                       dict(entitlements={'com.apple.security.cs.disable-library-validation': True}),
                       dict(certificates=('Developer ID Application: Someone Else (ABCDE12345)',) + DEVELOPER_ID['certificates'][1:])):
            with self.subTest(change=change):
                self.assertNotEqual(cli_zip.macho_signature(macho(signature=superblob(**{**DEVELOPER_ID, **change}))), base)

    def test_entitlements_count(self):
        old = self.zip('old.zip', self.tree(signature=superblob(entitlements={'com.apple.security.app-sandbox': True})))
        new = self.zip('new.zip', self.tree(signature=superblob(entitlements={'com.apple.security.app-sandbox': True, 'com.apple.security.get-task-allow': True})))
        self.assertEqual(cli_zip.compare(new, old)[1], ['graphink-cli/Contents/Helpers/graphink (signature)'])

    def test_code_counts(self):
        old = self.zip('old.zip', self.tree())
        new = self.zip('new.zip', self.tree(code=b'\x02' * 32))
        self.assertEqual(cli_zip.compare(new, old), (True, ['graphink-cli/Contents/Helpers/graphink']))

    def test_other_files_count(self):
        files = self.tree()
        old = self.zip('old.zip', files)
        files['graphink-cli/Contents/Resources/StyleFonts/Kalam-Regular.ttf'] = b'other font'
        files['graphink-cli/Contents/Frameworks/OmniQuartz.framework/OmniQuartz'] = b'new framework'
        new = self.zip('new.zip', files)
        self.assertEqual(cli_zip.compare(new, old)[1], ['graphink-cli/Contents/Frameworks/OmniQuartz.framework/OmniQuartz',
                                                         'graphink-cli/Contents/Resources/StyleFonts/Kalam-Regular.ttf'])

    def test_embedded_plist_content_other_than_version_counts(self):
        data = macho()
        changed = data.replace(b'com.diegomarino.Graphink.cli', b'com.diegomarino.Graphink.CLI')
        self.assertNotEqual(cli_zip.normalized_macho(data), cli_zip.normalized_macho(changed))

    def test_command_line(self):
        old = self.zip('old.zip', self.tree())
        self.assertEqual(cli_zip.main(['compare', str(old), str(old)]), 0)
        self.assertEqual(cli_zip.main(['compare', str(old), str(pathlib.Path(self.dir.name) / 'missing.zip')]), 1)

    def test_any_failure_is_one_error_line_and_exit_1(self):
        old = self.zip('old.zip', self.tree())
        broken = {
            'bad-signature.zip': self.tree(signature=b'\xfa\xde\x0c\xc0' + b'\0' * 8),
            'bad-plist.zip': {**self.tree(), 'graphink-cli/Contents/Info.plist': b'<plist><dict><key>'},
            'bad-link.zip': None,
        }
        for name, files in broken.items():
            with self.subTest(name=name):
                if files is None:
                    path = pathlib.Path(self.dir.name) / name
                    with zipfile.ZipFile(path, 'w') as archive:
                        info = zipfile.ZipInfo('graphink-cli/link')
                        info.external_attr = 0o120777 << 16
                        archive.writestr(info, b'\xff\xfe')
                else:
                    path = self.zip(name, files)
                stderr = io.StringIO()
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
                    self.assertEqual(cli_zip.main(['compare', str(path), str(old)]), 1)
                self.assertRegex(stderr.getvalue(), r'\Aerror: [^\n]+\n\Z')


if __name__ == '__main__':
    unittest.main()
