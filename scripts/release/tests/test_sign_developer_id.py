"""Tests for .github/scripts/sign-developer-id.sh notarize-zip with a stand-in xcrun (no Apple service).
Run: python3 -m unittest discover -s scripts/release/tests"""
import base64
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPT = ROOT / '.github/scripts/sign-developer-id.sh'
# Records its arguments and whether the key existed during the call, then answers like
# `notarytool submit --output-format json` with STUB_STATUS (or fails with STUB_EXIT).
XCRUN = '''#!/bin/sh
printf '%s\\n' "$@" > "$RUNNER_TEMP/xcrun-args"
for argument; do [ "$previous" = --key ] && test -f "$argument" && echo present > "$RUNNER_TEMP/key-during"; previous=$argument; done
[ -n "$STUB_EXIT" ] && { echo '{"message": "network"}'; exit "$STUB_EXIT"; }
printf '{"id": "1", "status": "%s", "message": "Processing complete"}\\n' "$STUB_STATUS"
'''


class NotarizeZip(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.root = pathlib.Path(self.dir.name)
        (self.root / 'bin').mkdir()
        (self.root / 'bin/xcrun').write_text(XCRUN)
        (self.root / 'bin/xcrun').chmod(0o755)
        self.zip = self.root / 'graphink-cli.zip'
        self.zip.write_bytes(b'zip')

    def run_script(self, status='Accepted', exit_code=''):
        env = dict(os.environ, PATH=f'{self.root / "bin"}:{os.environ["PATH"]}', RUNNER_TEMP=str(self.root),
                   NOTARY_KEY_P8_BASE64=base64.b64encode(b'-----BEGIN PRIVATE KEY-----').decode(),
                   NOTARY_KEY_ID='KEY', NOTARY_ISSUER_ID='ISSUER', STUB_STATUS=status, STUB_EXIT=exit_code)
        result = subprocess.run(['bash', str(SCRIPT), 'notarize-zip', str(self.zip)], cwd=ROOT, env=env,
                                capture_output=True, text=True)
        self.assertEqual((self.root / 'key-during').read_text(), 'present\n')
        self.assertFalse((self.root / 'notary-key.p8').exists(), 'the API key must not stay on disk')
        return result

    def test_accepted_passes_and_asks_for_json(self):
        result = self.run_script('Accepted')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--output-format\njson\n', (self.root / 'xcrun-args').read_text())

    def test_other_statuses_fail(self):
        for status in ('Invalid', 'Rejected', 'In Progress', ''):
            with self.subTest(status=status):
                result = self.run_script(status)
                self.assertEqual(result.returncode, 1)
                self.assertIn('not Accepted', result.stderr)

    def test_failed_submit_fails_and_removes_the_key(self):
        result = self.run_script(exit_code='69')
        self.assertEqual(result.returncode, 1)
        self.assertIn('notarytool submit', result.stderr)


if __name__ == '__main__':
    unittest.main()
