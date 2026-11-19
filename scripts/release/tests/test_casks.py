"""Unit tests for scripts/release/casks.py. Run: python3 -m unittest discover -s scripts/release/tests"""
import pathlib
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import casks  # noqa: E402

APP = '''cask "graphink-app" do
  version "2026.11.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/diegomarino/graphink/releases/download/v#{version}/Graphink.dmg"
  app "Graphink.app"
end
'''
CLI = APP.replace('graphink-app', 'graphink-cli').replace('Graphink.dmg', 'graphink-cli.zip').replace('app "Graphink.app"', 'binary "graphink-cli/Contents/Helpers/graphink"')


class Casks(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        root = pathlib.Path(self.dir.name)
        self.tap, self.dist = root / 'tap', root / 'dist'
        (self.tap / 'Casks').mkdir(parents=True)
        self.dist.mkdir()
        (self.tap / 'Casks/graphink-app.rb').write_text(APP)
        (self.tap / 'Casks/graphink-cli.rb').write_text(CLI)
        (self.dist / 'Graphink.dmg.sha256').write_text('a' * 64 + '  Graphink.dmg\n')
        (self.dist / 'graphink-cli.zip.sha256').write_text('b' * 64 + '  graphink-cli.zip\n')

    def cask(self, name):
        return (self.tap / f'Casks/{name}.rb').read_text()

    def test_previous(self):
        tags = ['v2026.11.0', 'v2026.11.1', 'v2026.12.0', 'v2026.11.01', 'nightly']
        self.assertEqual(casks.previous('v2026.12.0', tags), 'v2026.11.1')
        self.assertEqual(casks.previous('v2026.12.1', tags), 'v2026.12.0')
        self.assertIsNone(casks.previous('v2026.11.0', tags))
        with self.assertRaises(casks.CaskError):
            casks.previous('2026.12.0', tags)

    def test_cli_version(self):
        self.assertEqual(casks.cli_version(self.tap), '2026.11.0')
        self.assertEqual(casks.main(['cli-version', '--tap', str(self.tap)]), 0)
        (self.tap / 'Casks/graphink-cli.rb').write_text(CLI.replace('"2026.11.0"', '"latest"'))
        with self.assertRaises(casks.CaskError):
            casks.cli_version(self.tap)
        (self.tap / 'Casks/graphink-cli.rb').write_text(CLI + '  version "2026.12.0"\n')
        with self.assertRaises(casks.CaskError):
            casks.cli_version(self.tap)

    def test_changed_cli_moves_both_casks(self):
        self.assertEqual(casks.update(self.tap, '2026.11.1', self.dist, 'changed'), ['graphink-app 2026.11.1', 'graphink-cli 2026.11.1'])
        self.assertIn('version "2026.11.1"', self.cask('graphink-app'))
        self.assertIn('sha256 "' + 'a' * 64 + '"', self.cask('graphink-app'))
        self.assertIn('sha256 "' + 'b' * 64 + '"', self.cask('graphink-cli'))
        self.assertIn('download/v#{version}/graphink-cli.zip', self.cask('graphink-cli'))

    def test_unchanged_cli_keeps_its_cask(self):
        self.assertEqual(casks.update(self.tap, '2026.11.1', self.dist, 'unchanged'), ['graphink-app 2026.11.1'])
        self.assertEqual(self.cask('graphink-cli'), CLI)

    def test_malformed_inputs_are_refused(self):
        for cli in ('maybe', '', ' since v2026.11.0'):
            with self.subTest(cli=cli), self.assertRaises(casks.CaskError):
                casks.update(self.tap, '2026.11.1', self.dist, cli)
        (self.tap / 'Casks/graphink-app.rb').write_text(APP + '  version "2"\n')
        with self.assertRaises(casks.CaskError):
            casks.update(self.tap, '2026.11.1', self.dist, 'changed')
        with self.assertRaises(casks.CaskError):
            casks.update(self.tap, '2026.13.0', self.dist, 'changed')


if __name__ == '__main__':
    unittest.main()
