"""Unit tests for scripts/release/cli_zip.py. Run: python3 -m unittest discover -s scripts/release/tests"""
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


def macho(code=b'\x01' * 32, uuid=b'\xaa' * 16, version='2026.11.0', build='1', signature=b'SIG' * 10):
    """A minimal thin 64-bit Mach-O: __TEXT with __text and __info_plist, LC_UUID, __LINKEDIT and a signature."""
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
            'graphink-cli/Contents/Helpers/_CodeSignature/CodeResources': b'seal ' + binary.get('signature', b'x'),
            'graphink-cli/Contents/Frameworks/OmniBase.framework/Versions/A/Resources/Info.plist':
                plistlib.dumps({'CFBundleIdentifier': 'com.omnigroup.OmniBase', 'CFBundleVersion': binary.get('build', '1')}),
            'graphink-cli/Contents/Resources/StyleFonts/Kalam-Regular.ttf': b'font',
        }

    def test_signatures_uuids_versions_and_dates_do_not_count(self):
        old = self.zip('old.zip', self.tree())
        new = self.zip('new.zip', self.tree(uuid=b'\xbb' * 16, version='2026.12.0', build='2', signature=b'OTHER' * 9), date=(2026, 12, 1, 0, 0, 0))
        self.assertEqual(cli_zip.compare(new, old), (False, []))

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


if __name__ == '__main__':
    unittest.main()
